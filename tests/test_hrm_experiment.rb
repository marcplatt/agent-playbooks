# frozen_string_literal: true

require "minitest/autorun"
require_relative "../scripts/hrm_experiment"

class HrmExperimentTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  CAPSULE = File.join(ROOT, "examples/hrm-execution-capsule.example.yaml")
  EVENTS = File.join(ROOT, "examples/hrm-run-events.example.jsonl")
  SCORECARD = File.join(ROOT, "examples/hrm-run-scorecard.example.yaml")

  def test_validates_and_derives_the_example_scorecard
    capsule = HrmExperiment.load_yaml(CAPSULE)
    events = HrmExperiment.load_events(EVENTS)
    expected = HrmExperiment.load_yaml(SCORECARD)

    assert HrmExperiment.validate_capsule!(capsule)
    assert HrmExperiment.validate_events!(events)
    assert HrmExperiment.validate_scorecard!(expected)
    assert_equal expected, HrmExperiment.evaluate(capsule, events)
  end

  def test_rejects_a_capsule_without_the_operator_decision
    capsule = HrmExperiment.load_yaml(CAPSULE)
    capsule.fetch("hrm").delete("operator_decision")

    error = assert_raises(HrmExperiment::ValidationError) do
      HrmExperiment.validate_capsule!(capsule)
    end
    assert_includes error.message, "operator_decision"
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
end
