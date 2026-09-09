# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "open3"
require "pathname"
require "securerandom"
require "time"
require "tmpdir"

require_relative "error"
require_relative "host"
require_relative "store"

module HrmKernel
  # Copies a stopped, verified run into a new private state root. The ledger and
  # historical receipts are evidence: they are copied byte-for-byte and never
  # rewritten. Only the destination Driver configuration/runtime are derived so
  # the new kernel must make a fresh projection and a fresh orchestration request.
  class RunContinuation
    SCHEMA_VERSION = "ap-hrm-run-continuation/1"
    PROVENANCE_SCHEMA = "ap-hrm-supervisor-continuation/1"
    SOURCE_KERNEL_VERSION = "AP-INTERACT RC.35"
    TARGET_KERNEL_VERSION = "AP-INTERACT RC.36"
    MAX_FILE_BYTES = 16 * 1024 * 1024
    MAX_TOTAL_BYTES = 256 * 1024 * 1024
    MAX_ENTRIES = 20_000
    GIT_REVISION = /\A[0-9a-f]{40}\z/.freeze
    CONTINUATION_DIRECTORY = File.join("driver", "continuation")
    MANIFEST_PATH = File.join(CONTINUATION_DIRECTORY, "manifest.json")

    class << self
      def clone(source_state_dir:, destination_state_dir:, new_run_id:, source_kernel_root:,
                source_kernel_revision:, controller_stopped:, supervisor_provenance:,
                production: true)
        new(
          source_state_dir: source_state_dir,
          destination_state_dir: destination_state_dir,
          new_run_id: new_run_id,
          source_kernel_root: source_kernel_root,
          source_kernel_revision: source_kernel_revision,
          controller_stopped: controller_stopped,
          supervisor_provenance: supervisor_provenance,
          production: production
        ).clone!
      end
    end

    def initialize(source_state_dir:, destination_state_dir:, new_run_id:, source_kernel_root:,
                   source_kernel_revision:, controller_stopped:, supervisor_provenance:,
                   production: true)
      @source = canonical_existing_directory(source_state_dir, "source state directory")
      @destination = canonical_destination(destination_state_dir)
      @new_run_id = new_run_id
      @source_kernel_root = canonical_existing_directory(source_kernel_root, "source kernel root")
      @declared_source_revision = source_kernel_revision
      @controller_stopped = controller_stopped
      @supervisor_provenance = validate_provenance(supervisor_provenance)
      @production = production
      validate_request!
    end

    def clone!
      with_source_driver_lock do
        source = verify_source!
        request = request_record(source)
        return verify_idempotent_destination!(request) if File.exist?(@destination)

        staging = "#{@destination}.continuation-#{Process.pid}-#{SecureRandom.hex(6)}"
        destination_created = false
        fail!("continuation staging path already exists") if File.exist?(staging) || File.symlink?(staging)
        begin
          copy_tree(@source, staging)
          derive_destination!(staging, source, request)
          verify_source_unchanged!(source.fetch("tree"))
          File.rename(staging, @destination)
          destination_created = true
          reverify_target_preflight!(@destination, source.fetch("config"))
          finalize_destination!(@destination, source, request)
          fsync_directory(File.dirname(@destination))
          manifest = verify_created_destination!(request)
          destination_created = false
          manifest
        ensure
          FileUtils.remove_entry(staging) if staging && File.directory?(staging)
          FileUtils.remove_entry(@destination) if destination_created && File.directory?(@destination)
        end
      end
    rescue Errno::ELOOP => error
      fail!("unsafe symlink while continuing run: #{error.message}")
    rescue SystemCallError => error
      fail!("cannot create continued run: #{error.message}")
    end

    private

    def validate_request!
      fail!("new run id is invalid") unless @new_run_id.is_a?(String) &&
        Host::IDENTIFIER.match?(@new_run_id) && @new_run_id.length <= 40
      fail!("source kernel revision must be a full Git commit") unless @declared_source_revision.is_a?(String) &&
        GIT_REVISION.match?(@declared_source_revision)
      fail!("controller_stopped must be explicitly true") unless @controller_stopped.equal?(true)
      fail!("production must be true or false") unless @production.equal?(true) || @production.equal?(false)
      fail!("source and destination state roots overlap") if beneath?(@source, @destination) || beneath?(@destination, @source)
      unless @production
        temporary_root = File.realpath(Dir.tmpdir)
        unless [@source, @destination, @source_kernel_root].all? { |path| beneath?(path, temporary_root) }
          fail!("non-production continuation is restricted to temporary test fixtures")
        end
      end
    end

    def validate_provenance(value)
      fail!("supervisor provenance must be an object") unless value.is_a?(Hash)
      copy = JSON.parse(JSON.generate(value))
      required = %w[asserted_at commission_id schema_version source supervisor_id]
      fail!("supervisor provenance fields are invalid") unless copy.keys.sort == required
      fail!("supervisor provenance schema is unsupported") unless copy["schema_version"] == PROVENANCE_SCHEMA
      %w[supervisor_id source].each do |key|
        fail!("supervisor provenance #{key} must be nonempty text") unless copy[key].is_a?(String) && !copy[key].empty?
      end
      fail!("supervisor commission id is invalid") unless copy["commission_id"].is_a?(String) &&
        Host::IDENTIFIER.match?(copy["commission_id"])
      begin
        Time.iso8601(copy.fetch("asserted_at"))
        unless /(?:Z|[+-]\d{2}:\d{2})\z/.match?(copy["asserted_at"])
          fail!("supervisor provenance asserted_at must include a UTC offset")
        end
      rescue ArgumentError
        fail!("supervisor provenance asserted_at must be ISO8601")
      end
      copy
    rescue JSON::GeneratorError
      fail!("supervisor provenance must contain JSON values")
    end

    def with_source_driver_lock
      driver = File.join(@source, "driver")
      ensure_private_directory(driver, "source driver directory")
      path = File.join(driver, ".lock")
      fail!("source driver lock is a symlink") if File.symlink?(path)
      fail!("source Driver lock is missing") unless File.file?(path)
      flags = File::RDWR
      flags |= File::NOFOLLOW if defined?(File::NOFOLLOW)
      File.open(path, flags) do |lock|
        fail!("source driver lock must be a private regular file") unless lock.stat.file? && (lock.stat.mode & 0o077).zero?
        fail!("source Driver is still running or its stop is not observable") unless lock.flock(File::LOCK_EX | File::LOCK_NB)
        yield
      end
    end

    def verify_source!
      source_revision = verify_git_checkout!(@source_kernel_root, expected: @declared_source_revision,
        require_clean: true, scope: "source kernel")
      verify_source_kernel_version!(source_revision)
      target_root = File.realpath(File.expand_path("../..", __dir__))
      target_revision = verify_git_checkout!(target_root, require_clean: @production, scope: "executing target kernel")
      target_version_verified = verify_target_kernel_version!(target_root, target_revision.fetch("revision"), required: @production)
      if @production && target_revision.fetch("revision") == source_revision
        fail!("production continuation requires a target kernel revision newer than the RC35 source pin")
      end

      # Constructors used below are intended to be read-only for a valid RC35
      # run. Capture first so an unexpected mkdir/key/chmod is detected.
      tree = snapshot_tree(@source)
      store = Store.new(@source)
      store_receipt = store.verify!
      state = store.read.fetch("state")
      config_bytes = read_private(File.join(@source, "driver", "config.json"))
      runtime_bytes = read_private(File.join(@source, "driver", "runtime.json"))
      preflight_bytes = read_private(File.join(@source, "driver", "preflight.json"))
      config = parse_object(config_bytes, "source Driver configuration")
      runtime = parse_object(runtime_bytes, "source Driver runtime")
      preflight = parse_array(preflight_bytes, "source Driver preflight")
      fail!("source is already a versioned continuation") if config.key?("continuation") || runtime.key?("continuation")
      fail!("source contains RC36 supervisor input and is not an RC35 run") if File.exist?(File.join(@source, "driver", "supervisor-inputs.jsonl"))
      fail!("new run id must differ from the source run id") if config["run_id"] == @new_run_id
      fail!("source Driver has a pending dispatch") if runtime.key?("pending_dispatch")
      fail!("source Driver has a pending job registration") if runtime.key?("pending_job_registration")
      fail!("source Driver runtime round is invalid") unless runtime["round"].is_a?(Integer) && runtime["round"] >= 0
      fail!("source Driver job lists are malformed") unless string_array?(runtime["jobs"]) && string_array?(runtime["seen_jobs"])
      fail!("source Driver configuration run id is invalid") unless config["run_id"].is_a?(String) && Host::IDENTIFIER.match?(config["run_id"])
      fail!("source Driver project root differs from the ledger") unless File.realpath(config.fetch("project_root")) == state.dig("milestone", "project_root")
      fail!("source Driver max_turns is invalid") unless config["max_turns"].is_a?(Integer) && config["max_turns"].between?(1, 100)
      fail!("source Driver consumed more than its turn budget") if runtime["round"] > config["max_turns"]
      fail!("source Driver outcome is invalid") unless %w[active review_ready closed operator_input engineering_stalled host_failure preflight_failed turn_limit].include?(runtime["outcome"])
      fail!("source Driver runtime feedback is malformed") unless runtime["feedback"].is_a?(Array)
      fail!("source Driver seen_jobs is not a subset of jobs") unless (runtime["seen_jobs"] - runtime["jobs"]).empty?
      verify_preflight_records!(config, preflight)
      verify_driver_requests!
      Evidence.verify_completed_work!(state, state_dir: @source)

      host = Host.new(state_dir: @source)
      statuses = verify_host_records!(host)
      referenced = (runtime.fetch("jobs") + [runtime["orchestrator_job"], runtime["resume_job"]]).compact
      fail!("source Driver references a missing Host job") unless (referenced - statuses.keys).empty?
      active = statuses.values.select { |status| %w[running launch_unknown].include?(status["status"]) }
      fail!("source has a running or uncertain native job: #{active.map { |item| item['job_id'] }.sort.join(', ')}") unless active.empty?
      next_job_id = "#{@new_run_id}-astra-#{runtime['round'] + 1}"
      fail!("new run id would collide with copied Host history") if statuses.key?(next_job_id)

      verify_source_unchanged!(tree)
      {
        "store" => store_receipt,
        "config" => config, "config_bytes" => config_bytes,
        "runtime" => runtime, "runtime_bytes" => runtime_bytes,
        "preflight_bytes" => preflight_bytes,
        "statuses" => statuses, "tree" => tree,
        "source_kernel_revision" => source_revision,
        "target_kernel_root" => target_root,
        "target_kernel_revision" => target_revision.fetch("revision"),
        "target_checkout_clean" => target_revision.fetch("clean"),
        "target_version_verified" => target_version_verified
      }
    end

    def verify_preflight_records!(config, receipts)
      specs = config["preflight_checks"]
      fail!("source Driver preflight configuration is malformed") unless specs.is_a?(Array) && !specs.empty?
      fail!("source Driver preflight receipt set is malformed") unless receipts.length == specs.length
      fail!("source Driver preflight IDs changed") unless receipts.map { |entry| entry.is_a?(Hash) && entry["id"] } == specs.map { |spec| spec.is_a?(Hash) && spec["id"] }
      sentinel = File.join(@source, "driver", "isolation-sentinel.txt")
      read_private(sentinel)
      execution = Execution.new(
        project_root: config.fetch("project_root"), state_dir: @source,
        read_roots: config.fetch("read_roots", []),
        environment_allowlist: config.fetch("environment_allowlist", []),
        forbidden_read_path: sentinel, forbidden_write_path: sentinel
      )
      receipts.zip(specs).each do |entry, spec|
        descriptor = entry.fetch("execution").slice("receipt_path", "receipt_sha256")
        receipt = execution.verify_preflight!(descriptor, spec: spec)
        fail!("source Driver preflight did not pass") unless receipt["conclusion"] == "passed"
      end
    rescue KeyError => error
      fail!("source Driver preflight is incomplete: #{error.message}")
    end

    def verify_driver_requests!
      root = File.join(@source, "driver", "requests")
      return unless File.exist?(root)
      ensure_private_directory(root, "source Driver requests")
      Dir.children(root).sort.each do |name|
        fail!("source Driver request id is invalid") unless Host::IDENTIFIER.match?(name)
        directory = File.join(root, name)
        ensure_private_directory(directory, "source Driver request")
        children = Dir.children(directory).sort
        fail!("source Driver request has an unsafe layout") unless children == %w[receipt.json request.json]
        request = parse_object(read_private(File.join(directory, "request.json")), "source Driver request")
        receipt = parse_object(read_private(File.join(directory, "receipt.json")), "source Driver request receipt")
        fail!("source Driver request identity changed") unless request["request_id"] == name && receipt["request_id"] == name
        fail!("source Driver request operation changed") unless request["operation"].is_a?(String) && receipt["operation"] == request["operation"]
        fail!("source Driver request receipt is malformed") unless receipt["ok"].equal?(true) || receipt["ok"].equal?(false)
      end
    end

    def verify_host_records!(host)
      root = File.join(@source, "host-jobs")
      return {} unless File.exist?(root)
      ensure_private_directory(root, "source Host registry")
      statuses = {}
      Dir.children(root).sort.each do |name|
        path = File.join(root, name)
        if name == ".lock"
          read_private(path)
          next
        end
        ensure_private_directory(path, "source Host job")
        status = host.poll(job_id: name)
        fail!("duplicate Host job identity") if statuses.key?(status.fetch("job_id"))
        unless %w[succeeded failed running launch_unknown].include?(status["status"])
          fail!("source Host job has an invalid terminal status: #{name}")
        end
        verify_completed_job!(path, status) if %w[succeeded failed].include?(status["status"])
        statuses[status.fetch("job_id")] = status
      end
      statuses
    end

    def verify_completed_job!(path, status)
      completion = status.fetch("completion")
      if completion.key?("binding_digest") || completion.key?("check_plan_digest")
        fail!("Host completion binding changed") unless completion["binding_digest"] == status["binding_digest"]
        fail!("Host completion check plan changed") unless completion["check_plan_digest"] == status["check_plan_digest"]
      elsif status["status"] == "failed"
        fail!("failed Host completion is malformed") unless completion["error_class"].is_a?(String) &&
          completion["error"].is_a?(String) && completion["completed_at"].is_a?(String)
      end
      return unless status["status"] == "succeeded"

      fail!("successful Host job is missing a verified thread UUID") unless status["thread_id"] &&
        Host::UUID.match?(status["thread_id"]) && completion["thread_id"] == status["thread_id"]
      result_bytes = read_private(File.join(path, "result.json"), max_bytes: Host::MAX_RESULT_BYTES)
      fail!("Host result bytes changed after completion") unless Digest::SHA256.hexdigest(result_bytes) == completion["result_sha256"]
      Host.validate_result!(JSON.parse(result_bytes), role: status.fetch("role"))
    rescue JSON::ParserError => error
      fail!("invalid completed Host result: #{error.message}")
    end

    def request_record(source)
      body = {
        "schema_version" => SCHEMA_VERSION,
        "source_state_dir" => @source,
        "destination_state_dir" => @destination,
        "source_run_id" => source.dig("config", "run_id"),
        "new_run_id" => @new_run_id,
        "source_kernel_root" => @source_kernel_root,
        "source_kernel_version" => SOURCE_KERNEL_VERSION,
        "source_kernel_revision" => source.fetch("source_kernel_revision"),
        "target_kernel_root" => source.fetch("target_kernel_root"),
        "target_kernel_revision" => source.fetch("target_kernel_revision"),
        "target_kernel_version" => TARGET_KERNEL_VERSION,
        "target_version_verified" => source.fetch("target_version_verified"),
        "target_checkout_clean" => source.fetch("target_checkout_clean"),
        "production" => @production,
        "controller_stopped" => true,
        "supervisor_provenance" => @supervisor_provenance,
        "source_tree_sha256" => source.dig("tree", "sha256"),
        "source_cursor" => source.dig("store", "cursor"),
        "source_event_hash" => source.dig("store", "event_hash"),
        "legacy_controller_limit" => "The source Driver lock and explicit supervisor assertion establish the observed stop. This API cannot prove that an unrecorded legacy controller will not restart; both state roots are denied to new model jobs."
      }
      body.merge("request_sha256" => digest(body))
    end

    def copy_tree(source, destination)
      Dir.mkdir(destination, 0o700)
      snapshot = snapshot_tree(source)
      snapshot.fetch("entries").each do |entry|
        relative = entry.fetch("path")
        from = File.join(source, relative)
        to = File.join(destination, relative)
        if entry["type"] == "directory"
          FileUtils.mkdir_p(to, mode: 0o700)
          File.chmod(0o700, to)
        else
          FileUtils.mkdir_p(File.dirname(to), mode: 0o700)
          bytes = read_private(from)
          fail!("source file changed while copying: #{relative}") unless bytes.bytesize == entry["bytes"] &&
            Digest::SHA256.hexdigest(bytes) == entry["sha256"]
          Host.atomic_write(to, bytes)
        end
      end
    end

    def derive_destination!(root, source, request)
      continuation = File.join(root, CONTINUATION_DIRECTORY)
      Host.private_directory!(continuation)
      Host.atomic_write(File.join(continuation, "source-config.json"), source.fetch("config_bytes"))
      Host.atomic_write(File.join(continuation, "source-runtime.json"), source.fetch("runtime_bytes"))
      Host.atomic_write(File.join(continuation, "source-preflight.json"), source.fetch("preflight_bytes"))
      Host.atomic_json(File.join(continuation, "source-manifest.json"), source.fetch("tree"))

      config = JSON.parse(source.fetch("config_bytes"))
      config["run_id"] = @new_run_id
      config["forbidden_roots"] = (Array(config["forbidden_roots"]) + [@source, @destination]).uniq
      config["continuation"] = request.slice(
        "schema_version", "source_state_dir", "source_run_id", "source_kernel_revision",
        "source_kernel_version", "target_kernel_revision", "target_kernel_version", "source_tree_sha256", "source_cursor",
        "source_event_hash", "request_sha256"
      )

      runtime = JSON.parse(source.fetch("runtime_bytes"))
      resume_job = safe_astra_resume_job(source.fetch("statuses"), runtime)
      runtime.delete("pending_dispatch")
      runtime.delete("pending_job_registration")
      runtime["orchestrator_job"] = nil
      runtime["resume_job"] = resume_job
      runtime["observed_cursor"] = source.dig("store", "cursor")
      runtime["observed_technical_input_cursor"] = 0
      runtime["feedback"] = [continuation_notice(request, resume_job)] + Array(runtime["feedback"])
      runtime["outcome"] = "active" if runtime["outcome"] == "engineering_stalled"
      runtime["continuation"] = request.slice("schema_version", "source_state_dir", "source_run_id", "request_sha256")

      Host.atomic_json(File.join(root, "driver", "config.json"), config)
      Host.atomic_json(File.join(root, "driver", "runtime.json"), runtime)
    end

    # Preflight identity intentionally excludes the state root: descriptors are
    # relative, and the copied receipt key authenticates the unchanged receipt.
    # Reverify the historical evidence under the destination policy. Do not call
    # Execution#preflight and mislabel its deterministic reuse as a fresh check.
    def reverify_target_preflight!(root, config)
      sentinel = File.join(root, "driver", "isolation-sentinel.txt")
      execution = Execution.new(
        project_root: config.fetch("project_root"), state_dir: root,
        read_roots: config.fetch("read_roots", []),
        environment_allowlist: config.fetch("environment_allowlist", []),
        forbidden_read_path: sentinel, forbidden_write_path: sentinel
      )
      receipts = parse_array(read_private(File.join(root, "driver", "preflight.json")), "continued Driver preflight")
      fail!("continued Driver preflight set changed") unless receipts.map { |entry| entry["id"] } ==
        config.fetch("preflight_checks").map { |spec| spec["id"] }
      receipts.zip(config.fetch("preflight_checks")).each do |entry, spec|
        descriptor = entry.fetch("execution").slice("receipt_path", "receipt_sha256")
        receipt = execution.verify_preflight!(descriptor, spec: spec)
        fail!("continued Driver historical preflight did not pass re-verification") unless receipt["conclusion"] == "passed"
      end
      true
    rescue KeyError => error
      fail!("continued Driver preflight is incomplete: #{error.message}")
    end

    def finalize_destination!(root, source, request)
      resume_job = safe_astra_resume_job(source.fetch("statuses"), source.fetch("runtime"))
      manifest = request.merge(
        "created_at" => Time.now.utc.iso8601(6),
        "source_manifest_path" => File.join(CONTINUATION_DIRECTORY, "source-manifest.json"),
        "source_config_sha256" => Digest::SHA256.hexdigest(source.fetch("config_bytes")),
        "source_runtime_sha256" => Digest::SHA256.hexdigest(source.fetch("runtime_bytes")),
        "source_preflight_sha256" => Digest::SHA256.hexdigest(source.fetch("preflight_bytes")),
        "target_config_sha256" => Digest::SHA256.file(File.join(root, "driver", "config.json")).hexdigest,
        "target_runtime_sha256" => Digest::SHA256.file(File.join(root, "driver", "runtime.json")).hexdigest,
        "target_preflight_sha256" => Digest::SHA256.file(File.join(root, "driver", "preflight.json")).hexdigest,
        "resumed_astra_job_id" => resume_job,
        "resumed_astra_thread_id" => resume_job && source.dig("statuses", resume_job, "thread_id"),
        "ledger_copied_unchanged" => true,
        "historical_receipts_copied_unchanged" => true,
        "source_preflight_is_historical" => true,
        "target_preflight_is_fresh" => false,
        "target_preflight_reverified_for_destination" => true,
        "fresh_orchestrator_projection_required" => true
      )
      Host.atomic_json(File.join(root, MANIFEST_PATH), manifest)
      private_tree!(root)
    end

    def safe_astra_resume_job(statuses, runtime)
      candidates = [runtime["orchestrator_job"], runtime["resume_job"]].compact.uniq
      candidates.each do |job_id|
        status = statuses[job_id]
        next unless status && status["role"] == "orchestrator" &&
          %w[succeeded failed].include?(status["status"]) && status["thread_id"] && Host::UUID.match?(status["thread_id"])
        return job_id
      end
      nil
    end

    def continuation_notice(request, resume_job)
      {
        "kind" => "versioned_run_continuation",
        "ok" => true,
        "message" => "RC36 continuation: project the copied ledger and receipts afresh. Do not replay requests from any copied Astra result. Preserve operator decisions, authority, work state, and consumed turn budget.",
        "source_run_id" => request["source_run_id"],
        "source_kernel_version" => request["source_kernel_version"],
        "source_kernel_revision" => request["source_kernel_revision"],
        "target_kernel_revision" => request["target_kernel_revision"],
        "resume_job_id" => resume_job
      }
    end

    def verify_idempotent_destination!(request)
      path = File.join(@destination, MANIFEST_PATH)
      fail!("destination already exists and is not this continuation") unless File.file?(path) && !File.symlink?(path)
      manifest = parse_object(read_private(path), "continuation manifest")
      unless manifest["request_sha256"] == request["request_sha256"]
        changed = request.keys.reject { |key| key == "request_sha256" || manifest[key] == request[key] }
        fail!("destination already exists for a conflicting continuation (changed: #{changed.sort.join(', ')})")
      end
      verify_manifest_files!(@destination, manifest)
      Store.new(@destination).verify!
      manifest
    end

    def verify_created_destination!(request)
      manifest = verify_idempotent_destination!(request)
      Store.new(@destination).verify!
      manifest
    end

    def verify_manifest_files!(root, manifest)
      checks = {
        File.join("driver", "continuation", "source-config.json") => manifest["source_config_sha256"],
        File.join("driver", "continuation", "source-runtime.json") => manifest["source_runtime_sha256"],
        File.join("driver", "continuation", "source-preflight.json") => manifest["source_preflight_sha256"],
        File.join("driver", "config.json") => manifest["target_config_sha256"],
        File.join("driver", "runtime.json") => manifest["target_runtime_sha256"],
        File.join("driver", "preflight.json") => manifest["target_preflight_sha256"]
      }
      checks.each do |relative, expected|
        fail!("continuation manifest is incomplete") unless expected.is_a?(String) && /\A[0-9a-f]{64}\z/.match?(expected)
        bytes = read_private(File.join(root, relative))
        fail!("continued state differs from its manifest: #{relative}") unless Digest::SHA256.hexdigest(bytes) == expected
      end
      source_manifest = parse_object(
        read_private(File.join(root, manifest.fetch("source_manifest_path"))),
        "source tree manifest"
      )
      manifest_digest = source_manifest.fetch("sha256")
      fail!("source tree manifest attribution changed") unless manifest_digest == manifest["source_tree_sha256"] &&
        digest(source_manifest.reject { |key, _value| key == "sha256" }) == manifest_digest
      source_manifest.fetch("entries").each do |entry|
        next unless entry["type"] == "file"
        relative = entry.fetch("path")
        target = case relative
                 when File.join("driver", "config.json")
                   File.join(root, CONTINUATION_DIRECTORY, "source-config.json")
                 when File.join("driver", "runtime.json")
                   File.join(root, CONTINUATION_DIRECTORY, "source-runtime.json")
                 when File.join("driver", "preflight.json")
                   File.join(root, CONTINUATION_DIRECTORY, "source-preflight.json")
                 else File.join(root, relative)
                 end
        bytes = read_private(target)
        fail!("historical continued evidence changed: #{relative}") unless bytes.bytesize == entry["bytes"] &&
          Digest::SHA256.hexdigest(bytes) == entry["sha256"]
      end
    rescue KeyError => error
      fail!("continuation manifest is incomplete: #{error.message}")
    end

    def verify_source_unchanged!(expected)
      actual = snapshot_tree(@source)
      fail!("source state changed while it was being copied") unless actual == expected
    end

    def snapshot_tree(root)
      entries = []
      total = 0
      walk(root) do |path, relative, stat|
        fail!("state tree has too many entries") if entries.length >= MAX_ENTRIES
        if stat.directory?
          entries << { "path" => relative, "type" => "directory" } unless relative.empty?
        elsif stat.file?
          fail!("state file is not private: #{relative}") unless (stat.mode & 0o077).zero?
          fail!("state file exceeds continuation bound: #{relative}") if stat.size > MAX_FILE_BYTES
          total += stat.size
          fail!("state tree exceeds continuation byte bound") if total > MAX_TOTAL_BYTES
          entries << { "path" => relative, "type" => "file", "bytes" => stat.size,
                       "sha256" => Digest::SHA256.file(path).hexdigest }
        else
          fail!("state tree contains a symlink or special file: #{relative}")
        end
      end
      body = { "entries" => entries, "file_count" => entries.count { |item| item["type"] == "file" }, "total_bytes" => total }
      body.merge("sha256" => digest(body))
    end

    def walk(root, relative = "", &block)
      path = relative.empty? ? root : File.join(root, relative)
      stat = File.lstat(path)
      fail!("state tree contains a symlink: #{relative}") if stat.symlink?
      yield(path, relative, stat)
      return unless stat.directory?
      fail!("state directory is not private: #{relative}") unless (stat.mode & 0o077).zero?
      Dir.children(path).sort.each { |name| walk(root, relative.empty? ? name : File.join(relative, name), &block) }
    end

    def private_tree!(root)
      walk(root) do |path, _relative, stat|
        File.chmod(stat.directory? ? 0o700 : 0o600, path)
      end
    end

    def verify_git_checkout!(root, expected: nil, require_clean:, scope:)
      top = git(root, "rev-parse", "--show-toplevel").strip
      fail!("#{scope} root is not the Git top-level") unless File.realpath(top) == root
      revision = git(root, "rev-parse", "HEAD").strip
      fail!("#{scope} revision is not a full commit") unless GIT_REVISION.match?(revision)
      fail!("#{scope} does not match the declared revision") if expected && revision != expected
      status = git(root, "status", "--porcelain=v1", "--untracked-files=all")
      clean = status.empty?
      fail!("#{scope} checkout must be clean") if require_clean && !clean
      expected || { "revision" => revision, "clean" => clean }
    end

    def verify_source_kernel_version!(revision)
      playbook = git(@source_kernel_root, "show", "#{revision}:playbooks/hrm-interaction-kernel.md")
      expected = "title: #{SOURCE_KERNEL_VERSION}"
      fail!("declared source pin is not #{SOURCE_KERNEL_VERSION}") unless playbook.lines.first(12).any? { |line| line.start_with?(expected) }
    end

    def verify_target_kernel_version!(root, revision, required:)
      playbook = git(root, "show", "#{revision}:playbooks/hrm-interaction-kernel.md")
      expected = "title: #{TARGET_KERNEL_VERSION}"
      verified = playbook.lines.first(12).any? { |line| line.start_with?(expected) }
      fail!("executing target commit does not declare #{TARGET_KERNEL_VERSION}") if required && !verified
      verified
    end

    def git(root, *args)
      stdout, stderr, status = Open3.capture3("git", "-C", root, *args)
      fail!("cannot verify Git checkout: #{stderr.strip}") unless status.success?
      stdout
    end

    def canonical_existing_directory(value, label)
      fail!("#{label} must be an absolute path") unless value.is_a?(String) && Pathname.new(value).absolute?
      fail!("#{label} itself may not be a symlink") if File.symlink?(value)
      resolved = File.realpath(value)
      fail!("#{label} must be a directory") unless File.directory?(resolved)
      resolved
    rescue SystemCallError => error
      fail!("cannot resolve #{label}: #{error.message}")
    end

    def canonical_destination(value)
      fail!("destination state directory must be an absolute path") unless value.is_a?(String) && Pathname.new(value).absolute?
      expanded = File.expand_path(value)
      fail!("destination state directory itself may not be a symlink") if File.symlink?(expanded)
      return File.realpath(expanded) if File.exist?(expanded)
      ancestor = expanded
      until File.exist?(ancestor)
        parent = File.dirname(ancestor)
        fail!("cannot resolve destination parent") if parent == ancestor
        ancestor = parent
      end
      File.join(File.realpath(ancestor), Pathname.new(expanded).relative_path_from(Pathname.new(ancestor)).to_s)
    rescue SystemCallError, ArgumentError => error
      fail!("cannot resolve destination state directory: #{error.message}")
    end

    def ensure_private_directory(path, label)
      fail!("#{label} is a symlink") if File.symlink?(path)
      stat = File.stat(path)
      fail!("#{label} must be a private directory") unless stat.directory? && (stat.mode & 0o077).zero?
    rescue SystemCallError => error
      fail!("cannot read #{label}: #{error.message}")
    end

    def read_private(path, max_bytes: MAX_FILE_BYTES)
      fail!("unsafe symlink file: #{path}") if File.symlink?(path)
      stat = File.stat(path)
      fail!("expected a private regular file: #{path}") unless stat.file? && (stat.mode & 0o077).zero?
      fail!("file exceeds continuation bound: #{path}") if stat.size > max_bytes
      File.binread(path)
    rescue SystemCallError => error
      fail!("cannot read continuation input: #{error.message}")
    end

    def parse_object(bytes, label)
      value = JSON.parse(bytes)
      fail!("#{label} must be an object") unless value.is_a?(Hash)
      value
    rescue JSON::ParserError => error
      fail!("#{label} is invalid JSON: #{error.message}")
    end

    def parse_array(bytes, label)
      value = JSON.parse(bytes)
      fail!("#{label} must be an array") unless value.is_a?(Array)
      value
    rescue JSON::ParserError => error
      fail!("#{label} is invalid JSON: #{error.message}")
    end

    def string_array?(value)
      value.is_a?(Array) && value.all? { |item| item.is_a?(String) && Host::IDENTIFIER.match?(item) }
    end

    def beneath?(path, root)
      path == root || path.start_with?(root + File::SEPARATOR)
    end

    def digest(value)
      Digest::SHA256.hexdigest(JSON.generate(canonical(value)))
    end

    def canonical(value)
      case value
      when Hash then value.keys.sort.to_h { |key| [key, canonical(value.fetch(key))] }
      when Array then value.map { |item| canonical(item) }
      else value
      end
    end

    def fsync_directory(path)
      File.open(path, File::RDONLY) { |directory| directory.fsync }
    rescue Errno::EINVAL, Errno::EISDIR
      nil
    end

    def fail!(message)
      raise HrmKernel::Error, message
    end
  end
end
