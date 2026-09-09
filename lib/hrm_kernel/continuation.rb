# frozen_string_literal: true

require_relative "error"

module HrmKernel
  # Produces bounded orchestration advice from Host evidence. It does not mutate
  # kernel state, interpret prose as authority, or decide how work is decomposed.
  class Continuation
    SCHEMA_VERSION = "ap-hrm-continuation-advice/1"
    TERMINAL_HOST_STATUSES = %w[succeeded failed launch_unknown].freeze
    ACTIVE_HOST_STATUSES = %w[queued running].freeze
    RESULT_STATUSES = %w[implemented blocked reviewed].freeze
    def self.advise(host_status:, collected:, history:, work_order:, declared_dependencies: [], pending_decisions: [])
      new(host_status: host_status, collected: collected, history: history, work_order: work_order,
          declared_dependencies: declared_dependencies, pending_decisions: pending_decisions).advise
    end

    def initialize(host_status:, collected:, history:, work_order:, declared_dependencies:, pending_decisions:)
      @host_status = hash!(host_status, "host_status")
      @collected = collected.nil? ? nil : hash!(collected, "collected")
      @history = array!(history, "history")
      @order = hash!(work_order, "work_order")
      @dependencies = array!(declared_dependencies, "declared_dependencies")
      @decisions = array!(pending_decisions, "pending_decisions")
      validate_order!
    end

    def advise
      return advice("wait", "host_active") if ACTIVE_HOST_STATUSES.include?(@host_status["status"])

      unless TERMINAL_HOST_STATUSES.include?(@host_status["status"])
        fail!("host_status has an unsupported status")
      end
      unless @host_status["status"] == "succeeded"
        action = @host_status["failure_kind"] == "service_failure" ? "retry_service" : "orchestrator_triage"
        reason = action == "retry_service" ? "verified_service_failure" : "host_process_failure"
        return advice(action, reason, service_details(@host_status))
      end
      return advice("discard_stale", "stale_claim") unless current_binding?(@host_status)

      fail!("successful host status requires a collection") unless @collected
      job = hash!(@collected["job"], "collected.job")
      return advice("discard_stale", "stale_claim") unless current_binding?(job) && job["claim_current"] != false

      result = hash!(@collected["result"], "collected.result")
      fail!("invalid result status") unless RESULT_STATUSES.include?(result["status"])
      @current_job = job
      @result = result
      @matching_history = matching_history

      dependency = current_sources(@dependencies).find { |entry| entry["status"] == "pending" }
      return advice("await_dependency", "declared_dependency", dependency.slice("id", "status", "detail")) if dependency
      decision = current_sources(@decisions).find { |entry| entry["status"] == "unanswered" && entry["source"].is_a?(Hash) }
      return advice("request_operator_decision", "declared_operator_decision_unanswered", decision.slice("id", "status", "source")) if decision

      case result["status"]
      when "implemented"
        scenarios = scenario_counts(result)
        if scenarios["failed"].positive?
          advice("continue_engineering", "implemented_scenarios_incomplete")
        else
          # Workers cannot run trusted checks. Pending verification alone is not
          # evidence that another implementation turn is needed.
          reason = scenarios["pending"].positive? ? "implemented_scenarios_unverified" : "implementation_reported_checks_required"
          advice("run_checks", reason)
        end
      when "blocked"
        repeated_action("blocked_engineering")
      when "reviewed"
        advice("run_checks", "review_result_requires_orchestrator_handling")
      end
    end

    private

    def advice(action, reason_code, details = {})
      result = @result || {}
      current_job = @current_job || @host_status
      history = @matching_history || matching_history
      {
        "schema_version" => SCHEMA_VERSION,
        "action" => action,
        "reason_code" => reason_code,
        "binding" => binding(current_job),
        "assigned_deliverable" => {
          "objective" => @order["objective"],
          "requirement_revisions" => @order["requirement_revisions"].dup,
          "paths" => @order["paths"].dup,
          "check_ids" => @order["check_ids"].dup
        },
        "observed_changed_paths" => strings(result_from_collection("observed_changed_paths")),
        "reported_changed_paths" => strings(result["changed_paths"]),
        "cumulative_reported_changed_paths" => history.flat_map { |entry| history_result(entry)["changed_paths"] || [] }.select { |path| path.is_a?(String) }.uniq.sort,
        "attempts" => history.length,
        "scenario_counts" => scenario_counts(result),
        "details" => details
      }
    end

    def repeated_action(reason)
      attempts = @matching_history
      no_progress = attempts.count { |entry| observed_paths(entry).empty? }
      partial = attempts.count { |entry| !observed_paths(entry).empty? && history_result(entry)["status"] == "blocked" }
      if no_progress >= 2
        advice("decompose_engineering", "repeated_no_progress", "suggestion" => "assign a smaller bounded unit to Astra")
      elsif partial >= 2
        advice("decompose_engineering", "repeated_partial_progress", "suggestion" => "assign the remaining deliverable as smaller bounded units to Astra")
      else
        advice("continue_engineering", reason)
      end
    end

    def current_sources(entries)
      entries.select { |entry| entry.is_a?(Hash) && current_binding?(entry) }
    end

    def matching_history
      collections = @history.each_with_object([]) do |entry, matches|
        next unless entry.is_a?(Hash)
        collection = entry["collected"].is_a?(Hash) ? entry["collected"] : entry
        job = collection["job"] || entry["host_status"] || collection
        matches << collection if current_binding?(job) && job["claim_current"] != false
      end
      if @collected && current_binding?(@collected["job"])
        current_id = @collected.dig("job", "job_id")
        collections << @collected unless collections.any? { |entry| entry.dig("job", "job_id") == current_id }
      end
      collections
    end

    def current_binding?(source)
      source.is_a?(Hash) && source["work_order_id"] == @order["id"] &&
        source["revision"] == @order["revision"] && source["claim_id"] == @order["claim_id"]
    end

    def binding(source)
      {
        "job_id" => source["job_id"], "work_order_id" => source["work_order_id"],
        "revision" => source["revision"], "claim_id" => source["claim_id"]
      }
    end

    def history_result(entry)
      value = entry["result"]
      value.is_a?(Hash) ? value : {}
    end

    def observed_paths(entry)
      strings(entry["observed_changed_paths"])
    end

    def result_from_collection(key)
      @collected && @collected[key]
    end

    def scenario_counts(result)
      counts = { "passed" => 0, "failed" => 0, "pending" => 0 }
      Array(result["scenario_dispositions"]).each do |item|
        counts[item["status"]] += 1 if item.is_a?(Hash) && counts.key?(item["status"])
      end
      counts
    end

    def service_details(status)
      details = {}
      details["failure_kind"] = status["failure_kind"] if status["failure_kind"].is_a?(String)
      details["failure_code"] = status["failure_code"] if status["failure_code"].is_a?(String)
      details
    end

    def validate_order!
      %w[id objective claim_id].each { |key| fail!("work_order.#{key} is required") unless @order[key].is_a?(String) && !@order[key].empty? }
      fail!("work_order.revision must be an integer") unless @order["revision"].is_a?(Integer)
      fail!("work_order.requirement_revisions must be an object") unless @order["requirement_revisions"].is_a?(Hash)
      %w[paths check_ids].each { |key| fail!("work_order.#{key} must be strings") unless strings?(@order[key]) }
    end

    def strings(value)
      value.is_a?(Array) ? value.select { |item| item.is_a?(String) }.uniq.sort : []
    end

    def strings?(value)
      value.is_a?(Array) && value.all? { |item| item.is_a?(String) }
    end

    def hash!(value, name)
      fail!("#{name} must be an object") unless value.is_a?(Hash)
      value
    end

    def array!(value, name)
      fail!("#{name} must be an array") unless value.is_a?(Array)
      value
    end

    def fail!(message)
      raise Error.new("invalid_continuation_input", message)
    end
  end
end
