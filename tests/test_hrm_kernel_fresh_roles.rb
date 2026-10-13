# frozen_string_literal: true
require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../lib/hrm_kernel/driver"

# Offline transport seam checks; no native model or application runs.
class HrmKernelFreshRolesTest < Minitest::Test
  def setup
    @tmp = File.realpath(Dir.mktmpdir)
    @store = HrmKernel::Store.new(File.join(@tmp, "state"))
    @store.transact("command_id" => "initial", "type" => "milestone.create", "actor" => {"role" => "operator", "id" => "human"}, "data" => {
      "milestone_id" => "fresh", "outcome" => "Neutral gated journey", "project_root" => @tmp,
      "requirements" => [{"id" => "R1", "text" => "Original threshold"}, {"id" => "R2", "text" => "Retain unchanged behavior"}], "allowed_paths" => ["app.txt"]})
    @host = HrmKernel::Host.new(state_dir: File.join(@tmp, "state"))
  end
  def teardown
    FileUtils.remove_entry(@tmp)
  end
  def profile
    {"schema" => HrmKernel::Host::FRESH_PROFILE, "run_id" => "bounded", "session_limits" => {"worker" => 2, "orchestrator" => 1, "reviewer" => 1},
      "milestone_revision" => @store.read.dig("state", "milestone", "revision"), "state_revision" => HrmKernel::Host.digest(@store.read.fetch("state")),
      "workflow" => {"ordered_stages" => [{"stage" => "Prepare", "owner" => "builder"}, {"stage" => "Review", "owner" => "reviewer"}],
        "current_stage" => "Paused pending operator review", "next_eligible_action" => "Read declared sources only; no tests or activation"}}
  end
  def spec(role = "orchestrator", id = "one")
    {"job_id" => id, "role" => role, "model" => role == "worker" ? "gpt-6.1-sol" : "gpt-6-astra", "prompt" => "bounded task", "work_order_id" => role == "worker" ? "work" : nil,
      "check_plan" => {"environment_id" => "offline", "checks" => []}, "fresh_role_profile" => profile}
  end
  def test_current_requirements_replace_initial_and_preserve_unchanged
    @store.transact("command_id" => "amend", "type" => "intent.record", "actor" => {"role" => "operator", "id" => "human"}, "data" => {
      "intent_id" => "change", "kind" => "milestone_change", "text" => "Use current threshold", "source" => {"thread_id" => "human", "message_id" => "amend"}, "requirement_ids" => ["R1"], "requirements" => [{"id" => "R1", "text" => "Current threshold"}]})
    packet = @host.send(:build_packet, spec, "astra-orchestrator", @store.read.fetch("state"), [])
    assert_equal "Current threshold", packet.dig("effective_requirements", "R1", "text")
    assert_equal "Retain unchanged behavior", packet.dig("effective_requirements", "R2", "text")
    refute_includes JSON.generate(packet), "Original threshold"
    refute packet.key?("initial_contract")
    assert_equal profile["workflow"], packet["workflow"]
    assert_equal "gpt-6-astra", packet.dig("role_projection", "milestone", "models", "reviewer")
  end
  def test_models_fresh_launch_and_invalid_resume
    %w[worker reviewer orchestrator].each do |role|
      normalized = @host.send(:normalize_spec, spec(role))
      assert_equal spec(role)["model"], normalized["model"]
      assert_raises(HrmKernel::Error) { @host.send(:normalize_spec, spec(role).merge("resume_job_id" => "old")) }
      assert_raises(HrmKernel::Error) { @host.send(:normalize_spec, spec(role).merge("model" => "gpt-5.6-sol")) }
    end
  end
  def test_stale_and_incomplete_packets_fail_closed
    assert_raises(HrmKernel::Error) { @host.send(:normalize_spec, spec.merge("fresh_role_profile" => profile.merge("workflow" => {}))) }
    assert_raises(HrmKernel::Error) { @host.send(:validate_fresh_state!, spec.merge("fresh_role_profile" => profile.merge("state_revision" => "0" * 64)), @store.read.fetch("state")) }
  end
  def test_aggregate_budget_survives_host_restart_and_role_changes
    first = @host.send(:admit_fresh_session!, spec("orchestrator"))
    assert_equal 1, first["revision"]
    assert_equal 1, @host.send(:admit_fresh_session!, spec("orchestrator"))["revision"]
    assert first["current_session_debited"]
    assert_equal 0, first.dig("remaining", "orchestrator")
    reopened = HrmKernel::Host.new(state_dir: File.join(@tmp, "state"))
    second = reopened.send(:admit_fresh_session!, spec("worker", "two"))
    assert_equal 2, second["revision"]
    assert_equal 0, second.dig("remaining", "orchestrator")
    assert_raises(HrmKernel::Error) { reopened.send(:admit_fresh_session!, spec("orchestrator", "three")) }
    assert_raises(HrmKernel::Error) { reopened.send(:admit_fresh_session!, spec("worker", "four").merge("fresh_role_profile" => profile.merge("session_limits" => {"worker" => 3, "reviewer" => 1, "orchestrator" => 1}))) }
  end
end
