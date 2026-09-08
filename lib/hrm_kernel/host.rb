# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "open3"
require "pathname"
require "rbconfig"
require "time"
require_relative "store"

module HrmKernel
  # Local Codex transport. Worker output is evidence to inspect, never a test
  # receipt or a work_order.submit command. The Store remains the authority.
  class Host
    DEFAULT_CODEX = "/Applications/ChatGPT.app/Contents/Resources/codex"
    MODEL = "gpt-5.6-sol"
    MAX_RESULT_BYTES = 1024 * 1024
    RESULT_KEYS = %w[status summary changed_paths findings scenario_dispositions context_requests].freeze
    IDENTIFIER = /\A[a-zA-Z0-9][a-zA-Z0-9_.-]{0,100}\z/.freeze
    UUID = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i.freeze

    def self.object_schema(properties)
      { "type" => "object", "properties" => properties,
        "required" => properties.keys, "additionalProperties" => false }
    end

    TEXT = { "type" => "string" }.freeze
    TEXTS = { "type" => "array", "items" => TEXT }.freeze
    RESULT_SCHEMA = object_schema(
      "status" => { "type" => "string", "enum" => %w[implemented blocked reviewed] },
      "summary" => TEXT,
      "changed_paths" => TEXTS,
      "findings" => { "type" => "array", "items" => object_schema(
        "severity" => { "type" => "string", "enum" => %w[info warning error] },
        "message" => TEXT, "paths" => TEXTS, "scenario_ids" => TEXTS
      ) },
      "scenario_dispositions" => { "type" => "array", "items" => object_schema(
        "scenario_id" => TEXT,
        "status" => { "type" => "string", "enum" => %w[passed failed pending] },
        "evidence" => TEXT
      ) },
      "context_requests" => { "type" => "array", "items" => object_schema("path" => TEXT, "reason" => TEXT) }
    ).freeze

    def initialize(state_dir:, codex_path: DEFAULT_CODEX)
      @store = Store.new(state_dir)
      @state_dir = @store.directory
      @directory = File.join(@state_dir, "host-jobs")
      self.class.private_directory!(@directory)
      @codex_path = File.expand_path(codex_path)
    end

    def dispatch(spec)
      spec = normalize_spec(spec)
      with_registry_lock do
        path = job_path(spec.fetch("job_id"))
        if File.exist?(path)
          existing = read_job(spec.fetch("job_id"))
          fail!("job_id already has a different dispatch specification") unless existing["spec_digest"] == self.class.digest(spec)
          return poll(job_id: spec.fetch("job_id"))
        end
        fail!("Codex executable is unavailable") unless File.file?(@codex_path) && File.executable?(@codex_path)
        if !spec["forbidden_roots"].empty? && !File.executable?("/usr/bin/sandbox-exec")
          fail!("required host filesystem exclusions need sandbox-exec on this host")
        end
        state = @store.read.fetch("state")
        fail!("milestone is not initialized") unless state && state["milestone"]
        if spec["role"] == "reviewer"
          candidate = State.project(state, role: "reviewer").dig("milestone", "current_candidate")
          fail!("reviewer requires a completed current candidate") unless candidate
          Evidence.verify_completed_work!(state, state_dir: @state_dir)
        end
        root = File.realpath(state.fetch("milestone").fetch("project_root"))
        forbidden = spec["forbidden_roots"]
        fail!("project root overlaps a forbidden root") if forbidden.any? { |item| beneath?(root, item) }
        actor = spec["role"] == "worker" ? "worker-#{spec.fetch('work_order_id')}" : "reviewer-#{spec.fetch('job_id')}"
        resumed = resume_parent(spec, actor)
        order = spec["role"] == "worker" ? state.fetch("work_orders").fetch(spec["work_order_id"]) { fail!("unknown work order") } : nil
        if order
          plan_ids = spec.fetch("check_plan").fetch("checks").map { |item| item["id"] }
          fail!("host check plan must match the work order's declared check IDs") unless plan_ids.sort == order.fetch("check_ids").sort
        end
        # Read declared sources before claiming: bad context must not lease work.
        context = read_context(root, spec)
        preview_state = JSON.parse(JSON.generate(state))
        if order && order["status"] == "queued"
          preview = preview_state.fetch("work_orders").fetch(spec["work_order_id"])
          preview.merge!("status" => "running", "owner_id" => actor, "last_owner_id" => actor, "claim_id" => "claim-#{spec['job_id']}")
        end
        preview_prompt = JSON.pretty_generate(build_packet(spec, actor, preview_state, context))
        fail!("bounded prompt exceeds max_context_bytes") if preview_prompt.bytesize > spec["max_context_bytes"]
        if order
          unless order["status"] == "queued" || (resumed && order["status"] == "running" && order["owner_id"] == actor)
            fail!("worker requires a queued order or its own resumed active claim")
          end
          if order["status"] == "queued"
            @store.transact(
              "command_id" => "host-claim-#{spec['job_id']}", "type" => "work_order.claim",
              "actor" => { "role" => "worker", "id" => actor },
              "data" => { "work_order_id" => spec["work_order_id"], "revision" => order["revision"], "claim_id" => "claim-#{spec['job_id']}" }
            )
          end
          state = @store.read.fetch("state")
          order = state.fetch("work_orders").fetch(spec["work_order_id"])
        end
        packet = build_packet(spec, actor, state, context)
        prompt = JSON.pretty_generate(packet)
        fail!("bounded prompt exceeds max_context_bytes") if prompt.bytesize > spec["max_context_bytes"]
        binding = binding_for(state, order)
        job = {
          "schema_version" => "ap-hrm-host/1", "job_id" => spec["job_id"], "spec" => spec,
          "spec_digest" => self.class.digest(spec), "role" => spec["role"], "actor_id" => actor,
          "model_requested" => MODEL, "model_identity_evidence" => "requested_cli_argument",
          "work_order_id" => spec["work_order_id"], "revision" => order && order["revision"],
          "claim_id" => order && order["claim_id"], "binding" => binding,
          "binding_digest" => self.class.digest(binding), "project_root" => root,
          "candidate_digest" => binding.dig("candidate", "candidate_digest"),
          "check_plan" => spec["check_plan"], "check_plan_digest" => self.class.digest(spec["check_plan"]),
          "execution_read_roots" => spec["execution_read_roots"],
          "execution_environment_allowlist" => spec["execution_environment_allowlist"],
          "resume_thread_id" => resumed && resumed["thread_id"],
          "codex_path" => @codex_path, "prompt_bytes" => prompt.bytesize,
          "prompt_sha256" => Digest::SHA256.hexdigest(prompt),
          "created_at" => Time.now.utc.iso8601(6),
          "baseline_artifacts" => artifact_snapshot(root, order ? order["paths"] : [], forbidden)
        }
        self.class.private_directory!(path)
        self.class.atomic_write(File.join(path, "prompt.json"), prompt)
        self.class.atomic_json(File.join(path, "schema.json"), RESULT_SCHEMA)
        self.class.atomic_json(File.join(path, "job.json"), job)
        # The durable job identity precedes launch. A restart never redispatches
        # an uncertain launch; the operator can inspect its persisted status.
        helper = File.expand_path("../../scripts/hrm_host_worker.rb", __dir__)
        pid = File.open(File.join(path, "helper.stderr.log"), File::WRONLY | File::CREAT | File::EXCL, 0o600) do |errors|
          Process.spawn(RbConfig.ruby, helper, @state_dir, spec["job_id"],
                        in: File::NULL, out: File::NULL, err: errors, pgroup: true)
        end
        Process.detach(pid)
        self.class.atomic_json(File.join(path, "launch.json"), { "helper_pid" => pid, "launched_at" => Time.now.utc.iso8601(6) })
        poll(job_id: spec["job_id"])
      end
    end

    def poll(job_id:)
      job = read_job(job_id)
      path = job_path(job_id)
      completion = read_optional_json(File.join(path, "completion.json"))
      runtime = read_optional_json(File.join(path, "runtime.json"))
      launch = read_optional_json(File.join(path, "launch.json"))
      events = read_events(path)
      thread_ids = events.select { |event| event["type"] == "thread.started" }.map { |event| event["thread_id"] }.uniq
      thread_id = thread_ids.length == 1 && thread_ids.first.is_a?(String) && UUID.match?(thread_ids.first) ? thread_ids.first : nil
      status = completion ? completion.fetch("status") : "running"
      if !completion && !(runtime && process_alive?(runtime["helper_pid"])) && !(launch && process_alive?(launch["helper_pid"]))
        status = "launch_unknown"
      end
      completed_turns = events.select { |event| event["type"] == "turn.completed" }
      usage = completed_turns.map { |event| event["usage"] }.select { |item| item.is_a?(Hash) }
      output = job.slice("job_id", "role", "actor_id", "work_order_id", "revision", "claim_id", "model_requested", "model_identity_evidence", "prompt_bytes", "created_at", "check_plan_digest", "binding_digest")
      output.merge!("status" => status, "thread_id" => thread_id, "usage" => usage,
                    "artifact_paths" => %w[job.json prompt.json events.jsonl stderr.log helper.stderr.log result.json completion.json].to_h { |name| [name, File.join(path, name)] })
      output["completion"] = completion if completion
      output["claim_current"] = binding_current?(job)
      output
    end

    def collect(job_id:)
      job = read_job(job_id)
      assert_current!(job)
      status = poll(job_id: job_id)
      fail!("host job has no verified successful completion") unless status["status"] == "succeeded"
      completion = status.fetch("completion")
      path = File.join(job_path(job_id), "result.json")
      bytes = self.class.read_private(path, max_bytes: MAX_RESULT_BYTES)
      fail!("result bytes changed after host completion") unless Digest::SHA256.hexdigest(bytes) == completion["result_sha256"]
      result = JSON.parse(bytes)
      self.class.validate_result!(result, role: job["role"])
      fail!("host thread identity missing") unless status["thread_id"]
      if job["resume_thread_id"] && status["thread_id"] != job["resume_thread_id"]
        fail!("resumed host returned a different thread identity")
      end
      permitted = job.dig("binding", "order", "paths") || []
      result.fetch("changed_paths").each do |relative|
        fail!("worker reported a path outside its work order") unless permitted.include?(relative)
      end
      actual = artifact_snapshot(job["project_root"], permitted, job.dig("spec", "forbidden_roots"))
      changed = actual.keys.select { |relative| actual[relative] != job["baseline_artifacts"][relative] }
      fail!("worker changed declared files without reporting them") unless (changed - result["changed_paths"]).empty?
      { "job" => status, "result" => result, "verified_artifacts" => actual.map { |relative, sha| { "path" => relative, "sha256" => sha, "exists" => !sha.nil? } },
        "observed_changed_paths" => changed, "tests_verified" => false, "submitted" => false }
    rescue JSON::ParserError => error
      fail!("invalid structured worker result: #{error.message}")
    end

    # Execution callers receive the dispatch-time plan, never a worker-supplied
    # command. No check may be substituted between dispatch and evidence capture.
    def job_record(job_id:)
      job = read_job(job_id)
      assert_current!(job)
      job
    end

    def check_context(job_id:, check_id:)
      job = job_record(job_id: job_id)
      matches = job.fetch("check_plan").fetch("checks").select { |item| item.is_a?(Hash) && item["id"] == check_id }
      fail!("check_id is not uniquely declared in the host check plan") unless matches.length == 1
      { "job" => job, "spec" => matches.first }
    end

    # Invoked only by the detached helper. It has its own launch lock, so even
    # accidentally invoking two helpers cannot execute the same job twice.
    def run_job(job_id:)
      path = job_path(job_id)
      lock = File.open(File.join(path, ".run.lock"), File::RDWR | File::CREAT, 0o600)
      return unless lock.flock(File::LOCK_EX | File::LOCK_NB)
      return if File.exist?(File.join(path, "completion.json")) || File.exist?(File.join(path, "runtime.json"))
      job = read_job(job_id)
      self.class.atomic_json(File.join(path, "runtime.json"), { "helper_pid" => Process.pid, "started_at" => Time.now.utc.iso8601(6) })
      assert_current!(job)
      args = codex_arguments(job, path)
      profile = sandbox_profile(job)
      if profile
        self.class.atomic_write(File.join(path, "sandbox.sb"), profile)
        args = ["/usr/bin/sandbox-exec", "-f", File.join(path, "sandbox.sb")] + args
      end
      env = ENV.to_h.select { |key, _value| %w[HOME USER LOGNAME PATH TMPDIR CODEX_HOME].include?(key) }
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      status = nil
      File.open(File.join(path, "prompt.json"), "r") do |input|
        File.open(File.join(path, "events.jsonl"), File::WRONLY | File::CREAT | File::EXCL, 0o600) do |output|
          File.open(File.join(path, "stderr.log"), File::WRONLY | File::CREAT | File::EXCL, 0o600) do |errors|
            pid = Process.spawn(env, *args, in: input, out: output, err: errors, chdir: job["project_root"], unsetenv_others: true)
            _pid, status = Process.wait2(pid)
          end
        end
      end
      events = read_events(path)
      thread_ids = events.select { |event| event["type"] == "thread.started" }.map { |event| event["thread_id"] }.uniq
      valid_thread = thread_ids.length == 1 && thread_ids.first.is_a?(String) && UUID.match?(thread_ids.first)
      completed = events.any? { |event| event["type"] == "turn.completed" }
      failed_event = events.any? { |event| %w[turn.failed error].include?(event["type"]) }
      result_file = File.join(path, "result.json")
      result_sha = nil
      if File.file?(result_file)
        fail!("unsafe worker result symlink") if File.symlink?(result_file)
        File.chmod(0o600, result_file)
        result_bytes = self.class.read_private(result_file, max_bytes: MAX_RESULT_BYTES)
        self.class.validate_result!(JSON.parse(result_bytes), role: job["role"])
        result_sha = Digest::SHA256.hexdigest(result_bytes)
      end
      succeeded = status.success? && valid_thread && completed && !failed_event && result_sha
      succeeded &&= !job["resume_thread_id"] || thread_ids.first == job["resume_thread_id"]
      self.class.atomic_json(File.join(path, "completion.json"), {
        "status" => succeeded ? "succeeded" : "failed", "exit_code" => status.exitstatus,
        "term_signal" => status.termsig, "completed_at" => Time.now.utc.iso8601(6),
        "duration_seconds" => Process.clock_gettime(Process::CLOCK_MONOTONIC) - started,
        "result_sha256" => result_sha, "thread_id" => valid_thread ? thread_ids.first : nil,
        "binding_digest" => job["binding_digest"], "check_plan_digest" => job["check_plan_digest"]
      })
    rescue StandardError => error
      self.class.atomic_json(File.join(path, "completion.json"), {
        "status" => "failed", "error_class" => error.class.name, "error" => error.message,
        "completed_at" => Time.now.utc.iso8601(6)
      }) if path && File.directory?(path)
    ensure
      lock&.close
    end

    def self.validate_result!(result, role:)
      invalid = ->(message) { raise HrmKernel::Error, message }
      invalid.call("structured result has invalid fields") unless result.is_a?(Hash) && result.keys.sort == RESULT_KEYS.sort
      statuses = role == "reviewer" ? %w[reviewed blocked] : %w[implemented blocked]
      invalid.call("structured result has invalid role/status") unless statuses.include?(result["status"])
      invalid.call("summary must be a string") unless result["summary"].is_a?(String)
      invalid.call("changed_paths must be strings") unless strings?(result["changed_paths"])
      invalid.call("reviewer may not report file changes") if role == "reviewer" && !result["changed_paths"].empty?
      { "findings" => %w[severity message paths scenario_ids], "scenario_dispositions" => %w[scenario_id status evidence], "context_requests" => %w[path reason] }.each do |field, keys|
        invalid.call("#{field} must be an array") unless result[field].is_a?(Array)
        result[field].each do |entry|
          invalid.call("invalid #{field} entry") unless entry.is_a?(Hash) && entry.keys.sort == keys.sort
          keys.each do |key|
            valid = %w[paths scenario_ids].include?(key) ? strings?(entry[key]) : entry[key].is_a?(String)
            invalid.call("invalid #{field}.#{key}") unless valid
          end
          invalid.call("invalid finding severity") if field == "findings" && !%w[info warning error].include?(entry["severity"])
          invalid.call("invalid scenario status") if field == "scenario_dispositions" && !%w[passed failed pending].include?(entry["status"])
        end
      end
      true
    end

    def self.strings?(value)
      value.is_a?(Array) && value.all? { |item| item.is_a?(String) }
    end

    def self.canonical(value)
      case value
      when Hash then value.keys.sort.to_h { |key| [key, canonical(value[key])] }
      when Array then value.map { |item| canonical(item) }
      else value
      end
    end

    def self.digest(value)
      Digest::SHA256.hexdigest(JSON.generate(canonical(value)))
    end

    def self.private_directory!(path)
      raise HrmKernel::Error, "unsafe host directory" if File.symlink?(path)
      FileUtils.mkdir_p(path, mode: 0o700)
      raise HrmKernel::Error, "host directory must be private" unless File.directory?(path) && (File.stat(path).mode & 0o777) == 0o700
    end

    def self.atomic_json(path, value)
      atomic_write(path, JSON.pretty_generate(value) + "\n")
    end

    def self.atomic_write(path, bytes)
      raise HrmKernel::Error, "unsafe host file" if File.symlink?(path)
      temporary = "#{path}.#{Process.pid}.tmp"
      File.open(temporary, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
        file.write(bytes)
        file.flush
        file.fsync
      end
      File.rename(temporary, path)
    ensure
      File.unlink(temporary) if temporary && File.exist?(temporary)
    end

    def self.read_private(path, max_bytes: MAX_RESULT_BYTES)
      raise HrmKernel::Error, "unsafe host file" if File.symlink?(path)
      stat = File.stat(path)
      raise HrmKernel::Error, "host file must be private and regular" unless stat.file? && (stat.mode & 0o077).zero?
      raise HrmKernel::Error, "host file exceeds size bound" if stat.size > max_bytes
      File.binread(path)
    end

    private

    def fail!(message)
      raise HrmKernel::Error, message
    end

    def normalize_spec(value)
      fail!("dispatch specification must be an object") unless value.is_a?(Hash)
      spec = JSON.parse(JSON.generate(value))
      allowed = %w[job_id role work_order_id model prompt context_paths max_context_bytes check_plan resume_job_id forbidden_roots execution_read_roots execution_environment_allowlist]
      fail!("unknown dispatch fields") unless (spec.keys - allowed).empty?
      fail!("invalid job_id") unless spec["job_id"].is_a?(String) && IDENTIFIER.match?(spec["job_id"])
      fail!("invalid role") unless %w[worker reviewer].include?(spec["role"])
      fail!("only the requested Sol worker model is supported") unless spec["model"] == MODEL
      fail!("prompt must be nonempty text") unless spec["prompt"].is_a?(String) && !spec["prompt"].empty?
      if spec["role"] == "worker"
        fail!("worker needs work_order_id") unless spec["work_order_id"].is_a?(String) && IDENTIFIER.match?(spec["work_order_id"])
      elsif spec["work_order_id"] || spec["resume_job_id"]
        fail!("reviewer must be a fresh independent host session")
      end
      spec["context_paths"] ||= []
      fail!("context_paths must be strings") unless self.class.strings?(spec["context_paths"])
      spec["max_context_bytes"] ||= 64 * 1024
      fail!("max_context_bytes must be 1024..524288") unless spec["max_context_bytes"].is_a?(Integer) && spec["max_context_bytes"].between?(1024, 512 * 1024)
      plan = spec["check_plan"]
      valid_plan = plan.is_a?(Hash) && plan.keys.sort == %w[checks environment_id] && plan["environment_id"].is_a?(String) && !plan["environment_id"].empty? && plan["checks"].is_a?(Array)
      fail!("check_plan requires environment_id and checks") unless valid_plan && JSON.generate(plan).bytesize <= 64 * 1024
      plan_ids = plan["checks"].map do |item|
        fail!("each frozen check requires an id") unless item.is_a?(Hash) && item["id"].is_a?(String) && !item["id"].empty?
        item["id"]
      end
      fail!("check plan IDs must be unique") unless plan_ids.uniq == plan_ids
      spec["execution_read_roots"] ||= []
      spec["execution_environment_allowlist"] ||= []
      fail!("execution_read_roots must be absolute paths") unless self.class.strings?(spec["execution_read_roots"]) && spec["execution_read_roots"].all? { |path| Pathname.new(path).absolute? }
      fail!("execution_environment_allowlist must be environment names") unless self.class.strings?(spec["execution_environment_allowlist"]) && spec["execution_environment_allowlist"].all? { |name| /\A[A-Z][A-Z0-9_]*\z/.match?(name) }
      roots = spec["forbidden_roots"] || []
      fail!("forbidden_roots must be strings") unless self.class.strings?(roots)
      roots = [File.join(Dir.home, "Documents")] + roots
      spec["forbidden_roots"] = roots.map do |path|
        fail!("forbidden roots must be absolute") unless Pathname.new(path).absolute?
        File.exist?(path) ? File.realpath(path) : File.expand_path(path)
      end.uniq.sort
      spec
    end

    def with_registry_lock
      path = File.join(@directory, ".lock")
      fail!("unsafe host registry lock") if File.symlink?(path)
      File.open(path, File::RDWR | File::CREAT, 0o600) do |lock|
        fail!("unsafe host registry lock permissions") unless (lock.stat.mode & 0o077).zero?
        lock.flock(File::LOCK_EX)
        yield
      end
    end

    def job_path(id)
      fail!("invalid job_id") unless id.is_a?(String) && IDENTIFIER.match?(id)
      path = File.join(@directory, id)
      fail!("unsafe job directory") if File.symlink?(path)
      path
    end

    def read_job(id)
      job = JSON.parse(self.class.read_private(File.join(job_path(id), "job.json")))
      valid = job["job_id"] == id && job["spec_digest"] == self.class.digest(job["spec"]) &&
              job["binding_digest"] == self.class.digest(job["binding"]) &&
              job["check_plan_digest"] == self.class.digest(job["check_plan"]) &&
              job["check_plan"] == job.dig("spec", "check_plan")
      fail!("host job manifest integrity mismatch") unless valid
      job
    end

    def read_optional_json(path)
      File.exist?(path) ? JSON.parse(self.class.read_private(path)) : nil
    end

    def read_events(path)
      file = File.join(path, "events.jsonl")
      return [] unless File.exist?(file)
      fail!("unsafe host event file") if File.symlink?(file)
      events = []
      File.foreach(file) do |line|
        next unless line.end_with?("\n") # A live final partial line is not an event.
        begin
          event = JSON.parse(line)
          events << event if event.is_a?(Hash) && %w[thread.started turn.completed turn.failed error].include?(event["type"])
        rescue JSON::ParserError
          next
        end
      end
      events
    end

    def process_alive?(pid)
      return false unless pid.is_a?(Integer) && pid.positive?
      Process.kill(0, pid)
      true
    rescue Errno::ESRCH
      false
    end

    def resume_parent(spec, actor)
      return nil unless spec["resume_job_id"]
      prior = read_job(spec["resume_job_id"])
      fail!("resume must preserve worker actor and order") unless prior["role"] == "worker" && prior["actor_id"] == actor && prior["work_order_id"] == spec["work_order_id"]
      status = poll(job_id: prior["job_id"])
      fail!("resume parent must have a completed verified thread") unless %w[succeeded failed].include?(status["status"]) && status["thread_id"]
      status
    end

    def binding_for(state, order)
      milestone = state.fetch("milestone")
      result = { "initial_contract_digest" => milestone.fetch("initial_contract_digest"), "milestone_id" => milestone["id"] }
      if order
        result["order"] = order.slice("id", "revision", "owner_id", "claim_id", "paths", "check_ids", "requirement_revisions", "intent_ids", "objective")
        result["current_requirements"] = order.fetch("requirement_ids").to_h { |id| [id, milestone.fetch("requirements").fetch(id)] }
      else
        result["candidate"] = State.project(state, role: "reviewer").dig("milestone", "current_candidate")
      end
      result
    end

    def binding_current?(job)
      state = @store.read.fetch("state")
      return false unless state && state["milestone"]
      order = job["role"] == "worker" ? state.fetch("work_orders")[job["work_order_id"]] : nil
      return false if job["role"] == "worker" && (!order || order["status"] != "running")
      self.class.digest(binding_for(state, order)) == job["binding_digest"]
    end

    def assert_current!(job)
      fail!("stale host job: claim, contract or candidate changed") unless binding_current?(job)
      Evidence.verify_completed_work!(@store.read.fetch("state"), state_dir: @state_dir) if job["role"] == "reviewer"
    end

    def beneath?(path, root)
      path == root || path.start_with?(root + File::SEPARATOR)
    end

    def source_path(root, relative, forbidden, allow_missing: false)
      fail!("context/artifact path must be project-relative") unless relative.is_a?(String) && !Pathname.new(relative).absolute? && !relative.split("/").include?("..") && relative != "." && !relative.empty?
      path = File.expand_path(relative, root)
      if File.exist?(path)
        resolved = File.realpath(path)
      elsif allow_missing
        parent = File.dirname(path)
        parent = File.dirname(parent) until File.exist?(parent)
        fail!("artifact parent leaves project root") unless beneath?(File.realpath(parent), root)
        resolved = path
      else
        fail!("declared context path is missing: #{relative}")
      end
      fail!("source leaves project root") unless beneath?(resolved, root)
      fail!("source is inside a forbidden root") if forbidden.any? { |item| beneath?(resolved, item) }
      resolved
    end

    def read_context(root, spec)
      used = 0
      spec["context_paths"].map do |relative|
        path = source_path(root, relative, spec["forbidden_roots"])
        fail!("declared context must be a regular file") unless File.file?(path)
        used += File.size(path)
        fail!("declared source context exceeds max_context_bytes") if used > spec["max_context_bytes"]
        bytes = File.binread(path)
        text = bytes.dup.force_encoding(Encoding::UTF_8)
        fail!("declared context must be UTF-8 text") unless text.valid_encoding?
        { "path" => relative, "sha256" => Digest::SHA256.hexdigest(bytes), "text" => text }
      end
    end

    def artifact_snapshot(root, paths, forbidden)
      paths.to_h do |relative|
        path = source_path(root, relative, forbidden, allow_missing: true)
        fail!("work-order paths must name files") if File.exist?(path) && !File.file?(path)
        [relative, File.file?(path) ? Digest::SHA256.file(path).hexdigest : nil]
      end
    end

    def build_packet(spec, actor, state, context)
      # Only the immutable initial command is extracted; no history is sent.
      line = File.open(File.join(@state_dir, Store::LEDGER_NAME), &:gets)
      initial = JSON.parse(line).dig("command", "data")
      {
        "host_contract" => "AP-INTERACT RC34 bounded Codex worker",
        "instructions" => [
          spec["role"] == "worker" ? "Implement only your declared work-order files. Do not commit, push, run tests, launch servers, or call providers. The kernel execution runner performs checks after you return." : "Independently review the exact candidate read-only. Do not edit files, run tests, launch servers, or call providers.",
          "Read only the supplied packet and declared source paths. Ask for needed additional context through context_requests; technical discovery does not require operator approval.",
          "Do not access operator Documents, ambient databases, credentials, private evidence, or other checkouts. No provider, customer, deployment, or runtime effects are authorized.",
          "Return the required structured JSON. Scenario statements are your assessment, not verified execution receipts or human acceptance. Preserve unmet requirements and findings.",
          "This host measures supplied prompt bytes and actual reported token usage separately. The worker sandbox is workspace-write (reviewer read-only), with the listed filesystem exclusions; this is not a complete read allowlist."
        ],
        "task" => spec["prompt"], "actor_id" => actor,
        "initial_contract" => initial,
        "role_projection" => State.project(state, role: spec["role"], actor_id: actor),
        "declared_sources" => context, "check_plan" => spec["check_plan"],
        "forbidden_roots" => spec["forbidden_roots"]
      }
    end

    def codex_arguments(job, path)
      sandbox = job["role"] == "reviewer" ? "read-only" : "workspace-write"
      args = [job["codex_path"], "exec", "--ignore-user-config", "-m", MODEL, "-s", sandbox,
              "-c", 'approval_policy="never"', "-c", 'shell_environment_policy.inherit="none"',
              "-C", job["project_root"]]
      args += ["resume", job["resume_thread_id"]] if job["resume_thread_id"]
      args + ["--json", "--output-schema", File.join(path, "schema.json"), "-o", File.join(path, "result.json"), "-"]
    end

    def sandbox_profile(job)
      roots = job.dig("spec", "forbidden_roots")
      profile = "(version 1)\n(allow default)\n" + roots.map { |root| "(deny file-read* file-write* (subpath #{JSON.generate(root)}))\n" }.join
      path = job_path(job["job_id"])
      # The CLI needs its schema and output file. It does not need the control
      # ledger, receipt keys, execution records or other workers' private jobs.
      # Keep directory metadata traversable but deny data reads/listing.
      exceptions = %w[schema.json result.json].map { |name| "(require-not (literal #{JSON.generate(File.join(path, name))}))" }.join(" ")
      profile += "(deny file-read-data file-write* (require-all (subpath #{JSON.generate(@state_dir)}) #{exceptions}))\n"
      # Concurrent jobs share a candidate, but their write authority does not.
      # Enforce declared file ownership in the outer process sandbox as well as
      # in state. Reviewer sessions cannot mutate any candidate path.
      paths = job.dig("binding", "order", "paths") || []
      exclusions = paths.map { |relative| "(require-not (literal #{JSON.generate(File.join(job.fetch('project_root'), relative))}))" }.join(" ")
      profile + "(deny file-write* (require-all (subpath #{JSON.generate(job.fetch('project_root'))}) #{exclusions}))\n"
    end
  end
end
