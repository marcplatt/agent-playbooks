# frozen_string_literal: true

require "fileutils"
require "json"
require "minitest/autorun"
require "open3"
require "rbconfig"
require "tmpdir"
require_relative "../lib/hrm_kernel/driver"

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
        if control["task"] == "authority-test"
          requests << apply.call("forged-acceptance", "milestone.review", {"review_id" => "absent", "decision" => "accepted"}, "operator") if round == 1
        elsif %w[stale-test interleaved-test].include?(control["task"])
          requests << request.call("read-before-change", "status", {}) if control["task"] == "interleaved-test" && round == 1
          requests << apply.call("obsolete-order", "work_order.create", {"work_order_id" => "implement", "intent_id" => "milestone_initial", "objective" => "Old objective", "requirement_ids" => ["behavior"], "paths" => ["app.txt"], "check_ids" => ["behavior-check"], "effect_class" => "local_repository"}) if round == 1
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

  private

  def configuration
    { "run_id" => "test", "prompt" => "pipeline-test", "environment_id" => "native-test", "read_roots" => [],
      "environment_allowlist" => [], "forbidden_roots" => [], "max_turns" => 8, "max_parallel_workers" => 2,
      "preflight_checks" => [{"id" => "ruby-startup", "environment_id" => "native-test", "argv" => [File.realpath(RbConfig.ruby), "-e", 'puts "runtime ready"'],
        "env" => {}, "cwd" => @project, "timeout_seconds" => 10, "max_output_bytes" => 16384, "configuration_paths" => []}] }
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

  def git(*argv)
    output, status = Open3.capture2e("git", "-C", @project, *argv)
    raise output unless status.success?
  end
end
