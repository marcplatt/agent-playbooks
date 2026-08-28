# frozen_string_literal: true

require "minitest/autorun"
require "open3"
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

  def test_rejects_duplicate_required_api_skill_ids
    capsule = HrmExperiment.load_yaml(CAPSULE)
    duplicate = Marshal.load(Marshal.dump(capsule.dig("project_api_skills", "required_skills").first))
    duplicate["contract_fingerprint"] = "f" * 64
    capsule.dig("project_api_skills", "required_skills") << duplicate

    error = assert_raises(HrmExperiment::ValidationError) do
      HrmExperiment.validate_capsule!(capsule)
    end
    assert_includes error.message, "unique skill_id values"
  end

  def test_rejects_duplicate_context_dependency_ids
    capsule = HrmExperiment.load_yaml(CAPSULE)
    duplicate = Marshal.load(Marshal.dump(capsule.fetch("context_dependencies").first))
    duplicate["source_path"] = "examples/duplicate-capsule.yaml"
    capsule.fetch("context_dependencies") << duplicate

    error = assert_raises(HrmExperiment::ValidationError) do
      HrmExperiment.validate_capsule!(capsule)
    end
    assert_includes error.message, "unique dependency_id values"
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

  def test_mode_mismatch_requires_a_successor_before_work
    capsule = HrmExperiment.load_yaml(PRODUCTION_CAPSULE)
    capsule.dig("entry_condition")["known_missing_deliverable_types"] = ["runtime_change"]

    error = assert_raises(HrmExperiment::ValidationError) do
      HrmExperiment.validate_capsule!(capsule)
    end
    assert_includes error.message, "start a successor capsule"
  end

  def test_supersession_is_bound_to_a_validated_runtime_successor
    predecessor = HrmExperiment.load_yaml(PRODUCTION_CAPSULE)
    events = [session_started_event_for(predecessor)]
    successor = runtime_successor_for(predecessor)

    event = HrmExperiment.supersession_event(
      predecessor,
      events,
      successor,
      Time.iso8601("2026-09-09T01:00:00Z")
    )

    assert_equal "superseded", event.dig("details", "stop_reason")
    assert_equal successor["session_id"], event.dig("details", "successor_session_id")
    assert_equal ["runtime_change"], event.dig("details", "newly_missing_deliverable_types")
    assert_equal HrmExperiment.object_sha256(successor), event.dig("details", "successor_capsule_sha256")
    assert HrmExperiment.validate_events!(events + [event])

    Dir.mktmpdir do |directory|
      path = File.join(directory, "events.jsonl")
      HrmExperiment.append_event!(path, events.first)

      error = assert_raises(HrmExperiment::ValidationError) do
        HrmExperiment.append_event!(path, event)
      end
      assert_includes error.message, "use supersede-with-successor"

      receipt = HrmExperiment.append_event!(path, event, validated_supersession: true)
      assert_includes receipt, "type=stop_reason"
    end
  end

  def test_supersession_rejects_a_dangling_or_same_mode_successor
    predecessor = HrmExperiment.load_yaml(PRODUCTION_CAPSULE)
    events = [session_started_event_for(predecessor)]
    successor = runtime_successor_for(predecessor)
    successor.dig("session_lineage")["predecessor_session_id"] = "WRONG-PREDECESSOR"

    error = assert_raises(HrmExperiment::ValidationError) do
      HrmExperiment.supersession_event(predecessor, events, successor)
    end
    assert_includes error.message, "predecessor_session_id mismatch"

    successor = HrmExperiment.load_yaml(PRODUCTION_CAPSULE)
    successor["session_id"] = "MS-EXAMPLE-2026-09-09-HRM-2-OBSERVATION-2"
    successor.dig("session_lineage").merge!(
      "predecessor_session_id" => predecessor["session_id"],
      "capsule_sequence" => predecessor.dig("session_lineage", "capsule_sequence") + 1,
      "continuation_reason" => "execution_mode_changed",
      "inherited_state_path" => predecessor.dig("metrics", "session_state_path")
    )

    error = assert_raises(HrmExperiment::ValidationError) do
      HrmExperiment.supersession_event(predecessor, events, successor)
    end
    assert_includes error.message, "execution_mode must change"
    assert_includes error.message, "newly missing deliverable"
  end

  def test_legacy_supersede_cli_fails_closed_for_rc12_without_advancing_the_ledger
    predecessor = HrmExperiment.load_yaml(PRODUCTION_CAPSULE)
    successor = runtime_successor_for(predecessor)

    Dir.mktmpdir do |directory|
      events_path = File.join(directory, "events.jsonl")
      successor_path = File.join(directory, "successor.yaml")
      HrmExperiment.append_event!(events_path, session_started_event_for(predecessor))
      File.write(successor_path, YAML.dump(successor), mode: "w", perm: 0o600)
      ledger_before = File.binread(events_path)

      stdout, stderr, status = Open3.capture3(
        "ruby",
        File.join(ROOT, "scripts/hrm_experiment.rb"),
        "supersede-with-successor",
        PRODUCTION_CAPSULE,
        events_path,
        successor_path,
        "2026-09-09T01:00:00Z"
      )

      assert_equal 2, status.exitstatus
      assert_empty stdout
      assert_includes stderr, "legacy hrm_experiment.rb supersede-with-successor is disabled for 0.1.0-rc.12"
      assert_equal ledger_before, File.binread(events_path)
    end
  end

  def test_legacy_guard_cli_fails_closed_for_rc12_without_advancing_the_ledger
    events = HrmExperiment.load_events(EVENTS).first(2)

    Dir.mktmpdir do |directory|
      events_path = File.join(directory, "events.jsonl")
      write_events(events_path, events)
      ledger_before = File.binread(events_path)

      stdout, stderr, status = Open3.capture3(
        "ruby",
        File.join(ROOT, "scripts/hrm_experiment.rb"),
        "guard-action",
        CAPSULE,
        events_path,
        "inspect_read_only",
        "orchestrator",
        "2026-08-25T00:01:00Z"
      )

      assert_equal 2, status.exitstatus
      assert_empty stdout
      assert_includes stderr, "legacy hrm_experiment.rb guard-action is disabled for 0.1.0-rc.12"
      assert_equal ledger_before, File.binread(events_path)
    end
  end

  def test_legacy_append_cli_fails_closed_without_advancing_the_ledger
    events = HrmExperiment.load_events(EVENTS).first(2)

    Dir.mktmpdir do |directory|
      events_path = File.join(directory, "events.jsonl")
      write_events(events_path, events.first(1))
      ledger_before = File.binread(events_path)

      stdout, stderr, status = Open3.capture3(
        "ruby",
        File.join(ROOT, "scripts/hrm_experiment.rb"),
        "append-event",
        events_path,
        stdin_data: JSON.generate(events.last)
      )

      assert_equal 2, status.exitstatus
      assert_empty stdout
      assert_includes stderr, "legacy hrm_experiment.rb append-event is disabled for 0.1.0-rc.12"
      assert_equal ledger_before, File.binread(events_path)
    end
  end

  def test_rc6_legacy_mutation_paths_remain_fail_closed
    rc6_capsule = {"playbook_pin" => {"kernel_version" => "0.1.0-rc.6"}}

    error = assert_raises(HrmExperiment::ValidationError) do
      HrmExperiment.reject_legacy_mutation_cli!("guard-action", rc6_capsule)
    end
    assert_includes error.message, "disabled for 0.1.0-rc.6"
  end

  def test_rc10_legacy_mutation_paths_remain_fail_closed
    rc10_capsule = {"playbook_pin" => {"kernel_version" => "0.1.0-rc.10"}}

    error = assert_raises(HrmExperiment::ValidationError) do
      HrmExperiment.reject_legacy_mutation_cli!("append-event", rc10_capsule)
    end
    assert_includes error.message, "disabled for 0.1.0-rc.10"
  end

  def test_rc11_legacy_mutation_paths_remain_fail_closed
    rc11_capsule = {"playbook_pin" => {"kernel_version" => "0.1.0-rc.11"}}

    error = assert_raises(HrmExperiment::ValidationError) do
      HrmExperiment.reject_legacy_mutation_cli!("append-event", rc11_capsule)
    end
    assert_includes error.message, "disabled for 0.1.0-rc.11"
  end

  def test_named_profile_rejects_role_budget_override
    capsule = HrmExperiment.load_yaml(CAPSULE)
    capsule.dig("budgets", "context_bytes_by_role")["provider_observer"] = 12_001

    error = assert_raises(HrmExperiment::ValidationError) do
      HrmExperiment.validate_capsule!(capsule)
    end
    assert_includes error.message, "budgets.context_bytes_by_role"
    assert_includes error.message, "use custom for an intentional override"
  end

  def test_profile_template_preregisters_the_runtime_role_budget_contract
    template = HrmExperiment.load_yaml(File.join(ROOT, "templates/hrm-experiment-profiles.yaml"))

    HrmExperiment::PROFILE_CONTRACTS.each do |profile_name, contract|
      assert_equal contract.dig("budgets", "context_bytes_by_role"),
                   template.dig("profiles", profile_name, "budgets", "context_bytes_by_role")
    end
  end

  def test_superseded_stop_requires_machine_readable_successor_binding
    predecessor = HrmExperiment.load_yaml(PRODUCTION_CAPSULE)
    event = session_started_event_for(predecessor).merge(
      "sequence" => 2,
      "event_type" => "stop_reason",
      "occurred_at" => "2026-09-09T01:00:00Z",
      "caused_by_sequence" => 1,
      "details" => {"stop_reason" => "superseded", "material_progress" => true}
    )

    error = assert_raises(HrmExperiment::ValidationError) do
      HrmExperiment.validate_events!([session_started_event_for(predecessor), event])
    end
    assert_includes error.message, "superseded stop missing"
  end

  def test_orchestrator_cannot_execute_builder_work
    capsule = HrmExperiment.load_yaml(CAPSULE)
    events = HrmExperiment.load_events(EVENTS).first(2)

    error = assert_raises(HrmExperiment::ValidationError) do
      HrmExperiment.guard_action(capsule, events, "implement_frozen_slice", "orchestrator", Time.iso8601("2026-08-25T00:01:00Z"))
    end
    assert_includes error.message, "requires a fresh builder context"
  end

  def test_read_only_provider_diagnostic_runs_under_one_routine_lease
    capsule = HrmExperiment.load_yaml(CAPSULE)
    events = HrmExperiment.load_events(EVENTS).first(7)
    events << Marshal.load(Marshal.dump(HrmExperiment.load_events(EVENTS)[14])).merge(
      "sequence" => 8,
      "occurred_at" => "2026-08-25T00:12:00Z",
      "caused_by_sequence" => 7,
      "role" => "provider_observer"
    )

    guard = HrmExperiment.guard_action(
      capsule,
      events,
      "inspect_provider_read_only",
      "provider_observer",
      Time.iso8601("2026-08-25T00:13:00Z")
    )

    assert_equal "action_guard_passed", guard["event_type"]
    assert_equal "inspect_provider_read_only", guard.dig("details", "action")
  end

  def test_online_guard_stops_when_no_progress_budget_has_elapsed
    capsule = HrmExperiment.load_yaml(CAPSULE)
    capsule["experiment_profile"] = "custom"
    capsule.dig("budgets")["no_material_progress_minutes"] = 1
    events = HrmExperiment.load_events(EVENTS).first(2)

    guard = HrmExperiment.guard_action(
      capsule,
      events,
      "inspect_read_only",
      "orchestrator",
      Time.iso8601("2026-08-25T00:02:01Z")
    )

    assert_equal "stop_reason", guard["event_type"]
    assert_equal "no_progress", guard.dig("details", "stop_reason")
  end

  def test_online_guard_stops_after_pre_executable_orchestrator_compaction
    capsule = HrmExperiment.load_yaml(CAPSULE)
    events = HrmExperiment.load_events(EVENTS).first(2)
    events[1].dig("context")["context_compactions"] = 1

    guard = HrmExperiment.guard_action(
      capsule,
      events,
      "inspect_read_only",
      "orchestrator",
      Time.iso8601("2026-08-25T00:00:45Z")
    )

    assert_equal "stop_reason", guard["event_type"]
    assert_equal "budget_exhausted", guard.dig("details", "stop_reason")
  end

  def test_login_is_an_operator_action_not_a_decision
    events = HrmExperiment.load_events(EVENTS).first(2)
    events << {
      "schema_version" => "agent_playbooks.hrm_run_event.v0.3",
      "session_id" => "MS-EXAMPLE-2026-08-25-HRM-2",
      "hrm_id" => "HRM-2",
      "sequence" => 3,
      "event_type" => "operator_action_required",
      "occurred_at" => "2026-08-25T00:01:00Z",
      "caused_by_sequence" => 2,
      "details" => {
        "action_id" => "ACTION-EXAMPLE-SIGNIN-001",
        "operator_action_kind" => "sign_in",
        "exact_action" => "Sign in to the already in-scope provider portal."
      }
    }

    assert HrmExperiment.validate_events!(events)
  end

  def test_duplicate_conclusive_check_fails_the_process_envelope
    capsule = HrmExperiment.load_yaml(CAPSULE)
    events = HrmExperiment.load_events(EVENTS)
    duplicate = Marshal.load(Marshal.dump(events[16]))
    duplicate["sequence"] = 23
    duplicate["occurred_at"] = "2026-08-25T00:31:00Z"
    duplicate["caused_by_sequence"] = 17
    events.insert(17, duplicate)
    events.each_with_index { |event, index| event["sequence"] = index + 1 }

    scorecard = HrmExperiment.evaluate(capsule, events)

    assert_equal 1, scorecard.dig("validation", "duplicate_conclusive_checks")
    assert_equal "fail", scorecard.dig("verdict", "process_envelope")
    assert_equal "fail", scorecard.dig("verdict", "overall")
  end

  def test_missing_check_identity_invalidates_instrumentation
    capsule = HrmExperiment.load_yaml(CAPSULE)
    events = HrmExperiment.load_events(EVENTS)
    events[16]["candidate_sha"] = nil

    scorecard = HrmExperiment.evaluate(capsule, events)

    refute scorecard.dig("verdict", "run_valid")
    assert_equal "run_invalid", scorecard.dig("verdict", "overall")
    assert_includes scorecard.dig("instrumentation", "missing_required_events"), "check_identity:event_17"
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

  def test_uninterrupted_cold_start_must_reach_semantics_and_handoff_within_budget
    capsule = HrmExperiment.load_yaml(CAPSULE)
    events = [
      {
        "schema_version" => "agent_playbooks.hrm_run_event.v0.5",
        "session_id" => capsule["session_id"],
        "hrm_id" => capsule.dig("hrm", "id"),
        "sequence" => 1,
        "event_type" => "session_started",
        "occurred_at" => "2026-08-25T00:00:00Z",
        "role" => "orchestrator"
      },
      {
        "schema_version" => "agent_playbooks.hrm_run_event.v0.5",
        "session_id" => capsule["session_id"],
        "hrm_id" => capsule.dig("hrm", "id"),
        "sequence" => 2,
        "event_type" => "semantic_ready",
        "occurred_at" => "2026-08-25T00:00:31Z",
        "caused_by_sequence" => 1,
        "role" => "orchestrator",
        "details" => {"material_progress" => true}
      },
      {
        "schema_version" => "agent_playbooks.hrm_run_event.v0.5",
        "session_id" => capsule["session_id"],
        "hrm_id" => capsule.dig("hrm", "id"),
        "sequence" => 3,
        "event_type" => "worker_handoff_started",
        "occurred_at" => "2026-08-25T00:00:32Z",
        "caused_by_sequence" => 2,
        "role" => "provider_observer"
      }
    ]

    scorecard = HrmExperiment.evaluate(capsule, events)

    assert_equal 31, scorecard.dig("flow", "semantic_readiness_seconds")
    assert_equal 32, scorecard.dig("flow", "startup_to_first_worker_handoff_seconds")
    assert_equal "fail", scorecard.dig("verdict", "process_envelope")
    assert_includes scorecard.dig("verdict", "reasons"), "semantic-readiness startup budget exceeded"
    assert_includes scorecard.dig("verdict", "reasons"), "worker-handoff startup budget exceeded"
  end

  def test_context_redundancy_budget_is_derived_and_enforced
    capsule = HrmExperiment.load_yaml(CAPSULE)
    capsule["experiment_profile"] = "custom"
    capsule.dig("budgets")["max_context_redundancy_ratio"] = 0.03

    scorecard = HrmExperiment.evaluate(capsule, HrmExperiment.load_events(EVENTS))

    assert_equal 0.0385, scorecard.dig("context", "context_redundancy_ratio")
    assert_equal "fail", scorecard.dig("verdict", "process_envelope")
    assert_includes scorecard.dig("verdict", "reasons"), "context-redundancy budget exceeded"
  end

  def test_declared_external_kernel_dependency_does_not_escape_context_scope
    capsule = HrmExperiment.load_yaml(CAPSULE)
    events = HrmExperiment.load_events(EVENTS).first(2)
    events[1]["schema_version"] = "agent_playbooks.hrm_run_event.v0.4"
    events[1].fetch("context").merge!(
      "loaded_dependency_ids" => ["example.execution-capsule", "ap.exec.kernel"],
      "outside_declared_dependency_ids" => [],
      "files_outside_declared_dependencies" => 0
    )

    scorecard = HrmExperiment.evaluate(capsule, events)

    assert scorecard.dig("verdict", "run_valid")
    assert_equal "pending", scorecard.dig("verdict", "process_envelope")
    refute_includes scorecard.dig("verdict", "reasons"), "context scope escape"
  end

  def test_context_dependency_evidence_must_match_declared_ids_and_count
    capsule = HrmExperiment.load_yaml(CAPSULE)
    events = HrmExperiment.load_events(EVENTS).first(2)
    events[1]["schema_version"] = "agent_playbooks.hrm_run_event.v0.4"
    events[1].fetch("context").merge!(
      "loaded_dependency_ids" => ["example.execution-capsule", "undeclared.file"],
      "outside_declared_dependency_ids" => ["undeclared.file"],
      "files_outside_declared_dependencies" => 0
    )

    scorecard = HrmExperiment.evaluate(capsule, events)

    refute scorecard.dig("verdict", "run_valid")
    assert_equal "run_invalid", scorecard.dig("verdict", "overall")
    assert_includes scorecard.dig("verdict", "reasons"), "context dependency count mismatch at event 2"
  end

  def test_auditable_context_scope_escape_fails_process_and_overall
    capsule = HrmExperiment.load_yaml(CAPSULE)
    events = HrmExperiment.load_events(EVENTS).first(2)
    events[1]["schema_version"] = "agent_playbooks.hrm_run_event.v0.4"
    events[1].fetch("context").merge!(
      "loaded_dependency_ids" => ["example.execution-capsule", "undeclared.file"],
      "outside_declared_dependency_ids" => ["undeclared.file"],
      "files_outside_declared_dependencies" => 1
    )

    scorecard = HrmExperiment.evaluate(capsule, events)

    assert scorecard.dig("verdict", "run_valid")
    assert_equal "fail", scorecard.dig("verdict", "process_envelope")
    assert_equal "fail", scorecard.dig("verdict", "overall")
    assert_includes scorecard.dig("verdict", "reasons"), "context scope escape"
  end

  def test_routine_workflow_cannot_be_serialized_as_an_operator_decision
    events = HrmExperiment.load_events(EVENTS)
    events[3].dig("details")["decision_kind"] = "routine_workflow"
    events[3].dig("details")["exact_effect"] = "Authorize routine branch creation."

    error = assert_raises(HrmExperiment::ValidationError) { HrmExperiment.validate_events!(events) }
    assert_includes error.message, "not a genuine human gate"
  end

  def test_read_only_work_cannot_be_serialized_as_external_effect_authority
    events = HrmExperiment.load_events(EVENTS)
    events[3].dig("details").merge!(
      "decision_kind" => "external_effect_authority",
      "exact_effect" => "Inspect provider health without mutation."
    )

    error = assert_raises(HrmExperiment::ValidationError) { HrmExperiment.validate_events!(events) }
    assert_includes error.message, "mutation or transmission effect_class"
  end

  def test_pre_executable_context_compaction_fails_process_envelope
    capsule = HrmExperiment.load_yaml(CAPSULE)
    events = HrmExperiment.load_events(EVENTS)
    events[1].dig("context")["context_compactions"] = 1

    scorecard = HrmExperiment.evaluate(capsule, events)

    assert_equal 1, scorecard.dig("context", "orchestrator_context_compactions_before_first_executable_delta")
    assert_includes scorecard.dig("verdict", "reasons"), "pre-expected-value context-compaction budget exceeded"
  end

  def test_inline_raw_log_budget_is_enforced
    capsule = HrmExperiment.load_yaml(CAPSULE)
    events = HrmExperiment.load_events(EVENTS)
    events[14].dig("context")["inline_raw_log_bytes"] = 2001

    scorecard = HrmExperiment.evaluate(capsule, events)

    assert_equal 2001, scorecard.dig("context", "inline_raw_log_bytes")
    assert_includes scorecard.dig("verdict", "reasons"), "inline raw-log budget exceeded"
  end

  def test_state_artifact_echo_budget_is_enforced
    capsule = HrmExperiment.load_yaml(CAPSULE)
    events = HrmExperiment.load_events(EVENTS)
    events[1].dig("context")["state_artifact_echo_bytes"] = 1001

    scorecard = HrmExperiment.evaluate(capsule, events)

    assert_equal 1001, scorecard.dig("context", "state_artifact_echo_bytes")
    assert_includes scorecard.dig("verdict", "reasons"), "state-artifact echo budget exceeded"
  end

  def test_decision_request_requires_an_exact_prepared_effect
    events = HrmExperiment.load_events(EVENTS)
    events[3].dig("details").delete("exact_effect")

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
    events[20].dig("details", "scenario_results")["ACC-EX-01"] = "deferred"

    scorecard = HrmExperiment.evaluate(capsule, events)

    assert scorecard.dig("hard_gates", "accepted_scenarios_dispositioned")
    refute scorecard.dig("hard_gates", "accepted_scenarios_passed")
    assert_equal "fail", scorecard.dig("verdict", "overall")
  end

  def test_closed_run_requires_preregistered_checks_on_the_final_candidate
    capsule = HrmExperiment.load_yaml(CAPSULE)
    events = HrmExperiment.load_events(EVENTS)
    events[16].dig("check")["conclusion"] = "failed"

    scorecard = HrmExperiment.evaluate(capsule, events)

    refute scorecard.dig("hard_gates", "required_checks_passed")
    assert_equal "fail", scorecard.dig("verdict", "overall")
  end

  def test_validates_an_exact_head_merge_grant_against_the_capsule
    grant = HrmExperiment.load_yaml(AUTHORITY_GRANT)
    capsule = HrmExperiment.load_yaml(CAPSULE)

    assert HrmExperiment.validate_authority_grant!(grant, capsule)
  end

  def test_external_effect_grant_requires_an_expiry
    grant = HrmExperiment.load_yaml(AUTHORITY_GRANT)
    grant.merge!(
      "grant_type" => "external_effect_authority",
      "allowed_effects" => ["canary_execution"],
      "expires_at" => nil
    )

    error = assert_raises(HrmExperiment::ValidationError) do
      HrmExperiment.validate_authority_grant!(grant, HrmExperiment.load_yaml(CAPSULE))
    end
    assert_includes error.message, "external-effect grant requires an expiry"
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
      "schema_version" => "agent_playbooks.hrm_run_event.v0.3",
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

  private

  def write_events(path, events)
    File.write(
      path,
      events.map { |event| JSON.generate(event) }.join("\n") + "\n",
      mode: "w",
      perm: 0o600
    )
  end

  def session_started_event_for(capsule)
    {
      "schema_version" => "agent_playbooks.hrm_run_event.v0.3",
      "session_id" => capsule["session_id"],
      "hrm_id" => capsule.dig("hrm", "id"),
      "sequence" => 1,
      "event_type" => "session_started",
      "occurred_at" => "2026-09-09T00:00:00Z",
      "role" => "orchestrator"
    }
  end

  def runtime_successor_for(predecessor)
    successor = HrmExperiment.load_yaml(CAPSULE)
    successor["session_id"] = "MS-EXAMPLE-2026-09-09-HRM-2-RUNTIME-SUCCESSOR"
    successor["repository_bases"] = Marshal.load(Marshal.dump(predecessor["repository_bases"]))
    successor["target_resolution"] = Marshal.load(Marshal.dump(predecessor["target_resolution"]))
    successor["hrm"] = Marshal.load(Marshal.dump(predecessor["hrm"]))
    successor.dig("session_lineage").merge!(
      "predecessor_session_id" => predecessor["session_id"],
      "capsule_sequence" => predecessor.dig("session_lineage", "capsule_sequence") + 1,
      "continuation_reason" => "execution_mode_changed",
      "inherited_state_path" => predecessor.dig("metrics", "session_state_path")
    )
    successor
  end
end
