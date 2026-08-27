# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "../scripts/hrm_supervisor"

class HrmSupervisorTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  CAPSULE = File.join(ROOT, "examples/hrm-execution-capsule.example.yaml")
  EVENTS = File.join(ROOT, "examples/hrm-run-events.example.jsonl")

  def test_resume_atomically_starts_an_empty_ledger_and_dispatches_first_worker
    capsule = HrmExperiment.load_yaml(CAPSULE)

    with_run(capsule, []) do |capsule_path, events_path, paths|
      receipt = HrmSupervisor.resume(capsule_path, events_path, Time.iso8601("2026-08-27T22:00:00Z"))
      events = HrmExperiment.load_events(events_path)
      projection = JSON.parse(File.read(paths["projection"], encoding: "UTF-8"))
      dispatch = JSON.parse(File.read(paths["dispatch"], encoding: "UTF-8"))

      assert_equal "start", receipt["action"]
      assert_equal 1, receipt["ledger_cursor"]
      assert_equal "session_started", receipt["event_type"]
      assert_equal "inventory_runtime_bindings", receipt["next_action"]
      assert_equal 1, events.length
      assert_equal "2026-08-27T22:00:00Z", events.first["occurred_at"]
      assert projection.dig("scorecard_verdict", "run_valid")
      assert_equal "silent", projection.dig("operator_projection", "visibility")
      assert_equal "inventory_runtime_bindings", dispatch.dig("assignment", "action")
      assert_equal "provider_observer", dispatch.dig("assignment", "role")
    end
  end

  def test_resume_repairs_stale_projections_at_the_exact_ledger_cursor
    capsule = HrmExperiment.load_yaml(CAPSULE)
    all_events = HrmExperiment.load_events(EVENTS).first(7)

    with_run(capsule, all_events.first(3)) do |capsule_path, events_path, paths|
      HrmSupervisor.resume(capsule_path, events_path)
      File.write(
        events_path,
        all_events.map { |event| JSON.generate(event) }.join("\n") + "\n",
        mode: "w",
        perm: 0o600
      )

      receipt = HrmSupervisor.resume(capsule_path, events_path)
      state = HrmExperiment.load_yaml(paths["state"])
      scorecard = HrmExperiment.load_yaml(paths["scorecard"])
      projection = JSON.parse(File.read(paths["projection"], encoding: "UTF-8"))

      assert_equal 4, receipt["projection_lag_events_before"]
      assert_equal 0, receipt["projection_lag_events_after"]
      assert receipt["projection_repaired"]
      assert_equal 7, state["last_event_sequence"]
      assert_equal 7, scorecard.dig("run_identity", "event_count")
      assert_equal 7, projection["ledger_cursor"]
      assert_equal state["state_hash"], projection["state_hash"]
      assert HrmSupervisor.validate_projection!(projection)
    end
  end

  def test_attention_firewall_projects_only_open_operator_interrupts
    capsule = HrmExperiment.load_yaml(CAPSULE)
    session_started = HrmExperiment.load_events(EVENTS).first

    with_run(capsule, [session_started]) do |capsule_path, events_path, paths|
      append_event(capsule_path, events_path, "operator_action_required", "2026-08-25T00:01:00Z", {
        "action_id" => "ACTION-UNLOCK-001",
        "operator_action_kind" => "credential_unlock",
        "operator_interrupt_reason" => "environment_boundary",
        "exact_action" => "Unlock the local credential store."
      })
      append_event(capsule_path, events_path, "decision_requested", "2026-08-25T00:02:00Z", {
        "decision_id" => "DEC-AUTH-001",
        "decision_kind" => "business_meaning",
        "interrupt_class" => "S1",
        "exact_effect" => "Confirm the identity meaning."
      })
      append_event(capsule_path, events_path, "finding_opened", "2026-08-25T00:03:00Z", {
        "finding_id" => "FINDING-CONTRACT-001",
        "interrupt_class" => "S1",
        "blocking" => true,
        "note" => "A required read contract is absent."
      })

      projection = JSON.parse(File.read(paths["projection"], encoding: "UTF-8"))
      assert_equal %w[operator_action decision blocking_finding], projection["attention"].map { |item| item["kind"] }
      assert_equal "await_operator_action", projection["next_action"]

      append_event(capsule_path, events_path, "operator_action_completed", "2026-08-25T00:04:00Z", {
        "action_id" => "ACTION-UNLOCK-001",
        "operator_action_kind" => "credential_unlock",
        "operator_interrupt_reason" => "environment_boundary",
        "exact_action" => "Unlock the local credential store."
      })
      append_event(capsule_path, events_path, "decision_received", "2026-08-25T00:05:00Z", {
        "decision_id" => "DEC-AUTH-001",
        "decision_kind" => "business_meaning",
        "exact_effect" => "Confirm the identity meaning."
      })
      append_event(capsule_path, events_path, "finding_dispositioned", "2026-08-25T00:06:00Z", {
        "finding_id" => "FINDING-CONTRACT-001",
        "disposition" => "current_claim_blocker",
        "note" => "Routed to the contract owner."
      })

      projection = JSON.parse(File.read(paths["projection"], encoding: "UTF-8"))
      assert_empty projection["attention"]
      assert_equal "inventory_runtime_bindings", projection["next_action"]
    end
  end

  def test_concurrent_appends_are_serialized_and_refresh_one_projection
    capsule = HrmExperiment.load_yaml(CAPSULE)
    session_started = HrmExperiment.load_events(EVENTS).first

    with_run(capsule, [session_started]) do |capsule_path, events_path, paths|
      errors = Queue.new
      threads = 2.times.map do |index|
        Thread.new do
          event = {
            "schema_version" => "agent_playbooks.hrm_run_event.v0.5",
            "event_type" => "finding_opened",
            "occurred_at" => "2026-08-25T00:01:00Z",
            "role" => "orchestrator",
            "details" => {
              "finding_id" => "FINDING-CONCURRENT-#{index}",
              "interrupt_class" => "S3",
              "blocking" => false,
              "note" => "Reversible technical finding #{index}."
            }
          }
          HrmSupervisor.append(capsule_path, events_path, event)
        rescue StandardError => e
          errors << e
        end
      end
      threads.each(&:join)

      assert errors.empty?, errors.empty? ? nil : errors.pop.message
      events = HrmExperiment.load_events(events_path)
      projection = JSON.parse(File.read(paths["projection"], encoding: "UTF-8"))
      assert_equal [1, 2, 3], events.map { |event| event["sequence"] }
      assert_equal 3, projection["ledger_cursor"]
      assert_equal 3, HrmExperiment.load_yaml(paths["state"])["last_event_sequence"]
      assert_equal 3, HrmExperiment.load_yaml(paths["scorecard"]).dig("run_identity", "event_count")
    end
  end

  def test_terminal_run_is_compact_and_does_not_request_more_work
    capsule = HrmExperiment.load_yaml(CAPSULE)
    events = HrmExperiment.load_events(EVENTS)

    with_run(capsule, events) do |capsule_path, events_path, paths|
      receipt = HrmSupervisor.resume(capsule_path, events_path)
      projection = JSON.parse(File.read(paths["projection"], encoding: "UTF-8"))

      assert_equal "terminal", receipt["next_action"]
      assert_equal "closed", projection["terminal_state"]
      assert_operator receipt["projection_bytes"], :<=, HrmSupervisor::MAX_PROJECTION_BYTES
    end
  end

  def test_resume_projects_reusable_api_skills_without_rediscovery
    capsule = HrmExperiment.load_yaml(CAPSULE)
    session_started = HrmExperiment.load_events(EVENTS).first

    with_run(capsule, [session_started]) do |capsule_path, events_path, paths|
      receipt = HrmSupervisor.resume(capsule_path, events_path)
      projection = JSON.parse(File.read(paths["projection"], encoding: "UTF-8"))

      assert_equal 1, receipt["reusable_api_skill_count"]
      assert_equal 0, receipt["missing_api_skill_count"]
      assert_equal ["product-master.catalog-price.read"],
                   projection.dig("project_api_skills", "reusable_skill_ids")
      assert_equal "inventory_runtime_bindings", projection["next_action"]

      error = assert_raises(HrmExperiment::ValidationError) do
        HrmSupervisor.guard(
          capsule_path,
          events_path,
          "discover_project_api_skills",
          "provider_observer",
          Time.iso8601("2026-08-25T00:01:00Z")
        )
      end
      assert_includes error.message, "do not repeat API discovery"
      assert_equal 1, HrmExperiment.load_events(events_path).length
    end
  end

  def test_resume_emits_compiled_dispatch_and_quiet_operator_projection
    capsule = HrmExperiment.load_yaml(CAPSULE)
    session_started = HrmExperiment.load_events(EVENTS).first

    with_run(capsule, [session_started]) do |capsule_path, events_path, paths|
      receipt = HrmSupervisor.resume(capsule_path, events_path)
      projection = JSON.parse(File.read(paths["projection"], encoding: "UTF-8"))
      dispatch = JSON.parse(File.read(paths["dispatch"], encoding: "UTF-8"))

      assert_equal "inventory_runtime_bindings", receipt["next_action"]
      assert_equal "silent", projection.dig("operator_projection", "visibility")
      assert_equal "inventory_runtime_bindings", dispatch.dig("assignment", "action")
      assert_equal "provider_observer", dispatch.dig("assignment", "role")
      assert_equal "hashes_only_unless_changed", dispatch.dig("cache", "load_policy")
      assert_equal dispatch["dispatch_hash"], projection.dig("dispatch_ref", "sha256")
      assert_operator receipt["dispatch_bytes"], :<=, HrmSupervisor::MAX_DISPATCH_BYTES
      assert HrmSupervisor.validate_dispatch!(dispatch)
    end
  end

  def test_local_private_path_choice_cannot_be_serialized_as_operator_attention
    capsule = HrmExperiment.load_yaml(CAPSULE)
    session_started = HrmExperiment.load_events(EVENTS).first

    with_run(capsule, [session_started]) do |capsule_path, events_path, _paths|
      error = assert_raises(HrmExperiment::ValidationError) do
        HrmSupervisor.append(capsule_path, events_path, {
          "schema_version" => "agent_playbooks.hrm_run_event.v0.5",
          "event_type" => "operator_action_required",
          "occurred_at" => "2026-08-25T00:01:00Z",
          "role" => "operator",
          "details" => {
            "action_id" => "ACTION-LOCAL-PATH-001",
            "operator_action_kind" => "private_value_entry",
            "operator_interrupt_reason" => "owner_private_value",
            "exact_action" => "Choose a reversible local module path."
          }
        })
      end
      assert_includes error.message, "credential, destination, customer_case, or private_identity"
      assert_equal 1, HrmExperiment.load_events(events_path).length
    end
  end

  def test_first_executable_requires_prebuild_runtime_inventory
    capsule = HrmExperiment.load_yaml(CAPSULE)
    session_started = HrmExperiment.load_events(EVENTS).first
    seams = capsule.dig("function_slice", "required_real_seams")

    with_run(capsule, [session_started]) do |capsule_path, events_path, _paths|
      error = assert_raises(HrmExperiment::ValidationError) do
        HrmSupervisor.append(capsule_path, events_path, {
          "schema_version" => "agent_playbooks.hrm_run_event.v0.5",
          "event_type" => "first_executable_delta",
          "occurred_at" => "2026-08-25T00:01:00Z",
          "role" => "builder",
          "candidate_sha" => "3" * 40,
          "details" => {
            "deliverable_type" => "runtime_change",
            "material_progress" => true,
            "runtime_readiness" => {
              "required_real_seams" => seams,
              "bound_real_seams" => seams,
              "zero_effect_construction_verified" => true,
              "evidence_sha256" => "4" * 64
            }
          }
        })
      end
      assert_includes error.message, "run-invalid"
      assert_equal 1, HrmExperiment.load_events(events_path).length
    end
  end

  def test_transition_generates_and_binds_the_mode_successor
    capsule = HrmExperiment.load_yaml(File.join(ROOT, "examples/hrm-production-observation-capsule.example.yaml"))
    session_started = {
      "schema_version" => "agent_playbooks.hrm_run_event.v0.5",
      "session_id" => capsule["session_id"],
      "hrm_id" => capsule.dig("hrm", "id"),
      "sequence" => 1,
      "event_type" => "session_started",
      "occurred_at" => "2026-08-25T00:00:00Z",
      "role" => "orchestrator"
    }

    with_run(capsule, [session_started]) do |capsule_path, events_path, _paths|
      successor_path = File.join(File.dirname(capsule_path), "generated-successor.capsule.yaml")
      receipt = HrmSupervisor.transition(
        capsule_path,
        events_path,
        successor_path,
        "MS-EXAMPLE-2026-08-25-HRM-2-BUILD-2",
        "runtime_build",
        Time.iso8601("2026-08-25T00:01:00Z")
      )
      successor = HrmExperiment.load_yaml(successor_path)
      events = HrmExperiment.load_events(events_path)

      assert_equal "runtime_build", successor["execution_mode"]
      assert_equal "agent_playbooks.hrm_execution_capsule.v0.7", successor["schema_version"]
      assert_equal capsule["session_id"], successor.dig("session_lineage", "predecessor_session_id")
      assert_equal "superseded", events.last.dig("details", "stop_reason")
      assert_equal successor["session_id"], receipt["successor_session_id"]
      assert HrmExperiment.validate_capsule!(successor)
    end
  end

  def test_production_observation_dispatches_private_preparation_without_kernel_reread
    capsule = HrmExperiment.load_yaml(File.join(ROOT, "examples/hrm-production-observation-capsule.example.yaml"))
    session_started = {
      "schema_version" => "agent_playbooks.hrm_run_event.v0.5",
      "session_id" => capsule["session_id"],
      "hrm_id" => capsule.dig("hrm", "id"),
      "sequence" => 1,
      "event_type" => "session_started",
      "occurred_at" => "2026-08-25T00:00:00Z",
      "role" => "orchestrator"
    }

    with_run(capsule, [session_started]) do |capsule_path, events_path, paths|
      receipt = HrmSupervisor.resume(capsule_path, events_path)
      dispatch = HrmExperiment.load_json(paths["dispatch"])

      assert_equal "prepare_private_inputs", receipt["next_action"]
      assert_equal "prepare_private_inputs", dispatch.dig("assignment", "action")
      assert_equal "provider_observer", dispatch.dig("assignment", "role")
      assert_equal "hashes_only_unless_changed", dispatch.dig("cache", "load_policy")
    end
  end

  def test_changed_skill_fingerprint_routes_only_missing_discovery
    capsule = HrmExperiment.load_yaml(CAPSULE)
    capsule.dig("project_api_skills", "required_skills", 0)["contract_fingerprint"] = "c" * 64
    session_started = HrmExperiment.load_events(EVENTS).first

    Dir.mktmpdir("hrm-supervisor", ROOT) do |directory|
      capsule["project_root"] = directory
      capsule.dig("metrics")["event_log_path"] = File.basename(capsule.dig("metrics", "event_log_path"))
      capsule.dig("metrics")["session_state_path"] = File.basename(capsule.dig("metrics", "session_state_path"))
      capsule.dig("metrics")["scorecard_path"] = File.basename(capsule.dig("metrics", "scorecard_path"))
      capsule_path = File.join(directory, "capsule.yaml")
      File.write(capsule_path, YAML.dump(capsule), mode: "w", perm: 0o600)
      events_path = File.join(directory, File.basename(capsule.dig("metrics", "event_log_path")))
      File.write(events_path, "#{JSON.generate(session_started)}\n", mode: "w", perm: 0o600)

      receipt = HrmSupervisor.resume(capsule_path, events_path)
      assert_equal 0, receipt["reusable_api_skill_count"]
      assert_equal 1, receipt["missing_api_skill_count"]
      assert_equal "discover_missing_project_api_skills", receipt["next_action"]
    end
  end

  def test_project_root_binding_rejects_same_basename_outside_the_run_root
    capsule = HrmExperiment.load_yaml(CAPSULE)
    Dir.mktmpdir("hrm-supervisor", ROOT) do |directory|
      capsule["project_root"] = directory
      capsule.dig("metrics")["event_log_path"] = "run/events.jsonl"
      outside = File.join(File.dirname(directory), "events.jsonl")

      error = assert_raises(HrmExperiment::ValidationError) do
        HrmSupervisor.artifact_paths(capsule, outside)
      end
      assert_includes error.message, "project-root-bound"
      refute File.exist?(outside)
    end
  end

  def test_run_invalid_scorecard_stops_projection_and_future_writes
    capsule = HrmExperiment.load_yaml(CAPSULE)
    started = HrmExperiment.load_events(EVENTS).first
    unbound_response = {
      "schema_version" => "agent_playbooks.hrm_run_event.v0.4",
      "session_id" => capsule["session_id"],
      "hrm_id" => capsule.dig("hrm", "id"),
      "sequence" => 2,
      "event_type" => "decision_received",
      "occurred_at" => "2026-08-25T00:01:00Z",
      "caused_by_sequence" => 1,
      "role" => "orchestrator",
      "details" => {
        "decision_id" => "DEC-UNBOUND-001",
        "decision_kind" => "business_meaning",
        "exact_effect" => "Accepted without a bound request."
      }
    }

    with_run(capsule, [started, unbound_response]) do |capsule_path, events_path, paths|
      receipt = HrmSupervisor.resume(capsule_path, events_path)
      projection = JSON.parse(File.read(paths["projection"], encoding: "UTF-8"))
      assert_equal "stop_run_invalid", receipt["next_action"]
      refute projection.dig("scorecard_verdict", "run_valid")

      error = assert_raises(HrmExperiment::ValidationError) do
        HrmSupervisor.append(capsule_path, events_path, {
          "schema_version" => "agent_playbooks.hrm_run_event.v0.4",
          "event_type" => "finding_opened",
          "occurred_at" => "2026-08-25T00:02:00Z",
          "details" => {"finding_id" => "F-1", "blocking" => false, "note" => "Must not append."}
        })
      end
      assert_includes error.message, "run-invalid"
      assert_equal 2, HrmExperiment.load_events(events_path).length
    end
  end

  def test_active_context_failure_stops_projection
    capsule = HrmExperiment.load_yaml(CAPSULE)
    started = HrmExperiment.load_events(EVENTS).first
    context = Marshal.load(Marshal.dump(HrmExperiment.load_events(EVENTS)[1]))
    context.dig("context")["active_context_bytes"] = capsule.dig("budgets", "context_bytes_by_role", "orchestrator") + 1

    with_run(capsule, [started, context]) do |capsule_path, events_path, paths|
      receipt = HrmSupervisor.resume(capsule_path, events_path)
      projection = JSON.parse(File.read(paths["projection"], encoding: "UTF-8"))
      assert_equal "stop_process_envelope", receipt["next_action"]
      assert_equal "fail", projection.dig("scorecard_verdict", "process_envelope")
    end
  end

  def test_declared_external_kernel_context_reaches_routine_projection
    capsule = HrmExperiment.load_yaml(CAPSULE)
    started = HrmExperiment.load_events(EVENTS).first
    context = Marshal.load(Marshal.dump(HrmExperiment.load_events(EVENTS)[1]))
    context["schema_version"] = "agent_playbooks.hrm_run_event.v0.5"
    context.delete("sequence")
    context.delete("session_id")
    context.delete("hrm_id")
    context.delete("caused_by_sequence")
    context.fetch("context").merge!(
      "loaded_dependency_ids" => ["example.execution-capsule", "ap.exec.kernel"],
      "outside_declared_dependency_ids" => [],
      "files_outside_declared_dependencies" => 0
    )

    with_run(capsule, [started]) do |capsule_path, events_path, paths|
      receipt = HrmSupervisor.append(capsule_path, events_path, context)
      projection = JSON.parse(File.read(paths["projection"], encoding: "UTF-8"))

      assert_equal "inventory_runtime_bindings", receipt["next_action"]
      assert_equal "pending", projection.dig("scorecard_verdict", "process_envelope")
      assert_equal 2, projection["ledger_cursor"]
    end
  end

  def test_inherited_decision_receipt_is_bound_to_immutable_predecessor_event
    capsule = HrmExperiment.load_yaml(CAPSULE)
    predecessor_events = HrmExperiment.load_events(EVENTS).first(4)
    request = predecessor_events.last

    Dir.mktmpdir("hrm-supervisor", ROOT) do |directory|
      predecessor_path = File.join(directory, "predecessor.events.jsonl")
      predecessor_bytes = predecessor_events.map { |event| JSON.generate(event) }.join("\n") + "\n"
      File.write(predecessor_path, predecessor_bytes, mode: "w", perm: 0o600)

      receipt = {
        "decision_id" => request.dig("details", "decision_id"),
        "request_session_id" => request["session_id"],
        "request_sequence" => request["sequence"],
        "request_event_sha256" => HrmExperiment.object_sha256(request),
        "decision_kind" => request.dig("details", "decision_kind"),
        "effect_class" => request.dig("details", "effect_class")
      }
      capsule["session_id"] = "MS-EXAMPLE-2026-08-25-HRM-2-RC7"
      capsule["project_root"] = directory
      capsule["session_lineage"] = {
        "predecessor_session_id" => request["session_id"],
        "capsule_sequence" => 2,
        "continuation_reason" => "playbook_changed",
        "inherited_state_path" => "predecessor.state.yaml",
        "predecessor_event_log_path" => File.basename(predecessor_path),
        "predecessor_event_log_sha256" => Digest::SHA256.hexdigest(predecessor_bytes),
        "decision_receipts" => [receipt]
      }
      capsule.dig("metrics")["event_log_path"] = "successor.events.jsonl"
      capsule.dig("metrics")["session_state_path"] = "successor.state.yaml"
      capsule.dig("metrics")["scorecard_path"] = "successor.scorecard.yaml"
      capsule_path = File.join(directory, "capsule.yaml")
      File.write(capsule_path, YAML.dump(capsule), mode: "w", perm: 0o600)

      successor_events = [
        {
          "schema_version" => "agent_playbooks.hrm_run_event.v0.4",
          "session_id" => capsule["session_id"],
          "hrm_id" => capsule.dig("hrm", "id"),
          "sequence" => 1,
          "event_type" => "session_started",
          "occurred_at" => "2026-08-25T01:00:00Z",
          "role" => "orchestrator"
        },
        {
          "schema_version" => "agent_playbooks.hrm_run_event.v0.4",
          "session_id" => capsule["session_id"],
          "hrm_id" => capsule.dig("hrm", "id"),
          "sequence" => 2,
          "event_type" => "decision_received",
          "occurred_at" => "2026-08-25T01:01:00Z",
          "caused_by_sequence" => 1,
          "role" => "orchestrator",
          "details" => {
            "decision_id" => receipt["decision_id"],
            "decision_kind" => receipt["decision_kind"],
            "exact_effect" => "Accepted the predecessor request.",
            "request_receipt_sha256" => HrmExperiment.object_sha256(receipt)
          }
        }
      ]
      events_path = File.join(directory, capsule.dig("metrics", "event_log_path"))
      File.write(events_path, successor_events.map { |event| JSON.generate(event) }.join("\n") + "\n", mode: "w", perm: 0o600)

      result = HrmSupervisor.resume(capsule_path, events_path)
      assert_equal "inventory_runtime_bindings", result["next_action"]

      File.write(predecessor_path, "\n", mode: "a")
      error = assert_raises(HrmExperiment::ValidationError) do
        HrmSupervisor.resume(capsule_path, events_path)
      end
      assert_includes error.message, "hash mismatch"
    end
  end

  private

  def append_event(capsule_path, events_path, event_type, occurred_at, details)
    HrmSupervisor.append(capsule_path, events_path, {
      "schema_version" => "agent_playbooks.hrm_run_event.v0.5",
      "event_type" => event_type,
      "occurred_at" => occurred_at,
      "role" => "orchestrator",
      "details" => details
    })
  end

  def with_run(capsule, events)
    Dir.mktmpdir("hrm-supervisor", ROOT) do |directory|
      local_capsule = Marshal.load(Marshal.dump(capsule))
      local_capsule["project_root"] = directory
      local_capsule.dig("metrics")["event_log_path"] = File.basename(capsule.dig("metrics", "event_log_path"))
      local_capsule.dig("metrics")["session_state_path"] = File.basename(capsule.dig("metrics", "session_state_path"))
      local_capsule.dig("metrics")["scorecard_path"] = File.basename(capsule.dig("metrics", "scorecard_path"))
      capsule_path = File.join(directory, "capsule.yaml")
      File.write(capsule_path, YAML.dump(local_capsule), mode: "w", perm: 0o600)
      events_path = File.join(directory, local_capsule.dig("metrics", "event_log_path"))
      File.write(
        events_path,
        events.map { |event| JSON.generate(event) }.join("\n") + "\n",
        mode: "w",
        perm: 0o600
      )
      paths = HrmSupervisor.artifact_paths(local_capsule, events_path)
      yield capsule_path, events_path, paths
    end
  end
end
