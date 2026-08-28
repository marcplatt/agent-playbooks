# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "tmpdir"
require_relative "../scripts/hrm_supervisor"

class HrmSupervisorTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  CAPSULE = File.join(ROOT, "examples/hrm-execution-capsule.example.yaml")
  EVENTS = File.join(ROOT, "examples/hrm-run-events.example.jsonl")
  AE_SCALE_SESSION_ID = "AE-PRODUCTION-CANARY-APEXEC-RC13-20260828"
  AE_SCALE_HRM_ID = "AE-HRM-PRODUCTION-CANARY"
  AE_SCALE_REAL_SEAMS = %w[
    distinct_Website_Thomas_AE_RFQ_identities
    frozen_ADT_DT_roster_per_RFQ
    real_APM_config_price_provenance
    private_runtime_and_salesperson_manifest
    member_QBO_create_send_delivery_reconciliation
    RFQ_salesperson_SMS_after_all_deliveries
    automatic_GHL_ack_after_SMS_with_CRM_recovery
  ].freeze

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
      assert_equal %w[
        activate
        verify_dispatch_digest_without_dump
        bounded_source_materialization
        context
        guard
        result
      ],
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
        "context", File.basename(capsule_path), File.basename(events_path), "provider_observer",
        "__BASE64URL_CANONICAL_JSON_CONTEXT__"
      ], receipt.dig("worker_launch", "context_command")
      assert_equal expected_prefix + [
        "guard", File.basename(capsule_path), File.basename(events_path),
        "inventory_runtime_bindings", "provider_observer"
      ], receipt.dig("worker_launch", "guard_command")
      assert_equal expected_prefix + [
        "result", File.basename(capsule_path), File.basename(events_path),
        "__BASE64URL_CANONICAL_JSON_DETAILS__"
      ],
                   receipt.dig("worker_launch", "result_command")
      assert_equal "base64url_canonical_json", dispatch.dig("protocol", "context_report", "argument")
      assert_nil dispatch.dig("protocol", "context_report", "stdin")
      assert_equal "supervisor_derived_action_specific_domain_details",
                   dispatch.dig("protocol", "result_contract")
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
      assert_nil handoff_receipt["worker_claim"]
      assert_equal handoff_receipt.dig("worker_launch", "worker_claim", "worker_claim_id"),
                   handoff_receipt.dig("worker_launch", "activation_command", -3)
    end
  end

  def test_rc14_ae_scale_launch_compacts_the_rc13_overcap_failure_and_executes
    with_ae_scale_run("0.1.0-rc.13", project_root_bytes: 93) do |capsule_path, events_path, _paths|
      resume = HrmSupervisor.resume(capsule_path, events_path, Time.now.utc - 5)
      assert_operator JSON.generate(resume).bytesize, :<=, HrmSupervisor::MAX_RECEIPT_BYTES
      before = File.binread(events_path)

      error = assert_raises(HrmExperiment::ValidationError) do
        HrmSupervisor.handoff(capsule_path, events_path, Time.now.utc - 4)
      end
      assert_match(/worker launch receipt exceeds 4096 bytes \(\d+\)/, error.message)
      assert_equal before, File.binread(events_path)
      assert_equal 1, HrmExperiment.load_events(events_path).length
    end

    with_ae_scale_run("0.1.0-rc.14", project_root_bytes: 93) do |capsule_path, events_path, paths|
      resume = HrmSupervisor.resume(capsule_path, events_path, Time.now.utc - 5)
      resume_bytes = JSON.generate(resume).bytesize
      assert_operator resume_bytes, :<=, 3800
      assert_equal %w[action session_id ledger_cursor next_action worker_launch event_sequence event_type],
                   resume.keys
      assert_equal AE_SCALE_REAL_SEAMS,
                   resume.dig("worker_launch", "result_input", "template", "runtime_readiness", "required_real_seams")
      assert_equal "unpadded_base64url_canonical_json",
                   resume.dig("worker_launch", "one_shot_input", "encoding")
      assert_nil resume.dig("worker_launch", "activation_command")

      handoff_stdout, handoff_stderr, handoff_status = Open3.capture3(
        *resume.dig("worker_launch", "handoff_command"),
        chdir: resume.dig("worker_launch", "working_directory")
      )
      assert handoff_status.success?, handoff_stderr
      handoff = JSON.parse(handoff_stdout)
      handoff_bytes = JSON.generate(handoff).bytesize
      assert_operator handoff_bytes, :<=, 3800
      assert_operator HrmSupervisor::MAX_RECEIPT_BYTES - handoff_bytes, :>, 300
      launch = handoff.fetch("worker_launch")
      assert launch["activation_command"]
      assert_equal %w[activate verify_dispatch_digest_without_dump bounded_source_materialization context guard result],
                   launch.dig("launch_policy", "steps")
      assert_equal Digest::SHA256.file(paths["dispatch"]).hexdigest, launch["dispatch_sha256"]

      activation_stdout, activation_stderr, activation_status = Open3.capture3(
        *launch.fetch("activation_command"),
        chdir: launch.fetch("working_directory")
      )
      assert activation_status.success?, activation_stderr
      assert_equal "activate", JSON.parse(activation_stdout)["action"]

      context_command = launch.fetch("context_command").dup
      context_command[-1] = HrmSupervisor.encode_one_shot_argument(
        "turn_id" => "ae-scale-provider",
        "loaded_artifact_bytes_by_id" => {"ae.runtime-source" => 9482},
        "tool_output_bytes" => 1000
      )
      context_stdout, context_stderr, context_status = Open3.capture3(
        *context_command,
        chdir: launch.fetch("working_directory")
      )
      assert context_status.success?, context_stderr
      assert_equal "context_snapshot", JSON.parse(context_stdout)["event_type"]

      guard_stdout, guard_stderr, guard_status = Open3.capture3(
        *launch.fetch("guard_command"),
        chdir: launch.fetch("working_directory")
      )
      assert guard_status.success?, guard_stderr
      assert_equal "action_guard_passed", JSON.parse(guard_stdout)["event_type"]

      domain = Marshal.load(Marshal.dump(launch.dig("result_input", "template")))
      domain.dig("runtime_readiness")["bound_real_seams"] = AE_SCALE_REAL_SEAMS
      result_command = launch.fetch("result_command").dup
      result_command[-1] = HrmSupervisor.encode_one_shot_argument(domain)
      result_stdout, result_stderr, result_status = Open3.capture3(
        *result_command,
        chdir: launch.fetch("working_directory")
      )
      assert result_status.success?, result_stderr
      result = JSON.parse(result_stdout)
      assert_equal "implement_frozen_slice", result["next_action"]
      assert_equal "builder", result.dig("worker_launch", "role")
      assert_operator JSON.generate(result).bytesize, :<=, HrmSupervisor::MAX_RECEIPT_BYTES
    end
  end

  def test_rc15_ae_scale_launch_retains_compact_headroom
    rc15_capsule = capsule_for_kernel_version(HrmExperiment.load_yaml(CAPSULE), "0.1.0-rc.15")
    assert_equal "0a90f2318440530d49f610bfeec5586bceb74a6dc9258225c91d875f989914f9",
                 HrmExperiment.object_sha256(rc15_capsule)

    with_ae_scale_run("0.1.0-rc.15", project_root_bytes: 93) do |capsule_path, events_path, _paths|
      resume = HrmSupervisor.resume(capsule_path, events_path, Time.now.utc - 5)
      handoff = HrmSupervisor.handoff(capsule_path, events_path, Time.now.utc - 4)
      resume_bytes = JSON.generate(resume).bytesize
      handoff_bytes = JSON.generate(handoff).bytesize

      assert_operator resume_bytes, :<=, HrmSupervisor::MAX_RECEIPT_BYTES
      assert_operator handoff_bytes, :<=, HrmSupervisor::MAX_RECEIPT_BYTES
      assert_operator HrmSupervisor::MAX_RECEIPT_BYTES - handoff_bytes, :>, 300
      assert_equal %w[activate verify_dispatch_digest_without_dump bounded_source_materialization context guard result],
                   handoff.dig("worker_launch", "launch_policy", "steps")
      assert handoff.dig("worker_launch", "activation_command")
    end
  end

  def test_rc16_ae_scale_launch_retains_compact_headroom
    with_ae_scale_run("0.1.0-rc.16", project_root_bytes: 93) do |capsule_path, events_path, _paths|
      resume = HrmSupervisor.resume(capsule_path, events_path, Time.now.utc - 5)
      handoff = HrmSupervisor.handoff(capsule_path, events_path, Time.now.utc - 4)
      resume_bytes = JSON.generate(resume).bytesize
      handoff_bytes = JSON.generate(handoff).bytesize

      assert_equal 2953, resume_bytes
      assert_equal 3675, handoff_bytes
      assert_equal 421, HrmSupervisor::MAX_RECEIPT_BYTES - handoff_bytes
      assert_equal %w[activate verify_dispatch_digest_without_dump bounded_source_materialization context guard result],
                   handoff.dig("worker_launch", "launch_policy", "steps")
      assert handoff.dig("worker_launch", "activation_command")
    end
  end

  def test_rc13_dispatch_receipt_and_pending_claim_shape_remain_exactly_legacy
    capsule = capsule_for_kernel_version(HrmExperiment.load_yaml(CAPSULE), "0.1.0-rc.13")
    assert_equal "cd34a909d18361bf827a5a0e864b12c550d68264cf2e71c8fd9142d879a1a82d",
                 HrmExperiment.object_sha256(capsule)

    with_run(capsule, []) do |capsule_path, events_path, _paths|
      resume = HrmSupervisor.resume(capsule_path, events_path, Time.now.utc - 5)
      handoff = HrmSupervisor.handoff(capsule_path, events_path, Time.now.utc - 4)
      launch = handoff.fetch("worker_launch")

      assert resume.key?("projection_hash")
      assert handoff.key?("projection_hash")
      assert launch["launch_ready"]
      assert_equal "none", launch["spawn_fork_turns"]
      assert_equal "none_before_spawn_one_after", launch["root_wait_policy"]
      assert_equal "unpadded_base64url_canonical_json", launch.dig("result_input", "encoding")
      assert_nil launch["launch_policy"]
      assert_nil launch["one_shot_input"]
      assert_equal launch.dig("worker_claim", "worker_claim_id"), launch.dig("activation_command", -3)
      assert_equal launch["dispatch_sha256"], launch.dig("activation_command", -1)
    end
  end

  def test_rc14_adversarial_seam_expansion_fails_before_ledger_mutation
    capsule = HrmExperiment.load_yaml(CAPSULE)
    capsule.dig("function_slice")["required_real_seams"] = Array.new(18) do |index|
      "oversized_rc14_seam_#{index}_#{'x' * 180}"
    end

    with_run(capsule, []) do |capsule_path, events_path, _paths|
      before = File.binread(events_path)
      error = assert_raises(HrmExperiment::ValidationError) do
        HrmSupervisor.resume(capsule_path, events_path, Time.now.utc)
      end

      assert_includes error.message, "worker launch receipt exceeds"
      assert_equal before, File.binread(events_path)
      assert_empty HrmExperiment.load_events(events_path)
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

  def test_rc13_overlong_receipt_fails_before_ledger_mutation
    capsule = capsule_for_kernel_version(capsule_with_runtime_source, "0.1.0-rc.13")
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
      error = assert_raises(HrmExperiment::ValidationError) do
        HrmSupervisor.resume(capsule_path, events_path, base)
      end
      assert_includes error.message, "worker launch receipt exceeds"
      assert_empty HrmExperiment.load_events(events_path)
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
      handoff_and_activate(capsule_path, events_path, Time.iso8601("2026-08-27T22:00:05Z"))

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
      assert_equal %w[session_started worker_handoff_started worker_started context_snapshot stop_reason],
                   events.map { |event| event["event_type"] }
      context = events.find { |event| event["event_type"] == "context_snapshot" }
      assert_equal 0, context.dig("context", "artifact_bytes")
      assert_equal 0, context.dig("context", "state_artifact_echo_bytes")
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
      handoff_and_activate(capsule_path, events_path, Time.iso8601("2026-08-27T22:00:05Z"))
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
      handoff_and_activate(capsule_path, events_path, Time.iso8601("2026-08-27T22:00:05Z"))
      receipt = HrmSupervisor.record_context(capsule_path, events_path, "provider_observer", {
        "turn_id" => "provider-over-artifact-allowance",
        "loaded_artifact_bytes_by_id" => {"example.runtime-source" => 10_001},
        "tool_output_bytes" => 0
      })
      events = HrmExperiment.load_events(events_path)

      assert receipt["auto_terminalized"]
      context = events.find { |event| event["event_type"] == "context_snapshot" }
      assert_equal 10_001, context.dig("context", "active_context_bytes")
      assert_equal "budget_exhausted", events.last.dig("details", "stop_reason")
    end
  end

  def test_rc12_provider_accepts_observed_9482_bytes_inside_adaptive_allocation
    capsule = capsule_with_runtime_source

    with_run(capsule, []) do |capsule_path, events_path, paths|
      HrmSupervisor.resume(capsule_path, events_path, Time.iso8601("2026-08-27T22:00:00Z"))
      handoff_and_activate(capsule_path, events_path, Time.iso8601("2026-08-27T22:00:05Z"))
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
      handoff_and_activate(capsule_path, events_path, base - 5)
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
      receipt = HrmSupervisor.result(capsule_path, events_path, {
        "runtime_readiness" => {
          "required_real_seams" => seams,
          "bound_real_seams" => seams,
          "zero_effect_construction_verified" => false,
          "evidence_sha256" => "c" * 64
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
      handoff_and_activate(capsule_path, events_path, Time.iso8601("2026-08-27T22:00:05Z"))
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
      handoff_and_activate(capsule_path, events_path, base - 5)
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
      handoff_and_activate(capsule_path, events_path, base - 5)
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

  def test_rc12_dispatch_and_pending_claim_semantics_remain_unchanged
    capsule = capsule_with_runtime_source
    capsule.dig("playbook_pin")["kernel_version"] = "0.1.0-rc.12"
    capsule.fetch("context_dependencies").find do |dependency|
      dependency["dependency_id"] == "ap.exec.kernel"
    end["binding"] = "AP-EXEC-001/0.1.0-rc.12@#{'2' * 40}"
    capsule.fetch("context_dependencies").find do |dependency|
      dependency["dependency_id"] == "example.runtime-source"
    end["binding"] = "rc12-example-source"

    with_run(capsule, []) do |capsule_path, events_path, paths|
      base = Time.iso8601("2026-08-27T22:00:00Z")
      HrmSupervisor.resume(capsule_path, events_path, base)
      dispatch = HrmExperiment.load_json(paths["dispatch"])

      assert_equal %w[bounded_source_materialization context guard result],
                   dispatch.dig("protocol", "worker_execution_order")
      assert_equal "json", dispatch.dig("protocol", "context_report", "stdin")
      assert_nil dispatch.dig("protocol", "context_report", "argument")
      assert_nil dispatch.dig("protocol", "one_shot_argument_encoding")
      assert_equal "append_compact_events_only", dispatch.dig("protocol", "result_contract")
      assert_equal "provider_observer", dispatch.dig("assignment", "role")
      assert HrmSupervisor.validate_dispatch!(dispatch, HrmExperiment.load_yaml(capsule_path))

      handoff = HrmSupervisor.handoff(capsule_path, events_path, base + 5)
      assert_equal handoff["worker_claim"], handoff.dig("worker_launch", "worker_claim")
      assert_nil handoff.dig("worker_launch", "activation_command")
      context = HrmSupervisor.record_context(capsule_path, events_path, "provider_observer", {
        "turn_id" => "rc12-no-activation-required",
        "loaded_artifact_bytes_by_id" => {"example.runtime-source" => 9482},
        "tool_output_bytes" => 1000
      })
      assert_equal "context_snapshot", context["event_type"]

      error = assert_raises(HrmExperiment::ValidationError) do
        HrmSupervisor.activate(capsule_path, events_path, "f" * 64, 2, "e" * 64, base + 6)
      end
      assert_includes error.message, "requires an rc.13 capsule"
    end
  end

  def test_rc12_tool_output_can_use_unused_artifact_headroom_but_not_exceed_role_total
    capsule = capsule_with_runtime_source

    with_run(capsule, []) do |capsule_path, events_path, _paths|
      HrmSupervisor.resume(capsule_path, events_path, Time.iso8601("2026-08-27T22:00:00Z"))
      handoff_and_activate(capsule_path, events_path, Time.iso8601("2026-08-27T22:00:05Z"))
      accepted = HrmSupervisor.record_context(capsule_path, events_path, "provider_observer", {
        "turn_id" => "provider-one-way-headroom",
        "loaded_artifact_bytes_by_id" => {"example.runtime-source" => 4000},
        "tool_output_bytes" => 8000
      })
      refute accepted["auto_terminalized"]
    end

    with_run(capsule, []) do |capsule_path, events_path, _paths|
      HrmSupervisor.resume(capsule_path, events_path, Time.iso8601("2026-08-27T22:00:00Z"))
      handoff_and_activate(capsule_path, events_path, Time.iso8601("2026-08-27T22:00:05Z"))
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
      handoff_and_activate(capsule_path, events_path, Time.iso8601("2026-08-27T22:00:05Z"))
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
      assert_equal 3, HrmExperiment.load_events(events_path).length
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
      assert_nil receipt["worker_claim"]
      assert_equal event.dig("details", "worker_claim_id"),
                   receipt.dig("worker_launch", "worker_claim", "worker_claim_id")
      assert_equal event.dig("details", "source_dispatch_sha256"),
                   receipt.dig("worker_launch", "worker_claim", "source_dispatch_sha256")
      assert_equal paths["dispatch"], File.expand_path(
        receipt.dig("worker_launch", "dispatch_path"),
        receipt.dig("worker_launch", "working_directory")
      )
      assert_equal 2, receipt.dig("worker_launch", "ledger_cursor")
      assert_equal Digest::SHA256.file(paths["dispatch"]).hexdigest,
                   receipt.dig("worker_launch", "dispatch_sha256")
      refute_equal receipt.dig("worker_launch", "worker_claim", "source_dispatch_sha256"),
                   receipt.dig("worker_launch", "dispatch_sha256")
      assert_equal event.dig("details", "worker_claim_id"),
                   receipt.dig("worker_launch", "activation_command", -3)
      assert_equal "inventory_runtime_bindings", receipt.dig("worker_launch", "action")
      assert_equal "provider_observer", receipt.dig("worker_launch", "role")
      assert_nil receipt.dig("worker_launch", "launch_ready")
      assert_equal "none", receipt.dig("worker_launch", "launch_policy", "fork_turns")
      assert_equal "none_before_one_after", receipt.dig("worker_launch", "launch_policy", "root_wait")
      assert_equal %w[
        activate
        verify_dispatch_digest_without_dump
        bounded_source_materialization
        context
        guard
        result
      ], receipt.dig("worker_launch", "launch_policy", "steps")
      assert_equal "runtime_binding_inventory", receipt.dig("worker_launch", "result_input", "domain_event")
      assert_equal ["runtime_readiness"], receipt.dig("worker_launch", "result_input", "required_keys")
      assert_equal "unpadded_base64url_canonical_json",
                   receipt.dig("worker_launch", "one_shot_input", "encoding")
      assert_equal(-1, receipt.dig("worker_launch", "one_shot_input", "argument_index"))
      assert_equal HrmSupervisor::MAX_ONE_SHOT_ARGUMENT_BYTES,
                   receipt.dig("worker_launch", "one_shot_input", "max_encoded_bytes")
      assert_equal event.dig("details", "worker_claim_id"),
                   receipt.dig("worker_launch", "activation_command", -3)
      assert_equal receipt.dig("worker_launch", "ledger_cursor").to_s,
                   receipt.dig("worker_launch", "activation_command", -2)
      assert_equal receipt.dig("worker_launch", "dispatch_sha256"),
                   receipt.dig("worker_launch", "activation_command", -1)
      assert_operator JSON.generate(receipt).bytesize, :<=, HrmSupervisor::MAX_RECEIPT_BYTES
      assert_includes event.dig("details", "note"), "inventory_runtime_bindings"
      assert_raises(HrmExperiment::ValidationError) do
        HrmSupervisor.handoff(capsule_path, events_path)
      end
    end
  end

  def test_rc13_activation_is_exactly_bound_atomic_and_replay_safe
    capsule = capsule_for_kernel_version(capsule_with_runtime_source, "0.1.0-rc.13")

    with_run(capsule, []) do |capsule_path, events_path, paths|
      base = Time.iso8601("2026-08-27T22:00:00Z")
      HrmSupervisor.resume(capsule_path, events_path, base)
      handoff = HrmSupervisor.handoff(capsule_path, events_path, base + 5)
      command = handoff.dig("worker_launch", "activation_command")
      before = File.binread(events_path)

      invalid_bindings = [
        ["f" * 64, Integer(command[-2], 10), command[-1]],
        [command[-3], Integer(command[-2], 10) + 1, command[-1]],
        [command[-3], Integer(command[-2], 10), "e" * 64]
      ]
      invalid_bindings.each do |claim_id, cursor, dispatch_sha256|
        error = assert_raises(HrmExperiment::ValidationError) do
          HrmSupervisor.activate(
            capsule_path,
            events_path,
            claim_id,
            cursor,
            dispatch_sha256,
            base + 6
          )
        end
        assert_includes error.message, "exact pending claim"
        assert_equal before, File.binread(events_path)
      end

      receipt = HrmSupervisor.activate(
        capsule_path,
        events_path,
        command[-3],
        Integer(command[-2], 10),
        command[-1],
        base + 6
      )
      event = HrmExperiment.load_events(events_path).last
      assert_equal "worker_started", event["event_type"]
      assert_equal command[-3], event.dig("details", "worker_claim_id")
      assert_equal 3, receipt.dig("activated_dispatch", "ledger_cursor")
      assert_equal Digest::SHA256.file(paths["dispatch"]).hexdigest,
                   receipt.dig("activated_dispatch", "dispatch_sha256")
      scorecard = HrmExperiment.evaluate(HrmExperiment.load_yaml(capsule_path), HrmExperiment.load_events(events_path))
      assert_equal 6, scorecard.dig("flow", "startup_to_first_worker_activation_seconds")
      assert_equal 1, scorecard.dig("flow", "handoff_to_first_worker_activation_seconds")

      slow_events = Marshal.load(Marshal.dump(HrmExperiment.load_events(events_path)))
      slow_events.last["occurred_at"] = (base + 21).iso8601
      slow_scorecard = HrmExperiment.evaluate(HrmExperiment.load_yaml(capsule_path), slow_events)
      assert_equal "fail", slow_scorecard.dig("verdict", "process_envelope")
      assert_includes slow_scorecard.dig("verdict", "reasons"),
                      "worker-activation startup budget exceeded"
      assert_includes slow_scorecard.dig("verdict", "reasons"),
                      "worker activation after handoff budget exceeded"

      activated = File.binread(events_path)
      replay = assert_raises(HrmExperiment::ValidationError) do
        HrmSupervisor.activate(
          capsule_path,
          events_path,
          command[-3],
          Integer(command[-2], 10),
          command[-1],
          base + 7
        )
      end
      assert_includes replay.message, "first tool immediately after handoff"
      assert_equal activated, File.binread(events_path)
    end
  end

  def test_rc14_26_second_startup_and_20_second_handoff_remain_terminal
    capsule = capsule_for_kernel_version(capsule_with_runtime_source, "0.1.0-rc.14")

    with_run(capsule, []) do |capsule_path, events_path, _paths|
      base = Time.iso8601("2026-08-27T20:00:00Z")
      HrmSupervisor.resume(capsule_path, events_path, base)
      handoff = HrmSupervisor.handoff(capsule_path, events_path, base + 6)
      command = handoff.dig("worker_launch", "activation_command")
      receipt = HrmSupervisor.activate(
        capsule_path,
        events_path,
        command.fetch(-3),
        Integer(command.fetch(-2), 10),
        command.fetch(-1),
        base + 26
      )

      events = HrmExperiment.load_events(events_path)
      scorecard = HrmExperiment.evaluate(HrmExperiment.load_yaml(capsule_path), events)
      assert_equal %w[session_started worker_handoff_started worker_started stop_reason],
                   events.map { |event| event["event_type"] }
      assert receipt["auto_terminalized"]
      assert_nil receipt["reason_codes"]
      assert receipt["activated_dispatch"]
      assert_nil receipt["claim_validation"]
      assert_nil receipt["post_activation_dispatch"]
      assert_equal "fail", scorecard.dig("verdict", "process_envelope")
      assert_includes scorecard.dig("verdict", "reasons"), "worker-activation startup budget exceeded"
      assert_includes scorecard.dig("verdict", "reasons"), "worker activation after handoff budget exceeded"
    end
  end

  def test_rc15_26_second_startup_and_inclusive_20_second_handoff_activate_and_continue
    capsule = capsule_for_kernel_version(capsule_with_runtime_source, "0.1.0-rc.15")

    with_run(capsule, []) do |capsule_path, events_path, paths|
      base = Time.iso8601("2026-08-27T20:00:00Z")
      HrmSupervisor.resume(capsule_path, events_path, base)
      handoff = HrmSupervisor.handoff(capsule_path, events_path, base + 6)
      launch = handoff.fetch("worker_launch")
      command = launch.fetch("activation_command")
      receipt = HrmSupervisor.activate(
        capsule_path,
        events_path,
        command.fetch(-3),
        Integer(command.fetch(-2), 10),
        command.fetch(-1),
        base + 26
      )

      events = HrmExperiment.load_events(events_path)
      projection = HrmExperiment.load_json(paths.fetch("projection"))
      assert_equal %w[session_started worker_handoff_started worker_started],
                   events.map { |event| event["event_type"] }
      assert_equal "inventory_runtime_bindings", receipt["next_action"]
      assert_equal [], projection["reason_codes"]
      assert_equal "active", projection["terminal_state"]
      assert_equal "silent", projection.dig("operator_projection", "visibility")
      assert_equal launch["dispatch_sha256"], receipt.dig("claim_validation", "claimed_dispatch_sha256")
      assert_equal launch["dispatch_sha256"], receipt.dig("claim_validation", "observed_dispatch_sha256")
      assert receipt.dig("claim_validation", "matched")
      assert_equal 2, receipt.dig("claim_validation", "cursor")
      assert_equal 3, receipt.dig("post_activation_dispatch", "ledger_cursor")
      assert_equal Digest::SHA256.file(paths.fetch("dispatch")).hexdigest,
                   receipt.dig("post_activation_dispatch", "dispatch_sha256")
      refute_equal receipt.dig("claim_validation", "claimed_dispatch_sha256"),
                   receipt.dig("post_activation_dispatch", "dispatch_sha256")
      assert_nil receipt["activated_dispatch"]

      context = HrmSupervisor.record_context(capsule_path, events_path, "provider_observer", {
        "turn_id" => "rc15-after-inclusive-activation",
        "loaded_artifact_bytes_by_id" => {"example.runtime-source" => 1},
        "tool_output_bytes" => 0
      })
      assert_equal "context_snapshot", context["event_type"]
    end
  end

  def test_rc15_exact_30_second_startup_and_20_second_handoff_boundary_continues
    capsule = capsule_for_kernel_version(capsule_with_runtime_source, "0.1.0-rc.15")

    with_run(capsule, []) do |capsule_path, events_path, paths|
      base = Time.iso8601("2026-08-27T20:00:00Z")
      HrmSupervisor.resume(capsule_path, events_path, base)
      handoff = HrmSupervisor.handoff(capsule_path, events_path, base + 10)
      command = handoff.dig("worker_launch", "activation_command")
      receipt = HrmSupervisor.activate(
        capsule_path,
        events_path,
        command.fetch(-3),
        Integer(command.fetch(-2), 10),
        command.fetch(-1),
        base + 30
      )
      events = HrmExperiment.load_events(events_path)
      scorecard = HrmExperiment.evaluate(HrmExperiment.load_yaml(capsule_path), events)
      projection = HrmExperiment.load_json(paths.fetch("projection"))

      assert_equal %w[session_started worker_handoff_started worker_started],
                   events.map { |event| event["event_type"] }
      assert_equal 30, scorecard.dig("flow", "startup_to_first_worker_activation_seconds")
      assert_equal 20, scorecard.dig("flow", "handoff_to_first_worker_activation_seconds")
      assert_equal "pending", scorecard.dig("verdict", "process_envelope")
      assert_equal "active", projection["terminal_state"]
      assert_equal "inventory_runtime_bindings", receipt["next_action"]
      assert receipt.dig("claim_validation", "matched")
      refute receipt["auto_terminalized"]
    end
  end

  def test_rc15_activation_hard_limits_terminalize_with_stable_reason_codes
    cases = [
      {handoff: 11, activation: 31, code: "worker_activation_startup_budget_exceeded"},
      {handoff: 6, activation: 27, code: "worker_activation_handoff_budget_exceeded"}
    ]

    cases.each do |item|
      capsule = capsule_for_kernel_version(capsule_with_runtime_source, "0.1.0-rc.15")
      with_run(capsule, []) do |capsule_path, events_path, paths|
        base = Time.iso8601("2026-08-28T20:00:00Z")
        HrmSupervisor.resume(capsule_path, events_path, base)
        handoff = HrmSupervisor.handoff(capsule_path, events_path, base + item.fetch(:handoff))
        command = handoff.dig("worker_launch", "activation_command")
        receipt = HrmSupervisor.activate(
          capsule_path,
          events_path,
          command.fetch(-3),
          Integer(command.fetch(-2), 10),
          command.fetch(-1),
          base + item.fetch(:activation)
        )
        projection = HrmExperiment.load_json(paths.fetch("projection"))

        assert receipt["auto_terminalized"]
        assert_includes receipt.fetch("reason_codes"), item.fetch(:code)
        assert_equal receipt["reason_codes"], projection["reason_codes"]
        assert_equal "blocked", projection["terminal_state"]
        assert_equal "terminal", projection.dig("operator_projection", "visibility")
        assert_match(/\AProcess blocker: /, projection.dig("operator_projection", "summary"))
        refute_includes projection.dig("operator_projection", "summary"), "mismatch"
        assert receipt.dig("claim_validation", "matched")
        assert receipt["post_activation_dispatch"]
      end
    end
  end

  def test_rc15_activation_digest_mismatch_does_not_append_worker_started
    capsule = capsule_for_kernel_version(capsule_with_runtime_source, "0.1.0-rc.15")
    with_run(capsule, []) do |capsule_path, events_path, _paths|
      base = Time.iso8601("2026-08-28T20:00:00Z")
      HrmSupervisor.resume(capsule_path, events_path, base)
      handoff = HrmSupervisor.handoff(capsule_path, events_path, base + 6)
      command = handoff.dig("worker_launch", "activation_command")
      before = File.binread(events_path)

      error = assert_raises(HrmExperiment::ValidationError) do
        HrmSupervisor.activate(
          capsule_path,
          events_path,
          command.fetch(-3),
          Integer(command.fetch(-2), 10),
          "f" * 64,
          base + 26
        )
      end
      assert_includes error.message, "exact pending claim"
      assert_equal before, File.binread(events_path)
      refute HrmExperiment.load_events(events_path).any? { |event| event["event_type"] == "worker_started" }
    end
  end

  def test_rc15_production_observation_uses_the_same_30_and_20_second_hard_limits
    capsule = HrmExperiment.load_yaml(File.join(ROOT, "examples/hrm-production-observation-capsule.example.yaml"))
    capsule = capsule_for_kernel_version(capsule, "0.1.0-rc.15")

    with_run(capsule, []) do |capsule_path, events_path, _paths|
      base = Time.now.utc - 10
      HrmSupervisor.resume(capsule_path, events_path, base)
      handoff = HrmSupervisor.handoff(capsule_path, events_path, base + 6)
      command = handoff.dig("worker_launch", "activation_command")
      receipt = HrmSupervisor.activate(
        capsule_path,
        events_path,
        command.fetch(-3),
        Integer(command.fetch(-2), 10),
        command.fetch(-1),
        base + 27
      )

      assert receipt["auto_terminalized"]
      assert_includes receipt.fetch("reason_codes"), "worker_activation_handoff_budget_exceeded"
    end
  end

  def test_rc15_27_second_startup_and_21_second_handoff_remain_reason_coded_terminal
    capsule = capsule_for_kernel_version(capsule_with_runtime_source, "0.1.0-rc.15")

    with_run(capsule, []) do |capsule_path, events_path, _paths|
      base = Time.iso8601("2026-08-28T20:00:00Z")
      HrmSupervisor.resume(capsule_path, events_path, base)
      handoff = HrmSupervisor.handoff(capsule_path, events_path, base + 6)
      command = handoff.dig("worker_launch", "activation_command")
      receipt = HrmSupervisor.activate(
        capsule_path,
        events_path,
        command.fetch(-3),
        Integer(command.fetch(-2), 10),
        command.fetch(-1),
        base + 27
      )

      assert receipt["auto_terminalized"]
      assert_equal "worker_activation_handoff_budget_exceeded", receipt.fetch("reason_codes").first
      refute_includes receipt["reason_codes"], "worker_activation_startup_budget_exceeded"
      assert_equal %w[session_started worker_handoff_started worker_started stop_reason],
                   HrmExperiment.load_events(events_path).map { |event| event["event_type"] }
    end
  end

  def test_rc16_27_second_startup_and_21_second_handoff_continue
    with_run(capsule_with_runtime_source, []) do |capsule_path, events_path, paths|
      base = Time.iso8601("2026-08-28T20:00:00Z")
      HrmSupervisor.resume(capsule_path, events_path, base)
      handoff = HrmSupervisor.handoff(capsule_path, events_path, base + 6)
      launch = handoff.fetch("worker_launch")
      command = launch.fetch("activation_command")
      receipt = HrmSupervisor.activate(
        capsule_path,
        events_path,
        command.fetch(-3),
        Integer(command.fetch(-2), 10),
        command.fetch(-1),
        base + 27
      )

      assert_equal %w[session_started worker_handoff_started worker_started],
                   HrmExperiment.load_events(events_path).map { |event| event["event_type"] }
      assert_equal "inventory_runtime_bindings", receipt["next_action"]
      refute receipt["auto_terminalized"]
      assert receipt.dig("claim_validation", "matched")
      assert_equal launch["dispatch_sha256"], receipt.dig("claim_validation", "observed_dispatch_sha256")
      assert_equal [], HrmExperiment.load_json(paths.fetch("projection"))["reason_codes"]
    end
  end

  def test_rc16_exact_30_second_startup_and_25_second_handoff_boundary_continues
    with_run(capsule_with_runtime_source, []) do |capsule_path, events_path, paths|
      base = Time.iso8601("2026-08-28T20:00:00Z")
      HrmSupervisor.resume(capsule_path, events_path, base)
      handoff = HrmSupervisor.handoff(capsule_path, events_path, base + 5)
      command = handoff.dig("worker_launch", "activation_command")
      receipt = HrmSupervisor.activate(
        capsule_path,
        events_path,
        command.fetch(-3),
        Integer(command.fetch(-2), 10),
        command.fetch(-1),
        base + 30
      )
      scorecard = HrmExperiment.evaluate(
        HrmExperiment.load_yaml(capsule_path),
        HrmExperiment.load_events(events_path)
      )

      assert_equal 30, scorecard.dig("flow", "startup_to_first_worker_activation_seconds")
      assert_equal 25, scorecard.dig("flow", "handoff_to_first_worker_activation_seconds")
      assert_equal "pending", scorecard.dig("verdict", "process_envelope")
      assert_equal "active", HrmExperiment.load_json(paths.fetch("projection"))["terminal_state"]
      refute receipt["auto_terminalized"]
    end
  end

  def test_rc16_activation_hard_limits_terminalize_above_30_or_25_with_exact_reason_codes
    cases = [
      {handoff: 10, activation: 31, code: "worker_activation_startup_budget_exceeded"},
      {handoff: 4, activation: 30, code: "worker_activation_handoff_budget_exceeded"}
    ]

    cases.each do |item|
      with_run(capsule_with_runtime_source, []) do |capsule_path, events_path, paths|
        base = Time.iso8601("2026-08-28T20:00:00Z")
        HrmSupervisor.resume(capsule_path, events_path, base)
        handoff = HrmSupervisor.handoff(capsule_path, events_path, base + item.fetch(:handoff))
        command = handoff.dig("worker_launch", "activation_command")
        receipt = HrmSupervisor.activate(
          capsule_path,
          events_path,
          command.fetch(-3),
          Integer(command.fetch(-2), 10),
          command.fetch(-1),
          base + item.fetch(:activation)
        )

        assert receipt["auto_terminalized"]
        assert_equal item.fetch(:code), receipt.fetch("reason_codes").first
        other_code = item.fetch(:code) == "worker_activation_startup_budget_exceeded" ?
          "worker_activation_handoff_budget_exceeded" : "worker_activation_startup_budget_exceeded"
        refute_includes receipt["reason_codes"], other_code
        assert_equal receipt["reason_codes"], HrmExperiment.load_json(paths.fetch("projection"))["reason_codes"]
        assert receipt.dig("claim_validation", "matched")
      end
    end
  end

  def test_rc13_context_requires_activation_and_generic_append_cannot_forge_it
    capsule = capsule_with_runtime_source

    with_run(capsule, []) do |capsule_path, events_path, _paths|
      base = Time.iso8601("2026-08-27T22:00:00Z")
      HrmSupervisor.resume(capsule_path, events_path, base)
      HrmSupervisor.handoff(capsule_path, events_path, base + 5)
      before = File.binread(events_path)

      context_error = assert_raises(HrmExperiment::ValidationError) do
        HrmSupervisor.record_context(capsule_path, events_path, "provider_observer", {
          "turn_id" => "must-activate-first",
          "loaded_artifact_bytes_by_id" => {"example.runtime-source" => 1},
          "tool_output_bytes" => 0
        })
      end
      assert_includes context_error.message, "supervisor-accepted rc.13 activation"
      assert_equal before, File.binread(events_path)

      append_error = assert_raises(HrmExperiment::ValidationError) do
        HrmSupervisor.append(capsule_path, events_path, {
          "event_type" => "worker_started",
          "occurred_at" => (base + 6).iso8601,
          "role" => "provider_observer",
          "details" => {}
        })
      end
      assert_includes append_error.message, "supervisor-bound"
      assert_equal before, File.binread(events_path)
    end
  end

  def test_rc13_tampered_activation_digest_is_rejected_by_context_guard_and_result_without_mutation
    capsule = capsule_with_runtime_source
    seams = capsule.dig("function_slice", "required_real_seams")

    %w[context guard result].each do |operation|
      with_run(capsule, []) do |capsule_path, events_path, _paths|
        base = Time.now.utc - 10
        HrmSupervisor.resume(capsule_path, events_path, base)
        handoff_and_activate(capsule_path, events_path, base + 5)
        if %w[guard result].include?(operation)
          HrmSupervisor.record_context(capsule_path, events_path, "provider_observer", {
            "turn_id" => "activation-digest-#{operation}",
            "loaded_artifact_bytes_by_id" => {"example.runtime-source" => 9482},
            "tool_output_bytes" => 1000
          })
        end
        if operation == "result"
          HrmSupervisor.guard(
            capsule_path,
            events_path,
            "inventory_runtime_bindings",
            "provider_observer"
          )
        end
        tamper_worker_activation_digest(events_path)
        before = File.binread(events_path)

        error = assert_raises(HrmExperiment::ValidationError, operation) do
          case operation
          when "context"
            HrmSupervisor.record_context(capsule_path, events_path, "provider_observer", {
              "turn_id" => "tampered-activation-context",
              "loaded_artifact_bytes_by_id" => {"example.runtime-source" => 9482},
              "tool_output_bytes" => 1000
            })
          when "guard"
            HrmSupervisor.guard(
              capsule_path,
              events_path,
              "inventory_runtime_bindings",
              "provider_observer"
            )
          when "result"
            HrmSupervisor.result(capsule_path, events_path, {
              "runtime_readiness" => {
                "required_real_seams" => seams,
                "bound_real_seams" => seams,
                "zero_effect_construction_verified" => false,
                "evidence_sha256" => "9" * 64
              }
            })
          end
        end
        if operation == "result"
          assert_includes error.message, "supervisor-bound post-guard dispatch"
        else
          assert_includes error.message, "exact deterministic activation dispatch digest"
        end
        assert_equal before, File.binread(events_path)
      end
    end
  end

  def test_rc15_and_rc16_observed_activation_digest_tamper_is_rejected_without_mutation
    %w[0.1.0-rc.15 0.1.0-rc.16].each do |kernel_version|
      capsule = capsule_for_kernel_version(capsule_with_runtime_source, kernel_version)
      seams = capsule.dig("function_slice", "required_real_seams")

      %w[context guard result].each do |operation|
        with_run(capsule, []) do |capsule_path, events_path, _paths|
          base = Time.now.utc - 10
          HrmSupervisor.resume(capsule_path, events_path, base)
          handoff_and_activate(capsule_path, events_path, base + 5)
          if %w[guard result].include?(operation)
            HrmSupervisor.record_context(capsule_path, events_path, "provider_observer", {
              "turn_id" => "observed-activation-digest-#{operation}",
              "loaded_artifact_bytes_by_id" => {"example.runtime-source" => 9482},
              "tool_output_bytes" => 1000
            })
          end
          if operation == "result"
            HrmSupervisor.guard(
              capsule_path,
              events_path,
              "inventory_runtime_bindings",
              "provider_observer"
            )
          end
          tamper_worker_observed_activation_digest(events_path)
          before = File.binread(events_path)

          error = assert_raises(HrmExperiment::ValidationError, operation) do
            case operation
            when "context"
              HrmSupervisor.record_context(capsule_path, events_path, "provider_observer", {
                "turn_id" => "observed-only-tampered-context",
                "loaded_artifact_bytes_by_id" => {"example.runtime-source" => 9482},
                "tool_output_bytes" => 1000
              })
            when "guard"
              HrmSupervisor.guard(
                capsule_path,
                events_path,
                "inventory_runtime_bindings",
                "provider_observer"
              )
            when "result"
              HrmSupervisor.result(capsule_path, events_path, {
                "runtime_readiness" => {
                  "required_real_seams" => seams,
                  "bound_real_seams" => seams,
                  "zero_effect_construction_verified" => false,
                  "evidence_sha256" => "8" * 64
                }
              })
            end
          end
          assert_includes error.message, "matching claimed and observed activation dispatch digests"
          assert_equal before, File.binread(events_path)
        end
      end
    end
  end

  def test_rc15_and_rc16_missing_observed_activation_digest_is_rejected_on_load_without_mutation
    %w[0.1.0-rc.15 0.1.0-rc.16].each do |kernel_version|
      capsule = capsule_for_kernel_version(capsule_with_runtime_source, kernel_version)
      with_run(capsule, []) do |capsule_path, events_path, _paths|
        base = Time.now.utc - 10
        HrmSupervisor.resume(capsule_path, events_path, base)
        handoff_and_activate(capsule_path, events_path, base + 5)
        events = HrmExperiment.load_events(events_path)
        activation = events.find { |event| event["event_type"] == "worker_started" }
        activation.fetch("details").delete("observed_activation_dispatch_sha256")
        write_events(events_path, events)
        before = File.binread(events_path)

        error = assert_raises(HrmExperiment::ValidationError) do
          HrmSupervisor.record_context(capsule_path, events_path, "provider_observer", {
            "turn_id" => "missing-observed-activation-digest",
            "loaded_artifact_bytes_by_id" => {"example.runtime-source" => 1},
            "tool_output_bytes" => 0
          })
        end
        assert_includes error.message, "matching claimed and observed activation dispatch digests"
        assert_equal before, File.binread(events_path)
      end
    end
  end

  def test_rc15_claim_validation_match_is_derived_from_both_activation_digests
    validation = HrmSupervisor.activation_claim_validation(
      "activation_dispatch_sha256" => "a" * 64,
      "observed_activation_dispatch_sha256" => "b" * 64,
      "activation_dispatch_cursor" => 2
    )

    assert_equal "a" * 64, validation["claimed_dispatch_sha256"]
    assert_equal "b" * 64, validation["observed_dispatch_sha256"]
    refute validation["matched"]
    assert_equal 2, validation["cursor"]
    error = assert_raises(HrmExperiment::ValidationError) do
      HrmSupervisor.validate_rc15_activation_evidence!(
        "activation_dispatch_sha256" => "a" * 64,
        "observed_activation_dispatch_sha256" => "b" * 64,
        "activation_dispatch_cursor" => 2
      )
    end
    assert_includes error.message, "matching claimed and observed activation dispatch digests"
  end

  def test_rc14_worker_started_remains_valid_without_observed_activation_digest
    capsule = capsule_for_kernel_version(capsule_with_runtime_source, "0.1.0-rc.14")

    with_run(capsule, []) do |capsule_path, events_path, _paths|
      base = Time.now.utc - 10
      HrmSupervisor.resume(capsule_path, events_path, base)
      handoff_and_activate(capsule_path, events_path, base + 1)
      activation = HrmExperiment.load_events(events_path).find do |event|
        event["event_type"] == "worker_started"
      end
      refute activation.fetch("details").key?("observed_activation_dispatch_sha256")

      context = HrmSupervisor.record_context(capsule_path, events_path, "provider_observer", {
        "turn_id" => "rc14-without-observed-digest",
        "loaded_artifact_bytes_by_id" => {"example.runtime-source" => 1},
        "tool_output_bytes" => 0
      })
      assert_equal "context_snapshot", context["event_type"]
    end
  end

  def test_rc13_rebound_handoff_action_role_and_claim_fail_all_lifecycle_paths_without_mutation
    capsule = capsule_with_runtime_source
    forgeries = {
      "same-role-action" => ["record_operational_evidence", "provider_observer"],
      "action-and-role" => ["implement_frozen_slice", "builder"]
    }

    forgeries.each do |forgery, (forged_action, forged_role)|
      %w[context guard result].each do |operation|
        with_run(capsule, []) do |capsule_path, events_path, _paths|
          base = Time.now.utc - 10
          HrmSupervisor.resume(capsule_path, events_path, base)
          handoff_and_activate(capsule_path, events_path, base + 5)
          if %w[guard result].include?(operation)
            HrmSupervisor.record_context(capsule_path, events_path, "provider_observer", {
              "turn_id" => "rebound-#{forgery}-#{operation}",
              "loaded_artifact_bytes_by_id" => {"example.runtime-source" => 9482},
              "tool_output_bytes" => 1000
            })
          end
          if operation == "result"
            HrmSupervisor.guard(
              capsule_path,
              events_path,
              "inventory_runtime_bindings",
              "provider_observer"
            )
          end
          tamper_worker_claim_binding(events_path, forged_action, forged_role)
          before = File.binread(events_path)

          error = assert_raises(HrmExperiment::ValidationError, "#{forgery}/#{operation}") do
            case operation
            when "context"
              HrmSupervisor.record_context(capsule_path, events_path, forged_role, {
                "turn_id" => "forged-context",
                "loaded_artifact_bytes_by_id" => {"example.runtime-source" => 9482},
                "tool_output_bytes" => 1000
              })
            when "guard"
              HrmSupervisor.guard(capsule_path, events_path, forged_action, forged_role)
            when "result"
              HrmSupervisor.result(capsule_path, events_path, {"note" => "forged completion"})
            end
          end
          assert_match(
            /deterministic assignment|exact current deterministic assignment|does not match dispatched role|supervisor-bound post-guard dispatch/,
            error.message
          )
          assert_equal before, File.binread(events_path)
        end
      end
    end
  end

  def test_rc13_result_contracts_exhaust_every_reachable_worker_action_with_valid_templates
    capsule = HrmExperiment.load_yaml(CAPSULE)
    claim = {"worker_claim_id" => "a" * 64}

    HrmExperiment::WORKER_REQUIRED_ACTIONS.each do |action, role|
      contract = HrmSupervisor.rc13_result_input_contract(action, capsule)
      template = contract.fetch("template")
      assert_equal contract.fetch("required_keys").sort, template.keys.sort, action
      assert_operator HrmSupervisor.encode_one_shot_argument(template).bytesize,
                      :<=,
                      HrmSupervisor::MAX_ONE_SHOT_ARGUMENT_BYTES,
                      action
      event = HrmSupervisor.derive_rc13_result_event!(
        capsule,
        action,
        role,
        claim,
        template,
        Time.iso8601("2026-08-27T22:00:00Z")
      )
      prepared = HrmSupervisor.prepare_event(capsule, [], event)
      assert HrmExperiment.validate_events!([prepared]), action
    end
  end

  def test_rc13_launch_commands_execute_one_shot_without_stdin_and_expose_builder
    capsule = capsule_with_runtime_source
    seams = capsule.dig("function_slice", "required_real_seams")

    with_run(capsule, []) do |capsule_path, events_path, paths|
      resume = HrmSupervisor.resume(capsule_path, events_path, Time.now.utc)
      working_directory = resume.dig("worker_launch", "working_directory")

      handoff_stdout, handoff_stderr, handoff_status = Open3.capture3(
        *resume.dig("worker_launch", "handoff_command"),
        chdir: working_directory
      )
      assert handoff_status.success?, handoff_stderr
      handoff = JSON.parse(handoff_stdout)
      launch = handoff.fetch("worker_launch")

      activation_stdout, activation_stderr, activation_status = Open3.capture3(
        *launch.fetch("activation_command"),
        chdir: working_directory
      )
      assert activation_status.success?, activation_stderr
      activation = JSON.parse(activation_stdout)
      assert_equal Digest::SHA256.file(paths["dispatch"]).hexdigest,
                   activation.dig("post_activation_dispatch", "dispatch_sha256")

      before_context = File.binread(events_path)
      ["not*base64url", "A" * (HrmSupervisor::MAX_ONE_SHOT_ARGUMENT_BYTES + 1)].each do |bad_argument|
        bad_command = launch.fetch("context_command").dup
        bad_command[-1] = bad_argument
        bad_stdout, bad_stderr, bad_status = Open3.capture3(*bad_command, chdir: working_directory)
        refute bad_status.success?
        assert_empty bad_stdout
        assert_includes bad_stderr, "requires one bounded unpadded base64url canonical-JSON argument"
        assert_equal before_context, File.binread(events_path)
      end

      context_command = launch.fetch("context_command").dup
      context_command[-1] = HrmSupervisor.encode_one_shot_argument(
        "turn_id" => "provider-one-shot",
        "loaded_artifact_bytes_by_id" => {"example.runtime-source" => 9482},
        "tool_output_bytes" => 2000
      )
      context_stdout, context_stderr, context_status = Open3.capture3(
        *context_command,
        chdir: working_directory
      )
      assert context_status.success?, context_stderr
      assert_equal "context_snapshot", JSON.parse(context_stdout)["event_type"]

      guard_stdout, guard_stderr, guard_status = Open3.capture3(
        *launch.fetch("guard_command"),
        chdir: working_directory
      )
      assert guard_status.success?, guard_stderr
      assert_equal "action_guard_passed", JSON.parse(guard_stdout)["event_type"]

      result_command = launch.fetch("result_command").dup
      result_command[-1] = HrmSupervisor.encode_one_shot_argument(
        "runtime_readiness" => {
          "required_real_seams" => seams,
          "bound_real_seams" => seams,
          "zero_effect_construction_verified" => false,
          "evidence_sha256" => "b" * 64
        }
      )
      result_stdout, result_stderr, result_status = Open3.capture3(
        *result_command,
        chdir: working_directory
      )
      assert result_status.success?, result_stderr
      result = JSON.parse(result_stdout)
      assert_equal "implement_frozen_slice", result.dig("worker_launch", "action")
      assert_equal "builder", result.dig("worker_launch", "role")
      assert_equal "first_executable_delta", result.dig("worker_launch", "result_input", "domain_event")
      assert_operator JSON.generate(result).bytesize, :<=, HrmSupervisor::MAX_RECEIPT_BYTES
    end
  end

  def test_rc13_builder_result_accepts_post_guard_implementation_size_change
    capsule = HrmExperiment.load_yaml(CAPSULE)
    seams = capsule.dig("function_slice", "required_real_seams")
    base = Time.now.utc - 20

    with_run(capsule, []) do |capsule_path, events_path, _paths|
      HrmSupervisor.resume(capsule_path, events_path, base)
      handoff_and_activate(capsule_path, events_path, base + 2)
      HrmSupervisor.record_context(capsule_path, events_path, "provider_observer", {
        "turn_id" => "provider-before-builder-mutation",
        "loaded_artifact_bytes_by_id" => {"example.runtime-source" => 9482},
        "tool_output_bytes" => 1000
      })
      HrmSupervisor.guard(
        capsule_path,
        events_path,
        "inventory_runtime_bindings",
        "provider_observer"
      )
      builder_receipt = HrmSupervisor.result(capsule_path, events_path, {
        "runtime_readiness" => {
          "required_real_seams" => seams,
          "bound_real_seams" => seams,
          "zero_effect_construction_verified" => false,
          "evidence_sha256" => "8" * 64
        }
      })
      assert_equal "implement_frozen_slice", builder_receipt.dig("worker_launch", "action")

      handoff_and_activate(capsule_path, events_path, Time.now.utc, activation_offset: 0)
      HrmSupervisor.record_context(capsule_path, events_path, "builder", {
        "turn_id" => "builder-before-source-size-change",
        "loaded_artifact_bytes_by_id" => {"example.runtime-source" => 9000},
        "tool_output_bytes" => 1000
      })
      HrmSupervisor.guard(capsule_path, events_path, "implement_frozen_slice", "builder")

      local_capsule = HrmExperiment.load_yaml(capsule_path)
      source = local_capsule.fetch("context_dependencies").find do |dependency|
        dependency["dependency_id"] == "example.runtime-source"
      end
      source_path = File.expand_path(source.fetch("source_path"), local_capsule.fetch("project_root"))
      File.open(source_path, "a") { |file| file.write("\n# post-guard builder result fixture\n") }

      receipt = HrmSupervisor.result(capsule_path, events_path, {
        "change_unit_id" => "RC13-POST-GUARD-SOURCE-MUTATION-001",
        "candidate_sha" => "7" * 40,
        "runtime_readiness" => {
          "required_real_seams" => seams,
          "bound_real_seams" => seams,
          "zero_effect_construction_verified" => true,
          "evidence_sha256" => "6" * 64
        }
      })
      events = HrmExperiment.load_events(events_path)

      assert_equal "freeze_candidate", receipt["next_action"]
      assert events.any? { |event| event["event_type"] == "first_executable_delta" }
      assert_equal "worker_result_received", events.last["event_type"]
    end
  end

  def test_rc18_compact_root_receipt_delivers_accounted_pack_and_preapproved_expansion
    capsule = rc18_capsule
    seams = capsule.dig("function_slice", "required_real_seams")
    output_path = capsule.dig("worker_context", "output_target_path")
    FileUtils.rm_f(output_path)

    with_run(capsule, []) do |capsule_path, events_path, _paths|
      base = Time.now.utc - 10
      HrmSupervisor.resume(capsule_path, events_path, base)
      handoff_and_activate(capsule_path, events_path, base + 1)
      HrmSupervisor.record_context(capsule_path, events_path, "provider_observer", {
        "turn_id" => "rc18-provider",
        "loaded_artifact_bytes_by_id" => {"example.runtime-source" => 80_000},
        "tool_output_bytes" => 4_000
      })
      HrmSupervisor.guard(capsule_path, events_path, "inventory_runtime_bindings", "provider_observer")
      provider_result = HrmSupervisor.result(capsule_path, events_path, {
        "runtime_readiness" => {
          "required_real_seams" => seams,
          "bound_real_seams" => seams,
          "zero_effect_construction_verified" => false,
          "evidence_sha256" => "7" * 64
        }
      })
      assert_equal "implement_frozen_slice", provider_result.dig("worker_launch", "action")

      handoff = HrmSupervisor.handoff(capsule_path, events_path)
      receipt_bytes = JSON.generate(handoff).bytesize
      assert_operator receipt_bytes, :<=, HrmSupervisor::RC18_RECEIPT_TARGET_BYTES
      assert_operator HrmSupervisor::MAX_RECEIPT_BYTES - receipt_bytes, :>=, 1024
      refute_includes JSON.generate(handoff), '"sections"'
      refute_includes JSON.generate(handoff), '"result_input"'

      pack_ref = handoff.dig("worker_launch", "worker_context_pack")
      pack_path = File.join(File.dirname(capsule_path), pack_ref.fetch("path"))
      pack = JSON.parse(File.binread(pack_path))
      assert_equal pack_ref.fetch("sha256"), Digest::SHA256.file(pack_path).hexdigest
      assert_equal 0o600, File.stat(pack_path).mode & 0o777
      assert_operator pack_ref.fetch("bytes"), :>, 200_000
      assert_operator pack_ref.fetch("bytes"), :<=, 262_144
      assert_equal %w[
        api_contract focused_test imported_interface kernel_contract
        primary_source target_contract task_capsule
      ], pack.fetch("sections").map { |section| section["purpose"] }.compact.uniq.sort
      task_capsule = pack.fetch("sections").find { |section| section["purpose"] == "task_capsule" }
      assert_equal "canonical_capsule", task_capsule.fetch("selection")
      assert_equal "capsule://active-canonical", task_capsule.fetch("source_path")
      assert task_capsule.fetch("content").start_with?("{\n")

      activation_command = handoff.dig("worker_launch", "commands", "activate")
      HrmSupervisor.activate(
        capsule_path,
        events_path,
        activation_command.fetch(-3),
        Integer(activation_command.fetch(-2), 10),
        activation_command.fetch(-1)
      )
      before_direct_read_claim = File.binread(events_path)
      error = assert_raises(HrmExperiment::ValidationError) do
        HrmSupervisor.record_context(capsule_path, events_path, "builder", {
          "turn_id" => "rc18-direct-read-does-not-authorize",
          "worker_context_pack_sha256" => pack_ref.fetch("sha256"),
          "loaded_artifact_bytes_by_id" => {"example.runtime-source" => 1},
          "tool_output_bytes" => 0
        })
      end
      assert_includes error.message, "unsupported fields"
      assert_equal before_direct_read_claim, File.binread(events_path)
      claim_id = HrmExperiment.load_events(events_path).reverse.find do |event|
        event["event_type"] == "worker_handoff_started"
      end.dig("details", "worker_claim_id")
      expansion = HrmSupervisor.expand_context(capsule_path, events_path, claim_id, {
        "adjacency_class" => "direct_event_contract",
        "section_ids" => ["adjacent-event-contract"],
        "reason" => "The result event must preserve the exact output-artifact binding."
      })
      assert_equal "accepted_preapproved_adjacency",
                   expansion.dig("context_expansion", "context_expansion_disposition")
      expanded_ref = expansion.dig("context_expansion")
      assert_operator expanded_ref.fetch("worker_context_pack_bytes"), :<, pack_ref.fetch("bytes")
      delta_path = File.join(File.dirname(capsule_path), expanded_ref.fetch("worker_context_pack_path"))
      delta_pack = JSON.parse(File.binread(delta_path))
      assert_equal "delta", delta_pack.fetch("pack_kind")
      assert_equal ["adjacent-event-contract"], delta_pack.fetch("sections").map { |section| section["section_id"] }
      cumulative_pack_bytes = pack_ref.fetch("bytes") + expanded_ref.fetch("worker_context_pack_bytes")
      assert_operator cumulative_pack_bytes, :<=, 262_144

      HrmSupervisor.record_context(capsule_path, events_path, "builder", {
        "turn_id" => "rc18-builder-expanded",
        "worker_context_pack_sha256" => expanded_ref.fetch("worker_context_pack_sha256"),
        "tool_output_bytes" => 8_000
      })
      context_event = HrmExperiment.load_events(events_path).reverse.find do |event|
        event["event_type"] == "context_snapshot" && event["role"] == "builder"
      end
      assert_equal cumulative_pack_bytes, context_event.dig("context", "artifact_bytes")
      assert_equal cumulative_pack_bytes,
                   context_event.dig("context", "loaded_artifact_bytes_by_id", "ap.worker-context-pack")
      HrmSupervisor.guard(capsule_path, events_path, "implement_frozen_slice", "builder")
      File.write(output_path, "# owner-private safe-off RC18 artifact\n", mode: "w", perm: 0o600)
      output_sha = Digest::SHA256.file(output_path).hexdigest
      result = HrmSupervisor.result(capsule_path, events_path, {
        "candidate_sha" => "a" * 40,
        "change_unit_id" => "CU-RC18-CONTEXT-PACK",
        "output_artifact_sha256" => output_sha,
        "runtime_readiness" => {
          "required_real_seams" => seams,
          "bound_real_seams" => seams,
          "zero_effect_construction_verified" => true,
          "evidence_sha256" => "8" * 64
        }
      })
      assert_equal "first_executable_delta", result["accepted_result_event_type"]
      executable = HrmExperiment.load_events(events_path).find do |event|
        event["event_type"] == "first_executable_delta"
      end
      assert_equal output_sha, executable.dig("details", "output_artifact_sha256")
      File.open(output_path, "ab") { |file| file.write("# drift\n") }
      error = assert_raises(HrmExperiment::ValidationError) do
        HrmSupervisor.resume(capsule_path, events_path)
      end
      assert_includes error.message, "digest does not match"
    end
  ensure
    FileUtils.rm_f(output_path) if output_path
  end

  def test_rc19_publishes_claim_bound_result_contract_and_terminalizes_protocol_failure
    capsule = rc19_capsule
    with_run(capsule, []) do |capsule_path, events_path, paths|
      base = Time.now.utc - 10
      HrmSupervisor.resume(capsule_path, events_path, base)
      handoff = HrmSupervisor.handoff(capsule_path, events_path, base + 1)
      claim_id = handoff.dig("worker_launch", "worker_claim", "worker_claim_id")
      commands = handoff.dig("worker_launch", "commands")
      assert commands.fetch("result_contract")
      assert commands.fetch("fail_closed")
      assert_operator JSON.generate(handoff).bytesize, :<=, HrmSupervisor::RC18_RECEIPT_TARGET_BYTES
      assert_operator HrmSupervisor::MAX_RECEIPT_BYTES - JSON.generate(handoff).bytesize, :>=, 1024
      refute_includes JSON.generate(handoff), '"result_input"'

      before_activation = File.binread(events_path)
      error = assert_raises(HrmExperiment::ValidationError) do
        HrmSupervisor.result_contract(capsule_path, events_path, claim_id)
      end
      assert_includes error.message, "activation"
      assert_equal before_activation, File.binread(events_path)

      activation = commands.fetch("activate")
      HrmSupervisor.activate(
        capsule_path,
        events_path,
        activation.fetch(-3),
        Integer(activation.fetch(-2), 10),
        activation.fetch(-1),
        base + 2
      )
      contract = HrmSupervisor.result_contract(capsule_path, events_path, claim_id)
      assert_equal "inventory_runtime_bindings", contract.fetch("assigned_action")
      assert_equal "provider_observer", contract.fetch("assigned_role")
      assert_equal ["runtime_readiness"], contract.dig("result_input", "required_keys")
      assert_equal %w[error_code stage], contract.dig("failure_input", "required_keys")

      HrmSupervisor.record_context(capsule_path, events_path, "provider_observer", {
        "turn_id" => "rc19-provider",
        "loaded_artifact_bytes_by_id" => {"example.runtime-source" => 32_211},
        "tool_output_bytes" => 0
      })
      HrmSupervisor.guard(capsule_path, events_path, "inventory_runtime_bindings", "provider_observer")
      before_bad_result = File.binread(events_path)
      bad = assert_raises(HrmExperiment::ValidationError) do
        HrmSupervisor.result(capsule_path, events_path, {
          "candidate_runtime_delta" => false,
          "runtime_bindings" => []
        })
      end
      assert_includes bad.message, "requires only domain keys runtime_readiness"
      assert_equal before_bad_result, File.binread(events_path)

      receipt = HrmSupervisor.worker_failure(capsule_path, events_path, claim_id, {
        "error_code" => "result_payload_invalid",
        "stage" => "result"
      })
      events = HrmExperiment.load_events(events_path)
      assert_equal "stop_reason", events.last.fetch("event_type")
      assert_equal "protocol_failure", events.last.dig("details", "stop_reason")
      assert_equal "worker_protocol_failure", receipt.fetch("reason_codes").first
      assert_equal "fail", HrmExperiment.load_yaml(paths.fetch("scorecard")).dig("verdict", "process_envelope")
      assert_equal "stop_process_envelope", HrmExperiment.load_json(paths.fetch("projection")).fetch("next_action")
      stopped_ledger = File.binread(events_path)
      assert_raises(HrmExperiment::ValidationError) do
        HrmSupervisor.worker_failure(capsule_path, events_path, claim_id, {
          "error_code" => "result_payload_invalid",
          "stage" => "result"
        })
      end
      assert_equal stopped_ledger, File.binread(events_path)
    end
  end

  def test_rc19_exact_contract_drives_provider_to_builder_context_pack_handoff
    capsule = rc19_capsule
    seams = capsule.dig("function_slice", "required_real_seams")
    with_run(capsule, []) do |capsule_path, events_path, _paths|
      base = Time.now.utc - 10
      HrmSupervisor.resume(capsule_path, events_path, base)
      handoff, = handoff_and_activate(capsule_path, events_path, base + 1)
      claim_id = handoff.dig("worker_launch", "worker_claim", "worker_claim_id")
      contract = HrmSupervisor.result_contract(capsule_path, events_path, claim_id)
      domain = Marshal.load(Marshal.dump(contract.dig("result_input", "template")))
      domain.dig("runtime_readiness")["bound_real_seams"] = seams
      domain.dig("runtime_readiness")["evidence_sha256"] = "9" * 64

      HrmSupervisor.record_context(capsule_path, events_path, "provider_observer", {
        "turn_id" => "rc19-valid-provider",
        "loaded_artifact_bytes_by_id" => {"example.runtime-source" => 32_211},
        "tool_output_bytes" => 0
      })
      HrmSupervisor.guard(capsule_path, events_path, "inventory_runtime_bindings", "provider_observer")
      result = HrmSupervisor.result(capsule_path, events_path, domain)
      assert_equal "implement_frozen_slice", result.dig("worker_launch", "action")

      builder_handoff = HrmSupervisor.handoff(capsule_path, events_path)
      assert_operator JSON.generate(builder_handoff).bytesize, :<=, HrmSupervisor::RC18_RECEIPT_TARGET_BYTES
      assert_operator HrmSupervisor::MAX_RECEIPT_BYTES - JSON.generate(builder_handoff).bytesize, :>=, 1024
      assert builder_handoff.dig("worker_launch", "worker_context_pack", "sha256")
      assert builder_handoff.dig("worker_launch", "commands", "result_contract")
      refute_includes JSON.generate(builder_handoff), '"result_input"'

      activation = builder_handoff.dig("worker_launch", "commands", "activate")
      HrmSupervisor.activate(
        capsule_path,
        events_path,
        activation.fetch(-3),
        Integer(activation.fetch(-2), 10),
        activation.fetch(-1)
      )
      builder_claim = builder_handoff.dig("worker_launch", "worker_claim", "worker_claim_id")
      builder_contract = HrmSupervisor.result_contract(capsule_path, events_path, builder_claim)
      assert_equal "implement_frozen_slice", builder_contract.fetch("assigned_action")
      assert_equal %w[candidate_sha change_unit_id output_artifact_sha256 runtime_readiness].sort,
                   builder_contract.dig("result_input", "required_keys").sort
    end
  end

  def test_rc18_manifest_purposes_are_bound_to_authoritative_dependency_kinds
    capsule = rc18_capsule
    primary = capsule.dig("worker_context", "initial_sections").find do |section|
      section["purpose"] == "primary_source"
    end
    api = capsule.dig("worker_context", "initial_sections").find do |section|
      section["purpose"] == "api_contract"
    end
    primary["dependency_id"], api["dependency_id"] = api["dependency_id"], primary["dependency_id"]

    error = assert_raises(HrmExperiment::ValidationError) do
      HrmExperiment.validate_capsule!(capsule)
    end
    assert_includes error.message, "primary_source requires dependency kind implementation_source"
  end

  def test_rc18_task_capsule_content_is_supervisor_canonical_not_dependency_file_bytes
    capsule = rc18_capsule
    dependency = capsule.fetch("context_dependencies").find do |candidate|
      candidate["kind"] == "execution_capsule"
    end
    dependency["source_path"] = "alternate-capsule-with-comments.yaml"
    section = capsule.dig("worker_context", "initial_sections").find do |candidate|
      candidate["purpose"] == "task_capsule"
    end

    materialized = HrmSupervisor.worker_context_section(capsule, section)
    expected = "#{JSON.pretty_generate(HrmExperiment.canonical_value(capsule))}\n"
    assert_equal "capsule://active-canonical", materialized.fetch("source_path")
    assert_equal expected, materialized.fetch("content")
    refute_includes materialized.fetch("content"), "misleading comment"
  end

  def test_rc18_rejects_a_second_semantic_singleton_dependency
    capsule = rc18_capsule
    capsule.fetch("context_dependencies") << {
      "dependency_id" => "spoofed.api-contract",
      "kind" => "project_api_skill_registry",
      "source_path" => "README.md",
      "binding" => "not-a-registry"
    }
    capsule.dig("worker_context", "initial_sections") <<
      rc18_context_section("spoofed-api-contract", "spoofed.api-contract", "api_contract", true)

    error = assert_raises(HrmExperiment::ValidationError) do
      HrmExperiment.validate_capsule!(capsule)
    end
    assert_includes error.message, "exactly one authoritative project_api_skill_registry dependency"
  end

  def test_rc18_rejects_canonical_capsule_selection_on_an_adjacent_interface
    capsule = rc18_capsule
    adjacent = capsule.dig("worker_context", "initial_sections").find do |section|
      section["section_id"] == "adjacent-event-contract"
    end
    adjacent["selection"] = "canonical_capsule"

    error = assert_raises(HrmExperiment::ValidationError) do
      HrmExperiment.validate_capsule!(capsule)
    end
    assert_includes error.message, "required only and always for task_capsule"
  end

  def test_rc18_out_of_policy_expansion_is_a_no_write_escalation
    with_rc18_builder_handoff do |capsule_path, events_path, handoff|
      command = handoff.dig("worker_launch", "commands", "activate")
      HrmSupervisor.activate(
        capsule_path,
        events_path,
        command.fetch(-3),
        Integer(command.fetch(-2), 10),
        command.fetch(-1)
      )
      before_ledger = File.binread(events_path)
      before_packs = Dir.glob(File.join(File.dirname(events_path), "*.worker-context-*.json")).sort
      receipt = HrmSupervisor.expand_context(capsule_path, events_path, command.fetch(-3), {
        "adjacency_class" => "provider_surface_widening",
        "section_ids" => ["adjacent-event-contract"],
        "reason" => "Inspect an unapproved provider surface."
      })
      assert_equal "escalate_to_orchestrator", receipt["disposition"]
      assert_equal "outside_preapproved_adjacency", receipt["reason_code"]
      assert_equal before_ledger, File.binread(events_path)
      assert_equal before_packs, Dir.glob(File.join(File.dirname(events_path), "*.worker-context-*.json")).sort
    end
  end

  def test_rc18_expansion_that_exceeds_cumulative_retained_budget_is_a_no_write_escalation
    capsule = rc18_capsule
    capsule.dig("function_slice", "allowed_paths") << "scripts/hrm_supervisor.rb"
    adjacent_dependency = capsule.fetch("context_dependencies").find do |dependency|
      dependency["dependency_id"] == "example.adjacent-event-contract"
    end
    adjacent_dependency.merge!(
      "source_path" => "scripts/hrm_supervisor.rb",
      "binding" => "rc18-oversize-adjacent-interface"
    )
    capsule.dig("worker_context", "preapproved_adjacency", 0)["max_added_bytes"] = 200_000

    with_rc18_builder_handoff(capsule) do |capsule_path, events_path, handoff|
      command = handoff.dig("worker_launch", "commands", "activate")
      HrmSupervisor.activate(
        capsule_path,
        events_path,
        command.fetch(-3),
        Integer(command.fetch(-2), 10),
        command.fetch(-1)
      )
      before_ledger = File.binread(events_path)
      before_packs = Dir.glob(File.join(File.dirname(events_path), "*.worker-context-*.json")).sort
      receipt = HrmSupervisor.expand_context(capsule_path, events_path, command.fetch(-3), {
        "adjacency_class" => "direct_event_contract",
        "section_ids" => ["adjacent-event-contract"],
        "reason" => "Load a preapproved interface only if cumulative retained context remains bounded."
      })
      assert_equal "escalate_to_orchestrator", receipt["disposition"]
      assert_equal "worker_context_budget_exceeded", receipt["reason_code"]
      assert_equal before_ledger, File.binread(events_path)
      assert_equal before_packs, Dir.glob(File.join(File.dirname(events_path), "*.worker-context-*.json")).sort
    end
  end

  def test_rc18_expansion_accounting_tamper_is_rejected_before_context_advancement
    with_rc18_builder_handoff do |capsule_path, events_path, handoff|
      command = handoff.dig("worker_launch", "commands", "activate")
      HrmSupervisor.activate(
        capsule_path,
        events_path,
        command.fetch(-3),
        Integer(command.fetch(-2), 10),
        command.fetch(-1)
      )
      expansion = HrmSupervisor.expand_context(capsule_path, events_path, command.fetch(-3), {
        "adjacency_class" => "direct_event_contract",
        "section_ids" => ["adjacent-event-contract"],
        "reason" => "Load the exact preapproved result-event contract."
      })
      events = HrmExperiment.load_events(events_path)
      events.last.fetch("details")["context_expansion_added_bytes"] += 1
      File.write(
        events_path,
        events.map { |event| JSON.generate(event) }.join("\n") + "\n",
        mode: "w",
        perm: 0o600
      )
      before = File.binread(events_path)
      error = assert_raises(HrmExperiment::ValidationError) do
        HrmSupervisor.record_context(capsule_path, events_path, "builder", {
          "turn_id" => "rc18-tampered-expansion-accounting",
          "worker_context_pack_sha256" => expansion.dig(
            "context_expansion",
            "worker_context_pack_sha256"
          ),
          "tool_output_bytes" => 0
        })
      end
      assert_includes error.message, "expansion accounting"
      assert_equal before, File.binread(events_path)
    end
  end

  def test_rc18_pack_digest_drift_blocks_guard_without_advancing_ledger
    with_rc18_builder_handoff do |capsule_path, events_path, handoff|
      command = handoff.dig("worker_launch", "commands", "activate")
      HrmSupervisor.activate(
        capsule_path,
        events_path,
        command.fetch(-3),
        Integer(command.fetch(-2), 10),
        command.fetch(-1)
      )
      pack_ref = handoff.dig("worker_launch", "worker_context_pack")
      HrmSupervisor.record_context(capsule_path, events_path, "builder", {
        "turn_id" => "rc18-before-pack-drift",
        "worker_context_pack_sha256" => pack_ref.fetch("sha256"),
        "tool_output_bytes" => 1_000
      })
      pack_path = File.join(File.dirname(capsule_path), pack_ref.fetch("path"))
      File.open(pack_path, "ab") { |file| file.write(" ") }
      before = File.binread(events_path)
      error = assert_raises(HrmExperiment::ValidationError) do
        HrmSupervisor.guard(capsule_path, events_path, "implement_frozen_slice", "builder")
      end
      assert_includes error.message, "digest drifted"
      assert_equal before, File.binread(events_path)
    end
  end

  def test_rc18_python_symbol_context_keeps_decorators_with_their_definition
    Dir.mktmpdir do |directory|
      path = File.join(directory, "interfaces.py")
      File.write(path, <<~PYTHON)
        @dataclass(frozen=True)
        class FirstInterface:
            value: str

        @registered("direct")
        class SecondInterface:
            enabled: bool
      PYTHON

      first = HrmSupervisor.python_symbol_content(path, ["FirstInterface"])
      second = HrmSupervisor.python_symbol_content(path, ["SecondInterface"])
      assert first.start_with?("@dataclass(frozen=True)\nclass FirstInterface")
      refute_includes first, "@registered"
      assert second.start_with?("@registered(\"direct\")\nclass SecondInterface")
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
      worker_started
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
      handoff_and_activate(capsule_path, events_path, Time.iso8601("2026-08-27T22:00:05Z"))
      HrmSupervisor.record_context(capsule_path, events_path, "provider_observer", {
        "turn_id" => "provider-zero-source",
        "loaded_artifact_bytes_by_id" => {"example.runtime-source" => 0},
        "tool_output_bytes" => 100
      })

      error = assert_raises(HrmExperiment::ValidationError) do
        HrmSupervisor.guard(capsule_path, events_path, "inventory_runtime_bindings", "provider_observer")
      end
      assert_includes error.message, "positive materialized bytes"
      assert_equal 4, HrmExperiment.load_events(events_path).length
    end
  end

  def test_rc13_provider_domain_result_dispatches_fresh_builder_with_unchanged_allocation
    capsule = capsule_with_runtime_source
    seams = capsule.dig("function_slice", "required_real_seams")

    with_run(capsule, []) do |capsule_path, events_path, paths|
      base = Time.now.utc
      HrmSupervisor.resume(capsule_path, events_path, base - 10)
      handoff_and_activate(capsule_path, events_path, base - 5)
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
      result_domain = {
        "runtime_readiness" => {
          "required_real_seams" => seams,
          "bound_real_seams" => seams,
          "zero_effect_construction_verified" => false,
          "evidence_sha256" => "a" * 64
        }
      }
      tampered_results = {
        "claim" => lambda { |domain| domain["worker_claim_id"] = "f" * 64 },
        "action" => lambda { |domain| domain["action"] = "implement_frozen_slice" },
        "role" => lambda { |domain| domain["role"] = "builder" }
      }
      tampered_results.each do |name, mutation|
        tampered_result = Marshal.load(Marshal.dump(result_domain))
        mutation.call(tampered_result)
        error = assert_raises(HrmExperiment::ValidationError, name) do
          HrmSupervisor.result(capsule_path, events_path, tampered_result, base + 7)
        end
        assert_includes error.message, "requires only domain keys runtime_readiness"
        assert_equal 5, HrmExperiment.load_events(events_path).length
      end

      receipt = HrmSupervisor.result(capsule_path, events_path, result_domain, base + 7)
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
        HrmSupervisor.result(capsule_path, events_path, result_domain, base + 8)
      end
      assert_includes replay.message, "matching guard"
      assert_equal 7, HrmExperiment.load_events(events_path).length
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
      assert_equal ["terminal_closed"], receipt["reason_codes"]
      assert_equal receipt["reason_codes"], projection["reason_codes"]
      assert_equal "Terminal: terminal closed.", projection.dig("operator_projection", "summary")
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
      assert_equal 30, successor.dig("budgets", "max_startup_to_worker_activation_seconds")
      assert_equal 25, successor.dig("budgets", "max_handoff_to_worker_activation_seconds")
      assert_equal "agent_playbooks.hrm_execution_capsule.v0.7", successor["schema_version"]
      assert_equal capsule["session_id"], successor.dig("session_lineage", "predecessor_session_id")
      assert_equal "superseded", events.last.dig("details", "stop_reason")
      assert_equal successor["session_id"], receipt["successor_session_id"]
      assert HrmExperiment.validate_capsule!(successor)
    end
  end

  def test_production_observation_runs_every_reachable_worker_contract_to_review
    capsule = HrmExperiment.load_yaml(File.join(ROOT, "examples/hrm-production-observation-capsule.example.yaml"))

    with_run(capsule, []) do |capsule_path, events_path, paths|
      receipt = HrmSupervisor.resume(capsule_path, events_path, Time.now.utc - 10)
      actions = %w[prepare_private_inputs inspect_provider_read_only record_operational_evidence]

      actions.each_with_index do |action, index|
        dispatch = HrmExperiment.load_json(paths["dispatch"])
        assert_equal action, receipt["next_action"]
        assert_equal action, dispatch.dig("assignment", "action")
        assert_equal "provider_observer", dispatch.dig("assignment", "role")
        assert_equal "hashes_only_unless_changed", dispatch.dig("cache", "load_policy")
        assert_equal "worker_result_received", receipt.dig("worker_launch", "result_input", "domain_event") if index < 2
        assert_equal "first_operational_evidence",
                     receipt.dig("worker_launch", "result_input", "domain_event") if index == 2
        assert receipt.dig("worker_launch", "result_input", "template")
        assert_operator JSON.generate(receipt).bytesize, :<=, HrmSupervisor::MAX_RECEIPT_BYTES

        handoff_and_activate(capsule_path, events_path, Time.now.utc, activation_offset: 0)
        HrmSupervisor.record_context(capsule_path, events_path, "provider_observer", {
          "turn_id" => "production-observation-#{action}",
          "loaded_artifact_bytes_by_id" => {},
          "tool_output_bytes" => 256
        })
        HrmSupervisor.guard(capsule_path, events_path, action, "provider_observer")
        receipt = HrmSupervisor.result(
          capsule_path,
          events_path,
          {"note" => "completed bounded #{action}"}
        )
      end

      assert_equal "prepare_review", receipt["next_action"]
      assert HrmExperiment.load_events(events_path).any? do |event|
        event["event_type"] == "first_operational_evidence"
      end
    end
  end

  def test_changed_skill_fingerprint_routes_only_missing_discovery
    capsule = HrmExperiment.load_yaml(CAPSULE)
    capsule.dig("project_api_skills", "required_skills", 0)["contract_fingerprint"] = "c" * 64
    session_started = HrmExperiment.load_events(EVENTS).first

    Dir.mktmpdir("hrm-supervisor", ROOT) do |directory|
      FileUtils.mkdir_p(File.join(directory, ".git"))
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

  def test_rc13_discovery_result_accepts_registry_resolution_after_guard
    capsule = HrmExperiment.load_yaml(CAPSULE)
    registry = HrmExperiment.load_yaml(File.join(ROOT, "examples/project-api-skill-registry.example.yaml"))
    resolved_record = Marshal.load(Marshal.dump(registry.fetch("skills").first))
    resolved_record["contract_version"] = "public-config-v3"
    resolved_fingerprint = ProjectApiSkillRegistry.contract_fingerprint(resolved_record)
    capsule.dig("project_api_skills", "required_skills", 0)["contract_fingerprint"] = resolved_fingerprint

    with_run(capsule, []) do |capsule_path, events_path, _paths|
      base = Time.now.utc - 10
      receipt = HrmSupervisor.resume(capsule_path, events_path, base)
      assert_equal "discover_missing_project_api_skills", receipt["next_action"]

      handoff_and_activate(capsule_path, events_path, base + 2)
      HrmSupervisor.record_context(capsule_path, events_path, "provider_observer", {
        "turn_id" => "api-skill-resolution",
        "loaded_artifact_bytes_by_id" => {"example.api-skill-registry" => 512},
        "tool_output_bytes" => 256
      })
      HrmSupervisor.guard(
        capsule_path,
        events_path,
        "discover_project_api_skills",
        "provider_observer"
      )

      local_capsule = HrmExperiment.load_yaml(capsule_path)
      registry_path = ProjectApiSkillRegistry.registry_path(local_capsule, capsule_path)
      updated_registry = HrmExperiment.load_yaml(registry_path)
      updated_record = updated_registry.fetch("skills").first
      updated_record["contract_version"] = resolved_record.fetch("contract_version")
      updated_record["contract_fingerprint"] = resolved_fingerprint
      updated_registry["registry_version"] += 1
      updated_registry["updated_at"] = Time.now.utc.iso8601
      updated_registry["registry_hash"] = ProjectApiSkillRegistry.registry_hash(updated_registry)
      ProjectApiSkillRegistry.validate_registry!(updated_registry)
      File.write(registry_path, YAML.dump(updated_registry), mode: "w", perm: 0o600)

      receipt = HrmSupervisor.result(
        capsule_path,
        events_path,
        {"note" => "published the verified API skill contract"}
      )

      assert_equal "inventory_runtime_bindings", receipt["next_action"]
      assert_equal 1, receipt["reusable_api_skill_count"]
      assert_equal 0, receipt["missing_api_skill_count"]
      assert_equal "worker_result_received", HrmExperiment.load_events(events_path).last["event_type"]
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

  def capsule_for_kernel_version(capsule, kernel_version)
    capsule.dig("playbook_pin")["kernel_version"] = kernel_version
    kernel_dependency = capsule.fetch("context_dependencies").find do |dependency|
      dependency["kind"] == "playbook_kernel"
    end
    if kernel_dependency
      kernel_dependency["binding"] = kernel_dependency.fetch("binding").sub(
        %r{AP-EXEC-001/0\.1\.0-rc\.\d+},
        "AP-EXEC-001/#{kernel_version}"
      )
    end
    implementation_source = capsule.fetch("context_dependencies").find do |dependency|
      dependency["kind"] == "implementation_source"
    end
    if implementation_source && %w[0.1.0-rc.13 0.1.0-rc.14 0.1.0-rc.15].include?(kernel_version)
      implementation_source["binding"] =
        "#{kernel_version.delete_prefix('0.1.0-').delete('.')}-example-source"
    end
    if %w[0.1.0-rc.13 0.1.0-rc.14].include?(kernel_version)
      capsule.dig("budgets")["max_startup_to_worker_activation_seconds"] = 20
      capsule.dig("budgets")["max_handoff_to_worker_activation_seconds"] = 10
    elsif kernel_version == "0.1.0-rc.15"
      capsule.dig("budgets")["max_startup_to_worker_activation_seconds"] = 30
      capsule.dig("budgets")["max_handoff_to_worker_activation_seconds"] = 20
    end
    capsule
  end

  def rc18_capsule
    capsule = capsule_for_kernel_version(HrmExperiment.load_yaml(CAPSULE), "0.1.0-rc.18")
    capsule["session_id"] = AE_SCALE_SESSION_ID
    capsule.dig("budgets")["context_bytes_by_role"] = HrmExperiment::RC18_CONTEXT_BYTES_BY_ROLE
    capsule.dig("function_slice", "allowed_paths") << "schemas/hrm-run-event.schema.json"
    capsule.fetch("context_dependencies").find do |dependency|
      dependency["kind"] == "accepted_target_contract"
    end["source_path"] = "examples/hrm-directed-session.example.yaml"
    capsule.dig("target_resolution")["source_path"] = "examples/hrm-directed-session.example.yaml"
    capsule.fetch("context_dependencies").find do |dependency|
      dependency["kind"] == "execution_capsule"
    end["source_path"] = "capsule.yaml"
    runtime_source = capsule.fetch("context_dependencies").find do |dependency|
      dependency["kind"] == "implementation_source"
    end
    runtime_source.merge!("source_path" => "scripts/hrm_experiment.rb", "binding" => "rc18-primary-source")
    capsule.fetch("context_dependencies").concat([
      {
        "dependency_id" => "example.imported-interface",
        "kind" => "playbook_runtime",
        "source_path" => "scripts/project_api_skill_registry.rb",
        "binding" => "rc18-interface"
      },
      {
        "dependency_id" => "example.focused-test",
        "kind" => "declared_check",
        "source_path" => "tests/test_hrm_experiment.rb",
        "binding" => "rc18-focused-test"
      },
      {
        "dependency_id" => "example.adjacent-event-contract",
        "kind" => "playbook_runtime",
        "source_path" => "schemas/hrm-run-event.schema.json",
        "binding" => "agent_playbooks.hrm_run_event.v0.5"
      },
      {
        "dependency_id" => "ap.worker-context-pack",
        "kind" => "worker_context_pack",
        "source_path" => "supervisor://worker-context-pack",
        "binding" => "claim-dispatch-manifest-sha256"
      }
    ])
    capsule["worker_context"] = {
      "schema_version" => "agent_playbooks.worker_context_manifest.v0.1",
      "coordination_receipt_target_bytes" => 3072,
      "coordination_receipt_hard_cap_bytes" => 4096,
      "role_budgets" => {
        "builder" => {"loaded_artifact_bytes" => 262_144, "tool_output_reserve_bytes" => 65_536},
        "provider_observer" => {"loaded_artifact_bytes" => 98_304, "tool_output_reserve_bytes" => 32_768}
      },
      "initial_sections" => [
        rc18_context_section("complete-primary-source", "example.runtime-source", "primary_source", true),
        rc18_context_section("direct-imported-interface", "example.imported-interface", "imported_interface", true),
        rc18_context_section("focused-interface-test", "example.focused-test", "focused_test", true),
        rc18_context_section("registered-api-contracts", "example.api-skill-registry", "api_contract", true),
        rc18_context_section("exact-task-capsule", "example.execution-capsule", "task_capsule", true),
        rc18_context_section("released-kernel-contract", "ap.exec.kernel", "kernel_contract", true),
        rc18_context_section("accepted-target-contract", "example.target-contract", "target_contract", true),
        rc18_context_section("adjacent-event-contract", "example.adjacent-event-contract", "imported_interface", false)
      ],
      "preapproved_adjacency" => [{
        "adjacency_class" => "direct_event_contract",
        "section_ids" => ["adjacent-event-contract"],
        "max_added_bytes" => 16_384
      }],
      "output_target_path" => "/tmp/agent-playbooks-rc18-test-#{Process.pid}.rb",
      "tuning_status" => "provisional_until_two_representative_builder_runs"
    }
    capsule
  end

  def rc19_capsule
    capsule = capsule_for_kernel_version(rc18_capsule, "0.1.0-rc.19")
    capsule.dig("worker_context")["output_target_path"] =
      "/tmp/agent-playbooks-rc19-test-#{Process.pid}.rb"
    capsule
  end

  def rc18_context_section(section_id, dependency_id, purpose, initial)
    {
      "section_id" => section_id,
      "dependency_id" => dependency_id,
      "purpose" => purpose,
      "selection" => purpose == "task_capsule" ? "canonical_capsule" : "full_file",
      "privacy" => "repository_safe",
      "initial" => initial
    }
  end

  def with_rc18_builder_handoff(capsule = rc18_capsule)
    output_path = capsule.dig("worker_context", "output_target_path")
    FileUtils.rm_f(output_path)
    seams = capsule.dig("function_slice", "required_real_seams")
    with_run(capsule, []) do |capsule_path, events_path, _paths|
      base = Time.now.utc - 10
      HrmSupervisor.resume(capsule_path, events_path, base)
      handoff_and_activate(capsule_path, events_path, base + 1)
      HrmSupervisor.record_context(capsule_path, events_path, "provider_observer", {
        "turn_id" => "rc18-provider-helper",
        "loaded_artifact_bytes_by_id" => {"example.runtime-source" => 80_000},
        "tool_output_bytes" => 4_000
      })
      HrmSupervisor.guard(capsule_path, events_path, "inventory_runtime_bindings", "provider_observer")
      HrmSupervisor.result(capsule_path, events_path, {
        "runtime_readiness" => {
          "required_real_seams" => seams,
          "bound_real_seams" => seams,
          "zero_effect_construction_verified" => false,
          "evidence_sha256" => "6" * 64
        }
      })
      handoff = HrmSupervisor.handoff(capsule_path, events_path)
      yield capsule_path, events_path, handoff
    end
  ensure
    FileUtils.rm_f(output_path) if output_path
  end

  def with_ae_scale_run(kernel_version, project_root_bytes:)
    capsule = capsule_for_kernel_version(HrmExperiment.load_yaml(CAPSULE), kernel_version)
    capsule["session_id"] = AE_SCALE_SESSION_ID
    capsule.dig("target_resolution").merge!(
      "current_target_hrm" => AE_SCALE_HRM_ID,
      "resolved_hrm_id" => AE_SCALE_HRM_ID,
      "explicit_hrm_id" => nil
    )
    capsule.dig("hrm")["id"] = AE_SCALE_HRM_ID
    capsule.dig("function_slice")["required_real_seams"] = AE_SCALE_REAL_SEAMS
    runtime_source = capsule.fetch("context_dependencies").find do |dependency|
      dependency["kind"] == "implementation_source"
    end
    runtime_source.merge!(
      "dependency_id" => "ae.runtime-source",
      "source_path" => "src/estimating/operator_canary.py",
      "binding" => "ae-scale-runtime-source"
    )
    capsule.dig("metrics").merge!(
      "event_log_path" => ".codex/hrm-runs/#{AE_SCALE_SESSION_ID}.events.jsonl",
      "session_state_path" => ".codex/hrm-runs/#{AE_SCALE_SESSION_ID}.state.yaml",
      "scorecard_path" => ".codex/hrm-runs/#{AE_SCALE_SESSION_ID}.scorecard.yaml"
    )

    Dir.mktmpdir("aer", "/tmp") do |temporary_directory|
      directory = exact_length_directory(temporary_directory, project_root_bytes)
      FileUtils.mkdir_p(File.join(directory, ".git"))
      capsule["project_root"] = directory
      copy_relative_dependencies(capsule, directory)
      runtime_copy = File.join(directory, runtime_source.fetch("source_path"))
      FileUtils.mkdir_p(File.dirname(runtime_copy))
      FileUtils.cp(File.join(ROOT, "scripts/hrm_supervisor.rb"), runtime_copy)

      capsule_path = File.join(
        directory,
        "docs/experiments/ap-exec-001/AE-PRODUCTION-CANARY-capsule.yaml"
      )
      events_path = File.join(directory, capsule.dig("metrics", "event_log_path"))
      FileUtils.mkdir_p(File.dirname(capsule_path))
      FileUtils.mkdir_p(File.dirname(events_path))
      File.write(capsule_path, YAML.dump(capsule), mode: "w", perm: 0o600)
      File.write(events_path, "", mode: "w", perm: 0o600)
      paths = HrmSupervisor.artifact_paths(capsule, events_path)
      yield capsule_path, events_path, paths
    end
  end

  def exact_length_directory(directory, target_bytes)
    path = File.realpath(directory)
    component_index = 0
    while path.bytesize < target_bytes
      available = target_bytes - path.bytesize - 1
      raise "project root already exceeds #{target_bytes} bytes" unless available.positive?

      component_bytes = [available, 120].min
      prefix = "p#{component_index}"
      component = (prefix + ("x" * component_bytes))[0, component_bytes]
      path = File.join(path, component)
      FileUtils.mkdir_p(path)
      component_index += 1
    end
    raise "project root is #{path.bytesize} bytes, expected #{target_bytes}" unless path.bytesize == target_bytes

    path
  end

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

  def handoff_and_activate(capsule_path, events_path, occurred_at, activation_offset: 1)
    handoff_receipt = HrmSupervisor.handoff(capsule_path, events_path, occurred_at)
    command = handoff_receipt.dig("worker_launch", "activation_command") ||
              handoff_receipt.dig("worker_launch", "commands", "activate")
    raise "expected an rc.13 activation command" unless command

    activation_receipt = HrmSupervisor.activate(
      capsule_path,
      events_path,
      command.fetch(-3),
      Integer(command.fetch(-2), 10),
      command.fetch(-1),
      occurred_at + activation_offset
    )
    [handoff_receipt, activation_receipt]
  end

  def tamper_worker_activation_digest(events_path)
    events = HrmExperiment.load_events(events_path)
    activation = events.find { |event| event["event_type"] == "worker_started" }
    activation.fetch("details")["activation_dispatch_sha256"] = "f" * 64
    activation.fetch("details")["observed_activation_dispatch_sha256"] = "f" * 64
    write_events(events_path, events)
  end

  def tamper_worker_observed_activation_digest(events_path)
    events = HrmExperiment.load_events(events_path)
    activation = events.find { |event| event["event_type"] == "worker_started" }
    activation.fetch("details")["observed_activation_dispatch_sha256"] = "e" * 64
    write_events(events_path, events)
  end

  def tamper_worker_claim_binding(events_path, action, role)
    events = HrmExperiment.load_events(events_path)
    handoff = events.find { |event| event["event_type"] == "worker_handoff_started" }
    handoff["role"] = role
    handoff.fetch("details").merge!("action" => action, "worker_role" => role)
    claim_id = HrmExperiment.object_sha256(
      "session_id" => handoff.fetch("session_id"),
      "hrm_id" => handoff.fetch("hrm_id"),
      "action" => action,
      "role" => role,
      "source_dispatch_cursor" => handoff.dig("details", "source_dispatch_cursor"),
      "source_dispatch_sha256" => handoff.dig("details", "source_dispatch_sha256")
    )
    handoff.fetch("details")["worker_claim_id"] = claim_id

    activation = events.find { |event| event["event_type"] == "worker_started" }
    activation["role"] = role
    activation.fetch("details").merge!(
      "action" => action,
      "worker_role" => role,
      "worker_claim_id" => claim_id
    )
    context = events.find { |event| event["event_type"] == "context_snapshot" }
    context["role"] = role if context && role != "provider_observer"
    guard = events.find { |event| event["event_type"] == "action_guard_passed" }
    guard["role"] = role if guard
    guard.fetch("details").merge!("action" => action, "guarded_role" => role) if guard
    write_events(events_path, events)
  end

  def write_events(events_path, events)
    File.write(
      events_path,
      events.map { |event| JSON.generate(event) }.join("\n") + "\n",
      mode: "w",
      perm: 0o600
    )
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
      FileUtils.mkdir_p(File.join(directory, ".git"))
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
