# frozen_string_literal: true

require "fileutils"
require "json"
require "minitest/autorun"
require "open3"
require "rbconfig"
require "stringio"
require "tmpdir"
require_relative "../lib/hrm_kernel/driver"
require_relative "../scripts/hrm_kernel"

# Model output is deterministic here. Host subprocesses, frozen native checks,
# environment preflight, authority validation and ledger transitions are real.
class HrmKernelDriverTest < Minitest::Test
  def setup
    @temporary = File.realpath(Dir.mktmpdir("hrm-driver"))
    @project = File.join(@temporary, "project")
    Dir.mkdir(@project, 0o700)
    @state_dir = File.join(@temporary, "state")
    File.write(File.join(@project, "app.txt"), "before\n")
    File.write(File.join(@project, ".gitignore"), "/.codex/hrm-runs/\n")
    File.write(File.join(@project, "check.rb"), 'abort "unfinished behavior" unless File.read("app.txt") == "implemented\\n"; puts "verified behavior"')
    git("init", "--quiet")
    git("config", "user.email", "kernel-test@example.invalid")
    git("config", "user.name", "Kernel Test")
    git("add", ".")
    git("commit", "--quiet", "-m", "isolated baseline")
    @store = HrmKernel::Store.new(@state_dir)
    @store.transact("command_id" => "initial", "type" => "milestone.create", "actor" => {"id" => "human", "role" => "operator"}, "data" => {
      "milestone_id" => "driver-test", "outcome" => "Implement then review behavior", "project_root" => @project,
      "mode" => "implementation", "requirements" => [{"id" => "behavior", "text" => "Application contains implemented behavior"}],
      "allowed_paths" => ["app.txt"], "acceptance_scenarios" => [{"id" => "scenario", "text" => "Working behavior", "requirement_ids" => ["behavior"], "check_ids" => ["behavior-check"]}]
    })
    @fake = File.join(@temporary, "fake-codex")
    File.write(@fake, <<~'CODEX'.sub("RUBY_EXECUTABLE", RbConfig.ruby))
      #!RUBY_EXECUTABLE
      require "json"
      packet = JSON.parse(STDIN.read)
      orchestrator = packet["actor_id"] == "astra-orchestrator"
      reviewer = packet["actor_id"].start_with?("reviewer-")
      uuid = orchestrator ? "11234567-89ab-cdef-0123-456789abcdef" : reviewer ? "21234567-89ab-cdef-0123-456789abcdef" : "31234567-89ab-cdef-0123-456789abcdef"
      abort "resume changed identity" if ARGV.include?("resume") && ARGV[ARGV.index("resume") + 1] != uuid
      puts JSON.generate("type" => "thread.started", "thread_id" => uuid)
      if orchestrator
        control = JSON.parse(packet["task"])
        round = control.dig("budget", "turn")
        request = ->(id, op, input) { {"request_id" => id, "operation" => op, "input_json" => JSON.generate(input)} }
        apply = ->(id, type, data, role = "orchestrator") { request.call(id, "apply", {"command_id" => id, "type" => type, "actor" => {"id" => role == "operator" ? "human" : "astra-orchestrator", "role" => role}, "data" => data}) }
        env = control["environment"]
        check = env["preflight_checks"].first.merge("id" => "behavior-check", "argv" => [env["preflight_checks"].first["argv"].first, "check.rb"])
        dispatch = ->(id, role, parent = nil) {
          spec = {"job_id" => id, "role" => role, "model" => "gpt-5.6-sol", "prompt" => id, "context_paths" => [], "max_context_bytes" => 65536,
            "check_plan" => {"environment_id" => env["environment_id"], "checks" => role == "worker" ? [check] : []},
            "execution_read_roots" => env["read_roots"], "execution_environment_allowlist" => env["environment_allowlist"]}
          spec["work_order_id"] = "implement" if role == "worker"
          spec["resume_job_id"] = parent if parent
          request.call("dispatch-#{id}", "host-dispatch", spec)
        }
        requests = []
        if %w[host-failure-test host-failure-input-test].include?(control["task"]) && round == 1
          warn "fixture host interruption"
          exit 2
        end
        if control["task"] == "authority-test"
          requests << apply.call("forged-acceptance", "milestone.review", {"review_id" => "absent", "decision" => "accepted"}, "operator") if round == 1
        elsif %w[stale-test interleaved-test technical-stale-test].include?(control["task"])
          requests << request.call("read-before-change", "status", {}) if control["task"] == "interleaved-test" && round == 1
          requests << apply.call("obsolete-order", "work_order.create", {"work_order_id" => "implement", "intent_id" => "milestone_initial", "objective" => "Old objective", "requirement_ids" => ["behavior"], "paths" => ["app.txt"], "check_ids" => ["behavior-check"], "effect_class" => "local_repository"}) if round == 1
          if control["task"] == "technical-stale-test" && round == 2
            observations = control.dig("technical_observations", "records")
            abort "technical interruption missing" unless observations.length == 1 && observations.first.dig("input", "interruption", "reason_code") == "context_exhausted"
          end
        elsif control["task"] == "technical-wake-test"
          observations = control.dig("technical_observations", "records")
          if round <= 2
            abort "unexpected early technical input" unless observations.empty?
          elsif round == 3
            abort "technical fact missing" unless observations.length == 1 && observations.first.dig("input", "facts", 0, "name") == "dependency"
            abort "technical authority forged" unless control.dig("technical_observations", "authority").include?("not authenticated human identity")
          else
            abort "technical fact was delivered more than once" unless observations.empty?
          end
        elsif %w[host-failure-test host-failure-input-test].include?(control["task"])
          observations = control.dig("technical_observations", "records")
          if round == 2
            abort "failed-host technical evidence missing" unless observations.length == 1
          else
            abort "failed-host technical evidence was delivered more than once" unless observations.empty?
          end
        elsif control["task"] == "technical-launch-retry-test"
          observations = control.dig("technical_observations", "records")
          if round == 1
            abort "launch-retry technical evidence missing" unless observations.length == 1 && observations.first.dig("input", "input_id") == "prelaunch-fact"
          else
            abort "launch-retry technical evidence was delivered more than once" unless observations.empty?
          end
        elsif control["task"] == "environment-transition-test"
          case round
          when 1
            requests << apply.call("create-order", "work_order.create", {"work_order_id" => "implement", "intent_id" => "milestone_initial", "objective" => "Implement behavior", "requirement_ids" => ["behavior"], "paths" => ["app.txt"], "check_ids" => ["behavior-check"], "effect_class" => "local_repository"})
            requests << dispatch.call("partial-worker", "worker")
          when 2
            transition = control.fetch("environment_transition")
            abort "transition authority was mislabeled" unless transition.fetch("authority").include?("not operator intent")
            abort "old checks were not historical" unless transition.fetch("required_handling").include?("historical diagnostics only")
            request = dispatch.call("replacement-worker", "worker")
            input = JSON.parse(request.fetch("input_json"))
            input["historical_resume_job_id"] = "partial-worker"
            request["input_json"] = JSON.generate(input)
            requests << request
          end
        elsif control["task"] == "conflict-test"
          requests << apply.call("same-id", "work_order.create", {"work_order_id" => "implement", "intent_id" => "milestone_initial", "objective" => "objective #{round}", "requirement_ids" => ["behavior"], "paths" => ["app.txt"], "check_ids" => ["behavior-check"], "effect_class" => "local_repository"}) if round <= 2
        else
          case round
          when 1
            requests << apply.call("create-order", "work_order.create", {"work_order_id" => "implement", "intent_id" => "milestone_initial", "objective" => "Implement behavior", "requirement_ids" => ["behavior"], "paths" => ["app.txt"], "check_ids" => ["behavior-check"], "effect_class" => "local_repository"})
            requests << dispatch.call("partial-worker", "worker")
          when 2
            encoded = JSON.generate(control["feedback"])
            abort "diagnostics missing" unless encoded.include?("diagnostic_evidence") && encoded.include?("unfinished behavior") && encoded.include?("continue_engineering")
            requests << dispatch.call("complete-worker", "worker", "partial-worker")
          when 3
            requests << request.call("submit-worker", "submit", {"job_id" => "complete-worker"})
            requests << dispatch.call("independent-reviewer", "reviewer")
          when 4
            requests << request.call("assess-reviewer", "assess", {"job_id" => "independent-reviewer"})
            requests << apply.call("offer-review", "milestone.review_ready", {"review_id" => "human-review"})
          end
        end
        sleep 0.5 if control["task"] == "technical-stale-test" && round == 1
        result = {"status" => requests.empty? ? "blocked" : "continue", "summary" => "Fixture coordinator", "requests" => requests}
      else
        partial = packet["task"] == "partial-worker"
        File.write("app.txt", partial ? "partial\n" : "implemented\n") unless reviewer
        result = {"status" => reviewer ? "reviewed" : partial ? "blocked" : "implemented", "summary" => partial ? "Missing glue is engineering work" : "Fixture finished",
          "changed_paths" => reviewer ? [] : ["app.txt"], "findings" => [], "context_requests" => [],
          "scenario_dispositions" => reviewer ? [{"scenario_id" => "scenario", "status" => "passed", "evidence" => "Inspected actual native checks and source"}] : []}
      end
      File.write(ARGV[ARGV.index("-o") + 1], JSON.generate(result))
      puts JSON.generate("type" => "turn.completed", "usage" => {"input_tokens" => 10, "cached_input_tokens" => 0, "output_tokens" => 20})
    CODEX
    File.chmod(0o700, @fake)
    @driver = HrmKernel::Driver.new(state_dir: @state_dir, codex_path: @fake)
  end

  def teardown
    if File.directory?(File.join(@state_dir, "host-jobs"))
      host = HrmKernel::Host.new(state_dir: @state_dir, codex_path: @fake)
      Dir.glob(File.join(@state_dir, "host-jobs", "*", "job.json")).each do |file|
        id = File.basename(File.dirname(file))
        200.times do
          break unless host.poll(job_id: id)["status"] == "running"
          sleep 0.01
        end
      end
    end
    FileUtils.remove_entry(@temporary)
  end

  def test_driver_runs_partial_diagnostics_same_worker_continuation_and_independent_human_review
    assert_equal "active", @driver.start(configuration)["outcome"]
    final = finish
    assert_equal "review_ready", final["outcome"], final.inspect
    assert_equal 4, final["round"]
    state = @store.read["state"]
    assert_equal "completed", state.dig("work_orders", "implement", "status")
    assert_equal "pending", state.dig("reviews", "human-review", "status")
    assert_nil state.dig("reviews", "human-review", "decision")
    assert_empty state["decisions"]
    requests = Dir.glob(File.join(@state_dir, "driver", "requests", "*", "receipt.json")).map { |p| JSON.parse(File.read(p)) }
    diagnostic = requests.find { |r| r["request_id"] == "auto-partial-worker-behavior-check" }
    assert_equal "failed", diagnostic.dig("result", "conclusion")
    assert_equal "diagnostic_evidence", diagnostic.dig("result", "classification")
    worker = JSON.parse(File.read(File.join(@state_dir, "host-jobs", "complete-worker", "job.json")))
    assert_equal "31234567-89ab-cdef-0123-456789abcdef", worker["resume_thread_id"]
    orch = JSON.parse(File.read(File.join(@state_dir, "host-jobs", "test-astra-4", "job.json")))
    assert_equal "11234567-89ab-cdef-0123-456789abcdef", orch["resume_thread_id"]
    assert_equal "gpt-6-astra", orch["model_requested"]

    @driver.technical_input(technical_observation("review-fact"))
    gated = @driver.step
    assert_equal "review_ready", gated["outcome"]
    assert_equal 4, gated["round"]
    assert_equal 1, gated.dig("technical_input", "unread_count")
    assert_nil state.dig("reviews", "human-review", "decision")
  end

  def test_failed_environment_blocks_before_any_claim_or_host_launch
    config = configuration
    config["preflight_checks"][0]["argv"] = [File.realpath(RbConfig.ruby), "-e", 'abort "launcher unavailable"']
    assert_equal "preflight_failed", @driver.start(config)["outcome"]
    assert_equal "preflight_failed", @driver.start(config)["outcome"]
    assert_equal "preflight_failed", @driver.step["outcome"]
    assert_empty @store.read.dig("state", "work_orders")
    assert_empty Dir.glob(File.join(@state_dir, "host-jobs", "*", "job.json"))
  end

  def test_technical_input_does_not_lift_preflight_failure_or_turn_budget
    failed = configuration.merge("prompt" => "technical-wake-test")
    failed["preflight_checks"][0]["argv"] = [File.realpath(RbConfig.ruby), "-e", 'abort "launcher unavailable"']
    @driver.start(failed)
    @driver.technical_input(technical_observation("preflight-fact"))
    blocked = @driver.step
    assert_equal "preflight_failed", blocked["outcome"]
    assert_equal 0, blocked["round"]
    assert_equal 1, blocked.dig("technical_input", "unread_count")

    second_state = File.join(@temporary, "turn-state")
    second_store = HrmKernel::Store.new(second_state)
    second_store.transact(
      "command_id" => "initial", "type" => "milestone.create", "actor" => {"id" => "human", "role" => "operator"}, "data" => {
        "milestone_id" => "turn-test", "outcome" => "Implement then review behavior", "project_root" => @project,
        "mode" => "implementation", "requirements" => [{"id" => "behavior", "text" => "Application contains implemented behavior"}],
        "allowed_paths" => ["app.txt"], "acceptance_scenarios" => [{"id" => "scenario", "text" => "Working behavior", "requirement_ids" => ["behavior"], "check_ids" => ["behavior-check"]}]
      }
    )
    limited = HrmKernel::Driver.new(state_dir: second_state, codex_path: @fake)
    limited.start(configuration.merge("prompt" => "technical-wake-test", "max_turns" => 1))
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 10
    loop do
      result = limited.step
      break if result["outcome"] == "turn_limit"
      raise "turn-limit fixture timeout" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      sleep 0.01
    end
    limited.technical_input(technical_observation("budget-fact"))
    still_limited = limited.step
    assert_equal "turn_limit", still_limited["outcome"]
    assert_equal 1, still_limited["round"]
    assert_equal 1, still_limited.dig("technical_input", "unread_count")
  end

  def test_operator_impersonation_is_rejected_without_acceptance_or_approval_question
    @driver.start(configuration.merge("prompt" => "authority-test"))
    final = finish
    assert_equal "engineering_stalled", final["outcome"]
    assert_equal 1, @store.read["cursor"]
    receipt = JSON.parse(File.read(File.join(@state_dir, "driver", "requests", "forged-acceptance", "receipt.json")))
    refute receipt["ok"]
    assert_match(/only transports orchestrator/, receipt["error"])
  end

  def test_conflicting_request_id_produces_feedback_instead_of_wedging_restart
    @driver.start(configuration.merge("prompt" => "conflict-test"))
    final = finish
    assert_equal "engineering_stalled", final["outcome"]
    assert_equal 2, @store.read["cursor"]
    assert_equal "objective 1", @store.read.dig("state", "work_orders", "implement", "objective")
  end

  def test_start_is_idempotent_and_recovers_partial_initialization
    first = @driver.start(configuration)
    assert_equal first, @driver.start(configuration)
    File.unlink(File.join(@state_dir, "driver", "runtime.json"))
    assert_equal "active", @driver.start(configuration)["outcome"]
    assert_equal 1, @store.read["cursor"]
  end

  def test_operator_input_discards_the_in_flight_orchestrator_requests
    @driver.start(configuration.merge("prompt" => "stale-test"))
    @driver.step
    @store.transact("command_id" => "new-input", "type" => "intent.record",
      "actor" => {"id" => "human", "role" => "operator"}, "data" => {
        "intent_id" => "clarification", "kind" => "clarification", "text" => "Keep the clarified behavior",
        "source" => {"thread_id" => "human-task", "message_id" => "new-input"}, "requirement_ids" => ["behavior"]})
    assert_equal "engineering_stalled", finish["outcome"]
    assert_empty @store.read.dig("state", "work_orders")
    packet = JSON.parse(File.read(File.join(@state_dir, "host-jobs", "test-astra-2", "prompt.json")))
    assert_includes packet["task"], "stale_orchestrator_response"
  end

  def test_technical_input_wakes_engineering_idle_and_is_delivered_once_after_restart
    @driver.start(configuration.merge("prompt" => "technical-wake-test"))
    assert_equal "engineering_stalled", finish["outcome"]
    ledger_before = @store.read.slice("cursor", "event_hash")
    receipt = @driver.technical_input(technical_observation("dependency-fact"))
    assert_equal "non_authorizing_technical_evidence", receipt.dig("provenance", "authority")
    assert_equal ledger_before, @store.read.slice("cursor", "event_hash")

    @driver = HrmKernel::Driver.new(state_dir: @state_dir, codex_path: @fake)
    assert_equal "engineering_stalled", finish["outcome"]
    assert_equal 4, @driver.status["round"]
    assert_equal 0, @driver.status.dig("technical_input", "unread_count")
    round_three = JSON.parse(File.read(File.join(@state_dir, "host-jobs", "test-astra-3", "prompt.json")))
    round_four = JSON.parse(File.read(File.join(@state_dir, "host-jobs", "test-astra-4", "prompt.json")))
    round_three_control = JSON.parse(round_three.fetch("task"))
    round_four_control = JSON.parse(round_four.fetch("task"))
    assert_equal ["dependency-fact"], round_three_control.dig("technical_observations", "records").map { |event| event.dig("input", "input_id") }
    assert_empty round_four_control.dig("technical_observations", "records")
  end

  def test_technical_input_discards_in_flight_requests_and_preserves_operator_ledger
    @driver.start(configuration.merge("prompt" => "technical-stale-test"))
    dispatched = @driver.step
    job_id = dispatched.fetch("orchestrator_job")
    assert_equal "running", @driver.instance_variable_get(:@host).poll(job_id: job_id)["status"]
    @driver.technical_input(technical_interruption("context-stop", job_id))
    assert_equal "engineering_stalled", finish["outcome"]
    assert_empty @store.read.dig("state", "work_orders")
    assert_equal 1, @store.read["cursor"]
    refute File.exist?(File.join(@state_dir, "driver", "requests", "obsolete-order", "request.json"))
    packet = JSON.parse(File.read(File.join(@state_dir, "host-jobs", "test-astra-2", "prompt.json")))
    assert_includes packet["task"], "technical_input_changed"
    control = JSON.parse(packet.fetch("task"))
    assert_equal "context-stop", control.dig("technical_observations", "records", 0, "input", "input_id")
  end

  def test_driver_input_cli_is_idempotent_and_lock_contention_requests_retry
    @driver.start(configuration.merge("prompt" => "technical-wake-test"))
    out = StringIO.new
    err = StringIO.new
    argv = ["driver-input", "--state-dir", @state_dir, "--input", "-"]
    assert_equal 0, HrmKernel::CLI.run(argv, stdin: StringIO.new(JSON.generate(technical_observation("cli-fact"))), stdout: out, stderr: err)
    assert JSON.parse(out.string)["replayed"] == false
    replay = @driver.technical_input(technical_observation("cli-fact"))
    assert replay["replayed"]

    lock_path = File.join(@state_dir, "driver", ".lock")
    File.open(lock_path, File::RDWR) do |lock|
      assert lock.flock(File::LOCK_EX | File::LOCK_NB)
      error = assert_raises(HrmKernel::Error) { @driver.technical_input(technical_observation("busy-fact")) }
      assert_match(/retry technical input/, error.message)
    end
  end

  def test_technical_input_does_not_clear_an_unresolved_human_decision
    @driver.start(configuration.merge("prompt" => "technical-wake-test"))
    @store.transact(
      "command_id" => "business-question", "type" => "decision.request",
      "actor" => {"id" => "astra-orchestrator", "role" => "orchestrator"},
      "data" => {
        "decision_id" => "copy-choice", "revision" => 1, "kind" => "business_meaning",
        "exact_effect" => "select customer-visible wording", "requirement_ids" => ["behavior"],
        "question" => "Which customer-visible wording is required?",
        "authority_gap" => {"reason" => "The milestone does not select between two meanings.", "source_ref" => "requirements:behavior"}
      }
    )
    gated = @driver.step
    assert_equal "operator_input", gated["outcome"]
    round = gated["round"]
    cursor = @store.read["cursor"]
    @driver.technical_input(technical_observation("decision-fact"))
    still_gated = @driver.step
    assert_equal "operator_input", still_gated["outcome"]
    assert_equal round, still_gated["round"]
    assert_equal cursor, @store.read["cursor"]
    assert_equal "unresolved", @store.read.dig("state", "decisions", "copy-choice", "status")
    assert_equal 1, still_gated.dig("technical_input", "unread_count")
  end

  def test_failed_host_can_wake_on_job_bound_technical_evidence_without_prose_classification
    @driver.start(configuration.merge("prompt" => "host-failure-test"))
    assert_equal "host_failure", finish["outcome"]
    status = @driver.status
    assert_equal "test-astra-1", status["last_orchestrator_job"]
    @driver.technical_input(technical_interruption("failed-host-context", "test-astra-1"))
    resumed = @driver.step
    assert_equal "active", resumed["outcome"]
    assert_equal "test-astra-2", resumed["orchestrator_job"]
    assert_equal 2, resumed["round"]
    assert_equal "engineering_stalled", finish["outcome"]
  end

  def test_technical_input_remains_unread_when_dispatch_raises_before_launch
    @driver.start(configuration.merge("prompt" => "technical-launch-retry-test"))
    @driver.technical_input(technical_observation("prelaunch-fact"))
    host = @driver.instance_variable_get(:@host)
    host.define_singleton_method(:dispatch) { |_spec| raise "injected dispatch failure" }
    assert_raises(RuntimeError) { @driver.step }
    failed = @driver.status
    assert_equal 0, failed.dig("technical_input", "observed_cursor")
    assert_equal 1, failed.dig("technical_input", "unread_count")
    assert_equal 1, failed.dig("technical_input", "in_flight_cursor")

    @driver = HrmKernel::Driver.new(state_dir: @state_dir, codex_path: @fake)
    assert_equal "engineering_stalled", finish["outcome"]
    assert_equal 1, @driver.status.dig("technical_input", "observed_cursor")
    prompt = JSON.parse(File.read(File.join(@state_dir, "host-jobs", "test-astra-1", "prompt.json")))
    control = JSON.parse(prompt.fetch("task"))
    assert_equal "prelaunch-fact", control.dig("technical_observations", "records", 0, "input", "input_id")
  end

  def test_technical_input_is_redelivered_after_failed_astra_completion
    @driver.start(configuration.merge("prompt" => "host-failure-input-test"))
    @driver.technical_input(technical_observation("failed-completion-fact"))
    assert_equal "host_failure", finish["outcome"]
    failed = @driver.status
    assert_equal 0, failed.dig("technical_input", "observed_cursor")
    assert_equal 1, failed.dig("technical_input", "unread_count")
    assert_nil failed.dig("technical_input", "in_flight_cursor")

    resumed = @driver.step
    assert_equal "test-astra-2", resumed["orchestrator_job"]
    assert_equal 1, resumed.dig("technical_input", "unread_count")
    assert_equal "engineering_stalled", finish["outcome"]
    assert_equal 1, @driver.status.dig("technical_input", "observed_cursor")
    prompt = JSON.parse(File.read(File.join(@state_dir, "host-jobs", "test-astra-2", "prompt.json")))
    control = JSON.parse(prompt.fetch("task"))
    assert_equal "failed-completion-fact", control.dig("technical_observations", "records", 0, "input", "input_id")
  end

  def test_operator_input_between_requests_discards_the_remaining_batch
    @driver.start(configuration.merge("prompt" => "interleaved-test"))
    original = @driver.method(:perform)
    store = @store
    @driver.define_singleton_method(:perform) do |request, config, runtime|
      response = original.call(request, config, runtime)
      if request["request_id"] == "read-before-change"
        store.transact("command_id" => "interleaved-input", "type" => "intent.record",
          "actor" => {"id" => "human", "role" => "operator"}, "data" => {
            "intent_id" => "clarification", "kind" => "clarification", "text" => "New operator direction",
            "source" => {"thread_id" => "human-task", "message_id" => "interleaved-input"}, "requirement_ids" => ["behavior"]})
      end
      response
    end
    assert_equal "engineering_stalled", finish["outcome"]
    assert_empty @store.read.dig("state", "work_orders")
    refute File.exist?(File.join(@state_dir, "driver", "requests", "obsolete-order", "request.json"))
  end

  def test_restart_dispatches_the_durable_pending_identity_once
    @driver.start(configuration)
    host = @driver.instance_variable_get(:@host)
    host.define_singleton_method(:dispatch) { |_spec| raise "injected crash before dispatch" }
    assert_raises(RuntimeError) { @driver.step }
    @driver = HrmKernel::Driver.new(state_dir: @state_dir, codex_path: @fake)
    final = finish
    assert_equal "review_ready", final["outcome"], final.inspect
    assert_equal 4, final["round"]
    assert_equal 7, Dir.glob(File.join(@state_dir, "host-jobs", "*", "job.json")).length
  end

  def test_restart_reverifies_preflight_before_pending_dispatch
    @driver.start(configuration)
    host = @driver.instance_variable_get(:@host)
    host.define_singleton_method(:dispatch) { |_spec| raise "injected crash before dispatch" }
    assert_raises(RuntimeError) { @driver.step }
    path = File.join(@state_dir, "driver", "preflight.json")
    receipts = JSON.parse(File.read(path))
    receipts[0]["execution"]["receipt_sha256"] = "0" * 64
    File.write(path, JSON.generate(receipts))
    @driver = HrmKernel::Driver.new(state_dir: @state_dir, codex_path: @fake)
    assert_raises(HrmKernel::Error) { @driver.step }
    assert_empty Dir.glob(File.join(@state_dir, "host-jobs", "*", "job.json"))
  end

  def test_restart_recovers_worker_launched_before_driver_registration
    @driver.start(configuration)
    host = @driver.instance_variable_get(:@host)
    original = host.method(:dispatch)
    host.define_singleton_method(:dispatch) do |spec|
      status = original.call(spec)
      raise "injected crash after worker launch" if spec["role"] == "worker"
      status
    end
    error = assert_raises(RuntimeError) { finish }
    assert_includes error.message, "after worker launch"
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 10
    while host.poll(job_id: "partial-worker")["status"] == "running"
      raise "worker did not finish after controller crash" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      sleep 0.01
    end
    @driver = HrmKernel::Driver.new(state_dir: @state_dir, codex_path: @fake)
    final = finish
    assert_equal "review_ready", final["outcome"], final.inspect
    assert_equal 1, final["jobs"].count("partial-worker")
    assert_equal "completed", @store.read.dig("state", "work_orders", "implement", "status")
  end

  def test_environment_transition_resumes_same_claim_with_fresh_job_and_blocks_old_evidence
    @driver.start(configuration.merge("prompt" => "environment-transition-test"))
    @driver.step
    wait_for_job("test-astra-1")
    @driver.step
    old_status = wait_for_job("partial-worker")
    assert_equal "blocked", old_status["result_status"]
    install_environment_transition(old_status)

    @driver = HrmKernel::Driver.new(state_dir: @state_dir, codex_path: @fake)
    @driver.step
    wait_for_job("test-astra-2")
    result = @driver.step
    dispatch_receipt = JSON.parse(File.read(File.join(@state_dir, "driver", "requests", "dispatch-replacement-worker", "receipt.json")))
    assert dispatch_receipt["ok"], dispatch_receipt.inspect
    assert_includes result["jobs"], "replacement-worker", result.inspect
    replacement = JSON.parse(File.read(File.join(@state_dir, "host-jobs", "replacement-worker", "job.json")))
    assert_equal "31234567-89ab-cdef-0123-456789abcdef", replacement["resume_thread_id"]
    assert_equal "replacement-native-test", replacement.dig("check_plan", "environment_id")
    assert_equal [], JSON.parse(File.read(File.join(@state_dir, "driver", "runtime.json"))).fetch("jobs") & ["partial-worker"]

    coordinator = HrmKernel::Coordinator.new(state_dir: @state_dir, host: @driver.instance_variable_get(:@host))
    errors = [
      assert_raises(HrmKernel::Error) { coordinator.check("job_id" => "partial-worker", "check_id" => "behavior-check") },
      assert_raises(HrmKernel::Error) { coordinator.submit("job_id" => "partial-worker") },
      assert_raises(HrmKernel::Error) { coordinator.assess("job_id" => "partial-worker") }
    ]
    errors.each { |error| assert_match(/historical diagnostic evidence only/, error.message) }
  end

  def test_environment_transition_metadata_fails_closed
    @driver.start(configuration)
    config = JSON.parse(File.read(File.join(@state_dir, "driver", "config.json")))
    runtime = JSON.parse(File.read(File.join(@state_dir, "driver", "runtime.json")))
    config["continuation"] = {"environment_transition" => {"active_environment_id" => config["environment_id"]}}
    HrmKernel::Host.atomic_json(File.join(@state_dir, "driver", "config.json"), config)
    HrmKernel::Host.atomic_json(File.join(@state_dir, "driver", "runtime.json"), runtime)
    error = assert_raises(HrmKernel::Error) { @driver.step }
    assert_match(/metadata is incomplete/, error.message)
  end

  private

  def configuration
    { "run_id" => "test", "prompt" => "pipeline-test", "environment_id" => "native-test", "read_roots" => [],
      "environment_allowlist" => [], "forbidden_roots" => [], "max_turns" => 8, "max_parallel_workers" => 2,
      "preflight_checks" => [{"id" => "ruby-startup", "environment_id" => "native-test", "argv" => [File.realpath(RbConfig.ruby), "-e", 'puts "runtime ready"'],
        "env" => {}, "cwd" => @project, "timeout_seconds" => 10, "max_output_bytes" => 16384, "configuration_paths" => []}] }
  end

  def technical_observation(id)
    {
      "input_id" => id, "kind" => "technical_observation",
      "source" => {"adapter_id" => "test-supervisor", "reference" => "test:#{id}"},
      "summary" => "A declared project dependency is available.",
      "facts" => [{"name" => "dependency", "value" => "Use the project-readable source selected by argv."}],
      "usage" => {"input_tokens" => 100, "output_tokens" => 20}
    }
  end

  def technical_interruption(id, job_id)
    {
      "input_id" => id, "kind" => "execution_interruption",
      "source" => {"adapter_id" => "test-supervisor", "reference" => "test:#{id}"},
      "summary" => "The native turn failed before returning a usable result.", "facts" => [],
      "observed_job" => {"job_id" => job_id, "status" => "failed"},
      "interruption" => {"failed" => true, "reason_code" => "context_exhausted", "detail" => "Adapter-observed context exhaustion."},
      "usage" => {"input_tokens" => 200, "output_tokens" => 10}
    }
  end

  def finish
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 35
    loop do
      result = @driver.step
      return result if HrmKernel::Driver::TERMINAL.include?(result["outcome"])
      raise "driver timeout: #{result.inspect}" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      sleep 0.01
    end
  end

  def wait_for_job(id)
    host = @driver.instance_variable_get(:@host)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 10
    loop do
      status = host.poll(job_id: id)
      return status if %w[succeeded failed].include?(status["status"])
      raise "job timeout: #{id}" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      sleep 0.01
    end
  end

  def install_environment_transition(old_status)
    config_path = File.join(@state_dir, "driver", "config.json")
    runtime_path = File.join(@state_dir, "driver", "runtime.json")
    preflight_path = File.join(@state_dir, "driver", "preflight.json")
    config = JSON.parse(File.read(config_path))
    runtime = JSON.parse(File.read(runtime_path))
    order = @store.read.dig("state", "work_orders", "implement")
    source_id = config.fetch("environment_id")
    active_id = "replacement-native-test"
    config["environment_id"] = active_id
    config["preflight_checks"].each { |check| check["environment_id"] = active_id }
    configured = {
      "source_environment_id" => source_id, "active_environment_id" => active_id,
      "source_environment_sha256" => "1" * 64,
      "active_environment_sha256" => HrmKernel::Host.digest(config.slice("environment_id", "read_roots", "environment_allowlist", "preflight_checks")),
      "historical_job_ids" => ["partial-worker"], "old_checks_eligible_for_new_claims" => false,
      "fresh_preflight_required" => true
    }
    config["continuation"] = {"environment_transition" => configured}
    historical_job = old_status.slice("job_id", "role", "work_order_id", "revision", "claim_id", "status", "result_status", "thread_id")
    runtime["historical_environment"] = configured.slice(
      "source_environment_id", "active_environment_id", "source_environment_sha256", "active_environment_sha256",
      "old_checks_eligible_for_new_claims"
    ).merge(
      "jobs" => [historical_job],
      "work_orders" => [{"work_order_id" => "implement", "status" => order["status"], "revision" => order["revision"],
        "claim_id" => order["claim_id"], "last_owner_id" => order["last_owner_id"], "required_action" => "resume_or_release",
        "historical_resume_job_ids" => ["partial-worker"]}]
    )
    runtime["jobs"] = []
    runtime["seen_jobs"] = []
    runtime["history"] = []
    runtime["orchestrator_job"] = nil
    runtime["resume_job"] = "test-astra-1"
    runtime["feedback"] = [{"kind" => "versioned_environment_transition"}]
    execution = HrmKernel::Execution.new(project_root: @project, state_dir: @state_dir,
      read_roots: config.fetch("read_roots"), environment_allowlist: config.fetch("environment_allowlist"),
      forbidden_read_path: File.join(@state_dir, "driver", "isolation-sentinel.txt"),
      forbidden_write_path: File.join(@state_dir, "driver", "isolation-sentinel.txt"))
    receipts = config.fetch("preflight_checks").map do |spec|
      {"id" => spec.fetch("id"), "execution" => execution.preflight(spec: spec)}
    end
    HrmKernel::Host.atomic_json(config_path, config)
    HrmKernel::Host.atomic_json(runtime_path, runtime)
    HrmKernel::Host.atomic_json(preflight_path, receipts)
  end

  def git(*argv)
    output, status = Open3.capture2e("git", "-C", @project, *argv)
    raise output unless status.success?
  end
end
