# frozen_string_literal: true

require "fileutils"
require "json"
require "minitest/autorun"
require "open3"
require "rbconfig"
require "tmpdir"
require_relative "../lib/hrm_kernel/coordinator"

# These are process integration tests. The model executable is a deterministic
# substitute, but claims, persistence, native sandbox checks, authenticated
# receipts, independent reviewer dispatch and state transitions are real.
class HrmKernelCoordinatorTest < Minitest::Test
  def setup
    @temporary = File.realpath(Dir.mktmpdir("hrm-coordinator"))
    @project = File.join(@temporary, "project")
    Dir.mkdir(@project, 0o700)
    @state_dir = File.join(@temporary, "state")
    File.write(File.join(@project, ".gitignore"), "/.codex/hrm-runs/\n")
    File.write(File.join(@project, "app.txt"), "before\n")
    File.write(File.join(@project, "check.rb"), <<~'RUBY')
      require "json"
      abort "worker did not implement the behavior" unless File.read("app.txt") == "implemented\n"
      File.write(File.join(ENV.fetch("RUN_ROOT"), "test.sqlite3"), "temporary test data")
      puts JSON.generate("conclusion" => "passed")
      exit 7 if ENV["FAIL_CHECK"] == "yes"
    RUBY
    git("init", "--quiet")
    git("config", "user.email", "kernel-test@example.invalid")
    git("config", "user.name", "Kernel Test")
    git("add", ".")
    git("commit", "--quiet", "-m", "isolated integration baseline")
    @store = HrmKernel::Store.new(@state_dir)
    @counter = 0
    command("milestone.create", "operator", "human", {
      "milestone_id" => "native-trial", "outcome" => "Implement then independently review the application",
      "project_root" => @project, "mode" => "implementation",
      "requirements" => [{ "id" => "behavior", "text" => "Application contains implemented behavior" }],
      "allowed_paths" => ["app.txt"],
      "acceptance_scenarios" => [{ "id" => "scenario", "text" => "Operator can use implemented behavior", "requirement_ids" => ["behavior"], "check_ids" => ["behavior-check"] }]
    })
    command("work_order.create", "orchestrator", "astra", {
      "work_order_id" => "implement", "intent_id" => "milestone_initial", "objective" => "Implement app.txt behavior",
      "requirement_ids" => ["behavior"], "paths" => ["app.txt"], "check_ids" => ["behavior-check"], "effect_class" => "local_repository"
    })
    @fake = File.join(@temporary, "fake-codex")
    File.write(@fake, <<~'RUBY'.sub("RUBY_EXECUTABLE", RbConfig.ruby))
      #!RUBY_EXECUTABLE
      require "json"
      packet = JSON.parse(STDIN.read)
      JSON.parse(File.read(ARGV[ARGV.index("--output-schema") + 1]))
      reviewer = packet["actor_id"].start_with?("reviewer-")
      thread = reviewer ? "11234567-89ab-cdef-0123-456789abcdef" : "01234567-89ab-cdef-0123-456789abcdef"
      puts JSON.generate("type" => "thread.started", "thread_id" => thread)
      File.write("app.txt", "implemented\n") unless reviewer
      pending = packet.fetch("task") == "request-changes"
      result = {
        "status" => reviewer ? "reviewed" : "implemented", "summary" => "Process fixture completed",
        "changed_paths" => reviewer ? [] : ["app.txt"],
        "findings" => pending ? [{"severity" => "error", "message" => "Required behavior remains incomplete", "paths" => ["app.txt"], "scenario_ids" => ["scenario"]}] : [],
        "scenario_dispositions" => reviewer ? [{"scenario_id" => "scenario", "status" => pending ? "failed" : "passed", "evidence" => pending ? "A required part remains missing" : "Inspected implemented behavior and native check evidence"}] : [],
        "context_requests" => []
      }
      File.write(ARGV[ARGV.index("-o") + 1], JSON.generate(result))
      puts JSON.generate("type" => "turn.completed", "usage" => {"input_tokens" => 10, "cached_input_tokens" => 0, "output_tokens" => 20})
    RUBY
    File.chmod(0o700, @fake)
    @host = HrmKernel::Host.new(state_dir: @state_dir, codex_path: @fake)
    @coordinator = HrmKernel::Coordinator.new(state_dir: @state_dir, host: @host)
    @jobs = []
  end

  def teardown
    @jobs.each { |id| wait_job(id) rescue nil }
    FileUtils.remove_entry(@temporary) if File.exist?(@temporary)
  end

  def test_implementation_native_check_submit_independent_assessment_and_review_ready
    implement
    assert_equal "implemented\n", File.read(File.join(@project, "app.txt"))
    first_check = @coordinator.check("job_id" => "worker-job", "check_id" => "behavior-check")
    assert_equal "passed", first_check["conclusion"]
    repeated = @coordinator.check("job_id" => "worker-job", "check_id" => "behavior-check")
    assert repeated["reused"]
    assert_equal first_check["execution"], repeated["execution"]
    submitted = @coordinator.submit("job_id" => "worker-job")
    assert_equal "completed", submitted.dig("projection", "work_orders", "implement", "status")
    cursor = submitted["cursor"]
    retried = @coordinator.submit("job_id" => "worker-job")
    assert retried["replayed"]
    assert_equal cursor, retried["cursor"]
    refute_equal "review_ready", @store.read.dig("state", "milestone", "phase")

    reviewed = review
    refute_equal @host.poll(job_id: "worker-job")["thread_id"], reviewed["thread_id"]
    assessed = @coordinator.assess("job_id" => "reviewer-job")
    assert_equal "accepted", assessed.dig("projection", "assessments", "reviewer-job", "status")
    ready = ready_for_review
    assert_equal "review_ready", ready.dig("projection", "milestone", "phase")
    assert_equal "pending", @store.read.dig("state", "reviews", "human-review", "status")
    assert_nil @store.read.dig("state", "reviews", "human-review", "decision")
    assert_equal "reviewer-reviewer-job", @store.read.dig("state", "assessments", "reviewer-job", "assessor_id")
  end

  def test_added_file_invalidates_dispatched_review_and_assessment
    implement_and_submit
    review
    File.write(File.join(@project, "unreviewed.txt"), "New code after the frozen check\n")
    assert_raises(HrmKernel::Error) { @host.collect(job_id: "reviewer-job") }
    assert_raises(HrmKernel::Error) { @coordinator.assess("job_id" => "reviewer-job") }
    assert_raises(HrmKernel::Error) { ready_for_review }
    assert_empty @store.read.fetch("state").fetch("assessments")
  end

  def test_failed_native_check_cannot_be_overruled_by_printed_pass_or_forged_receipt
    implement(fail_check: true)
    checked = @coordinator.check("job_id" => "worker-job", "check_id" => "behavior-check")
    assert_equal "failed", checked["conclusion"]
    assert_raises(HrmKernel::Error) { @coordinator.submit("job_id" => "worker-job") }
    refute File.exist?(File.join(@state_dir, "coordinator", "submit-worker-job.json"))
    fake_receipt = File.join(@state_dir, "execution", "forged.json")
    HrmKernel::Host.atomic_json(fake_receipt, "conclusion" => "passed", "exit_status" => 0)
    record_path = File.join(@state_dir, "coordinator", "check-worker-job-behavior-check.json")
    record = JSON.parse(File.read(record_path))
    record["execution"] = { "receipt_path" => "execution/forged.json", "receipt_sha256" => Digest::SHA256.file(fake_receipt).hexdigest }
    record["conclusion"] = "passed"
    HrmKernel::Host.atomic_json(record_path, record)
    assert_raises(HrmKernel::Error) { @coordinator.submit("job_id" => "worker-job") }
    assert_equal "running", @store.read.dig("state", "work_orders", "implement", "status")
  end

  def test_stale_claim_cannot_submit_previously_passing_execution
    implement
    @coordinator.check("job_id" => "worker-job", "check_id" => "behavior-check")
    command("work_order.release", "orchestrator", "astra", {
      "work_order_id" => "implement", "revision" => 1, "claim_id" => "claim-worker-job", "reason" => "Superseded assignment"
    })
    assert_raises(HrmKernel::Error) { @coordinator.submit("job_id" => "worker-job") }
    assert_equal "queued", @store.read.dig("state", "work_orders", "implement", "status")
  end

  def test_reviewer_failed_scenario_becomes_durable_finding_and_blocks_readiness
    implement_and_submit
    review(prompt: "request-changes")
    @coordinator.assess("job_id" => "reviewer-job")
    state = @store.read.fetch("state")
    assert_equal "changes_requested", state.dig("assessments", "reviewer-job", "status")
    assert_equal "unresolved", state.dig("findings", "reviewer-job-scenario", "status")
    assert_raises(HrmKernel::Error) { ready_for_review }
    @coordinator.assess("job_id" => "reviewer-job")
    assert_equal 2, @store.read.fetch("state").fetch("findings").length
  end

  private

  def command(type, role, actor, data)
    @counter += 1
    @store.transact("command_id" => "command-#{@counter}", "type" => type,
                    "actor" => { "role" => role, "id" => actor }, "data" => data)
  end

  def plan(fail_check: false)
    {
      "environment_id" => "isolated-ruby",
      "checks" => [{
        "id" => "behavior-check", "environment_id" => "isolated-ruby",
        "argv" => [File.realpath(RbConfig.ruby), "check.rb"],
        "env" => { "RUN_ROOT" => "{run_root}", "FAIL_CHECK" => fail_check ? "yes" : "no" },
        "cwd" => @project, "timeout_seconds" => 10, "max_output_bytes" => 1024 * 1024,
        "configuration_paths" => ["{run_root}"]
      }]
    }
  end

  def implement(fail_check: false)
    @jobs << "worker-job"
    @host.dispatch(
      "job_id" => "worker-job", "role" => "worker", "work_order_id" => "implement", "model" => "gpt-5.6-sol",
      "prompt" => "Implement the behavior", "context_paths" => ["app.txt"], "check_plan" => plan(fail_check: fail_check),
      "execution_environment_allowlist" => %w[RUN_ROOT FAIL_CHECK]
    )
    job = wait_job("worker-job")
    assert_equal "succeeded", job["status"], JSON.pretty_generate(job)
    job
  end

  def implement_and_submit
    implement
    checked = @coordinator.check("job_id" => "worker-job", "check_id" => "behavior-check")
    assert_equal "passed", checked["conclusion"]
    @coordinator.submit("job_id" => "worker-job")
  end

  def review(prompt: "Review the exact candidate")
    @jobs << "reviewer-job"
    @host.dispatch(
      "job_id" => "reviewer-job", "role" => "reviewer", "model" => "gpt-5.6-sol", "prompt" => prompt,
      "context_paths" => ["app.txt"], "check_plan" => plan,
      "execution_environment_allowlist" => %w[RUN_ROOT FAIL_CHECK]
    )
    job = wait_job("reviewer-job")
    assert_equal "succeeded", job["status"], JSON.pretty_generate(job)
    job
  end

  def ready_for_review
    command("milestone.review_ready", "orchestrator", "astra", { "review_id" => "human-review" })
  end

  def wait_job(id)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 10
    loop do
      job = @host.poll(job_id: id)
      return job if %w[succeeded failed].include?(job["status"])
      raise "fixture host timed out" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      sleep 0.025
    end
  end

  def git(*args)
    output, status = Open3.capture2e("git", "-C", @project, *args)
    raise output unless status.success?
    output
  end
end
