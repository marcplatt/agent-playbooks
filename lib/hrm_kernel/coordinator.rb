# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "open3"
require_relative "host"
require_relative "execution"

module HrmKernel
  # Trusted host glue: consumes persisted jobs and native receipts, never a
  # model-written assertion that a command passed. Human decisions use the
  # operator command boundary; this class cannot manufacture acceptance.
  class Coordinator
    REPORT_DIRECTORY = ".codex/hrm-runs/native-checks"

    def initialize(state_dir:, host: nil)
      @store = Store.new(state_dir)
      @host = host || Host.new(state_dir: state_dir)
      @directory = File.join(@store.directory, "coordinator")
      Host.private_directory!(@directory)
    end

    def check(input)
      exact_input!(input, %w[job_id check_id])
      state = implementation_state!
      existing_path = check_path(input.fetch("job_id"), input.fetch("check_id"))
      existing = File.exist?(existing_path) && read_record(existing_path)
      refreshable = existing && existing["worker_disposition"] == "implemented" &&
                    existing["classification"] == "completion_evidence"
      job = refreshable && refresh_job(existing["refresh_context"], state, input.fetch("check_id"))
      unless job
        context = @host.check_context(job_id: input.fetch("job_id"), check_id: input.fetch("check_id"))
        job = context.fetch("job")
        collected = @host.collect(job_id: job.fetch("job_id"))
        disposition = collected.dig("result", "status")
        fail!("only a completed worker may run its frozen checks") unless job["role"] == "worker" && %w[implemented blocked].include?(disposition)
      end
      disposition ||= "implemented"
      classification = disposition == "implemented" ? "completion_evidence" : "diagnostic_evidence"
      spec = Array(job.fetch("check_plan").fetch("checks")).find { |entry| entry["id"] == input.fetch("check_id") }
      fail!("check_id is not uniquely declared in the frozen plan") unless spec && job.fetch("check_plan").fetch("checks").count { |entry| entry["id"] == input.fetch("check_id") } == 1
      order = state.fetch("work_orders").fetch(job.fetch("work_order_id"))
      runner = execution(job)
      candidate = runner.capture_candidate(
        work_order: order, milestone: state.fetch("milestone"), claim_id: job.fetch("claim_id"),
        revision: job.fetch("revision"), requirement_revisions: order.fetch("requirement_revisions"),
        check_plan: job.fetch("check_plan"), authorized_paths: authorized_paths(state)
      )
      outcome = runner.run(spec: spec, binding: candidate.fetch("binding"), candidate: candidate)
      record = { "job_id" => job["job_id"], "check_id" => input["check_id"],
                 "candidate" => candidate, "execution" => descriptor(outcome), "conclusion" => outcome["conclusion"],
                 "worker_disposition" => disposition, "classification" => classification,
                 "refresh_context" => refresh_context(job) }
      Host.atomic_json(check_path(job["job_id"], input["check_id"]), record)
      record.slice("job_id", "check_id", "conclusion", "execution", "worker_disposition", "classification")
            .merge("candidate_digest" => candidate["candidate_digest"], "reused" => outcome["reused"])
    end

    def submit(input)
      exact_input!(input, %w[job_id])
      id = identifier!(input.fetch("job_id"))
      persisted = File.join(@directory, "submit-#{id}.json")
      state = implementation_state!
      if File.exist?(persisted)
        prior = read_record(persisted)
        begin
          Evidence.verify_completed_work!(state, state_dir: @store.directory)
          return @store.transact(prior)
        rescue HrmKernel::Error
          # A changed full candidate needs fresh checks and an evidence refresh.
        end
      end
      job = nil
      if File.exist?(persisted)
        work_order_id = read_record(persisted).dig("data", "work_order_id")
        order = state.fetch("work_orders").fetch(work_order_id)
        if order["status"] == "completed"
          first_check = order.fetch("check_ids").first
          record = read_record(check_path(id, first_check))
          job = refresh_job(record["refresh_context"], state, first_check)
          fail!("completed work requires fresh native check records") unless job
        end
      end
      unless job
        job = @host.job_record(job_id: id)
        collected = @host.collect(job_id: id)
        fail!("only an implemented worker can submit") unless job["role"] == "worker" && collected.dig("result", "status") == "implemented"
      end
      order = state.fetch("work_orders").fetch(job.fetch("work_order_id"))
      runner = execution(job)
      records = order.fetch("check_ids").map { |check_id| read_record(check_path(id, check_id)) }
      fail!("checks were not run against the same candidate") unless records.map { |record| record.dig("candidate", "candidate_digest") }.uniq.length == 1
      records.each do |record|
        fail!("check record belongs to another job") unless record["job_id"] == id
        fail!("diagnostic check cannot support submission") unless record["worker_disposition"] == "implemented" && record["classification"] == "completion_evidence"
        receipt = runner.verify_receipt!(record.fetch("execution"), candidate: record.fetch("candidate"), current_exact: true)
        fail!("native check has not passed") unless receipt["conclusion"] == "passed"
      end
      candidate = records.first.fetch("candidate")
      artifacts = candidate.fetch("changes").select { |entry| order.fetch("paths").include?(entry["path"]) }
                           .map do |entry|
        sha = entry["status"] == "D" ? Digest::SHA256.hexdigest("deleted\0#{entry.fetch('path')}") : entry.fetch("sha256")
        { "path" => entry.fetch("path"), "sha256" => sha }
      end
      if order["status"] == "completed"
        fail!("evidence refresh cannot change the completed order's artifacts") unless order.fetch("artifacts") == artifacts
      else
        fail!("work order is not running") unless order["status"] == "running"
      end
      root = state.fetch("milestone").fetch("project_root")
      checks = records.map do |record|
        check_id = identifier!(record.fetch("check_id"))
        relative = "#{REPORT_DIRECTORY}/#{id}-#{check_id}-#{candidate.fetch('candidate_digest')}.json"
        ignored_report_path!(root, relative)
        report = { "check_id" => check_id, "conclusion" => "passed", "work_order_id" => order["id"],
                   "revision" => order["revision"], "artifacts" => artifacts, "execution" => record.fetch("execution") }
        path = File.join(root, relative)
        FileUtils.mkdir_p(File.dirname(path), mode: 0o700)
        Host.atomic_json(path, report)
        { "id" => check_id, "conclusion" => "passed", "artifact_path" => relative, "sha256" => Digest::SHA256.file(path).hexdigest }
      end
      submit_command = {
        "command_id" => "native-submit-#{id}", "type" => "work_order.submit",
        "actor" => { "role" => "worker", "id" => job.fetch("actor_id") },
        "data" => { "work_order_id" => order["id"], "revision" => order["revision"],
                    "claim_id" => job.fetch("claim_id"), "artifacts" => artifacts, "checks" => checks }
      }
      if order["status"] == "completed"
        if File.exist?(persisted) && read_record(persisted) == submit_command
          return @store.transact(submit_command)
        end
        refresh_command = submit_command.merge(
          "command_id" => "native-refresh-#{id}-#{candidate.fetch('candidate_digest')}",
          "type" => "work_order.refresh_evidence"
        )
        refresh_path = File.join(@directory, "refresh-#{id}-#{candidate.fetch('candidate_digest')}.json")
        if File.exist?(refresh_path)
          fail!("persisted evidence refresh does not match current evidence") unless read_record(refresh_path) == refresh_command
        else
          Host.atomic_json(refresh_path, refresh_command)
        end
        return @store.transact(read_record(refresh_path))
      end

      # Persist before append, making a crash after the append safely replayable.
      if File.exist?(persisted)
        fail!("persisted submission does not match current evidence") unless read_record(persisted) == submit_command
      else
        Host.atomic_json(persisted, submit_command)
      end
      @store.transact(read_record(persisted))
    end

    def assess(input)
      exact_input!(input, %w[job_id])
      id = identifier!(input.fetch("job_id"))
      job = @host.job_record(job_id: id)
      collected = @host.collect(job_id: id)
      fail!("assessment requires an independent completed reviewer") unless job["role"] == "reviewer" && collected.dig("result", "status") == "reviewed"
      state = implementation_state!
      Evidence.verify_completed_work!(state, state_dir: @store.directory)
      candidate = State.project(state, role: "orchestrator").dig("milestone", "current_candidate")
      fail!("reviewer has no completed current candidate") unless candidate
      actor = { "role" => "reviewer", "id" => job.fetch("actor_id") }
      scenarios = state.fetch("milestone").fetch("acceptance_scenarios")
      dispositions = collected.fetch("result").fetch("scenario_dispositions")
      fail!("reviewer must disposition every scenario exactly once") unless dispositions.map { |entry| entry["scenario_id"] }.sort == scenarios.keys.sort
      errors = collected.dig("result", "findings").select { |finding| finding["severity"] == "error" }
      errors.each do |finding|
        ids = finding.fetch("scenario_ids")
        unless !ids.empty? && (ids - scenarios.keys).empty? && ids.all? { |scenario_id| dispositions.any? { |entry| entry["scenario_id"] == scenario_id && entry["status"] != "passed" } }
          fail!("every reviewer error finding must bind explicitly to failed or pending scenarios")
        end
      end
      mapped = dispositions.map do |entry|
        scenario = scenarios.fetch(entry.fetch("scenario_id"))
        refs = evidence_refs(state, scenario)
        finding_ids = []
        unless entry["status"] == "passed"
          finding_id = "#{id}-#{entry['scenario_id']}"
          @store.transact(
            "command_id" => "raise-#{finding_id}", "type" => "finding.raise", "actor" => actor,
            "data" => { "finding_id" => finding_id, "candidate_digest" => candidate["candidate_digest"],
                        "requirement_ids" => scenario.fetch("requirement_ids"), "text" => entry.fetch("evidence"), "evidence_refs" => refs }
          )
          finding_ids << finding_id
          errors.each_with_index do |finding, index|
            next unless finding.fetch("scenario_ids").include?(entry["scenario_id"])
            explicit_id = "#{id}-#{entry['scenario_id']}-error-#{index}"
            @store.transact(
              "command_id" => "raise-#{explicit_id}", "type" => "finding.raise", "actor" => actor,
              "data" => { "finding_id" => explicit_id, "candidate_digest" => candidate["candidate_digest"],
                          "requirement_ids" => scenario.fetch("requirement_ids"), "text" => finding.fetch("message"), "evidence_refs" => refs }
            )
            finding_ids << explicit_id
          end
        end
        { "scenario_id" => entry["scenario_id"], "disposition" => entry["status"] == "passed" ? "accepted" : "changes_requested",
          "evidence_refs" => refs, "finding_ids" => finding_ids }
      end
      @store.transact(
        "command_id" => "assess-#{id}", "type" => "milestone.assess", "actor" => actor,
        "data" => { "assessment_id" => id, "candidate_digest" => candidate["candidate_digest"], "scenario_dispositions" => mapped }
      )
    end

    private

    def implementation_state!
      state = @store.read.fetch("state")
      fail!("native coordination requires implementation mode") unless state && state.dig("milestone", "mode") == "implementation"
      state
    end

    def refresh_context(job)
      job.slice(
        "job_id", "role", "actor_id", "work_order_id", "claim_id", "revision", "project_root",
        "check_plan", "execution_read_roots", "execution_environment_allowlist"
      )
    end

    def refresh_job(context, state, check_id)
      return nil unless context.is_a?(Hash)
      required = %w[job_id role actor_id work_order_id claim_id revision project_root check_plan execution_read_roots execution_environment_allowlist]
      fail!("native check refresh context is malformed") unless context.keys.sort == required.sort
      order = state.fetch("work_orders")[context["work_order_id"]]
      return nil unless order && order["status"] == "completed"
      valid = context["role"] == "worker" && context["actor_id"] == order["last_owner_id"] &&
              context["revision"] == order["revision"] && context["claim_id"] == order.fetch("claim_history").last &&
              context["project_root"] == state.dig("milestone", "project_root") &&
              Array(context.dig("check_plan", "checks")).count { |entry| entry["id"] == check_id } == 1
      fail!("native check refresh context is stale") unless valid
      context
    end

    def execution(job)
      sentinel = File.join(@directory, "isolation-sentinel.txt")
      Host.atomic_write(sentinel, "Harmless RC34 isolation probe.\n") unless File.exist?(sentinel)
      Execution.new(project_root: job.fetch("project_root"), state_dir: @store.directory,
                    read_roots: job.fetch("execution_read_roots"), environment_allowlist: job.fetch("execution_environment_allowlist"),
                    forbidden_read_path: sentinel, forbidden_write_path: sentinel)
    end

    def authorized_paths(state)
      state.fetch("work_orders").values.reject { |order| order["status"] == "cancelled" }.flat_map { |order| order.fetch("paths") }.uniq
    end

    def evidence_refs(state, scenario)
      state.fetch("work_orders").values.each_with_object([]) do |order, refs|
        checks = order.fetch("check_ids") & scenario.fetch("check_ids")
        next if checks.empty? || order["status"] != "completed"
        refs << { "work_order_id" => order["id"], "revision" => order["revision"], "check_ids" => checks }
      end
    end

    def ignored_report_path!(root, relative)
      current = root
      relative.split("/").each do |part|
        current = File.join(current, part)
        fail!("check report path may not contain a symlink") if File.symlink?(current)
      end
      _output, status = Open3.capture2e("git", "-C", root, "check-ignore", "--quiet", "--", relative)
      fail!("native reports must be ignored by the candidate repository: #{REPORT_DIRECTORY}") unless status.success?
    end

    def descriptor(outcome)
      outcome.slice("receipt_path", "receipt_sha256")
    end

    def check_path(job_id, check_id)
      File.join(@directory, "check-#{identifier!(job_id)}-#{identifier!(check_id)}.json")
    end

    def read_record(path)
      JSON.parse(Host.read_private(path, max_bytes: 8 * 1024 * 1024))
    rescue Errno::ENOENT
      fail!("required native check record is missing")
    end

    def exact_input!(input, keys)
      fail!("input must contain exactly #{keys.join(', ')}") unless input.is_a?(Hash) && input.keys.sort == keys.sort
    end

    def identifier!(value)
      fail!("invalid host identifier") unless value.is_a?(String) && Host::IDENTIFIER.match?(value)
      value
    end

    def fail!(message)
      raise HrmKernel::Error.new("invalid_native_coordination", message)
    end
  end
end
