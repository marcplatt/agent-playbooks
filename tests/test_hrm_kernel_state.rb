# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/hrm_kernel/state"

class HrmKernelStateTest < Minitest::Test
  PROJECT_ROOT = "/workspace/product"
  VIEW_PATH = "app/view.rb"
  API_PATH = "app/api.rb"
  OTHER_PATH = "ops/deploy.rb"
  SHA_A = "a" * 64
  SHA_B = "b" * 64

  def setup
    @command_sequence = 0
  end

  def test_operator_can_complete_a_build_correction_and_acceptance_cycle
    state = milestone_state
    state = create_order(state)
    state = claim(state, "claim-1")
    state = submit(state, "claim-1", SHA_A)
    state = apply_command(state, "milestone.review_ready", orchestrator, "review_id" => "review-1")
    state = review(state, "review-1", "changes_requested", "Use the approved blue accent", message_id: "m-review-1")

    state = apply_command(
      state,
      "intent.record",
      operator,
      "intent_id" => "intent-color",
      "kind" => "presentation_adjustment",
      "text" => "Use the approved blue accent throughout the milestone surface.",
      "source" => source("m-color"),
      "requirement_ids" => ["req-view", "req-api"]
    )
    state = amend_order(state, "intent-color", 1)

    stale = assert_raises(HrmKernel::Error) do
      submit(state, "claim-1", SHA_A, revision: 1)
    end
    assert_equal "stale_revision", stale.code

    assert_kernel_error("invalid_transition") do
      apply_command(state, "milestone.review_ready", orchestrator, "review_id" => "review-too-early")
    end

    state = claim(state, "claim-2", revision: 2)
    state = submit(state, "claim-2", SHA_B, revision: 2)
    state = resolve_finding(state, "review-1-requested-change", "fixed", "The corrected behavior now passes.")
    state = apply_command(state, "milestone.review_ready", orchestrator, "review_id" => "review-2")
    state = review(state, "review-2", "accepted", "The corrected milestone outcome is accepted.", message_id: "m-review-2")

    operator_view = HrmKernel::State.project(state, role: "operator")
    assert_equal "closed", operator_view.dig("milestone", "phase")
    assert_equal 2, operator_view.dig("work_orders", "work-1", "revision")
    assert_equal "accepted", operator_view.dig("reviews", "review-2", "decision")
    assert_empty operator_view.fetch("decisions")
  end

  def test_presentation_intent_releases_normal_multifile_work_without_an_approval_gate
    state = milestone_state
    state = apply_command(
      state,
      "intent.record",
      operator,
      "intent_id" => "intent-mirror",
      "kind" => "presentation_adjustment",
      "text" => "Show the same approved value in the view and its API mirror.",
      "source" => source("m-mirror"),
      "requirement_ids" => ["req-view", "req-api"]
    )
    state = create_order(
      state,
      intent_id: "intent-mirror",
      paths: [VIEW_PATH, API_PATH],
      requirement_ids: ["req-view", "req-api"],
      check_ids: ["check-view", "check-api"]
    )

    view = HrmKernel::State.project(state, role: "operator")
    assert_equal [VIEW_PATH, API_PATH], view.dig("work_orders", "work-1", "paths")
    assert_empty view.fetch("decisions")
    assert_equal "Show the same approved value in the view and its API mirror.",
                 view.dig("intents", "intent-mirror", "desired_behavior")
  end

  def test_orchestrator_routes_a_missing_technical_mirror_without_interrupting_the_operator
    state = milestone_state
    state = apply_command(
      state,
      "intent.record",
      operator,
      "intent_id" => "intent-mirror",
      "kind" => "presentation_adjustment",
      "text" => "Keep the view and API mirror consistent.",
      "source" => source("m-mirror"),
      "requirement_ids" => ["req-view", "req-api"]
    )
    state = create_order(
      state,
      intent_id: "intent-mirror",
      paths: [VIEW_PATH],
      requirement_ids: ["req-view"],
      check_ids: ["check-view"]
    )
    state = amend_order(
      state,
      "intent-mirror",
      1,
      paths: [VIEW_PATH, API_PATH],
      requirement_ids: ["req-view", "req-api"],
      check_ids: ["check-view", "check-api"]
    )

    view = HrmKernel::State.project(state, role: "operator")
    assert_equal 2, view.dig("work_orders", "work-1", "revision")
    assert_equal [VIEW_PATH, API_PATH], view.dig("work_orders", "work-1", "paths")
    assert_empty view.fetch("decisions")

    assert_kernel_error("forbidden") do
      request_decision(state, actor: worker("worker-1"))
    end
  end

  def test_source_identity_cannot_be_reused_for_conflicting_operator_input
    state = milestone_state
    state = apply_command(state, "intent.record", operator, intent_data("intent-1", "m-source", "Make the title blue."))

    error = assert_raises(HrmKernel::Error) do
      apply_command(state, "intent.record", operator, intent_data("intent-2", "m-source", "Make the title green."))
    end

    assert_equal "conflict", error.code
    refute HrmKernel::State.project(state, role: "operator").fetch("intents").key?("intent-2")
  end

  def test_operator_projection_keeps_all_uncommissioned_intents_visible
    state = milestone_state
    state = apply_command(state, "intent.record", operator, intent_data("intent-1", "m-intent-1", "Make the title blue."))
    state = apply_command(state, "intent.record", operator, intent_data("intent-2", "m-intent-2", "Increase the title spacing."))

    intents = HrmKernel::State.project(state, role: "operator").fetch("intents")
    assert_equal ["intent-1", "intent-2"], intents.keys.sort
  end

  def test_new_intent_invalidates_pending_review_until_new_work_is_completed
    state = completed_initial_state
    state = apply_command(state, "milestone.review_ready", orchestrator, "review_id" => "review-old")
    state = apply_command(state, "intent.record", operator,
                          intent_data("intent-new", "m-new", "Use the corrected blue title."))

    refute HrmKernel::State.project(state, role: "operator").fetch("reviews").key?("review-old")
    assert_kernel_error("stale_revision") do
      review(state, "review-old", "accepted", "Accept the old candidate.", message_id: "m-old-acceptance")
    end
    assert_kernel_error("work_remaining") do
      apply_command(state, "milestone.review_ready", orchestrator, "review_id" => "review-uncommissioned")
    end

    state = create_order(
      state,
      intent_id: "intent-new", work_order_id: "work-new",
      requirement_ids: ["req-view"], paths: [VIEW_PATH], check_ids: ["check-new"]
    )
    assert_kernel_error("invalid_transition") do
      apply_command(state, "milestone.review_ready", orchestrator, "review_id" => "review-unfinished")
    end
    state = claim(state, "claim-new", work_order_id: "work-new")
    state = submit(
      state, "claim-new", SHA_B,
      work_order_id: "work-new", paths: [VIEW_PATH], check_ids: ["check-new"]
    )
    state = apply_command(state, "milestone.review_ready", orchestrator, "review_id" => "review-current")

    projection = HrmKernel::State.project(state, role: "operator")
    assert_equal "review_ready", projection.dig("milestone", "phase")
    assert_equal "commissioned", projection.dig("intents", "intent-new", "status")
  end

  def test_pending_intent_blocks_readiness_even_when_old_work_covers_its_requirements
    state = completed_initial_state
    state = apply_command(state, "intent.record", operator,
                          intent_data("intent-pending", "m-pending", "Increase the title spacing."))

    blocker = HrmKernel::State.project(state, role: "operator")
                              .dig("milestone", "readiness_blockers")
                              .find { |entry| entry["kind"] == "pending_intents" }
    assert_equal ["intent-pending"], blocker.fetch("intent_ids")
    assert_kernel_error("work_remaining") do
      apply_command(state, "milestone.review_ready", orchestrator, "review_id" => "review-bypassed")
    end
    assert_empty HrmKernel::State.project(state, role: "operator").fetch("decisions")
  end

  def test_partial_intent_decomposition_remains_pending_until_every_bound_requirement_is_commissioned
    state = completed_initial_state
    state = apply_command(
      state,
      "intent.record",
      operator,
      "intent_id" => "intent-two-part",
      "kind" => "presentation_adjustment",
      "text" => "Apply the corrected presentation to the view and API mirror.",
      "source" => source("m-two-part"),
      "requirement_ids" => ["req-view", "req-api"]
    )
    state = create_order(
      state,
      intent_id: "intent-two-part", work_order_id: "work-view-only",
      requirement_ids: ["req-view"], paths: [VIEW_PATH], check_ids: ["check-view-only"]
    )
    state = claim(state, "claim-view-only", work_order_id: "work-view-only")
    state = submit(
      state, "claim-view-only", SHA_B,
      work_order_id: "work-view-only", paths: [VIEW_PATH], check_ids: ["check-view-only"]
    )

    projection = HrmKernel::State.project(state, role: "operator")
    assert_equal "pending", projection.dig("intents", "intent-two-part", "status")
    assert_kernel_error("work_remaining") do
      apply_command(state, "milestone.review_ready", orchestrator, "review_id" => "review-partial")
    end
  end

  def test_amending_order_to_new_intent_supersedes_projection_but_preserves_full_history
    state = milestone_state
    state = apply_command(state, "intent.record", operator,
                          intent_data("intent-old", "m-old-intent", "Use the first title treatment."))
    state = create_order(
      state,
      intent_id: "intent-old", requirement_ids: ["req-view"],
      paths: [VIEW_PATH], check_ids: ["check-old"]
    )
    state = apply_command(state, "intent.record", operator,
                          intent_data("intent-new", "m-new-intent", "Use the replacement title treatment.").merge(
                            "supersedes" => [{"intent_id" => "intent-old", "requirement_ids" => ["req-view"]}]
                          ))
    state = amend_order(
      state, "intent-new", 1,
      requirement_ids: ["req-view"], paths: [VIEW_PATH], check_ids: ["check-new"]
    )

    operator_intents = HrmKernel::State.project(state, role: "operator").fetch("intents")
    reviewer_intents = HrmKernel::State.project(state, role: "reviewer").fetch("intents")
    refute operator_intents.key?("intent-old")
    refute reviewer_intents.key?("intent-old")
    assert_equal "commissioned", operator_intents.dig("intent-new", "status")
    assert_equal "superseded", state.dig("intents", "intent-old", "status")
    assert_equal "Use the first title treatment.", state.dig("intents", "intent-old", "text")
    assert_equal source("m-old-intent"), state.dig("intents", "intent-old", "source")
    assert state.fetch("ledger").any? { |event| event["intent_id"] == "intent-old" }
  end

  def test_partial_intent_replacement_keeps_other_bound_requirement_without_reauthorizing_replaced_part
    state = milestone_state
    state = apply_command(
      state, "intent.record", operator,
      intent_data("intent-old", "m-partial-old", "Apply the old treatment to view and API.").merge(
        "requirement_ids" => ["req-view", "req-api"]
      )
    )
    state = create_order(
      state,
      intent_id: "intent-old", requirement_ids: ["req-view"],
      paths: [VIEW_PATH], check_ids: ["check-view"]
    )
    state = create_order(
      state,
      intent_id: "intent-old", work_order_id: "work-api",
      requirement_ids: ["req-api"], paths: [API_PATH], check_ids: ["check-api"]
    )
    state = apply_command(state, "intent.record", operator,
                          intent_data("intent-new", "m-partial-new", "Replace the view treatment.").merge(
                            "supersedes" => [{"intent_id" => "intent-old", "requirement_ids" => ["req-view"]}]
                          ))
    state = amend_order(
      state, "intent-new", 1,
      requirement_ids: ["req-view"], paths: [VIEW_PATH], check_ids: ["check-new-view"]
    )

    intents = HrmKernel::State.project(state, role: "reviewer").fetch("intents")
    assert_equal ["req-api"], intents.dig("intent-old", "requirement_ids")
    assert_equal "commissioned", intents.dig("intent-old", "status")
    assert_equal ["req-view"], intents.dig("intent-new", "requirement_ids")
    assert_kernel_error("stale_revision") do
      create_order(
        state,
        intent_id: "intent-old", work_order_id: "work-reintroduced-view",
        requirement_ids: ["req-view"], paths: [VIEW_PATH], check_ids: ["check-reintroduced"]
      )
    end
  end

  def test_removed_unreplaced_requirement_returns_to_pending_old_intent_scope
    state = milestone_state
    state = apply_command(
      state, "intent.record", operator,
      intent_data("intent-old", "m-removed-old", "Apply the old treatment to view and API.").merge(
        "requirement_ids" => ["req-view", "req-api"]
      )
    )
    state = create_order(state, intent_id: "intent-old")
    state = apply_command(state, "intent.record", operator,
                          intent_data("intent-new", "m-removed-new", "Replace only the view treatment.").merge(
                            "supersedes" => [{"intent_id" => "intent-old", "requirement_ids" => ["req-view"]}]
                          ))
    state = amend_order(
      state, "intent-new", 1,
      requirement_ids: ["req-view"], paths: [VIEW_PATH], check_ids: ["check-new-view"]
    )

    projection = HrmKernel::State.project(state, role: "reviewer")
    assert_equal ["req-api"], projection.dig("intents", "intent-old", "requirement_ids")
    assert_equal "pending", projection.dig("intents", "intent-old", "status")
    blocker = projection.dig("milestone", "readiness_blockers")
                        .find { |entry| entry["kind"] == "pending_intents" }
    assert_includes blocker.fetch("intent_ids"), "intent-old"
  end

  def test_additive_amendment_retains_existing_requirement_authority
    state = milestone_state
    state = create_order(state)
    state = apply_command(state, "intent.record", operator,
                          intent_data("intent-view-only", "m-view-only", "Replace only the view treatment."))

    state = amend_order(state, "intent-view-only", 1)

    order = HrmKernel::State.project(state, role: "orchestrator").dig("work_orders", "work-1")
    assert_equal ["milestone_initial", "intent-view-only"], order.fetch("intent_ids")
    assert_equal ["req-view", "req-api"], order.fetch("requirement_ids")
  end

  def test_amending_a_reviewed_order_removes_the_invalidated_pending_review
    state = milestone_state
    state = apply_command(
      state, "intent.record", operator,
      intent_data("intent-old", "m-amend-old", "Use the first approved presentation.").merge(
        "requirement_ids" => ["req-view", "req-api"]
      )
    )
    state = create_order(state, intent_id: "intent-old")
    state = claim(state, "claim-old")
    state = submit(state, "claim-old", SHA_A)
    state = apply_command(
      state, "intent.record", operator,
      intent_data("intent-new", "m-amend-new", "Use the replacement approved presentation.").merge(
        "requirement_ids" => ["req-view", "req-api"]
      )
    )
    state = create_order(state, intent_id: "intent-new", work_order_id: "work-new")
    state = claim(state, "claim-new", work_order_id: "work-new")
    state = submit(state, "claim-new", SHA_B, work_order_id: "work-new")
    state = apply_command(state, "milestone.review_ready", orchestrator, "review_id" => "review-before-amend")
    state = amend_order(state, "intent-new", 1)

    refute HrmKernel::State.project(state, role: "reviewer").fetch("reviews").key?("review-before-amend")
  end

  def test_cancelling_only_bound_order_returns_intent_to_pending_and_blocks_review
    state = completed_initial_state
    state = apply_command(state, "intent.record", operator,
                          intent_data("intent-cancelled", "m-cancelled", "Use the corrected title."))
    state = create_order(
      state,
      intent_id: "intent-cancelled", work_order_id: "work-cancelled",
      requirement_ids: ["req-view"], paths: [VIEW_PATH], check_ids: ["check-cancelled"]
    )
    state = apply_command(
      state,
      "work_order.cancel",
      orchestrator,
      "work_order_id" => "work-cancelled", "revision" => 1,
      "reason" => "Replace this assignment."
    )

    assert_equal "pending", HrmKernel::State.project(state, role: "operator")
                                          .dig("intents", "intent-cancelled", "status")
    assert_kernel_error("work_remaining") do
      apply_command(state, "milestone.review_ready", orchestrator, "review_id" => "review-after-cancel")
    end
  end

  def test_unscoped_clarification_is_rejected_without_changing_review_readiness
    state = completed_initial_state
    snapshot = Marshal.load(Marshal.dump(state))
    assert_kernel_error("invalid_command") do
      apply_command(
        state,
        "intent.record",
        operator,
        "intent_id" => "intent-context",
        "kind" => "clarification",
        "text" => "Blue means the existing reviewed brand blue.",
        "source" => source("m-context"),
        "requirement_ids" => []
      )
    end
    assert_equal snapshot, state
    state = apply_command(state, "milestone.review_ready", orchestrator, "review_id" => "review-context")

    projection = HrmKernel::State.project(state, role: "operator")
    refute projection.fetch("intents").key?("intent-context")
    assert_equal "review_ready", projection.dig("milestone", "phase")
  end

  def test_old_rejected_or_deferred_decision_does_not_reask_after_operator_changes_requirement
    %w[rejected deferred].each do |disposition|
      state = milestone_state
      state = request_decision(state)
      state = respond_decision(
        state,
        disposition: disposition,
        message_id: "m-#{disposition}-answer"
      )
      state = change_view_requirement(
        state,
        intent_id: "intent-#{disposition}-replacement",
        message_id: "m-#{disposition}-replacement"
      )
      state = create_order(
        state,
        intent_id: "intent-#{disposition}-replacement",
        requirement_ids: ["req-view"], paths: [VIEW_PATH], check_ids: ["check-view"]
      )
      state = claim(state, "claim-#{disposition}")

      projection = HrmKernel::State.project(state, role: "operator")
      assert_equal "running", projection.dig("work_orders", "work-1", "status")
      refute projection.fetch("decisions").key?("decision-1")
    end
  end

  def test_accepted_decision_for_old_requirement_revision_is_not_projected_as_current
    state = milestone_state
    state = request_decision(state)
    state = respond_decision(state)
    state = change_view_requirement(
      state,
      intent_id: "intent-accepted-replacement",
      message_id: "m-accepted-replacement"
    )

    refute HrmKernel::State.project(state, role: "operator").fetch("decisions").key?("decision-1")
    assert_equal "accepted", state.dig("decisions", "decision-1", "status")
  end

  def test_stale_decision_response_and_reopen_cannot_cross_requirement_revision
    unresolved = milestone_state
    unresolved = request_decision(unresolved)
    unresolved = change_view_requirement(
      unresolved,
      intent_id: "intent-unresolved-replacement",
      message_id: "m-unresolved-replacement"
    )
    assert_kernel_error("stale_revision") { respond_decision(unresolved) }

    answered = milestone_state
    answered = request_decision(answered)
    answered = respond_decision(answered, disposition: "rejected", message_id: "m-rejected-old")
    answered = change_view_requirement(
      answered,
      intent_id: "intent-reopen-replacement",
      message_id: "m-reopen-replacement"
    )
    assert_kernel_error("stale_revision") do
      apply_command(
        answered,
        "decision.reopen",
        operator,
        "decision_id" => "decision-1", "revision" => 1,
        "text" => "Reopen the obsolete question.", "source" => source("m-stale-reopen")
      )
    end
  end

  def test_stale_uncommissioned_intent_is_superseded_without_hiding_new_pending_intent
    state = milestone_state
    state = apply_command(
      state,
      "intent.record",
      operator,
      intent_data("intent-stale", "m-stale-intent", "Use the original approved title.")
    )
    state = change_view_requirement(
      state,
      intent_id: "intent-current",
      message_id: "m-current-intent"
    )

    projection = HrmKernel::State.project(state, role: "operator")
    refute projection.fetch("intents").key?("intent-stale")
    assert_equal "superseded", state.dig("intents", "intent-stale", "status")
    assert_equal "pending", projection.dig("intents", "intent-current", "status")
    blocker = projection.dig("milestone", "readiness_blockers")
                        .find { |entry| entry["kind"] == "pending_intents" }
    assert_equal ["intent-current"], blocker.fetch("intent_ids")
  end

  def test_one_operator_message_can_answer_multiple_questions_without_losing_question_binding
    state = milestone_state
    state = request_decision(state)
    state = apply_command(
      state,
      "decision.request",
      orchestrator,
      decision_request_data.merge(
        "decision_id" => "decision-2",
        "exact_effect" => "select the fictional accent",
        "question" => "Which accent is correct?"
      )
    )
    shared_source = source("m-two-answers")
    state = apply_command(state, "decision.respond", operator,
                          decision_response_data.merge("source" => shared_source))
    state = apply_command(
      state,
      "decision.respond",
      operator,
      decision_response_data.merge(
        "decision_id" => "decision-2",
        "exact_effect" => "select the fictional accent",
        "source" => shared_source
      )
    )

    decisions = HrmKernel::State.project(state, role: "operator").fetch("decisions")
    assert_equal "Which customer-visible copy is correct?", decisions.dig("decision-1", "question")
    assert_equal "Which accent is correct?", decisions.dig("decision-2", "question")
    assert_equal "Use the reviewed wording.", decisions.dig("decision-1", "response", "answer")
    assert_equal "Use the reviewed wording.", decisions.dig("decision-2", "response", "answer")
  end

  def test_decision_response_is_bound_to_revision_kind_effect_and_original_question
    state = milestone_state
    state = request_decision(state)

    mismatch = assert_raises(HrmKernel::Error) do
      respond_decision(state, exact_effect: "deploy production")
    end
    assert_equal "stale_revision", mismatch.code

    state = respond_decision(state)
    decision = HrmKernel::State.project(state, role: "operator").dig("decisions", "decision-1")
    assert_equal "Which customer-visible copy is correct?", decision.fetch("question")
    assert_equal "Use the reviewed wording.", decision.dig("response", "answer")
    assert_equal "change customer-visible wording", decision.fetch("exact_effect")
    assert_equal 1, decision.fetch("revision")
  end

  def test_decision_request_without_intent_id_rejects_permission_already_supplied_by_broader_intent
    state = milestone_state
    state = apply_command(
      state,
      "intent.record",
      operator,
      "intent_id" => "intent-existing-authority",
      "kind" => "clarification",
      "text" => "change customer-visible wording",
      "source" => source("m-existing-authority"),
      "requirement_ids" => ["req-view", "req-api"]
    )
    snapshot = Marshal.load(Marshal.dump(state))

    assert_kernel_error("redundant_decision") do
      apply_command(state, "decision.request", orchestrator, decision_request_data)
    end
    assert_equal snapshot, state
    assert_empty HrmKernel::State.project(state, role: "operator").fetch("decisions")
  end

  def test_stale_decision_answer_cannot_answer_a_revised_question
    state = milestone_state
    state = request_decision(state)
    state = apply_command(
      state,
      "decision.revise",
      orchestrator,
      decision_request_data.merge(
        "expected_revision" => 1,
        "question" => "Which reviewed headline and subtitle are correct?"
      ).tap { |data| data.delete("revision") }
    )

    error = assert_raises(HrmKernel::Error) { respond_decision(state, revision: 1) }
    assert_equal "stale_revision", error.code

    state = respond_decision(state, revision: 2, message_id: "m-answer-2")
    decision = HrmKernel::State.project(state, role: "operator").dig("decisions", "decision-1")
    assert_equal "Which reviewed headline and subtitle are correct?", decision.fetch("question")
    assert_equal 2, decision.fetch("revision")
  end

  def test_revised_decision_cannot_duplicate_an_existing_decision_frontier_item
    state = milestone_state
    state = request_decision(state)
    state = apply_command(
      state,
      "decision.request",
      orchestrator,
      decision_request_data.merge(
        "decision_id" => "decision-2",
        "exact_effect" => "select the fictional accent",
        "question" => "Which accent is correct?"
      )
    )

    assert_kernel_error("conflict") do
      apply_command(
        state,
        "decision.revise",
        orchestrator,
        decision_request_data.merge(
          "decision_id" => "decision-2",
          "expected_revision" => 1
        ).tap { |data| data.delete("revision") }
      )
    end
  end

  def test_claim_identity_and_one_writer_rule_are_enforced
    state = milestone_state
    state = create_order(state)
    state = claim(state, "claim-1", worker_id: "worker-1")

    assert_kernel_error("forbidden") do
      submit(state, "claim-1", SHA_A, worker_id: "worker-2")
    end

    state = create_order(state, work_order_id: "work-2", paths: [VIEW_PATH], check_ids: ["check-view-2"])
    assert_kernel_error("conflict") do
      apply_command(
        state,
        "work_order.claim",
        worker("worker-2"),
        "work_order_id" => "work-2", "revision" => 1, "claim_id" => "claim-overlap"
      )
    end

    state = apply_command(
      state,
      "work_order.release",
      orchestrator,
      "work_order_id" => "work-1",
      "revision" => 1,
      "claim_id" => "claim-1",
      "reason" => "Worker is unavailable."
    )
    state = claim(state, "claim-2", worker_id: "worker-2")
    assert_equal "worker-2", HrmKernel::State.project(state, role: "orchestrator").dig("work_orders", "work-1", "owner_id")
  end

  def test_one_intent_can_be_decomposed_and_workers_only_see_their_assignment
    state = milestone_state
    state = apply_command(
      state,
      "intent.record",
      operator,
      "intent_id" => "intent-multifile",
      "kind" => "clarification",
      "text" => "Keep the fictional view and API representation consistent.",
      "source" => source("m-decompose"),
      "requirement_ids" => ["req-view", "req-api"]
    )
    state = create_order(
      state,
      intent_id: "intent-multifile",
      requirement_ids: ["req-view"],
      paths: [VIEW_PATH],
      check_ids: ["check-view"]
    )
    state = create_order(
      state,
      intent_id: "intent-multifile",
      work_order_id: "work-2",
      requirement_ids: ["req-api"],
      paths: [API_PATH],
      check_ids: ["check-api"]
    )
    state = claim(state, "claim-1", worker_id: "worker-1")
    state = apply_command(
      state,
      "work_order.claim",
      worker("worker-2"),
      "work_order_id" => "work-2", "revision" => 1, "claim_id" => "claim-2"
    )

    worker_view = HrmKernel::State.project(state, role: "worker", actor_id: "worker-1")
    assert_equal ["work-1"], worker_view.fetch("work_orders").keys
    assert_equal [VIEW_PATH], worker_view.dig("work_orders", "work-1", "paths")
  end

  def test_requirement_change_invalidates_old_claim_result_and_old_intent
    state = milestone_state
    state = apply_command(state, "intent.record", operator, intent_data("intent-old", "m-old", "Use the approved title."))
    state = create_order(
      state,
      intent_id: "intent-old",
      requirement_ids: ["req-view"],
      paths: [VIEW_PATH],
      check_ids: ["check-view"]
    )
    state = claim(state, "claim-1")
    state = apply_command(
      state,
      "intent.record",
      operator,
      "intent_id" => "intent-requirement-change",
      "kind" => "milestone_change",
      "text" => "The title and subtitle must use the approved wording.",
      "source" => source("m-requirement-change"),
      "requirement_ids" => ["req-view"],
      "requirements" => [
        {"id" => "req-view", "text" => "The title and subtitle use the approved wording."}
      ]
    )

    assert_kernel_error("stale_revision") do
      submit(state, "claim-1", SHA_A, paths: [VIEW_PATH], check_ids: ["check-view"])
    end
    assert_kernel_error("stale_revision") do
      create_order(
        state,
        intent_id: "intent-old",
        work_order_id: "work-stale",
        requirement_ids: ["req-view"],
        paths: [VIEW_PATH],
        check_ids: ["check-stale"]
      )
    end
  end

  def test_work_is_limited_to_milestone_paths_and_local_repository_effects
    state = milestone_state

    assert_kernel_error("invalid_path") do
      create_order(state, paths: [OTHER_PATH])
    end

    assert_kernel_error("invalid_command") do
      create_order(state, effect_class: "production_deployment")
    end

    state = apply_command(
      state,
      "decision.request",
      orchestrator,
      decision_request_data.merge(
        "decision_id" => "decision-deploy",
        "kind" => "external_effect_authority",
        "exact_effect" => "deploy the fictional surface to production",
        "question" => "May the fictional surface be deployed?"
      )
    )
    state = apply_command(
      state,
      "decision.respond",
      operator,
      decision_response_data.merge(
        "decision_id" => "decision-deploy",
        "kind" => "external_effect_authority",
        "exact_effect" => "deploy the fictional surface to production",
        "source" => source("m-deploy-answer")
      )
    )
    assert_kernel_error("invalid_command") do
      create_order(state, effect_class: "production_deployment")
    end
  end

  def test_review_ready_requires_every_required_scenario_to_have_passing_evidence
    state = milestone_state
    state = create_order(
      state,
      requirement_ids: ["req-view"],
      paths: [VIEW_PATH],
      check_ids: ["check-view"]
    )
    state = claim(state, "claim-1")
    state = submit(state, "claim-1", SHA_A, paths: [VIEW_PATH], check_ids: ["check-view"])

    assert_kernel_error("work_remaining") do
      apply_command(state, "milestone.review_ready", orchestrator, "review_id" => "review-incomplete")
    end
  end

  def test_submit_rejects_missing_or_failed_required_checks
    state = milestone_state
    state = create_order(state)
    state = claim(state, "claim-1")

    assert_kernel_error("invalid_command") do
      submit(state, "claim-1", SHA_A, check_ids: ["check-view"])
    end

    checks = check_results(SHA_A)
    checks.last["conclusion"] = "failed"
    assert_kernel_error("invalid_command") do
      apply_command(state, "work_order.submit", worker("worker-1"), submit_data("claim-1", SHA_A).merge("checks" => checks))
    end
  end

  def test_rejected_candidate_cannot_be_presented_again_unchanged
    state = milestone_state
    state = create_order(state)
    state = claim(state, "claim-1")
    state = submit(state, "claim-1", SHA_A)
    state = apply_command(state, "milestone.review_ready", orchestrator, "review_id" => "review-1")
    state = review(state, "review-1", "changes_requested", "Correct the color.", message_id: "m-changes")

    assert_kernel_error("work_remaining") do
      apply_command(state, "milestone.review_ready", orchestrator, "review_id" => "review-2")
    end
  end

  def test_withdrawing_a_mistaken_business_question_releases_existing_operator_intent
    state = milestone_state
    state = apply_command(state, "intent.record", operator, intent_data("intent-1", "m-intent", "Make the title blue."))
    state = request_decision(state, intent_id: "intent-1")
    state = create_order(
      state,
      intent_id: "intent-1",
      requirement_ids: ["req-view"], paths: [VIEW_PATH], check_ids: ["check-view"]
    )

    assert_kernel_error("authority_gap") do
      claim(state, "claim-blocked")
    end

    state = apply_command(
      state,
      "decision.withdraw",
      orchestrator,
      "decision_id" => "decision-1",
      "revision" => 1,
      "reason" => "Engineering evidence shows no business choice remains.",
      "source_ref" => "investigation:local-mirror"
    )
    state = claim(state, "claim-released")

    assert_equal "withdrawn", HrmKernel::State.project(state, role: "operator").dig("decisions", "decision-1", "status")
    assert_equal "running", HrmKernel::State.project(state, role: "operator").dig("work_orders", "work-1", "status")
  end

  def test_operator_answer_cannot_be_erased_or_asked_again_as_a_fresh_gate
    state = milestone_state
    state = request_decision(state)
    state = respond_decision(state, disposition: "rejected")
    state = create_order(state)

    assert_kernel_error("authority_gap") { claim(state, "claim-blocked") }
    assert_kernel_error("invalid_transition") do
      apply_command(
        state,
        "decision.withdraw",
        orchestrator,
        "decision_id" => "decision-1", "revision" => 1,
        "reason" => "Try to erase the answer.", "source_ref" => "investigation:retry"
      )
    end
    assert_kernel_error("invalid_transition") do
      apply_command(
        state,
        "decision.revise",
        orchestrator,
        decision_request_data.merge("expected_revision" => 1).tap { |data| data.delete("revision") }
      )
    end
    assert_kernel_error("conflict") do
      apply_command(
        state,
        "decision.request",
        orchestrator,
        decision_request_data.merge("decision_id" => "decision-duplicate")
      )
    end


    assert_kernel_error("forbidden") do
      apply_command(
        state,
        "decision.reopen",
        orchestrator,
        "decision_id" => "decision-1", "revision" => 1,
        "text" => "I have changed my answer.", "source" => source("m-reopen-wrong-actor")
      )
    end
    state = apply_command(
      state,
      "decision.reopen",
      operator,
      "decision_id" => "decision-1", "revision" => 1,
      "text" => "I have changed my answer; use the reviewed wording.",
      "source" => source("m-reopen")
    )
    state = respond_decision(state, revision: 2, message_id: "m-reopened-answer")
    state = claim(state, "claim-released")

    decision = HrmKernel::State.project(state, role: "operator").dig("decisions", "decision-1")
    assert_equal 2, decision.fetch("revision")
    assert_equal "accepted", decision.fetch("status")
    assert_equal "running", HrmKernel::State.project(state, role: "operator").dig("work_orders", "work-1", "status")
  end

  def test_closed_milestone_cannot_be_reopened_or_mutated
    state = milestone_state
    state = create_order(state)
    state = claim(state, "claim-1")
    state = submit(state, "claim-1", SHA_A)
    state = apply_command(state, "milestone.review_ready", orchestrator, "review_id" => "review-1")
    state = review(state, "review-1", "accepted", "Accepted.", message_id: "m-accepted")

    assert_kernel_error("invalid_transition") do
      apply_command(state, "intent.record", operator, intent_data("intent-late", "m-late", "Reopen it."))
    end
    assert_kernel_error("invalid_transition") do
      create_order(state, work_order_id: "work-late")
    end
  end

  def test_apply_is_pure_for_successful_and_failed_commands
    initial = HrmKernel::State.initial
    snapshot = Marshal.load(Marshal.dump(initial))
    created = apply_command(initial, "milestone.create", operator, milestone_data)

    assert_equal snapshot, initial
    refute_same initial, created

    created_snapshot = Marshal.load(Marshal.dump(created))
    assert_raises(HrmKernel::Error) { create_order(created, paths: [OTHER_PATH]) }
    assert_equal created_snapshot, created
  end

  def test_commands_reject_unknown_types_fields_and_conflicting_normalized_keys
    state = HrmKernel::State.initial
    envelope = command("milestone.create", operator, milestone_data)

    assert_kernel_error("invalid_command") do
      HrmKernel::State.apply(state, envelope.merge("unexpected" => true))
    end
    assert_kernel_error("invalid_command") do
      HrmKernel::State.apply(state, command("milestone.launch", operator, {}))
    end
    assert_kernel_error("invalid_command") do
      HrmKernel::State.apply(state, command("milestone.create", operator, milestone_data.merge("unexpected" => true)))
    end
    assert_kernel_error("invalid_command") do
      mixed = command("milestone.create", operator, milestone_data)
      mixed[:type] = mixed.fetch("type")
      HrmKernel::State.apply(state, mixed)
    end
  end

  def test_role_projection_hides_raw_sources_and_internal_ledger
    state = milestone_state
    state = apply_command(state, "intent.record", operator, intent_data("intent-1", "m-private", "Make the title blue."))

    projection = HrmKernel::State.project(state, role: "operator", actor_id: "operator-1")
    refute projection.key?("source_records")
    refute projection.key?("ledger")
    refute projection.dig("intents", "intent-1").key?("source")
    assert_equal "Make the title blue.", projection.dig("intents", "intent-1", "desired_behavior")
  end

  def test_reviewer_sees_current_operator_desired_behavior_without_private_history
    state = milestone_state
    state = apply_command(
      state,
      "intent.record",
      operator,
      "intent_id" => "intent-review",
      "kind" => "presentation_adjustment",
      "text" => "Use the operator-approved blue accent on the view and API mirror.",
      "source" => source("m-review-intent"),
      "requirement_ids" => ["req-view", "req-api"]
    )
    state = create_order(state, intent_id: "intent-review")
    state = claim(state, "claim-review")
    state = submit(state, "claim-review", SHA_A)
    state = apply_command(state, "milestone.review_ready", orchestrator, "review_id" => "review-current")

    projection = HrmKernel::State.project(state, role: "reviewer", actor_id: "reviewer-1")
    intent = projection.dig("intents", "intent-review")
    refute_nil intent
    assert_equal "Use the operator-approved blue accent on the view and API mirror.", intent.fetch("desired_behavior")
    refute_equal intent.fetch("desired_behavior"), projection.dig("work_orders", "work-1", "objective")
    refute intent.key?("source")
    refute projection.key?("source_records")
    refute projection.key?("ledger")
    refute projection.dig("work_orders", "work-1").key?("claim_history")
  end

  def test_additive_feedback_survives_repeated_amendment_cycles
    state = milestone_state
    state = apply_command(state, "intent.record", operator,
                          intent_data("intent-blue", "m-blue", "Use the approved blue accent."))
    state = create_order(
      state, intent_id: "intent-blue", requirement_ids: ["req-view"],
      paths: [VIEW_PATH], check_ids: ["check-view"]
    )
    state = apply_command(state, "intent.record", operator,
                          intent_data("intent-bold", "m-bold", "Also make the title bold."))
    state = amend_order(
      state, "intent-bold", 1,
      requirement_ids: ["req-view"], paths: [VIEW_PATH], check_ids: ["check-view"]
    )
    state = apply_command(state, "intent.record", operator,
                          intent_data("intent-space", "m-space", "Also increase title spacing."))
    state = amend_order(
      state, "intent-space", 2,
      requirement_ids: ["req-view"], paths: [VIEW_PATH], check_ids: ["check-view"]
    )

    projection = HrmKernel::State.project(state, role: "reviewer")
    assert_equal %w[intent-blue intent-bold intent-space], projection.fetch("intents").keys.sort
    assert_equal %w[intent-blue intent-bold intent-space],
                 projection.dig("work_orders", "work-1", "intent_ids")
    assert projection.fetch("intents").values.all? { |intent| intent["status"] == "commissioned" }
    assert state.fetch("intents").values.all? { |intent| intent["superseded_requirement_ids"].empty? }
  end

  def test_only_explicit_operator_supersession_replaces_an_active_constraint
    state = milestone_state
    state = apply_command(state, "intent.record", operator,
                          intent_data("intent-blue", "m-explicit-blue", "Use blue."))
    state = create_order(
      state, intent_id: "intent-blue", requirement_ids: ["req-view"],
      paths: [VIEW_PATH], check_ids: ["check-view"]
    )
    state = apply_command(state, "intent.record", operator,
                          intent_data("intent-green-additive", "m-green-additive", "Use green."))
    state = amend_order(
      state, "intent-green-additive", 1,
      requirement_ids: ["req-view"], paths: [VIEW_PATH], check_ids: ["check-view"]
    )
    assert_empty state.dig("intents", "intent-blue", "superseded_requirement_ids")

    state = apply_command(
      state,
      "intent.record",
      operator,
      intent_data("intent-green-final", "m-green-final", "Replace blue with green.").merge(
        "supersedes" => [{"intent_id" => "intent-blue", "requirement_ids" => ["req-view"]}]
      )
    )
    state = amend_order(
      state, "intent-green-final", 2,
      requirement_ids: ["req-view"], paths: [VIEW_PATH], check_ids: ["check-view"]
    )

    refute HrmKernel::State.project(state, role: "operator").fetch("intents").key?("intent-blue")
    assert_equal ["req-view"], state.dig("intents", "intent-blue", "superseded_requirement_ids")
  end

  def test_metadata_only_resubmission_cannot_resolve_requested_change_as_fixed
    state = milestone_state
    state = create_order(state)
    state = claim(state, "claim-original")
    state = submit(state, "claim-original", SHA_A)
    state = apply_command(state, "milestone.review_ready", orchestrator, "review_id" => "review-original")
    state = review(state, "review-original", "changes_requested", "The visible behavior is wrong.", message_id: "m-wrong")
    original_behavior = state.dig("findings", "review-original-requested-change", "behavior_digest")

    state = amend_order(state, "milestone_initial", 1)
    state = claim(state, "claim-report-only", revision: 2)
    state = submit(state, "claim-report-only", SHA_A, revision: 2)
    current = HrmKernel::State.project(state, role: "reviewer").dig("milestone", "current_candidate")
    assert_equal original_behavior, current.fetch("behavior_digest")

    assert_kernel_error("work_remaining") do
      resolve_finding(state, "review-original-requested-change", "fixed", "Only the report changed.")
    end
    assert_kernel_error("work_remaining") do
      apply_command(state, "milestone.review_ready", orchestrator, "review_id" => "review-bypass")
    end
  end

  def test_no_change_needed_requires_current_independent_behavioral_evidence
    state = milestone_state
    state = create_order(state)
    state = claim(state, "claim-original")
    state = submit(state, "claim-original", SHA_A)
    state = apply_command(state, "milestone.review_ready", orchestrator, "review_id" => "review-original")
    state = review(state, "review-original", "changes_requested", "Verify the apparent mismatch.", message_id: "m-verify")

    candidate = HrmKernel::State.project(state, role: "reviewer").dig("milestone", "current_candidate")
    assert_kernel_error("invalid_command") do
      apply_command(
        state, "finding.resolve", reviewer,
        "finding_id" => "review-original-requested-change",
        "candidate_digest" => candidate.fetch("candidate_digest"),
        "disposition" => "no_change_needed",
        "text" => "Dismiss without evidence.",
        "evidence_refs" => []
      )
    end

    state = resolve_finding(
      state, "review-original-requested-change", "no_change_needed",
      "Independent current checks demonstrate that the requested behavior already holds."
    )
    state = apply_command(state, "milestone.review_ready", orchestrator, "review_id" => "review-verified")
    assert_equal "review_ready", state.dig("milestone", "phase")
  end

  def test_implementation_mode_requires_current_independent_scenario_assessment
    state = implementation_milestone_state
    state = create_order(state)
    state = claim(state, "claim-implementation")
    state = submit(state, "claim-implementation", SHA_A)
    candidate = HrmKernel::State.project(state, role: "reviewer").dig("milestone", "current_candidate")

    assert_kernel_error("work_remaining") do
      apply_command(state, "milestone.review_ready", orchestrator, "review_id" => "review-unassessed")
    end
    assert_kernel_error("forbidden") do
      assess_candidate(state, candidate, reviewer_id: "worker-1")
    end

    state = assess_candidate(state, candidate)
    assessment = state.dig("assessments", "assessment-1")
    assert_equal candidate.fetch("candidate_digest"), assessment.fetch("candidate_digest")
    assert_equal candidate.fetch("requirement_revisions"), assessment.fetch("requirement_revisions")
    assert_equal "reviewer-1", assessment.fetch("assessor_id")
    state = apply_command(state, "milestone.review_ready", orchestrator, "review_id" => "review-assessed")
    state = review(state, "review-assessed", "accepted", "The behavior is accepted.", message_id: "m-accepted-implementation")
    assert_equal "closed", state.dig("milestone", "phase")
  end

  def test_unchanged_completed_work_can_refresh_stale_evidence_but_requires_reassessment
    state = implementation_milestone_state
    state = create_order(state)
    state = claim(state, "claim-implementation")
    state = submit(state, "claim-implementation", SHA_A)
    original = HrmKernel::State.project(state, role: "reviewer").dig("milestone", "current_candidate")
    state = assess_candidate(state, original)

    changed_artifacts = submit_data("claim-implementation", SHA_B)
    assert_kernel_error("invalid_command") do
      apply_command(state, "work_order.refresh_evidence", worker("worker-1"), changed_artifacts)
    end

    refresh = submit_data("claim-implementation", SHA_A)
    refresh["checks"] = check_results(SHA_B)
    state = apply_command(state, "work_order.refresh_evidence", worker("worker-1"), refresh)
    order = state.dig("work_orders", "work-1")
    assert_equal 1, order.fetch("revision")
    assert_equal [{ "path" => VIEW_PATH, "sha256" => SHA_A }, { "path" => API_PATH, "sha256" => SHA_A }], order.fetch("artifacts")
    assert_equal 1, order.fetch("evidence_history").length
    refute_equal order.dig("evidence_history", 0, "evidence_digest"), order.fetch("evidence_digest")

    current = HrmKernel::State.project(state, role: "reviewer").dig("milestone", "current_candidate")
    refute_equal original.fetch("candidate_digest"), current.fetch("candidate_digest")
    assert_kernel_error("work_remaining") do
      apply_command(state, "milestone.review_ready", orchestrator, "review_id" => "review-stale-assessment")
    end
    state = assess_candidate(state, current, assessment_id: "assessment-refreshed")
    state = apply_command(state, "milestone.review_ready", orchestrator, "review_id" => "review-refreshed")
    assert_equal "assessment-refreshed", state.dig("reviews", "review-refreshed", "assessment_id")
  end

  def test_reviewer_finding_blocks_implementation_until_behavior_changes_and_is_reassessed
    state = implementation_milestone_state
    state = create_order(state)
    state = claim(state, "claim-first")
    state = submit(state, "claim-first", SHA_A)
    candidate = HrmKernel::State.project(state, role: "reviewer").dig("milestone", "current_candidate")
    state = apply_command(
      state, "finding.raise", reviewer,
      "finding_id" => "finding-visible-value",
      "candidate_digest" => candidate.fetch("candidate_digest"),
      "requirement_ids" => ["req-view"],
      "text" => "The visible value does not match the accepted scenario.",
      "evidence_refs" => current_evidence_refs(state)
    )
    state = assess_candidate(
      state, candidate,
      dispositions: {
        "scenario-view" => ["changes_requested", ["finding-visible-value"]],
        "scenario-api" => ["accepted", []]
      }
    )
    assert_kernel_error("work_remaining") do
      apply_command(state, "milestone.review_ready", orchestrator, "review_id" => "review-with-finding")
    end

    state = amend_order(state, "milestone_initial", 1)
    state = claim(state, "claim-fixed", revision: 2)
    state = submit(state, "claim-fixed", SHA_B, revision: 2)
    state = resolve_finding(state, "finding-visible-value", "fixed", "The visible behavior now matches.")
    current = HrmKernel::State.project(state, role: "reviewer").dig("milestone", "current_candidate")
    state = assess_candidate(state, current, assessment_id: "assessment-2")
    state = apply_command(state, "milestone.review_ready", orchestrator, "review_id" => "review-fixed")
    assert_equal "review_ready", state.dig("milestone", "phase")
  end

  def test_same_worker_can_reopen_completed_order_from_direct_operator_source
    state = milestone_state
    state = create_order(state)
    state = claim(state, "claim-first")
    state = submit(state, "claim-first", SHA_A)
    state = apply_command(
      state,
      "work_order.reopen",
      worker("worker-1"),
      "work_order_id" => "work-1",
      "expected_revision" => 1,
      "claim_id" => "claim-direct",
      "intent" => intent_data("intent-direct", "m-direct", "Also make the title bold.")
    )

    order = state.dig("work_orders", "work-1")
    assert_equal "running", order.fetch("status")
    assert_equal "worker-1", order.fetch("owner_id")
    assert_equal ["milestone_initial", "intent-direct"], order.fetch("intent_ids")
    assert_equal [VIEW_PATH, API_PATH], order.fetch("paths")
    assert_equal source("m-direct"), state.dig("intents", "intent-direct", "source")
    assert_empty state.fetch("decisions")
  end

  def test_direct_reopen_cannot_bypass_an_unresolved_business_decision
    state = milestone_state
    state = create_order(state)
    state = claim(state, "claim-first")
    state = submit(state, "claim-first", SHA_A)
    state = request_decision(state)

    assert_kernel_error("authority_gap") do
      direct_reopen(state, "intent-blocked", "m-direct-blocked")
    end
    refute state.fetch("intents").key?("intent-blocked")
    assert_equal "completed", state.dig("work_orders", "work-1", "status")
  end

  def test_direct_reopen_cannot_overlap_another_active_writer
    state = milestone_state
    state = create_order(
      state, requirement_ids: ["req-view"], paths: [VIEW_PATH], check_ids: ["check-view"]
    )
    state = claim(state, "claim-first")
    state = submit(
      state, "claim-first", SHA_A,
      paths: [VIEW_PATH], check_ids: ["check-view"]
    )
    state = create_order(
      state, work_order_id: "work-overlap", requirement_ids: ["req-view"],
      paths: [VIEW_PATH], check_ids: ["check-overlap"]
    )
    state = claim(
      state, "claim-overlap", worker_id: "worker-2", work_order_id: "work-overlap"
    )

    error = assert_kernel_error("conflict") do
      direct_reopen(state, "intent-overlap", "m-direct-overlap")
    end
    assert_match(/work-overlap/, error.message)
    refute state.fetch("intents").key?("intent-overlap")
  end

  def test_direct_reopen_rejects_stale_requirement_authority
    state = milestone_state
    state = create_order(state)
    state = claim(state, "claim-first")
    state = submit(state, "claim-first", SHA_A)
    state = change_view_requirement(state, intent_id: "intent-requirement-change", message_id: "m-stale-direct")

    assert_kernel_error("stale_revision") do
      direct_reopen(state, "intent-stale-direct", "m-stale-direct-feedback")
    end
    refute state.fetch("intents").key?("intent-stale-direct")
  end

  def test_initial_contract_is_frozen_while_operator_requirement_amendments_are_retained
    state = milestone_state
    initial_digest = state.dig("milestone", "initial_contract_digest")
    initial_outcome = state.dig("milestone", "outcome")
    state = change_view_requirement(state, intent_id: "intent-requirement-change", message_id: "m-contract-change")

    assert_equal initial_digest, state.dig("milestone", "initial_contract_digest")
    assert_equal initial_outcome, state.dig("milestone", "outcome")
    amendment = state.dig("milestone", "requirement_amendments").fetch(0)
    assert_equal "req-view", amendment.fetch("requirement_id")
    assert_equal 1, amendment.dig("previous", "revision")
    assert_equal 2, amendment.dig("current", "revision")
    assert_equal source("m-contract-change"), amendment.fetch("source")

    assert_kernel_error("forbidden") do
      apply_command(
        state, "intent.record", orchestrator,
        intent_data("intent-bad-change", "m-bad-change", "Change the requirement.").merge(
          "kind" => "milestone_change",
          "requirements" => [{"id" => "req-view", "text" => "Orchestrator rewrite."}]
        )
      )
    end
  end

  private

  def operator
    {"id" => "operator-1", "role" => "operator"}
  end

  def orchestrator
    {"id" => "orchestrator-1", "role" => "orchestrator"}
  end

  def reviewer(id = "reviewer-1")
    {"id" => id, "role" => "reviewer"}
  end

  def worker(id)
    {"id" => id, "role" => "worker"}
  end

  def source(message_id)
    {"thread_id" => "thread-1", "message_id" => message_id}
  end

  def command(type, actor, data)
    @command_sequence += 1
    {
      "command_id" => "command-#{@command_sequence}",
      "type" => type,
      "actor" => actor,
      "data" => data
    }
  end

  def apply_command(state, type, actor, data)
    HrmKernel::State.apply(state, command(type, actor, data))
  end

  def milestone_state
    apply_command(HrmKernel::State.initial, "milestone.create", operator, milestone_data)
  end

  def implementation_milestone_state
    apply_command(
      HrmKernel::State.initial,
      "milestone.create",
      operator,
      milestone_data.merge(
        "mode" => "implementation",
        "acceptance_scenarios" => [
          {
            "id" => "scenario-view",
            "text" => "The product view visibly shows the approved presentation.",
            "requirement_ids" => ["req-view"],
            "check_ids" => ["check-view"]
          },
          {
            "id" => "scenario-api",
            "text" => "The API returns the same approved value.",
            "requirement_ids" => ["req-api"],
            "check_ids" => ["check-api"]
          }
        ]
      )
    )
  end

  def completed_initial_state
    state = milestone_state
    state = create_order(state)
    state = claim(state, "claim-initial")
    submit(state, "claim-initial", SHA_A)
  end

  def milestone_data
    {
      "milestone_id" => "milestone-1",
      "outcome" => "The reviewed product surface shows one consistent approved presentation.",
      "project_root" => PROJECT_ROOT,
      "requirements" => [
        {"id" => "req-view", "text" => "The product view shows the approved presentation."},
        {"id" => "req-api", "text" => "The API mirror returns the same approved value."}
      ],
      "allowed_paths" => [VIEW_PATH, API_PATH]
    }
  end

  def intent_data(intent_id, message_id, text)
    {
      "intent_id" => intent_id,
      "kind" => "presentation_adjustment",
      "text" => text,
      "source" => source(message_id),
      "requirement_ids" => ["req-view"]
    }
  end

  def change_view_requirement(state, intent_id:, message_id:)
    apply_command(
      state,
      "intent.record",
      operator,
      "intent_id" => intent_id,
      "kind" => "milestone_change",
      "text" => "Replace the view requirement with the operator's current wording.",
      "source" => source(message_id),
      "requirement_ids" => ["req-view"],
      "requirements" => [
        {"id" => "req-view", "text" => "The title and subtitle use the operator's current wording."}
      ]
    )
  end

  def create_order(state, intent_id: "milestone_initial", work_order_id: "work-1",
                   requirement_ids: ["req-view", "req-api"], paths: [VIEW_PATH, API_PATH],
                   check_ids: ["check-view", "check-api"], effect_class: "local_repository")
    apply_command(
      state,
      "work_order.create",
      orchestrator,
      "work_order_id" => work_order_id,
      "intent_id" => intent_id,
      "objective" => "Implement the approved presentation and its API mirror.",
      "requirement_ids" => requirement_ids,
      "paths" => paths,
      "check_ids" => check_ids,
      "effect_class" => effect_class
    )
  end

  def amend_order(state, intent_id, expected_revision, paths: [VIEW_PATH, API_PATH],
                  requirement_ids: ["req-view", "req-api"], check_ids: ["check-view", "check-api"])
    apply_command(
      state,
      "work_order.amend",
      orchestrator,
      "work_order_id" => "work-1",
      "intent_id" => intent_id,
      "objective" => "Apply the requested correction consistently.",
      "requirement_ids" => requirement_ids,
      "paths" => paths,
      "check_ids" => check_ids,
      "expected_revision" => expected_revision
    )
  end

  def claim(state, claim_id, revision: 1, worker_id: "worker-1", work_order_id: "work-1")
    apply_command(
      state,
      "work_order.claim",
      worker(worker_id),
      "work_order_id" => work_order_id,
      "revision" => revision,
      "claim_id" => claim_id
    )
  end

  def submit(state, claim_id, sha, revision: 1, worker_id: "worker-1",
             work_order_id: "work-1", paths: [VIEW_PATH, API_PATH],
             check_ids: ["check-view", "check-api"])
    apply_command(
      state,
      "work_order.submit",
      worker(worker_id),
      submit_data(
        claim_id, sha, revision: revision, work_order_id: work_order_id,
        paths: paths, check_ids: check_ids
      )
    )
  end

  def submit_data(claim_id, sha, revision: 1, work_order_id: "work-1", paths: [VIEW_PATH, API_PATH],
                  check_ids: ["check-view", "check-api"])
    {
      "work_order_id" => work_order_id,
      "revision" => revision,
      "claim_id" => claim_id,
      "artifacts" => paths.map { |path| {"path" => path, "sha256" => sha} },
      "checks" => check_results(sha, check_ids)
    }
  end

  def check_results(sha, check_ids = ["check-view", "check-api"])
    check_ids.map do |check_id|
      {
        "id" => check_id,
        "conclusion" => "passed",
        "artifact_path" => ".codex/checks/#{check_id}.json",
        "sha256" => sha
      }
    end
  end

  def review(state, review_id, decision, text, message_id:)
    apply_command(
      state,
      "milestone.review",
      operator,
      "review_id" => review_id,
      "decision" => decision,
      "text" => text,
      "source" => source(message_id)
    )
  end

  def resolve_finding(state, finding_id, disposition, text, reviewer_id: "reviewer-1")
    order = state.fetch("work_orders").values.find { |candidate| candidate["status"] == "completed" }
    candidate = HrmKernel::State.project(state, role: "reviewer").dig("milestone", "current_candidate")
    apply_command(
      state,
      "finding.resolve",
      reviewer(reviewer_id),
      "finding_id" => finding_id,
      "candidate_digest" => candidate.fetch("candidate_digest"),
      "disposition" => disposition,
      "text" => text,
      "evidence_refs" => [{
        "work_order_id" => order.fetch("id"),
        "revision" => order.fetch("revision"),
        "check_ids" => order.fetch("check_ids")
      }]
    )
  end

  def direct_reopen(state, intent_id, message_id)
    apply_command(
      state,
      "work_order.reopen",
      worker("worker-1"),
      "work_order_id" => "work-1",
      "expected_revision" => 1,
      "claim_id" => "claim-#{intent_id}",
      "intent" => intent_data(intent_id, message_id, "Also apply this bounded correction.")
    )
  end

  def current_evidence_refs(state)
    state.fetch("work_orders").values.select { |order| order["status"] == "completed" }.map do |order|
      {
        "work_order_id" => order.fetch("id"),
        "revision" => order.fetch("revision"),
        "check_ids" => order.fetch("check_ids")
      }
    end
  end

  def assess_candidate(state, candidate, reviewer_id: "reviewer-1", assessment_id: "assessment-1", dispositions: nil)
    dispositions ||= {
      "scenario-view" => ["accepted", []],
      "scenario-api" => ["accepted", []]
    }
    evidence_refs = current_evidence_refs(state)
    apply_command(
      state,
      "milestone.assess",
      reviewer(reviewer_id),
      "assessment_id" => assessment_id,
      "candidate_digest" => candidate.fetch("candidate_digest"),
      "scenario_dispositions" => dispositions.map do |scenario_id, (disposition, finding_ids)|
        {
          "scenario_id" => scenario_id,
          "disposition" => disposition,
          "evidence_refs" => evidence_refs,
          "finding_ids" => finding_ids
        }
      end
    )
  end

  def decision_request_data
    {
      "decision_id" => "decision-1",
      "revision" => 1,
      "kind" => "business_meaning",
      "exact_effect" => "change customer-visible wording",
      "requirement_ids" => ["req-view"],
      "question" => "Which customer-visible copy is correct?",
      "authority_gap" => {
        "reason" => "The milestone does not select between two business meanings.",
        "source_ref" => "requirements:req-view"
      }
    }
  end

  def request_decision(state, actor: orchestrator, intent_id: nil)
    data = decision_request_data
    data = data.merge("intent_id" => intent_id) if intent_id
    apply_command(state, "decision.request", actor, data)
  end

  def respond_decision(state, revision: 1, exact_effect: "change customer-visible wording",
                       message_id: "m-answer", disposition: "accepted")
    apply_command(
      state,
      "decision.respond",
      operator,
      decision_response_data.merge(
        "revision" => revision,
        "exact_effect" => exact_effect,
        "disposition" => disposition,
        "source" => source(message_id)
      )
    )
  end

  def decision_response_data
    {
      "decision_id" => "decision-1",
      "revision" => 1,
      "kind" => "business_meaning",
      "exact_effect" => "change customer-visible wording",
      "disposition" => "accepted",
      "source" => source("m-answer"),
      "text" => "Use the reviewed wording."
    }
  end

  def assert_kernel_error(expected_code)
    error = assert_raises(HrmKernel::Error) { yield }
    assert_equal expected_code, error.code
    error
  end
end
