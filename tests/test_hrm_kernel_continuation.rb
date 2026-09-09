# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/hrm_kernel/continuation"

class HrmKernelContinuationTest < Minitest::Test
  def test_active_job_waits
    assert_equal "wait", advise(host_status: status("running"), collected: nil)["action"]
  end

  def test_blocked_partial_changes_continue_and_keep_observed_separate_from_reported
    collection = collected("blocked", reported: %w[a.rb b.rb], observed: ["a.rb"])
    advice = advise(collected: collection, history: [collection])
    assert_equal "continue_engineering", advice["action"]
    assert_equal ["a.rb"], advice["observed_changed_paths"]
    assert_equal %w[a.rb b.rb], advice["reported_changed_paths"]
    assert_equal %w[a.rb b.rb], advice["cumulative_reported_changed_paths"]
    assert_equal "Implement the assigned behavior", advice.dig("assigned_deliverable", "objective")
  end

  def test_repeated_no_progress_suggests_bounded_decomposition
    attempts = [collected("blocked"), collected("blocked", job_id: "job-2")]
    advice = advise(collected: attempts.last, history: attempts)
    assert_equal "decompose_engineering", advice["action"]
    assert_equal "repeated_no_progress", advice["reason_code"]
    assert_match(/smaller bounded unit/, advice.dig("details", "suggestion"))
  end

  def test_repeated_partial_progress_suggests_decomposition_without_completion
    attempts = [collected("blocked", observed: ["a.rb"]), collected("blocked", observed: ["b.rb"], job_id: "job-2")]
    advice = advise(collected: attempts.last, history: attempts)
    assert_equal "decompose_engineering", advice["action"]
    assert_equal "repeated_partial_progress", advice["reason_code"]
  end

  def test_driver_history_envelope_counts_prior_and_current_partial_collections
    first = collected("blocked", reported: ["a.rb"], observed: ["a.rb"], job_id: "job-1")
    second = collected("blocked", reported: ["b.rb"], observed: ["b.rb"], job_id: "job-2")
    history = [{"host_status" => compact(first.fetch("job")), "collected" => first}]

    advice = advise(collected: second, history: history)

    assert_equal "decompose_engineering", advice["action"]
    assert_equal "repeated_partial_progress", advice["reason_code"]
    assert_equal 2, advice["attempts"]
    assert_equal %w[a.rb b.rb], advice["cumulative_reported_changed_paths"]
    assert_equal ["b.rb"], advice["observed_changed_paths"]
  end

  def test_pending_worker_verification_runs_checks_while_failed_scenarios_need_engineering
    %w[pending failed].each do |scenario_status|
      collection = collected("implemented", scenarios: [{"scenario_id" => "s1", "status" => scenario_status, "evidence" => "structured"}])
      expected = scenario_status == "failed" ? "continue_engineering" : "run_checks"
      assert_equal expected, advise(collected: collection, history: [collection])["action"]
    end
    complete = collected("implemented", scenarios: [{"scenario_id" => "s1", "status" => "passed", "evidence" => "structured"}])
    assert_equal "run_checks", advise(collected: complete, history: [complete])["action"]
  end

  def test_stale_current_claim_is_discarded_and_stale_history_is_excluded
    stale = collected("blocked", revision: 1, claim_id: "old")
    current = collected("blocked")
    assert_equal "discard_stale", advise(collected: stale, history: [stale])["action"]
    advice = advise(collected: current, history: [stale, current])
    assert_equal 1, advice["attempts"]
    assert_equal "continue_engineering", advice["action"]
  end

  def test_structured_declared_dependency_and_unanswered_operator_decision_are_distinct
    collection = collected("blocked")
    dependency = source("dep-1", "pending")
    assert_equal "await_dependency", advise(collected: collection, history: [collection], declared_dependencies: [dependency])["action"]

    decision = source("finish", "unanswered").merge("source" => {"thread_id" => "thread", "message_id" => "message"})
    assert_equal "request_operator_decision", advise(collected: collection, history: [collection], pending_decisions: [decision])["action"]

    stale = decision.merge("revision" => 1)
    assert_equal "continue_engineering", advise(collected: collection, history: [collection], pending_decisions: [stale])["action"]
  end

  def test_service_failure_uses_structured_host_classification_not_summary_words
    prose_only = collected("blocked", summary: "capacity unavailable; ask operator")
    assert_equal "continue_engineering", advise(collected: prose_only, history: [prose_only])["action"]
    service_status = status("failed").merge("failure_kind" => "service_failure", "failure_code" => "CAPACITY")
    assert_equal "retry_service", advise(host_status: service_status, collected: nil)["action"]
    assert_equal "orchestrator_triage", advise(host_status: status("failed"), collected: nil)["action"]
  end

  private

  def order
    {
      "id" => "work-1", "revision" => 2, "claim_id" => "claim-2", "status" => "running",
      "objective" => "Implement the assigned behavior", "requirement_revisions" => {"req-1" => 3},
      "paths" => %w[a.rb b.rb], "check_ids" => ["unit"]
    }
  end

  def status(value = "succeeded", job_id: "job-1", revision: 2, claim_id: "claim-2")
    {"status" => value, "job_id" => job_id, "work_order_id" => "work-1", "revision" => revision, "claim_id" => claim_id}
  end

  def collected(result_status, reported: [], observed: [], scenarios: [], summary: "result", **binding)
    result = {
      "status" => result_status, "summary" => summary, "changed_paths" => reported,
      "findings" => [], "scenario_dispositions" => scenarios, "context_requests" => []
    }
    {"job" => status("succeeded", **binding).merge("claim_current" => true), "result" => result,
     "observed_changed_paths" => observed, "tests_verified" => false, "submitted" => false}
  end

  def source(id, source_status)
    {"id" => id, "status" => source_status, "work_order_id" => "work-1", "revision" => 2, "claim_id" => "claim-2"}
  end

  def compact(job)
    job.slice("job_id", "role", "work_order_id", "revision", "claim_id", "status", "claim_current")
  end

  def advise(host_status: nil, collected:, history: [], declared_dependencies: [], pending_decisions: [])
    host_status ||= collected.fetch("job")
    HrmKernel::Continuation.advise(host_status: host_status, collected: collected, history: history, work_order: order,
                                   declared_dependencies: declared_dependencies, pending_decisions: pending_decisions)
  end
end
