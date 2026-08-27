# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "../scripts/hrm_supervisor"

class HrmSupervisorTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  CAPSULE = File.join(ROOT, "examples/hrm-execution-capsule.example.yaml")
  EVENTS = File.join(ROOT, "examples/hrm-run-events.example.jsonl")

  def test_resume_repairs_stale_projections_at_the_exact_ledger_cursor
    capsule = HrmExperiment.load_yaml(CAPSULE)
    all_events = HrmExperiment.load_events(EVENTS).first(7)

    with_run(capsule, all_events.first(3)) do |events_path, paths|
      HrmSupervisor.resume(CAPSULE, events_path)
      File.write(
        events_path,
        all_events.map { |event| JSON.generate(event) }.join("\n") + "\n",
        mode: "w",
        perm: 0o600
      )

      receipt = HrmSupervisor.resume(CAPSULE, events_path)
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

    with_run(capsule, [session_started]) do |events_path, paths|
      append_event(events_path, "operator_action_required", "2026-08-25T00:01:00Z", {
        "action_id" => "ACTION-UNLOCK-001",
        "operator_action_kind" => "credential_unlock",
        "exact_action" => "Unlock the local credential store."
      })
      append_event(events_path, "decision_requested", "2026-08-25T00:02:00Z", {
        "decision_id" => "DEC-AUTH-001",
        "decision_kind" => "business_meaning",
        "interrupt_class" => "S1",
        "exact_effect" => "Confirm the identity meaning."
      })
      append_event(events_path, "finding_opened", "2026-08-25T00:03:00Z", {
        "finding_id" => "FINDING-CONTRACT-001",
        "interrupt_class" => "S1",
        "blocking" => true,
        "note" => "A required read contract is absent."
      })

      projection = JSON.parse(File.read(paths["projection"], encoding: "UTF-8"))
      assert_equal %w[operator_action decision blocking_finding], projection["attention"].map { |item| item["kind"] }
      assert_equal "await_operator_action", projection["next_action"]

      append_event(events_path, "operator_action_completed", "2026-08-25T00:04:00Z", {
        "action_id" => "ACTION-UNLOCK-001",
        "operator_action_kind" => "credential_unlock",
        "exact_action" => "Unlock the local credential store."
      })
      append_event(events_path, "decision_received", "2026-08-25T00:05:00Z", {
        "decision_id" => "DEC-AUTH-001",
        "decision_kind" => "business_meaning",
        "exact_effect" => "Confirm the identity meaning."
      })
      append_event(events_path, "finding_dispositioned", "2026-08-25T00:06:00Z", {
        "finding_id" => "FINDING-CONTRACT-001",
        "disposition" => "current_claim_blocker",
        "note" => "Routed to the contract owner."
      })

      projection = JSON.parse(File.read(paths["projection"], encoding: "UTF-8"))
      assert_empty projection["attention"]
      assert_equal "continue_routine_workflow", projection["next_action"]
    end
  end

  def test_concurrent_appends_are_serialized_and_refresh_one_projection
    capsule = HrmExperiment.load_yaml(CAPSULE)
    session_started = HrmExperiment.load_events(EVENTS).first

    with_run(capsule, [session_started]) do |events_path, paths|
      errors = Queue.new
      threads = 2.times.map do |index|
        Thread.new do
          event = {
            "schema_version" => "agent_playbooks.hrm_run_event.v0.3",
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
          HrmSupervisor.append(CAPSULE, events_path, event)
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

    with_run(capsule, events) do |events_path, paths|
      receipt = HrmSupervisor.resume(CAPSULE, events_path)
      projection = JSON.parse(File.read(paths["projection"], encoding: "UTF-8"))

      assert_equal "terminal", receipt["next_action"]
      assert_equal "closed", projection["terminal_state"]
      assert_operator receipt["projection_bytes"], :<=, HrmSupervisor::MAX_PROJECTION_BYTES
    end
  end

  def test_resume_projects_reusable_api_skills_without_rediscovery
    capsule = HrmExperiment.load_yaml(CAPSULE)
    session_started = HrmExperiment.load_events(EVENTS).first

    with_run(capsule, [session_started]) do |events_path, paths|
      receipt = HrmSupervisor.resume(CAPSULE, events_path)
      projection = JSON.parse(File.read(paths["projection"], encoding: "UTF-8"))

      assert_equal 1, receipt["reusable_api_skill_count"]
      assert_equal 0, receipt["missing_api_skill_count"]
      assert_equal ["product-master.catalog-price.read"],
                   projection.dig("project_api_skills", "reusable_skill_ids")
      assert_equal "continue_routine_workflow", projection["next_action"]

      error = assert_raises(HrmExperiment::ValidationError) do
        HrmSupervisor.guard(
          CAPSULE,
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

  def test_changed_skill_fingerprint_routes_only_missing_discovery
    capsule = HrmExperiment.load_yaml(CAPSULE)
    capsule.dig("project_api_skills", "required_skills", 0)["contract_fingerprint"] = "c" * 64
    session_started = HrmExperiment.load_events(EVENTS).first

    Dir.mktmpdir("hrm-supervisor", ROOT) do |directory|
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

  private

  def append_event(events_path, event_type, occurred_at, details)
    HrmSupervisor.append(CAPSULE, events_path, {
      "schema_version" => "agent_playbooks.hrm_run_event.v0.3",
      "event_type" => event_type,
      "occurred_at" => occurred_at,
      "role" => "orchestrator",
      "details" => details
    })
  end

  def with_run(capsule, events)
    Dir.mktmpdir do |directory|
      events_path = File.join(directory, File.basename(capsule.dig("metrics", "event_log_path")))
      File.write(
        events_path,
        events.map { |event| JSON.generate(event) }.join("\n") + "\n",
        mode: "w",
        perm: 0o600
      )
      paths = HrmSupervisor.artifact_paths(capsule, events_path)
      yield events_path, paths
    end
  end
end
