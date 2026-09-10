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
    File.write(File.join(@project, "sibling.txt"), "before\n")
    File.write(File.join(@project, "check.rb"), <<~'RUBY')
      require "json"
      target = ENV.fetch("TARGET", "app.txt")
      expected = ENV.fetch("EXPECTED", "implemented") + "\n"
      abort "worker did not implement the behavior" unless File.read(target) == expected
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
      "allowed_paths" => ["app.txt", "sibling.txt"],
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
      order_id = packet.dig("role_projection", "work_orders").keys.first
      target = order_id == "sibling" ? "sibling.txt" : "app.txt"
      blocked = packet.fetch("task").start_with?("blocked")
      unless reviewer
        value = blocked ? "partial\n" : packet.fetch("task").include?("correct") ? "corrected\n" : "implemented\n"
        File.write(target, value)
      end
      pending = packet.fetch("task") == "request-changes"
      result = {
        "status" => reviewer ? "reviewed" : blocked ? "blocked" : "implemented", "summary" => "Process fixture completed",
        "changed_paths" => reviewer ? [] : [target],
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
    if File.exist?(@temporary)
      FileUtils.chmod_R(0o700, @temporary)
      FileUtils.remove_entry(@temporary)
    end
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

  def test_blocked_worker_can_run_candidate_bound_diagnostic_but_cannot_submit
    blocked = dispatch_worker("blocked-job", "implement", "blocked after partial work", plan(expected: "partial"))
    assert_equal "blocked", blocked["result_status"]

    checked = @coordinator.check("job_id" => "blocked-job", "check_id" => "behavior-check")
    assert_equal "passed", checked["conclusion"]
    assert_equal "blocked", checked["worker_disposition"]
    assert_equal "diagnostic_evidence", checked["classification"]
    assert_raises(HrmKernel::Error) { @coordinator.submit("job_id" => "blocked-job") }
    assert_equal "running", @store.read.dig("state", "work_orders", "implement", "status")
  end

  def test_failed_blocked_worker_diagnostic_reports_failure_without_losing_disposition
    blocked = dispatch_worker("blocked-job", "implement", "blocked after partial work", plan(expected: "implemented"))
    assert_equal "blocked", blocked["result_status"]

    checked = @coordinator.check("job_id" => "blocked-job", "check_id" => "behavior-check")
    assert_equal "failed", checked["conclusion"]
    assert_equal "blocked", checked["worker_disposition"]
    assert_equal "diagnostic_evidence", checked["classification"]
    record = JSON.parse(File.read(File.join(@state_dir, "coordinator", "check-blocked-job-behavior-check.json")))
    assert_equal checked["worker_disposition"], record["worker_disposition"]
    assert_equal checked["classification"], record["classification"]
  end

  def test_completed_order_cannot_upgrade_an_earlier_blocked_diagnostic
    dispatch_worker("blocked-job", "implement", "blocked after partial work", plan(expected: "partial"))
    diagnostic = @coordinator.check("job_id" => "blocked-job", "check_id" => "behavior-check")
    assert_equal "diagnostic_evidence", diagnostic["classification"]

    resumed = dispatch_worker(
      "resumed-job", "implement", "Implement the behavior", plan,
      resume_job_id: "blocked-job"
    )
    assert_equal "implemented", resumed["result_status"]
    @coordinator.check("job_id" => "resumed-job", "check_id" => "behavior-check")
    @coordinator.submit("job_id" => "resumed-job")

    assert_raises(HrmKernel::Error) do
      @coordinator.check("job_id" => "blocked-job", "check_id" => "behavior-check")
    end
    persisted = JSON.parse(File.read(File.join(@state_dir, "coordinator", "check-blocked-job-behavior-check.json")))
    assert_equal "blocked", persisted["worker_disposition"]
    assert_equal "diagnostic_evidence", persisted["classification"]
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

  def test_sibling_correction_requires_unchanged_order_evidence_refresh_and_fresh_assessment
    implement_and_submit
    command("work_order.create", "orchestrator", "astra", {
      "work_order_id" => "sibling", "intent_id" => "milestone_initial", "objective" => "Implement sibling behavior",
      "requirement_ids" => ["behavior"], "paths" => ["sibling.txt"], "check_ids" => ["sibling-check"],
      "effect_class" => "local_repository"
    })
    dispatch_worker("sibling-job", "sibling", "Implement sibling behavior", sibling_plan(expected: "implemented"))
    @coordinator.check("job_id" => "sibling-job", "check_id" => "sibling-check")
    @coordinator.submit("job_id" => "sibling-job")

    # The sibling candidate invalidated the first order's full-candidate receipt.
    assert_raises(HrmKernel::Error) { review(job_id: "reviewer-stale-before-refresh", context_paths: ["app.txt", "sibling.txt"]) }
    @coordinator.check("job_id" => "worker-job", "check_id" => "behavior-check")
    refreshed = @coordinator.submit("job_id" => "worker-job")
    assert_equal 1, refreshed.dig("projection", "work_orders", "implement", "evidence_history").length
    review(job_id: "reviewer-initial", context_paths: ["app.txt", "sibling.txt"])
    @coordinator.assess("job_id" => "reviewer-initial")
    original_assessment = @store.read.dig("state", "assessments", "reviewer-initial", "candidate_digest")

    command("work_order.reopen", "worker", "worker-sibling", {
      "work_order_id" => "sibling", "expected_revision" => 1, "claim_id" => "claim-sibling-correction",
      "intent" => {
        "intent_id" => "human-sibling-correction", "kind" => "presentation_adjustment",
        "text" => "Correct the sibling behavior.", "source" => { "thread_id" => "operator-thread", "message_id" => "sibling-correction" },
        "requirement_ids" => ["behavior"]
      }
    })
    dispatch_worker(
      "sibling-correction-job", "sibling", "Implement the correct sibling behavior",
      sibling_plan(expected: "corrected"), resume_job_id: "sibling-job"
    )
    @coordinator.check("job_id" => "sibling-correction-job", "check_id" => "sibling-check")
    @coordinator.submit("job_id" => "sibling-correction-job")

    assert_raises(HrmKernel::Error) { ready_for_review(review_id: "stale-after-sibling-correction") }
    @coordinator.check("job_id" => "worker-job", "check_id" => "behavior-check")
    second_refresh = @coordinator.submit("job_id" => "worker-job")
    assert_equal 2, second_refresh.dig("projection", "work_orders", "implement", "evidence_history").length
    assert_raises(HrmKernel::Error) { ready_for_review(review_id: "missing-current-assessment") }

    review(job_id: "reviewer-current", context_paths: ["app.txt", "sibling.txt"])
    @coordinator.assess("job_id" => "reviewer-current")
    current_assessment = @store.read.dig("state", "assessments", "reviewer-current", "candidate_digest")
    refute_equal original_assessment, current_assessment
    ready = ready_for_review(review_id: "current-human-review")
    assert_equal "reviewer-current", ready.dig("projection", "reviews", "current-human-review", "assessment_id")
  end

  def test_completed_contribution_is_preserved_and_locally_revalidated_in_active_environment
    implement_and_submit
    before = @store.read.fetch("state").fetch("work_orders").fetch("implement")
    host_entries = Dir.children(File.join(@state_dir, "host-jobs")).sort
    active_plan = plan
    active_plan["environment_id"] = "isolated-ruby-rc38"
    active_plan["checks"].each { |check| check["environment_id"] = "isolated-ruby-rc38" }
    git_executable = bundled_git_executable
    git_environment = {
      "PATH" => "#{File.dirname(git_executable)}:/usr/bin:/bin",
      "GIT_CONFIG_NOSYSTEM" => "1", "GIT_CONFIG_GLOBAL" => "/dev/null",
      "GIT_CONFIG_SYSTEM" => "/dev/null", "GIT_ATTR_NOSYSTEM" => "1",
      "GIT_OPTIONAL_LOCKS" => "0", "GIT_NO_LAZY_FETCH" => "1", "GIT_TERMINAL_PROMPT" => "0"
    }
    active_plan["checks"].each { |check| check["env"].merge!(git_environment) }
    driver = File.join(@state_dir, "driver")
    HrmKernel::Host.private_directory!(driver)
    HrmKernel::Host.atomic_json(File.join(driver, "config.json"), {
      "run_id" => "rc38-test", "prompt" => "preserve submission", "project_root" => @project,
      "environment_id" => "isolated-ruby-rc38", "read_roots" => [],
      "environment_allowlist" => (%w[RUN_ROOT FAIL_CHECK TARGET EXPECTED] + git_environment.keys),
      "preflight_checks" => active_plan.fetch("checks"), "forbidden_roots" => [@state_dir],
      "check_repository" => { "schema_version" => HrmKernel::Execution::REPOSITORY_VIEW_SCHEMA,
        "kind" => "isolated_head_candidate", "git_executable" => git_executable },
      "max_turns" => 8, "max_parallel_workers" => 1,
      "continuation" => { "environment_transition" => {
        "active_environment_id" => "isolated-ruby-rc38",
        "old_checks_eligible_for_new_claims" => false
      } }
    })

    projection = @store.project(role: "orchestrator").fetch("projection")
    assert_equal ["implement"], projection.dig("technical_validation", "pending_work_order_ids")
    assert_equal ["implement"], HrmKernel::Store.new(@state_dir).project(role: "orchestrator")
      .dig("projection", "technical_validation", "pending_work_order_ids")
    assert_includes projection.dig("milestone", "readiness_blockers").map { |item| item["kind"] }, "fresh_environment_validation"
    assert_raises(HrmKernel::Error) { ready_for_review(review_id: "stale-environment") }
    error = assert_raises(HrmKernel::Error) do
      HrmKernel::Evidence.verify_completed_work!(@store.read.fetch("state"), state_dir: @state_dir)
    end
    assert_match(/historical environment|repository view is missing/, error.message)

    result = @coordinator.revalidate(
      "revalidation_id" => "fresh-rc38", "work_order_id" => "implement", "check_plan" => active_plan
    )
    assert result["refreshed"]
    assert_equal "passed", result.dig("checks", 0, "conclusion")
    assert_equal host_entries, Dir.children(File.join(@state_dir, "host-jobs")).sort
    after = @store.read.fetch("state").fetch("work_orders").fetch("implement")
    assert_equal "completed", after["status"]
    assert_equal before["revision"], after["revision"]
    assert_equal before["artifacts"], after["artifacts"]
    assert_equal before["evidence_digest"], after.dig("evidence_history", 0, "evidence_digest")
    assert_empty @store.project(role: "orchestrator").dig("projection", "technical_validation", "pending_work_order_ids")

    cli_input = File.join(@temporary, "revalidation.json")
    File.write(cli_input, JSON.generate(
      "revalidation_id" => "fresh-rc38", "work_order_id" => "implement", "check_plan" => active_plan
    ))
    cursor = @store.read.fetch("cursor")
    script = File.realpath(File.join(__dir__, "..", "scripts", "hrm_kernel.rb"))
    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby, script, "revalidate", "--state-dir", @state_dir, "--input", cli_input
    )
    assert status.success?, stderr
    assert JSON.parse(stdout).fetch("refreshed")
    assert_equal cursor, @store.read.fetch("cursor")
  end

  private

  def bundled_git_executable
    File.realpath(File.join(Dir.home, ".cache/codex-runtimes/codex-primary-runtime/dependencies/native/git/bin/git"))
  end

  def command(type, role, actor, data)
    @counter += 1
    @store.transact("command_id" => "command-#{@counter}", "type" => type,
                    "actor" => { "role" => role, "id" => actor }, "data" => data)
  end

  def plan(fail_check: false, expected: nil)
    env = { "RUN_ROOT" => "{run_root}", "FAIL_CHECK" => fail_check ? "yes" : "no" }
    env["EXPECTED"] = expected if expected
    {
      "environment_id" => "isolated-ruby",
      "checks" => [{
        "id" => "behavior-check", "environment_id" => "isolated-ruby",
        "argv" => [File.realpath(RbConfig.ruby), "check.rb"],
        "env" => env,
        "cwd" => @project, "timeout_seconds" => 10, "max_output_bytes" => 1024 * 1024,
        "configuration_paths" => ["{run_root}"]
      }]
    }
  end

  def sibling_plan(expected:)
    spec = plan
    spec["checks"][0]["id"] = "sibling-check"
    spec["checks"][0]["env"].merge!("TARGET" => "sibling.txt", "EXPECTED" => expected)
    spec
  end

  def implement(fail_check: false)
    job = dispatch_worker("worker-job", "implement", "Implement the behavior", plan(fail_check: fail_check))
    assert_equal "succeeded", job["status"], JSON.pretty_generate(job)
    job
  end

  def dispatch_worker(job_id, work_order_id, prompt, check_plan, resume_job_id: nil)
    @jobs << job_id
    spec = {
      "job_id" => job_id, "role" => "worker", "work_order_id" => work_order_id, "model" => "gpt-5.6-sol",
      "prompt" => prompt, "context_paths" => [work_order_id == "sibling" ? "sibling.txt" : "app.txt"],
      "check_plan" => check_plan, "execution_environment_allowlist" => %w[RUN_ROOT FAIL_CHECK TARGET EXPECTED]
    }
    spec["resume_job_id"] = resume_job_id if resume_job_id
    @host.dispatch(spec)
    wait_job(job_id)
  end

  def implement_and_submit
    implement
    checked = @coordinator.check("job_id" => "worker-job", "check_id" => "behavior-check")
    assert_equal "passed", checked["conclusion"]
    @coordinator.submit("job_id" => "worker-job")
  end

  def review(prompt: "Review the exact candidate", job_id: "reviewer-job", context_paths: ["app.txt"])
    @jobs << job_id
    @host.dispatch(
      "job_id" => job_id, "role" => "reviewer", "model" => "gpt-5.6-sol", "prompt" => prompt,
      "context_paths" => context_paths, "check_plan" => plan,
      "execution_environment_allowlist" => %w[RUN_ROOT FAIL_CHECK TARGET EXPECTED]
    )
    job = wait_job(job_id)
    assert_equal "succeeded", job["status"], JSON.pretty_generate(job)
    job
  end

  def ready_for_review(review_id: "human-review")
    command("milestone.review_ready", "orchestrator", "astra", { "review_id" => review_id })
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
