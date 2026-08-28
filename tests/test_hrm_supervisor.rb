# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "tmpdir"
require_relative "../scripts/hrm_supervisor"

class HrmSupervisorTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  CAPSULE = File.join(ROOT, "examples/hrm-execution-capsule.example.yaml")
  EVENTS = File.join(ROOT, "examples/hrm-run-events.example.jsonl")

  def test_resume_atomically_starts_an_empty_ledger_and_dispatches_first_worker
    capsule = HrmExperiment.load_yaml(CAPSULE)

    with_run(capsule, []) do |capsule_path, events_path, paths|
      started_at = Time.now.utc
      receipt = HrmSupervisor.resume(capsule_path, events_path, started_at)
      events = HrmExperiment.load_events(events_path)
      projection = JSON.parse(File.read(paths["projection"], encoding: "UTF-8"))
      dispatch = JSON.parse(File.read(paths["dispatch"], encoding: "UTF-8"))

      assert_equal "start", receipt["action"]
      assert_equal 1, receipt["ledger_cursor"]
      assert_equal "session_started", receipt["event_type"]
      assert_equal "inventory_runtime_bindings", receipt["next_action"]
      assert_equal 1, events.length
      assert_equal started_at.iso8601, events.first["occurred_at"]
      assert projection.dig("scorecard_verdict", "run_valid")
      assert_equal "silent", projection.dig("operator_projection", "visibility")
      assert_equal "inventory_runtime_bindings", dispatch.dig("assignment", "action")
      assert_equal "provider_observer", dispatch.dig("assignment", "role")
      assert_equal ["example.runtime-source"], dispatch.dig("assignment", "required_dependency_ids")
      assert_equal "agent_playbooks.hrm_dispatch_envelope.v0.3", dispatch["schema_version"]
      assert_equal 12_000, dispatch.dig("assignment", "role_context_budget_bytes")
      assert_equal 10_000, dispatch.dig("assignment", "loaded_artifact_budget_bytes")
      assert_equal 2_000, dispatch.dig("assignment", "tool_output_reserve_bytes")
      assert_equal "bounded_queries_never_full_source", dispatch.dig("assignment", "load_policy")
      assert_equal "handoff", dispatch.dig("protocol", "handoff_command", 2)
      assert_equal "context", dispatch.dig("protocol", "context_command", 2)
      assert_equal "guard", dispatch.dig("protocol", "guard_command", 2)
      assert_equal "result", dispatch.dig("protocol", "result_command", 2)
      assert_equal File.dirname(capsule_path), dispatch.dig("protocol", "working_directory")
      assert_equal %w[bounded_source_materialization context guard result],
                   dispatch.dig("protocol", "worker_execution_order")
      assert_equal "optional_and_ignored_for_artifact_identity_and_redundancy",
                   dispatch.dig("protocol", "zero_artifact_preflight")
      assert_equal 0, dispatch.dig("protocol", "context_report", "machine_parsed_dispatch_echo_bytes")
      assert_equal "inventory_runtime_bindings", receipt.dig("worker_launch", "action")
      assert_equal "provider_observer", receipt.dig("worker_launch", "role")
      assert_equal 1, receipt.dig("worker_launch", "ledger_cursor")
      working_directory = receipt.dig("worker_launch", "working_directory")
      relative_dispatch = receipt.dig("worker_launch", "dispatch_path")
      assert_equal File.dirname(capsule_path), working_directory
      assert_equal paths["dispatch"], File.expand_path(relative_dispatch, working_directory)
      refute Pathname.new(relative_dispatch).absolute?
      assert_equal Digest::SHA256.file(paths["dispatch"]).hexdigest,
                   receipt.dig("worker_launch", "dispatch_sha256")
      expected_prefix = ["ruby", File.join(ROOT, "scripts/hrm_supervisor.rb")]
      assert_equal expected_prefix + ["handoff", File.basename(capsule_path), File.basename(events_path)],
                   receipt.dig("worker_launch", "handoff_command")
      assert_equal expected_prefix + [
        "context", File.basename(capsule_path), File.basename(events_path), "provider_observer"
      ], receipt.dig("worker_launch", "context_command")
      assert_equal expected_prefix + [
        "guard", File.basename(capsule_path), File.basename(events_path),
        "inventory_runtime_bindings", "provider_observer"
      ], receipt.dig("worker_launch", "guard_command")
      assert_equal expected_prefix + ["result", File.basename(capsule_path), File.basename(events_path)],
                   receipt.dig("worker_launch", "result_command")
      assert_equal dispatch.dig("assignment", "required_dependency_ids"),
                   receipt.dig("worker_launch", "required_dependency_ids")
      assert_equal 12_000, receipt.dig("worker_launch", "role_context_budget_bytes")
      assert_equal 10_000, receipt.dig("worker_launch", "loaded_artifact_budget_bytes")
      assert_equal 2_000, receipt.dig("worker_launch", "tool_output_reserve_bytes")
      assert_operator JSON.generate(receipt).bytesize, :<=, HrmSupervisor::MAX_RECEIPT_BYTES

      local_capsule = HrmExperiment.load_yaml(capsule_path)
      assert HrmSupervisor.validate_dispatch!(dispatch, local_capsule)
      missing_rc12_contract = Marshal.load(Marshal.dump(dispatch))
      missing_rc12_contract.fetch("protocol").delete("worker_execution_order")
      missing_rc12_contract.fetch("protocol").delete("zero_artifact_preflight")
      missing_rc12_contract["dispatch_hash"] = HrmExperiment.object_sha256(
        missing_rc12_contract.reject { |key, _value| key == "dispatch_hash" }
      )
      assert_raises(HrmExperiment::ValidationError) do
        HrmSupervisor.validate_dispatch!(missing_rc12_contract, local_capsule)
      end

      stdout, stderr, status = Open3.capture3(
        *receipt.dig("worker_launch", "handoff_command"),
        chdir: working_directory
      )
      assert status.success?, "status=#{status.exitstatus} stdout=#{stdout.inspect} stderr=#{stderr.inspect}"
      assert_equal "handoff", JSON.parse(stdout)["action"]
    end
  end

  def test_release_check_does_not_start_or_create_runtime_artifacts
    capsule = HrmExperiment.load_yaml(CAPSULE)

    Dir.mktmpdir("hrm-release", ROOT) do |directory|
      local_capsule = Marshal.load(Marshal.dump(capsule))
      local_capsule["project_root"] = directory
      local_capsule.dig("metrics")["event_log_path"] = ".codex/hrm-runs/release.events.jsonl"
      local_capsule.dig("metrics")["session_state_path"] = ".codex/hrm-runs/release.state.yaml"
      local_capsule.dig("metrics")["scorecard_path"] = ".codex/hrm-runs/release.scorecard.yaml"
      copy_relative_dependencies(local_capsule, directory)
      capsule_path = File.join(directory, "capsule.yaml")
      File.write(capsule_path, YAML.dump(local_capsule), mode: "w", perm: 0o600)
      events_path = File.join(directory, ".codex/hrm-runs/release.events.jsonl")

      receipt = HrmSupervisor.validate_release(capsule_path, events_path)

      assert receipt["release_ready"]
      refute File.exist?(events_path)
      HrmSupervisor.resume(capsule_path, events_path, Time.iso8601("2026-08-27T22:00:00Z"))
      assert File.directory?(File.dirname(events_path))
      error = assert_raises(HrmExperiment::ValidationError) do
        HrmSupervisor.validate_release(capsule_path, events_path)
      end
      assert_includes error.message, "unstarted session"
    end
  end

  def test_rc12_deep_project_root_keeps_resume_and_handoff_receipts_bounded_and_coherent
    capsule = capsule_with_runtime_source

    with_run(capsule, [], min_project_root_bytes: 643) do |capsule_path, events_path, paths|
      base = Time.now.utc
      receipt = HrmSupervisor.resume(capsule_path, events_path, base)

      assert_operator receipt.dig("worker_launch", "working_directory").bytesize, :>=, 643
      assert_operator JSON.generate(receipt).bytesize, :<=, HrmSupervisor::MAX_RECEIPT_BYTES
      assert_equal paths["dispatch"], File.expand_path(
        receipt.dig("worker_launch", "dispatch_path"),
        receipt.dig("worker_launch", "working_directory")
      )
      assert_equal Digest::SHA256.file(paths["dispatch"]).hexdigest,
                   receipt.dig("worker_launch", "dispatch_sha256")

      handoff_receipt = HrmSupervisor.handoff(capsule_path, events_path, base + 1)
      assert_operator JSON.generate(handoff_receipt).bytesize, :<=, HrmSupervisor::MAX_RECEIPT_BYTES
      assert_equal 2, handoff_receipt.dig("worker_launch", "ledger_cursor")
      assert_equal paths["dispatch"], File.expand_path(
        handoff_receipt.dig("worker_launch", "dispatch_path"),
        handoff_receipt.dig("worker_launch", "working_directory")
      )
      assert_equal Digest::SHA256.file(paths["dispatch"]).hexdigest,
                   handoff_receipt.dig("worker_launch", "dispatch_sha256")
      assert_equal handoff_receipt["worker_claim"], handoff_receipt.dig("worker_launch", "worker_claim")
    end
  end

  def test_rc12_adversarial_launch_expansion_fails_before_ledger_mutation
    capsule = capsule_with_runtime_source
    14.times do |index|
      capsule.fetch("context_dependencies") << {
        "dependency_id" => "oversized-launch-#{index}-#{'x' * 72}",
        "kind" => "implementation_source",
        "source_path" => File.join(ROOT, "scripts/hrm_supervisor.rb"),
        "binding" => "receipt-size-regression-#{index}"
      }
    end

    with_run(capsule, []) do |capsule_path, events_path, _paths|
      before = File.binread(events_path)
      error = assert_raises(HrmExperiment::ValidationError) do
        HrmSupervisor.resume(capsule_path, events_path, Time.now.utc)
      end

      assert_match(/dispatch envelope exceeds|worker launch receipt exceeds/, error.message)
      assert_equal before, File.binread(events_path)
      assert_empty HrmExperiment.load_events(events_path)
    end
  end

  def test_rc12_runtime_receipt_limit_rejects_an_overlarge_worker_launch
    capsule = capsule_with_runtime_source
    receipt = {"worker_launch" => {"padding" => "x" * HrmSupervisor::MAX_RECEIPT_BYTES}}

    error = assert_raises(HrmExperiment::ValidationError) do
      HrmSupervisor.validate_receipt_size!(capsule, receipt)
    end
    assert_includes error.message, "worker launch receipt exceeds"
  end

  def test_rc12_overlong_receipt_fails_before_ledger_mutation
    capsule = capsule_with_runtime_source
    10.times do |index|
      capsule.fetch("context_dependencies") << {
        "dependency_id" => "deep-launch-#{index}-#{'x' * 72}",
        "kind" => "implementation_source",
        "source_path" => File.join(ROOT, "scripts/hrm_supervisor.rb"),
        "binding" => "deep-receipt-size-regression-#{index}"
      }
    end

    with_run(capsule, [], min_project_root_bytes: 940) do |capsule_path, events_path, _paths|
      base = Time.now.utc
      HrmSupervisor.resume(capsule_path, events_path, base)
      before = File.binread(events_path)

      error = assert_raises(HrmExperiment::ValidationError) do
        HrmSupervisor.handoff(capsule_path, events_path, base + 1)
      end
      assert_includes error.message, "worker launch receipt exceeds"
      assert_equal before, File.binread(events_path)
      assert_equal 1, HrmExperiment.load_events(events_path).length
    end
  end

  def test_supervisor_measures_context_and_terminalizes_failure_in_same_locked_append
    capsule = HrmExperiment.load_yaml(CAPSULE)

    Dir.mktmpdir("hrm-context", ROOT) do |directory|
      local_capsule = Marshal.load(Marshal.dump(capsule))
      local_capsule["project_root"] = directory
      local_capsule.dig("metrics")["event_log_path"] = "context.events.jsonl"
      local_capsule.dig("metrics")["session_state_path"] = "context.state.yaml"
      local_capsule.dig("metrics")["scorecard_path"] = "context.scorecard.yaml"
      copy_relative_dependencies(local_capsule, directory)
      capsule_path = File.join(directory, "capsule.yaml")
      File.write(capsule_path, YAML.dump(local_capsule), mode: "w", perm: 0o600)
      events_path = File.join(directory, "context.events.jsonl")
      HrmSupervisor.resume(capsule_path, events_path, Time.iso8601("2026-08-27T22:00:00Z"))
      HrmSupervisor.handoff(capsule_path, events_path, Time.iso8601("2026-08-27T22:00:05Z"))

      receipt = HrmSupervisor.record_context(capsule_path, events_path, "provider_observer", {
        "turn_id" => "provider-1",
        "loaded_artifact_bytes_by_id" => {},
        "tool_output_bytes" => local_capsule.dig("budgets", "context_bytes_by_role", "provider_observer") + 1
      })
      events = HrmExperiment.load_events(events_path)
      state = HrmExperiment.load_yaml(File.join(directory, "context.state.yaml"))

      assert receipt["auto_terminalized"]
      assert_equal "context_snapshot", receipt["accepted_event_type"]
      assert_equal "stop_reason", receipt["event_type"]
      assert_equal %w[session_started worker_handoff_started context_snapshot stop_reason],
                   events.map { |event| event["event_type"] }
      assert_equal 0, events[2].dig("context", "artifact_bytes")
      assert_equal 0, events[2].dig("context", "state_artifact_echo_bytes")
      assert_equal "budget_exhausted", events.last.dig("details", "stop_reason")
      assert_equal "blocked", state.dig("terminal", "state")
      assert_raises(HrmExperiment::ValidationError) do
        HrmSupervisor.append(capsule_path, events_path, {
          "event_type" => "finding_opened",
          "occurred_at" => "2026-08-27T22:01:00Z",
          "role" => "orchestrator",
          "details" => {"finding_id" => "F-1", "blocking" => false, "note" => "must not append"}
        })
      end
    end
  end

  def test_rc12_counts_bounded_dependency_bytes_once_and_excludes_them_from_tool_output
    capsule = capsule_with_runtime_source

    with_run(capsule, []) do |capsule_path, events_path, paths|
      HrmSupervisor.resume(capsule_path, events_path, Time.iso8601("2026-08-27T22:00:00Z"))
      HrmSupervisor.handoff(capsule_path, events_path, Time.iso8601("2026-08-27T22:00:05Z"))
      dispatch = HrmExperiment.load_json(paths["dispatch"])
      dependency = dispatch.dig("assignment", "dependencies", 0)

      receipt = HrmSupervisor.record_context(capsule_path, events_path, "provider_observer", {
        "turn_id" => "provider-bounded-1",
        "loaded_artifact_bytes_by_id" => {"example.runtime-source" => 512},
        "tool_output_bytes" => 128
      })
      context = HrmExperiment.load_events(events_path).last.fetch("context")

      assert_equal "context_snapshot", receipt["event_type"]
      assert_equal "targeted_queries_and_bounded_slices", dependency["access_policy"]
      assert_operator dependency["source_size_bytes"], :>, 512
      assert_equal 512, context["artifact_bytes"]
      assert_equal 128, context["tool_output_bytes"]
      assert_equal 640, context["active_context_bytes"]
      assert_equal({"example.runtime-source" => 512}, context["loaded_artifact_bytes_by_id"])
    end
  end

  def test_rc12_terminalizes_assignment_artifact_allowance_even_below_role_budget
    capsule = capsule_with_runtime_source

    with_run(capsule, []) do |capsule_path, events_path, paths|
      HrmSupervisor.resume(capsule_path, events_path, Time.iso8601("2026-08-27T22:00:00Z"))
      HrmSupervisor.handoff(capsule_path, events_path, Time.iso8601("2026-08-27T22:00:05Z"))
      receipt = HrmSupervisor.record_context(capsule_path, events_path, "provider_observer", {
        "turn_id" => "provider-over-artifact-allowance",
        "loaded_artifact_bytes_by_id" => {"example.runtime-source" => 10_001},
        "tool_output_bytes" => 0
      })
      events = HrmExperiment.load_events(events_path)

      assert receipt["auto_terminalized"]
      assert_equal 10_001, events[2].dig("context", "active_context_bytes")
      assert_equal "budget_exhausted", events.last.dig("details", "stop_reason")
    end
  end

  def test_rc12_provider_accepts_observed_9482_bytes_inside_adaptive_allocation
    capsule = capsule_with_runtime_source

    with_run(capsule, []) do |capsule_path, events_path, paths|
      HrmSupervisor.resume(capsule_path, events_path, Time.iso8601("2026-08-27T22:00:00Z"))
      HrmSupervisor.handoff(capsule_path, events_path, Time.iso8601("2026-08-27T22:00:05Z"))
      receipt = HrmSupervisor.record_context(capsule_path, events_path, "provider_observer", {
        "turn_id" => "provider-observed-9482",
        "loaded_artifact_bytes_by_id" => {"example.runtime-source" => 9482},
        "tool_output_bytes" => 2000
      })
      context = HrmExperiment.load_events(events_path).last.fetch("context")

      refute receipt["auto_terminalized"]
      assert_equal 9482, context["artifact_bytes"]
      assert_equal 11_482, context["active_context_bytes"]
      assert_equal 10_000, context["loaded_artifact_budget_bytes"]
      assert_equal 2_000, context["tool_output_reserve_bytes"]
    end
  end

  def test_rc12_zero_preflights_do_not_materialize_or_seed_repetition_and_result_reaches_builder
    capsule = capsule_with_runtime_source
    seams = capsule.dig("function_slice", "required_real_seams")

    with_run(capsule, []) do |capsule_path, events_path, paths|
      base = Time.now.utc
      HrmSupervisor.resume(capsule_path, events_path, base - 10)
      HrmSupervisor.handoff(capsule_path, events_path, base - 5)
      2.times do |index|
        receipt = HrmSupervisor.record_context(capsule_path, events_path, "provider_observer", {
          "turn_id" => "provider-zero-preflight-#{index + 1}",
          "loaded_artifact_bytes_by_id" => {"example.runtime-source" => 0},
          "tool_output_bytes" => 0
        })
        refute receipt["auto_terminalized"]
      end
      final_context_receipt = HrmSupervisor.record_context(
        capsule_path,
        events_path,
        "provider_observer",
        {
          "turn_id" => "provider-final-cumulative",
          "loaded_artifact_bytes_by_id" => {"example.runtime-source" => 9928},
          "tool_output_bytes" => 1108
        }
      )
      refute final_context_receipt["auto_terminalized"]
      contexts = HrmExperiment.load_events(events_path).select do |event|
        event["event_type"] == "context_snapshot"
      end
      contexts.first(2).each do |event|
        assert_equal({}, event.dig("context", "loaded_artifact_bytes_by_id"))
        assert_empty event.dig("context", "loaded_dependency_ids")
        assert_equal 0, event.dig("context", "files_loaded")
        assert_equal 0, event.dig("context", "artifact_bytes")
        assert_equal 0, event.dig("context", "repeated_artifact_bytes")
      end
      final_context = contexts.last.fetch("context")
      assert_equal 9928, final_context["artifact_bytes"]
      assert_equal 1108, final_context["tool_output_bytes"]
      assert_equal 11_036, final_context["active_context_bytes"]
      assert_equal 0, final_context["repeated_artifact_bytes"]

      HrmSupervisor.guard(
        capsule_path,
        events_path,
        "inventory_runtime_bindings",
        "provider_observer",
        base + 5
      )
      handoff = HrmExperiment.load_events(events_path).find do |event|
        event["event_type"] == "worker_handoff_started"
      end
      receipt = HrmSupervisor.result(capsule_path, events_path, {
        "event_type" => "runtime_binding_inventory",
        "occurred_at" => (base + 6).iso8601,
        "role" => "provider_observer",
        "details" => {
          "action" => "inventory_runtime_bindings",
          "worker_role" => "provider_observer",
          "worker_claim_id" => handoff.dig("details", "worker_claim_id"),
          "material_progress" => true,
          "runtime_readiness" => {
            "required_real_seams" => seams,
            "bound_real_seams" => seams,
            "zero_effect_construction_verified" => false,
            "evidence_sha256" => "c" * 64
          }
        }
      }, base + 7)
      dispatch = HrmExperiment.load_json(paths["dispatch"])

      assert_equal "implement_frozen_slice", receipt["next_action"]
      assert_equal "builder", receipt.dig("worker_launch", "role")
      assert_equal "implement_frozen_slice", receipt.dig("worker_launch", "action")
      assert_equal paths["dispatch"], File.expand_path(
        receipt.dig("worker_launch", "dispatch_path"),
        receipt.dig("worker_launch", "working_directory")
      )
      assert_equal Digest::SHA256.file(paths["dispatch"]).hexdigest,
                   receipt.dig("worker_launch", "dispatch_sha256")
      assert_equal "builder", dispatch.dig("assignment", "role")
      assert_operator JSON.generate(receipt).bytesize, :<=, HrmSupervisor::MAX_RECEIPT_BYTES
    end
  end

  def test_rc12_positive_context_remains_cumulatively_repeated
    capsule = capsule_with_runtime_source

    with_run(capsule, []) do |capsule_path, events_path, _paths|
      HrmSupervisor.resume(capsule_path, events_path, Time.iso8601("2026-08-27T22:00:00Z"))
      HrmSupervisor.handoff(capsule_path, events_path, Time.iso8601("2026-08-27T22:00:05Z"))
      2.times do |index|
        HrmSupervisor.record_context(capsule_path, events_path, "provider_observer", {
          "turn_id" => "positive-repeat-#{index + 1}",
          "loaded_artifact_bytes_by_id" => {"example.runtime-source" => 512},
          "tool_output_bytes" => 0
        })
      end
      contexts = HrmExperiment.load_events(events_path).select do |event|
        event["event_type"] == "context_snapshot"
      end

      assert_equal 0, contexts.first.dig("context", "repeated_artifact_bytes")
      assert_equal 512, contexts.last.dig("context", "repeated_artifact_bytes")
    end
  end

  def test_rc12_result_rejects_a_prior_positive_context_without_mutation
    capsule = capsule_with_runtime_source
    capsule["experiment_profile"] = "custom"
    capsule.dig("budgets")["max_context_redundancy_ratio"] = 1.0
    seams = capsule.dig("function_slice", "required_real_seams")

    with_run(capsule, []) do |capsule_path, events_path, _paths|
      base = Time.now.utc
      HrmSupervisor.resume(capsule_path, events_path, base - 10)
      HrmSupervisor.handoff(capsule_path, events_path, base - 5)
      [100, 9928].each_with_index do |bytes, index|
        HrmSupervisor.record_context(capsule_path, events_path, "provider_observer", {
          "turn_id" => "positive-before-final-#{index + 1}",
          "loaded_artifact_bytes_by_id" => {"example.runtime-source" => bytes},
          "tool_output_bytes" => 0
        })
      end
      HrmSupervisor.guard(
        capsule_path,
        events_path,
        "inventory_runtime_bindings",
        "provider_observer",
        base + 5
      )
      before = File.binread(events_path)

      error = assert_raises(HrmExperiment::ValidationError) do
        HrmSupervisor.result(
          capsule_path,
          events_path,
          inventory_result_for(events_path, seams, base + 6),
          base + 7
        )
      end
      assert_includes error.message, "zero-artifact preflight"
      assert_equal before, File.binread(events_path)
    end
  end

  def test_rc12_result_rejects_an_intervening_business_event_without_mutation
    capsule = capsule_with_runtime_source
    seams = capsule.dig("function_slice", "required_real_seams")

    with_run(capsule, []) do |capsule_path, events_path, _paths|
      base = Time.now.utc
      HrmSupervisor.resume(capsule_path, events_path, base - 10)
      HrmSupervisor.handoff(capsule_path, events_path, base - 5)
      HrmSupervisor.append(capsule_path, events_path, {
        "event_type" => "finding_opened",
        "occurred_at" => (base - 4).iso8601,
        "role" => "orchestrator",
        "details" => {
          "finding_id" => "F-RC12-INTERVENING",
          "interrupt_class" => "S3",
          "blocking" => false,
          "note" => "Intervening business event must not join the worker protocol."
        }
      })
      HrmSupervisor.record_context(capsule_path, events_path, "provider_observer", {
        "turn_id" => "context-after-intervening",
        "loaded_artifact_bytes_by_id" => {"example.runtime-source" => 9928},
        "tool_output_bytes" => 1000
      })
      HrmSupervisor.guard(
        capsule_path,
        events_path,
        "inventory_runtime_bindings",
        "provider_observer",
        base + 5
      )
      before = File.binread(events_path)

      error = assert_raises(HrmExperiment::ValidationError) do
        HrmSupervisor.result(
          capsule_path,
          events_path,
          inventory_result_for(events_path, seams, base + 6),
          base + 7
        )
      end
      assert_includes error.message, "only same-role context snapshots"
      assert_equal before, File.binread(events_path)
    end
  end

  def test_rc11_zero_materialization_and_exact_result_order_remain_unchanged
    capsule = capsule_with_runtime_source
    capsule.dig("playbook_pin")["kernel_version"] = "0.1.0-rc.11"
    capsule.fetch("context_dependencies").find do |dependency|
      dependency["dependency_id"] == "ap.exec.kernel"
    end["binding"] = "AP-EXEC-001/0.1.0-rc.11@#{'1' * 40}"
    capsule.fetch("context_dependencies").find do |dependency|
      dependency["dependency_id"] == "example.runtime-source"
    end["binding"] = "rc11-example-source"

    with_run(capsule, []) do |capsule_path, events_path, _paths|
      HrmSupervisor.resume(capsule_path, events_path, Time.iso8601("2026-08-27T22:00:00Z"))
      receipt = HrmSupervisor.handoff(
        capsule_path,
        events_path,
        Time.iso8601("2026-08-27T22:00:05Z")
      )
      context_receipt = HrmSupervisor.record_context(capsule_path, events_path, "provider_observer", {
        "turn_id" => "rc11-zero-stays-materialized",
        "loaded_artifact_bytes_by_id" => {"example.runtime-source" => 0},
        "tool_output_bytes" => 0
      })
      context = HrmExperiment.load_events(events_path).last.fetch("context")

      assert_nil receipt["worker_launch"]
      assert_equal({"example.runtime-source" => 0}, context["loaded_artifact_bytes_by_id"])
      assert_equal ["example.runtime-source"], context["loaded_dependency_ids"]
      assert_equal 1, context["files_loaded"]
      assert_equal "context_snapshot", context_receipt["event_type"]
    end
  end

  def test_rc11_predecessor_dispatch_pending_claim_and_result_protocol_remain_supported
    capsule = capsule_with_runtime_source
    capsule.dig("playbook_pin")["kernel_version"] = "0.1.0-rc.11"
    capsule.fetch("context_dependencies").find do |dependency|
      dependency["dependency_id"] == "ap.exec.kernel"
    end["binding"] = "AP-EXEC-001/0.1.0-rc.11@#{'1' * 40}"
    capsule.fetch("context_dependencies").find do |dependency|
      dependency["dependency_id"] == "example.runtime-source"
    end["binding"] = "rc11-example-source"
    seams = capsule.dig("function_slice", "required_real_seams")

    with_run(capsule, []) do |capsule_path, events_path, paths|
      base = Time.now.utc
      HrmSupervisor.resume(capsule_path, events_path, base - 10)
      predecessor_dispatch = HrmExperiment.load_json(paths["dispatch"])
      assert_equal %w[
        context_command
        context_report
        guard_command
        handoff_command
        result_command
        result_contract
      ], predecessor_dispatch.fetch("protocol").keys.sort
      assert_equal File.expand_path(capsule_path),
                   predecessor_dispatch.dig("protocol", "handoff_command", 3)
      handoff_receipt = HrmSupervisor.handoff(capsule_path, events_path, base - 5)
      assert_equal predecessor_dispatch["dispatch_hash"],
                   handoff_receipt.dig("worker_claim", "source_dispatch_sha256")
      HrmSupervisor.record_context(capsule_path, events_path, "provider_observer", {
        "turn_id" => "rc11-exact-context",
        "loaded_artifact_bytes_by_id" => {"example.runtime-source" => 9482},
        "tool_output_bytes" => 1000
      })
      HrmSupervisor.guard(
        capsule_path,
        events_path,
        "inventory_runtime_bindings",
        "provider_observer",
        base + 5
      )
      receipt = HrmSupervisor.result(
        capsule_path,
        events_path,
        inventory_result_for(events_path, seams, base + 6),
        base + 7
      )

      assert_equal "implement_frozen_slice", receipt["next_action"]
      assert_nil receipt["worker_launch"]
      assert_equal "builder", HrmExperiment.load_json(paths["dispatch"]).dig("assignment", "role")
    end
  end

  def test_rc12_tool_output_can_use_unused_artifact_headroom_but_not_exceed_role_total
    capsule = capsule_with_runtime_source

    with_run(capsule, []) do |capsule_path, events_path, _paths|
      HrmSupervisor.resume(capsule_path, events_path, Time.iso8601("2026-08-27T22:00:00Z"))
      HrmSupervisor.handoff(capsule_path, events_path, Time.iso8601("2026-08-27T22:00:05Z"))
      accepted = HrmSupervisor.record_context(capsule_path, events_path, "provider_observer", {
        "turn_id" => "provider-one-way-headroom",
        "loaded_artifact_bytes_by_id" => {"example.runtime-source" => 4000},
        "tool_output_bytes" => 8000
      })
      refute accepted["auto_terminalized"]
    end

    with_run(capsule, []) do |capsule_path, events_path, _paths|
      HrmSupervisor.resume(capsule_path, events_path, Time.iso8601("2026-08-27T22:00:00Z"))
      HrmSupervisor.handoff(capsule_path, events_path, Time.iso8601("2026-08-27T22:00:05Z"))
      stopped = HrmSupervisor.record_context(capsule_path, events_path, "provider_observer", {
        "turn_id" => "provider-over-total",
        "loaded_artifact_bytes_by_id" => {"example.runtime-source" => 4000},
        "tool_output_bytes" => 8001
      })
      assert stopped["auto_terminalized"]
      assert_equal "budget_exhausted", HrmExperiment.load_events(events_path).last.dig("details", "stop_reason")
    end
  end

  def test_rc12_rejects_reported_dependency_bytes_above_source_size
    capsule = capsule_with_runtime_source

    with_run(capsule, []) do |capsule_path, events_path, paths|
      HrmSupervisor.resume(capsule_path, events_path, Time.iso8601("2026-08-27T22:00:00Z"))
      HrmSupervisor.handoff(capsule_path, events_path, Time.iso8601("2026-08-27T22:00:05Z"))
      source_size = HrmExperiment.load_json(paths["dispatch"]).dig(
        "assignment", "dependencies", 0, "source_size_bytes"
      )

      error = assert_raises(HrmExperiment::ValidationError) do
        HrmSupervisor.record_context(capsule_path, events_path, "provider_observer", {
          "turn_id" => "provider-impossible-size",
          "loaded_artifact_bytes_by_id" => {"example.runtime-source" => source_size + 1},
          "tool_output_bytes" => 0
        })
      end
      assert_includes error.message, "exceed source size"
      assert_equal 2, HrmExperiment.load_events(events_path).length
    end
  end

  def test_handoff_records_exact_fresh_worker_and_rejects_replay
    capsule = HrmExperiment.load_yaml(CAPSULE)

    with_run(capsule, []) do |capsule_path, events_path, paths|
      HrmSupervisor.resume(capsule_path, events_path, Time.iso8601("2026-08-27T22:00:00Z"))
      receipt = HrmSupervisor.handoff(
        capsule_path,
        events_path,
        Time.iso8601("2026-08-27T22:00:05Z")
      )
      event = HrmExperiment.load_events(events_path).last

      assert_equal "handoff", receipt["action"]
      assert_equal "worker_handoff_started", event["event_type"]
      assert_equal "provider_observer", event["role"]
      assert_equal "inventory_runtime_bindings", event.dig("details", "action")
      assert_equal "provider_observer", event.dig("details", "worker_role")
      assert_equal 1, event.dig("details", "source_dispatch_cursor")
      assert_match(/\A[0-9a-f]{64}\z/, event.dig("details", "source_dispatch_sha256"))
      assert_match(/\A[0-9a-f]{64}\z/, event.dig("details", "worker_claim_id"))
      assert_equal event.dig("details", "worker_claim_id"), receipt.dig("worker_claim", "worker_claim_id")
      assert_equal event.dig("details", "source_dispatch_sha256"),
                   receipt.dig("worker_claim", "source_dispatch_sha256")
      assert_equal paths["dispatch"], File.expand_path(
        receipt.dig("worker_launch", "dispatch_path"),
        receipt.dig("worker_launch", "working_directory")
      )
      assert_equal 2, receipt.dig("worker_launch", "ledger_cursor")
      assert_equal Digest::SHA256.file(paths["dispatch"]).hexdigest,
                   receipt.dig("worker_launch", "dispatch_sha256")
      refute_equal receipt.dig("worker_claim", "source_dispatch_sha256"),
                   receipt.dig("worker_launch", "dispatch_sha256")
      assert_equal receipt["worker_claim"], receipt.dig("worker_launch", "worker_claim")
      assert_equal "inventory_runtime_bindings", receipt.dig("worker_launch", "action")
      assert_equal "provider_observer", receipt.dig("worker_launch", "role")
      assert_operator JSON.generate(receipt).bytesize, :<=, HrmSupervisor::MAX_RECEIPT_BYTES
      assert_includes event.dig("details", "note"), "inventory_runtime_bindings"
      assert_raises(HrmExperiment::ValidationError) do
        HrmSupervisor.handoff(capsule_path, events_path)
      end
    end
  end

  def test_rc12_rejects_unbound_worker_handoff_append
    with_run(capsule_with_runtime_source, []) do |capsule_path, events_path, _paths|
      HrmSupervisor.resume(capsule_path, events_path, Time.iso8601("2026-08-27T22:00:00Z"))

      error = assert_raises(HrmExperiment::ValidationError) do
        HrmSupervisor.append(capsule_path, events_path, {
          "event_type" => "worker_handoff_started",
          "occurred_at" => "2026-08-27T22:00:05Z",
          "role" => "provider_observer",
          "details" => {"material_progress" => false, "note" => "Unbound handoff."}
        })
      end
      assert_includes error.message, "supervisor-bound"
      assert_equal 1, HrmExperiment.load_events(events_path).length
    end
  end

  def test_rc12_context_requires_a_live_structured_handoff_claim
    with_run(capsule_with_runtime_source, []) do |capsule_path, events_path, _paths|
      HrmSupervisor.resume(capsule_path, events_path, Time.iso8601("2026-08-27T22:00:00Z"))

      error = assert_raises(HrmExperiment::ValidationError) do
        HrmSupervisor.record_context(capsule_path, events_path, "provider_observer", {
          "turn_id" => "unclaimed-context",
          "loaded_artifact_bytes_by_id" => {"example.runtime-source" => 100},
          "tool_output_bytes" => 0
        })
      end
      assert_includes error.message, "pending structured worker handoff"
      assert_equal 1, HrmExperiment.load_events(events_path).length
    end
  end

  def test_rc12_direct_worker_lifecycle_appends_cannot_reach_builder
    blocked_types = %w[
      action_guard_passed
      change_unit_started
      runtime_binding_inventory
      first_executable_delta
      first_operational_evidence
      check_started
      check_completed
      worker_result_received
    ]

    with_run(capsule_with_runtime_source, []) do |capsule_path, events_path, paths|
      HrmSupervisor.resume(capsule_path, events_path, Time.iso8601("2026-08-27T22:00:00Z"))
      blocked_types.each do |event_type|
        error = assert_raises(HrmExperiment::ValidationError, event_type) do
          HrmSupervisor.append(capsule_path, events_path, {
            "event_type" => event_type,
            "occurred_at" => "2026-08-27T22:00:05Z",
            "role" => "provider_observer",
            "details" => {}
          })
        end
        assert_includes error.message, "supervisor-bound"
      end

      assert_equal 1, HrmExperiment.load_events(events_path).length
      assert_equal "inventory_runtime_bindings",
                   HrmExperiment.load_json(paths["dispatch"]).dig("assignment", "action")
    end
  end

  def test_rc12_rejects_self_rehashed_dispatch_tampering_across_write_protocol
    mutations = {
      "role" => lambda { |dispatch|
        dispatch.dig("assignment")["role"] = "builder"
      },
      "budget" => lambda { |dispatch|
        dispatch.dig("assignment")["loaded_artifact_budget_bytes"] = 9999
        dispatch.dig("assignment")["tool_output_reserve_bytes"] = 2001
      },
      "action" => lambda { |dispatch|
        dispatch.dig("assignment")["action"] = "implement_frozen_slice"
      },
      "dependency" => lambda { |dispatch|
        dispatch.dig("assignment")["required_dependency_ids"] = []
        dispatch.dig("assignment")["dependencies"] = []
      }
    }
    operations = {
      "handoff" => lambda { |capsule_path, events_path, _dispatch|
        HrmSupervisor.handoff(capsule_path, events_path)
      },
      "context" => lambda { |capsule_path, events_path, dispatch|
        ids = dispatch.dig("assignment", "required_dependency_ids")
        HrmSupervisor.record_context(capsule_path, events_path, dispatch.dig("assignment", "role"), {
          "turn_id" => "tampered-context",
          "loaded_artifact_bytes_by_id" => ids.to_h { |dependency_id| [dependency_id, 0] },
          "tool_output_bytes" => 0
        })
      },
      "guard" => lambda { |capsule_path, events_path, dispatch|
        HrmSupervisor.guard(
          capsule_path,
          events_path,
          dispatch.dig("assignment", "action"),
          dispatch.dig("assignment", "role")
        )
      }
    }

    mutations.each do |mutation_name, mutation|
      operations.each do |operation_name, operation|
        with_run(capsule_with_runtime_source, []) do |capsule_path, events_path, paths|
          HrmSupervisor.resume(capsule_path, events_path, Time.iso8601("2026-08-27T22:00:00Z"))
          tampered = rewrite_dispatch_and_projection(paths, &mutation)

          error = assert_raises(HrmExperiment::ValidationError, "#{mutation_name}/#{operation_name}") do
            operation.call(capsule_path, events_path, tampered)
          end
          assert_includes error.message, "differs from deterministic supervisor derivation"
          assert_equal 1, HrmExperiment.load_events(events_path).length
        end
      end
    end
  end

  def test_rc12_inventory_guard_requires_positive_implementation_source_bytes
    capsule = capsule_with_runtime_source

    with_run(capsule, []) do |capsule_path, events_path, _paths|
      HrmSupervisor.resume(capsule_path, events_path, Time.iso8601("2026-08-27T22:00:00Z"))
      HrmSupervisor.handoff(capsule_path, events_path, Time.iso8601("2026-08-27T22:00:05Z"))
      HrmSupervisor.record_context(capsule_path, events_path, "provider_observer", {
        "turn_id" => "provider-zero-source",
        "loaded_artifact_bytes_by_id" => {"example.runtime-source" => 0},
        "tool_output_bytes" => 100
      })

      error = assert_raises(HrmExperiment::ValidationError) do
        HrmSupervisor.guard(capsule_path, events_path, "inventory_runtime_bindings", "provider_observer")
      end
      assert_includes error.message, "positive materialized bytes"
      assert_equal 3, HrmExperiment.load_events(events_path).length
    end
  end

  def test_rc12_provider_inventory_result_dispatches_fresh_builder_with_unchanged_allocation
    capsule = capsule_with_runtime_source
    seams = capsule.dig("function_slice", "required_real_seams")

    with_run(capsule, []) do |capsule_path, events_path, paths|
      base = Time.now.utc
      HrmSupervisor.resume(capsule_path, events_path, base - 10)
      HrmSupervisor.handoff(capsule_path, events_path, base - 5)
      HrmSupervisor.record_context(capsule_path, events_path, "provider_observer", {
        "turn_id" => "provider-inventory",
        "loaded_artifact_bytes_by_id" => {"example.runtime-source" => 9482},
        "tool_output_bytes" => 2000
      })
      HrmSupervisor.guard(
        capsule_path,
        events_path,
        "inventory_runtime_bindings",
        "provider_observer",
        base + 5
      )
      claim_id = HrmExperiment.load_events(events_path)[1].dig("details", "worker_claim_id")
      result_event = {
        "event_type" => "runtime_binding_inventory",
        "occurred_at" => (base + 6).iso8601,
        "role" => "provider_observer",
        "details" => {
          "action" => "inventory_runtime_bindings",
          "worker_role" => "provider_observer",
          "worker_claim_id" => claim_id,
          "material_progress" => true,
          "runtime_readiness" => {
            "required_real_seams" => seams,
            "bound_real_seams" => seams,
            "zero_effect_construction_verified" => false,
            "evidence_sha256" => "a" * 64
          }
        }
      }
      tampered_results = {
        "claim" => lambda { |event| event.dig("details")["worker_claim_id"] = "f" * 64 },
        "action" => lambda { |event| event.dig("details")["action"] = "implement_frozen_slice" },
        "worker_role" => lambda { |event| event.dig("details")["worker_role"] = "builder" },
        "event_role" => lambda { |event| event["role"] = "builder" }
      }
      tampered_results.each do |name, mutation|
        tampered_result = Marshal.load(Marshal.dump(result_event))
        mutation.call(tampered_result)
        error = assert_raises(HrmExperiment::ValidationError, name) do
          HrmSupervisor.result(capsule_path, events_path, tampered_result, base + 7)
        end
        assert_match(/exact pending worker claim|role must equal/, error.message)
        assert_equal 4, HrmExperiment.load_events(events_path).length
      end

      receipt = HrmSupervisor.result(capsule_path, events_path, result_event, base + 7)
      dispatch = HrmExperiment.load_json(paths["dispatch"])

      assert_equal "implement_frozen_slice", receipt["next_action"]
      assert_equal claim_id, receipt.dig("worker_claim", "worker_claim_id")
      assert_equal "inventory_runtime_bindings", receipt.dig("worker_claim", "action")
      assert_equal "provider_observer", receipt.dig("worker_claim", "worker_role")
      assert_equal "implement_frozen_slice", dispatch.dig("assignment", "action")
      assert_equal "builder", dispatch.dig("assignment", "role")
      assert_equal 20_000, dispatch.dig("assignment", "role_context_budget_bytes")
      assert_equal 10_000, dispatch.dig("assignment", "loaded_artifact_budget_bytes")
      assert_equal 10_000, dispatch.dig("assignment", "tool_output_reserve_bytes")
      events = HrmExperiment.load_events(events_path)
      assert_equal %w[runtime_binding_inventory worker_result_received],
                   events.last(2).map { |event| event["event_type"] }
      assert_equal claim_id, events.last.dig("details", "worker_claim_id")

      replay = assert_raises(HrmExperiment::ValidationError) do
        HrmSupervisor.result(capsule_path, events_path, result_event, base + 8)
      end
      assert_includes replay.message, "matching guard"
      assert_equal 6, HrmExperiment.load_events(events_path).length
    end
  end

  def test_resume_terminalizes_a_prestarted_stale_run
    capsule = HrmExperiment.load_yaml(CAPSULE)

    with_run(capsule, []) do |capsule_path, events_path, _paths|
      HrmSupervisor.resume(capsule_path, events_path, Time.iso8601("2026-08-27T22:00:00Z"))
      receipt = HrmSupervisor.resume(capsule_path, events_path, Time.iso8601("2026-08-27T23:00:00Z"))
      events = HrmExperiment.load_events(events_path)

      assert_equal "terminalize", receipt["action"]
      assert_equal "stop_reason", receipt["event_type"]
      assert_equal "no_progress", events.last.dig("details", "stop_reason")
    end
  end

  def test_rc10_rejects_free_form_context_snapshot_append
    capsule = HrmExperiment.load_yaml(CAPSULE)
    started = HrmExperiment.load_events(EVENTS).first
    context = Marshal.load(Marshal.dump(HrmExperiment.load_events(EVENTS)[1]))
    context["schema_version"] = "agent_playbooks.hrm_run_event.v0.5"
    context.delete("sequence")
    context.delete("session_id")
    context.delete("hrm_id")
    context.delete("caused_by_sequence")

    with_run(capsule, [started]) do |capsule_path, events_path, _paths|
      error = assert_raises(HrmExperiment::ValidationError) do
        HrmSupervisor.append(capsule_path, events_path, context)
      end
      assert_includes error.message, "supervisor-bound"
      assert_equal 1, HrmExperiment.load_events(events_path).length
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
      assert_equal "bounded_queries_never_full_source", dispatch.dig("assignment", "load_policy")
      assert_equal 12_000, dispatch.dig("assignment", "role_context_budget_bytes")
      assert_equal 10_000, dispatch.dig("assignment", "loaded_artifact_budget_bytes")
      assert_equal 2_000, dispatch.dig("assignment", "tool_output_reserve_bytes")
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
      assert_includes error.message, "supervisor-bound"
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
      registry_path = File.join(directory, "examples/project-api-skill-registry.example.yaml")
      FileUtils.mkdir_p(File.dirname(registry_path))
      FileUtils.cp(File.join(ROOT, "examples/project-api-skill-registry.example.yaml"), registry_path)
      capsule_path = File.join(directory, "capsule.yaml")
      copy_relative_dependencies(capsule, directory)
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

  def test_declared_external_kernel_context_is_valid_evaluator_evidence
    capsule = HrmExperiment.load_yaml(CAPSULE)
    started = HrmExperiment.load_events(EVENTS).first
    context = Marshal.load(Marshal.dump(HrmExperiment.load_events(EVENTS)[1]))
    context["schema_version"] = "agent_playbooks.hrm_run_event.v0.5"
    context.fetch("context").merge!(
      "loaded_dependency_ids" => ["example.execution-capsule", "ap.exec.kernel"],
      "loaded_artifact_bytes_by_id" => {
        "example.execution-capsule" => 3000,
        "ap.exec.kernel" => 3000
      },
      "loaded_artifact_budget_bytes" => 6000,
      "tool_output_reserve_bytes" => 6000,
      "active_context_bytes" => 8000,
      "files_loaded" => 2,
      "outside_declared_dependency_ids" => [],
      "files_outside_declared_dependencies" => 0
    )

    scorecard = HrmExperiment.evaluate(capsule, [started, context])

    assert scorecard.dig("verdict", "run_valid")
    assert_equal "pending", scorecard.dig("verdict", "process_envelope")
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
      copy_relative_dependencies(capsule, directory)
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

  def capsule_with_runtime_source
    capsule = HrmExperiment.load_yaml(CAPSULE)
    source = capsule.fetch("context_dependencies").find do |dependency|
      dependency["dependency_id"] == "example.runtime-source"
    end
    source["source_path"] = File.join(ROOT, "scripts/hrm_supervisor.rb")
    source["binding"] = "test-source"
    capsule
  end

  def copy_relative_dependencies(capsule, directory)
    capsule.fetch("context_dependencies").each do |dependency|
      source = dependency.fetch("source_path").split("#", 2).first
      next if source == "verification.exact_checks" || Pathname.new(source).absolute?

      original = File.join(ROOT, source)
      next unless File.file?(original)

      copy = File.join(directory, source)
      FileUtils.mkdir_p(File.dirname(copy))
      FileUtils.cp(original, copy)
    end
  end

  def inventory_result_for(events_path, seams, occurred_at)
    handoff = HrmExperiment.load_events(events_path).reverse.find do |event|
      event["event_type"] == "worker_handoff_started"
    end
    {
      "event_type" => "runtime_binding_inventory",
      "occurred_at" => occurred_at.iso8601,
      "role" => "provider_observer",
      "details" => {
        "action" => "inventory_runtime_bindings",
        "worker_role" => "provider_observer",
        "worker_claim_id" => handoff.dig("details", "worker_claim_id"),
        "material_progress" => true,
        "runtime_readiness" => {
          "required_real_seams" => seams,
          "bound_real_seams" => seams,
          "zero_effect_construction_verified" => false,
          "evidence_sha256" => "d" * 64
        }
      }
    }
  end

  def rewrite_dispatch_and_projection(paths)
    dispatch = HrmExperiment.load_json(paths.fetch("dispatch"))
    yield dispatch
    dispatch["dispatch_hash"] = HrmExperiment.object_sha256(
      dispatch.reject { |key, _value| key == "dispatch_hash" }
    )
    File.write(paths.fetch("dispatch"), "#{JSON.generate(dispatch)}\n", mode: "w", perm: 0o600)

    projection = HrmExperiment.load_json(paths.fetch("projection"))
    projection.dig("dispatch_ref")["sha256"] = dispatch.fetch("dispatch_hash")
    projection["projection_hash"] = HrmExperiment.object_sha256(
      projection.reject { |key, _value| key == "projection_hash" }
    )
    File.write(paths.fetch("projection"), "#{JSON.generate(projection)}\n", mode: "w", perm: 0o600)
    dispatch
  end

  def append_event(capsule_path, events_path, event_type, occurred_at, details)
    HrmSupervisor.append(capsule_path, events_path, {
      "schema_version" => "agent_playbooks.hrm_run_event.v0.5",
      "event_type" => event_type,
      "occurred_at" => occurred_at,
      "role" => "orchestrator",
      "details" => details
    })
  end

  def with_run(capsule, events, min_project_root_bytes: nil)
    Dir.mktmpdir("hrm-supervisor", ROOT) do |temporary_directory|
      directory = temporary_directory
      component_index = 0
      while min_project_root_bytes && directory.bytesize < min_project_root_bytes
        component_prefix = "nested-#{component_index}-"
        component = component_prefix + ("x" * (120 - component_prefix.bytesize))
        directory = File.join(directory, component)
        FileUtils.mkdir_p(directory)
        component_index += 1
      end
      local_capsule = Marshal.load(Marshal.dump(capsule))
      local_capsule["project_root"] = directory
      local_capsule.dig("metrics")["event_log_path"] = File.basename(capsule.dig("metrics", "event_log_path"))
      local_capsule.dig("metrics")["session_state_path"] = File.basename(capsule.dig("metrics", "session_state_path"))
      local_capsule.dig("metrics")["scorecard_path"] = File.basename(capsule.dig("metrics", "scorecard_path"))
      copy_relative_dependencies(local_capsule, directory)
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
