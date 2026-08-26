# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "../scripts/hrm_experiment"

class HrmExperimentTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  CAPSULE = File.join(ROOT, "examples/hrm-execution-capsule.example.yaml")
  PRODUCTION_CAPSULE = File.join(ROOT, "examples/hrm-production-observation-capsule.example.yaml")
  EVENTS = File.join(ROOT, "examples/hrm-run-events.example.jsonl")
  SCORECARD = File.join(ROOT, "examples/hrm-run-scorecard.example.yaml")
  SESSION_STATE = File.join(ROOT, "examples/hrm-session-state.example.yaml")
  AUTHORITY_GRANT = File.join(ROOT, "examples/hrm-authority-grant.example.yaml")

  def test_validates_and_derives_the_example_scorecard
    capsule = HrmExperiment.load_yaml(CAPSULE)
    events = HrmExperiment.load_events(EVENTS)
    expected = HrmExperiment.load_yaml(SCORECARD)
    expected_state = HrmExperiment.load_yaml(SESSION_STATE)

    assert HrmExperiment.validate_capsule!(capsule)
    assert HrmExperiment.validate_events!(events)
    assert HrmExperiment.validate_scorecard!(expected)
    assert HrmExperiment.validate_session_state!(expected_state)
    assert_equal expected, HrmExperiment.evaluate(capsule, events)
    assert_equal expected_state, HrmExperiment.derive_session_state(capsule, events)
  end

  def test_rejects_a_capsule_without_the_operator_decision
    capsule = HrmExperiment.load_yaml(CAPSULE)
    capsule.fetch("hrm").delete("operator_decision")

    error = assert_raises(HrmExperiment::ValidationError) do
      HrmExperiment.validate_capsule!(capsule)
    end
    assert_includes error.message, "operator_decision"
  end

  def test_validates_production_observation_continuation_profile
    capsule = HrmExperiment.load_yaml(PRODUCTION_CAPSULE)

    assert HrmExperiment.validate_capsule!(capsule)
  end

  def test_session_state_hash_detects_hand_edits
    state = HrmExperiment.load_yaml(SESSION_STATE)
    state["phase"] = "ready"

    error = assert_raises(HrmExperiment::ValidationError) do
      HrmExperiment.validate_session_state!(state)
    end
    assert_includes error.message, "session state hash mismatch"
  end

  def test_rejects_a_capsule_that_silently_selects_a_noncurrent_hrm
    capsule = HrmExperiment.load_yaml(CAPSULE)
    capsule.dig("target_resolution")["resolved_hrm_id"] = "HRM-3"

    error = assert_raises(HrmExperiment::ValidationError) do
      HrmExperiment.validate_capsule!(capsule)
    end
    assert_includes error.message, "resolved_hrm_id must equal hrm.id"
  end

  def test_exact_noncurrent_hrm_override_is_explicit_and_valid
    capsule = HrmExperiment.load_yaml(CAPSULE)
    capsule.dig("target_resolution").merge!(
      "method" => "explicit_exact_override",
      "resolved_hrm_id" => "HRM-3",
      "explicit_hrm_id" => "HRM-3"
    )
    capsule.dig("hrm")["id"] = "HRM-3"

    assert HrmExperiment.validate_capsule!(capsule)
  end

  def test_workflow_lease_cannot_exceed_workflow_authority
    capsule = HrmExperiment.load_yaml(CAPSULE)
    capsule.dig("authority", "workflow")["publish_review_pr"] = false

    error = assert_raises(HrmExperiment::ValidationError) do
      HrmExperiment.validate_capsule!(capsule)
    end
    assert_includes error.message, "publish_or_update_review_pr"
  end

  def test_named_profile_is_reproducible_and_fails_closed_on_override
    capsule = HrmExperiment.load_yaml(CAPSULE)
    capsule.dig("budgets")["max_ci_minutes"] = 31

    error = assert_raises(HrmExperiment::ValidationError) do
      HrmExperiment.validate_capsule!(capsule)
    end
    assert_includes error.message, "budgets.max_ci_minutes"
    assert_includes error.message, "use custom"
  end

  def test_named_profile_requires_a_preregistered_check_plan
    capsule = HrmExperiment.load_yaml(CAPSULE)
    capsule.dig("verification")["exact_checks"] = []

    error = assert_raises(HrmExperiment::ValidationError) do
      HrmExperiment.validate_capsule!(capsule)
    end
    assert_includes error.message, "verification.exact_checks"
  end

  def test_named_profile_rejects_a_silent_aftercare_override
    capsule = HrmExperiment.load_yaml(CAPSULE)
    capsule.dig("metrics")["aftercare_window_days"] = 0

    error = assert_raises(HrmExperiment::ValidationError) do
      HrmExperiment.validate_capsule!(capsule)
    end
    assert_includes error.message, "metrics.aftercare_window_days"
  end

  def test_duplicate_conclusive_check_fails_the_process_envelope
    capsule = HrmExperiment.load_yaml(CAPSULE)
    events = HrmExperiment.load_events(EVENTS)
    duplicate = Marshal.load(Marshal.dump(events[9]))
    duplicate["sequence"] = 11
    duplicate["occurred_at"] = "2026-08-25T00:31:00Z"
    duplicate["caused_by_sequence"] = 10
    events.insert(10, duplicate)
    events.each_with_index { |event, index| event["sequence"] = index + 1 }

    scorecard = HrmExperiment.evaluate(capsule, events)

    assert_equal 1, scorecard.dig("validation", "duplicate_conclusive_checks")
    assert_equal "fail", scorecard.dig("verdict", "process_envelope")
    assert_equal "fail", scorecard.dig("verdict", "overall")
  end

  def test_missing_check_identity_invalidates_instrumentation
    capsule = HrmExperiment.load_yaml(CAPSULE)
    events = HrmExperiment.load_events(EVENTS)
    events[9]["candidate_sha"] = nil

    scorecard = HrmExperiment.evaluate(capsule, events)

    refute scorecard.dig("verdict", "run_valid")
    assert_equal "run_invalid", scorecard.dig("verdict", "overall")
    assert_includes scorecard.dig("instrumentation", "missing_required_events"), "check_identity:event_10"
  end

  def test_no_material_progress_budget_is_derived_and_enforced
    capsule = HrmExperiment.load_yaml(CAPSULE)
    capsule["experiment_profile"] = "custom"
    capsule.dig("budgets")["no_material_progress_minutes"] = 5

    scorecard = HrmExperiment.evaluate(capsule, HrmExperiment.load_events(EVENTS))

    assert_equal 600, scorecard.dig("flow", "maximum_no_progress_seconds")
    assert_equal "fail", scorecard.dig("verdict", "process_envelope")
    assert_includes scorecard.dig("verdict", "reasons"), "no-material-progress budget exceeded"
  end

  def test_context_redundancy_budget_is_derived_and_enforced
    capsule = HrmExperiment.load_yaml(CAPSULE)
    capsule["experiment_profile"] = "custom"
    capsule.dig("budgets")["max_context_redundancy_ratio"] = 0.05

    scorecard = HrmExperiment.evaluate(capsule, HrmExperiment.load_events(EVENTS))

    assert_equal 0.0606, scorecard.dig("context", "context_redundancy_ratio")
    assert_equal "fail", scorecard.dig("verdict", "process_envelope")
    assert_includes scorecard.dig("verdict", "reasons"), "context-redundancy budget exceeded"
  end

  def test_mechanical_operator_prompt_before_review_ready_fails_process_envelope
    capsule = HrmExperiment.load_yaml(CAPSULE)
    events = HrmExperiment.load_events(EVENTS)
    events[2].dig("details")["decision_kind"] = "routine_workflow"
    events[2].dig("details")["exact_effect"] = "Authorize routine branch creation."

    scorecard = HrmExperiment.evaluate(capsule, events)

    assert_equal 1, scorecard.dig("decisions", "mechanical_operator_prompts_before_review_ready")
    assert_equal "fail", scorecard.dig("verdict", "process_envelope")
    assert_includes scorecard.dig("verdict", "reasons"), "mechanical operator prompt budget exceeded"
  end

  def test_pre_value_context_compaction_fails_process_envelope
    capsule = HrmExperiment.load_yaml(CAPSULE)
    events = HrmExperiment.load_events(EVENTS)
    events.first.dig("context")["context_compactions"] = 1

    scorecard = HrmExperiment.evaluate(capsule, events)

    assert_equal 1, scorecard.dig("context", "context_compactions_before_first_value")
    assert_includes scorecard.dig("verdict", "reasons"), "pre-value context-compaction budget exceeded"
  end

  def test_inline_raw_log_budget_is_enforced
    capsule = HrmExperiment.load_yaml(CAPSULE)
    events = HrmExperiment.load_events(EVENTS)
    events[9].dig("context")["inline_raw_log_bytes"] = 2001

    scorecard = HrmExperiment.evaluate(capsule, events)

    assert_equal 2001, scorecard.dig("context", "inline_raw_log_bytes")
    assert_includes scorecard.dig("verdict", "reasons"), "inline raw-log budget exceeded"
  end

  def test_state_artifact_echo_budget_is_enforced
    capsule = HrmExperiment.load_yaml(CAPSULE)
    events = HrmExperiment.load_events(EVENTS)
    events.first.dig("context")["state_artifact_echo_bytes"] = 1001

    scorecard = HrmExperiment.evaluate(capsule, events)

    assert_equal 1001, scorecard.dig("context", "state_artifact_echo_bytes")
    assert_includes scorecard.dig("verdict", "reasons"), "state-artifact echo budget exceeded"
  end

  def test_decision_request_requires_an_exact_prepared_effect
    events = HrmExperiment.load_events(EVENTS)
    events[2].dig("details").delete("exact_effect")

    error = assert_raises(HrmExperiment::ValidationError) do
      HrmExperiment.validate_events!(events)
    end
    assert_includes error.message, "decision_requested missing exact_effect"
  end

  def test_aftercare_cannot_complete_before_the_preregistered_window
    capsule = HrmExperiment.load_yaml(CAPSULE)
    events = HrmExperiment.load_events(EVENTS)
    events.last["occurred_at"] = "2026-08-26T00:45:00Z"

    scorecard = HrmExperiment.evaluate(capsule, events)

    refute scorecard.dig("instrumentation", "aftercare_complete")
    assert_equal "pending", scorecard.dig("verdict", "outcome_and_safety")
    assert_equal "pending", scorecard.dig("verdict", "overall")
  end

  def test_closed_run_requires_accepted_scenarios_to_pass
    capsule = HrmExperiment.load_yaml(CAPSULE)
    events = HrmExperiment.load_events(EVENTS)
    events[13].dig("details", "scenario_results")["ACC-EX-01"] = "deferred"

    scorecard = HrmExperiment.evaluate(capsule, events)

    assert scorecard.dig("hard_gates", "accepted_scenarios_dispositioned")
    refute scorecard.dig("hard_gates", "accepted_scenarios_passed")
    assert_equal "fail", scorecard.dig("verdict", "overall")
  end

  def test_closed_run_requires_preregistered_checks_on_the_final_candidate
    capsule = HrmExperiment.load_yaml(CAPSULE)
    events = HrmExperiment.load_events(EVENTS)
    events[9].dig("check")["conclusion"] = "failed"

    scorecard = HrmExperiment.evaluate(capsule, events)

    refute scorecard.dig("hard_gates", "required_checks_passed")
    assert_equal "fail", scorecard.dig("verdict", "overall")
  end

  def test_validates_an_exact_head_merge_grant_against_the_capsule
    grant = HrmExperiment.load_yaml(AUTHORITY_GRANT)
    capsule = HrmExperiment.load_yaml(CAPSULE)

    assert HrmExperiment.validate_authority_grant!(grant, capsule)
  end

  def test_live_effect_grant_requires_an_expiry
    grant = HrmExperiment.load_yaml(AUTHORITY_GRANT)
    grant.merge!(
      "grant_type" => "live_effect_authority",
      "allowed_effects" => ["canary_execution"],
      "expires_at" => nil
    )

    error = assert_raises(HrmExperiment::ValidationError) do
      HrmExperiment.validate_authority_grant!(grant, HrmExperiment.load_yaml(CAPSULE))
    end
    assert_includes error.message, "live grant requires an expiry"
  end

  def test_append_event_returns_a_compact_receipt_and_preserves_valid_jsonl
    event = HrmExperiment.load_events(EVENTS).first
    Dir.mktmpdir do |directory|
      path = File.join(directory, "events.jsonl")
      receipt = HrmExperiment.append_event!(path, event)

      assert_equal "event appended: MS-EXAMPLE-2026-08-25-HRM-2 sequence=1 type=session_started", receipt
      assert_equal [event], HrmExperiment.load_events(path)
    end
  end

  def test_derived_state_tracks_unconsumed_authority_grants
    capsule = HrmExperiment.load_yaml(CAPSULE)
    events = HrmExperiment.load_events(EVENTS).first(10)
    events << {
      "schema_version" => "agent_playbooks.hrm_run_event.v0.2",
      "session_id" => capsule["session_id"],
      "hrm_id" => capsule.dig("hrm", "id"),
      "sequence" => 11,
      "event_type" => "authority_granted",
      "occurred_at" => "2026-08-25T00:31:00Z",
      "caused_by_sequence" => 10,
      "details" => {
        "grant_id" => "GRANT-EXAMPLE-MERGE-001",
        "decision_kind" => "exact_head_merge_release",
        "exact_effect" => "Merge the exact reviewed candidate."
      }
    }

    state = HrmExperiment.derive_session_state(capsule, events)

    assert_equal ["GRANT-EXAMPLE-MERGE-001"], state["active_grant_ids"]
  end
end
