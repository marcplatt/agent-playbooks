# frozen_string_literal: true

require "fileutils"
require "json"
require "minitest/autorun"
require "rbconfig"
require "tmpdir"
require_relative "../lib/hrm_kernel/host"

class HrmKernelHostTest < Minitest::Test
  THREAD = "01234567-89ab-cdef-0123-456789abcdef"

  def setup
    @temporary = File.realpath(Dir.mktmpdir("hrm-host"))
    @project = File.join(@temporary, "project")
    FileUtils.mkdir_p(@project)
    File.write(File.join(@project, "app.txt"), "original\n")
    @state_dir = File.join(@temporary, "state")
    @store = HrmKernel::Store.new(@state_dir)
    @counter = 0
    transact("milestone.create", "operator", "human", {
      "milestone_id" => "trial", "outcome" => "Build a reviewable application",
      "project_root" => @project, "requirements" => [{ "id" => "R1", "text" => "Keep reviewed intent" }],
      "allowed_paths" => ["app.txt", "other.txt", "owned/feature.txt"]
    })
    create_order("work", "app.txt")
    @fake = File.join(@temporary, "fake-codex")
    File.write(@fake, <<~'RUBY'.sub("RUBY_EXECUTABLE", RbConfig.ruby))
      #!RUBY_EXECUTABLE
      require "json"
      require "securerandom"
      require "open3"
      require "rbconfig"
      packet = JSON.parse(STDIN.read)
      task = packet.fetch("task")
      JSON.parse(File.read(ARGV[ARGV.index("--output-schema") + 1]))
      permissions = JSON.parse(File.read(File.join(File.dirname(ARGV[ARGV.index("-o") + 1]), "permissions.json")))
      puts JSON.generate("type" => "fixture.argv", "argv" => ARGV)
      thread = if ARGV.include?("resume")
                 ARGV[ARGV.index("resume") + 1]
               elsif packet["actor_id"].start_with?("reviewer-")
                 "11234567-89ab-cdef-0123-456789abcdef"
               else
                 "01234567-89ab-cdef-0123-456789abcdef"
               end
      puts JSON.generate("type" => "thread.started", "thread_id" => thread)
      $stdout.flush
      sleep 0.2 if task == "slow"
      abort "fake host failure" if task == "fail"
      status = packet["actor_id"].start_with?("reviewer-") ? "reviewed" : "implemented"
      status = "blocked" if task == "blocked"
      # Simulate one native tool sandbox inside the fake CLI. The CLI parent
      # remains outside it, exactly as required for schema/result transport.
      rules = ["(version 1)", "(deny default)", "(allow process*)", "(allow sysctl-read)", "(deny network*)"]
      rules << '(allow file-read* (literal "/"))'
      rules << '(allow file-write* (literal "/dev/null"))'
      %w[/System/Library /usr /Library/Apple /Library/Ruby /private/var/db/dyld /private/var/select /dev/null /dev/urandom].each do |path|
        rules << "(allow file-read* (subpath #{JSON.generate(path)}))"
      end
      filesystem = permissions.fetch("filesystem")
      ["/System/Library", "/usr", "/Library/Apple", "/Library/Ruby", "/private/var/db/dyld", "/private/var/select", *filesystem.keys.reject { |path| path.start_with?(":") }].each do |path|
        parent = File.dirname(path)
        until parent == "/"
          rules << "(allow file-read* (literal #{JSON.generate(parent)}))"
          parent = File.dirname(parent)
        end
      end
      filesystem.each do |path, access|
        next if path.start_with?(":") || access == "deny"
        rules << "(allow file-read* (subpath #{JSON.generate(path)}))"
        if access == "write"
          kind = File.directory?(path) ? "subpath" : "literal"
          rules << "(allow file-write* (#{kind} #{JSON.generate(path)}))"
        end
      end
      filesystem.each do |path, access|
        next if path.start_with?(":") || access != "deny"
        rules << "(deny file-read* file-write* (subpath #{JSON.generate(path)}))"
      end
      tool = <<~'TOOL'
        require "json"
        task = ARGV.fetch(0)
        changed = []
        summary = "Actual fake process completed"
        if task == "edit" || task == "unreported-edit"
          File.write("app.txt", "changed\n")
          changed = ["app.txt"] if task == "edit"
        elsif task.start_with?("read-forbidden:")
          begin
            File.read(task.delete_prefix("read-forbidden:"))
            summary = "forbidden read unexpectedly succeeded"
          rescue Errno::EPERM, Errno::EACCES
            summary = "forbidden read denied"
          end
        elsif task == "write-other-order"
          begin
            File.write("other.txt", "unauthorized change")
            summary = "cross-order write unexpectedly succeeded"
          rescue Errno::EPERM, Errno::EACCES
            summary = "cross-order write denied"
          end
        elsif task == "scratch"
          File.write(File.join(ENV.fetch("TMPDIR"), "probe.txt"), "scratch")
          summary = "scratch write succeeded"
        end
        puts JSON.generate("changed" => changed, "summary" => summary)
      TOOL
      output, errors, outcome = Open3.capture3("/usr/bin/sandbox-exec", "-p", rules.join("\n"), RbConfig.ruby, "-e", tool, task)
      abort "fixture tool exit=#{outcome.exitstatus.inspect} signal=#{outcome.termsig.inspect}: #{errors} #{output}" unless outcome.success?
      observed = JSON.parse(output)
      result = if packet["actor_id"] == "astra-orchestrator"
                 {
                   "status" => "continue", "summary" => observed.fetch("summary"),
                   "requests" => [{"request_id" => "next-step", "operation" => "status", "input_json" => "{}"}]
                 }
               else
                 {
                   "status" => status, "summary" => observed.fetch("summary"), "changed_paths" => observed.fetch("changed"),
                   "findings" => [], "scenario_dispositions" => [], "context_requests" => []
                 }
               end
      result["status"] = "complete" if task == "invalid-result"
      output = ARGV[ARGV.index("-o") + 1]
      File.write(output, JSON.generate(result))
      unless task == "no-completion-event"
        puts JSON.generate("type" => "turn.completed", "usage" => {
          "input_tokens" => 123, "cached_input_tokens" => 45, "output_tokens" => 67
        })
      end
    RUBY
    File.chmod(0o700, @fake)
    @host = HrmKernel::Host.new(state_dir: @state_dir, codex_path: @fake)
    @jobs = []
  end

  def teardown
    @jobs.each { |id| await_job(id) rescue nil }
    @jobs.each do |id|
      temporary = @host.poll(job_id: id)["tool_tmp"] rescue nil
      FileUtils.remove_entry(temporary) if temporary && File.directory?(temporary)
      Dir.rmdir(File.dirname(temporary)) if temporary && File.directory?(File.dirname(temporary)) && Dir.empty?(File.dirname(temporary))
    end
    FileUtils.remove_entry(@temporary) if File.exist?(@temporary)
  end

  def test_real_child_dispatch_persists_thread_usage_claim_and_structured_artifacts
    job = dispatch("one", prompt: "edit", context_paths: ["app.txt"])
    assert_equal "worker-work", job["actor_id"]
    assert_equal "claim-one", job["claim_id"]
    done = await_job("one")
    assert_equal "succeeded", done["status"]
    assert_equal THREAD, done["thread_id"]
    assert_equal [{ "input_tokens" => 123, "cached_input_tokens" => 45, "output_tokens" => 67 }], done["usage"]
    collected = @host.collect(job_id: "one")
    assert_equal ["app.txt"], collected["observed_changed_paths"]
    assert_equal Digest::SHA256.hexdigest("changed\n"), collected["verified_artifacts"].first["sha256"]
    refute collected["submitted"]
    refute collected["tests_verified"]
    assert_equal "running", @store.read.dig("state", "work_orders", "work", "status")
    packet = JSON.parse(File.read(done["artifact_paths"]["prompt.json"]))
    refute packet.key?("ledger")
    assert_equal "original\n", packet.dig("declared_sources", 0, "text")
    assert_equal "Build a reviewable application", packet.dig("initial_contract", "outcome")
    assert_equal File.size(done["artifact_paths"]["prompt.json"]), done["prompt_bytes"]
    assert_equal 0o600, File.stat(done["artifact_paths"]["events.jsonl"]).mode & 0o777
    assert_equal 0o700, File.stat(File.dirname(done["artifact_paths"]["job.json"])).mode & 0o777
    argv = JSON.parse(File.readlines(done["artifact_paths"]["events.jsonl"]).first)["argv"]
    assert_includes argv, "--ignore-user-config"
    assert_includes argv, "--strict-config"
    assert_includes argv, 'default_permissions="hrm-worker"'
    refute_includes argv, "-s"
    refute_includes argv, "--sandbox"
    frozen_permissions = @host.job_record(job_id: "one").fetch("permission_profile")
    assert_includes argv, "permissions.hrm-worker=#{HrmKernel::Host.toml_inline(frozen_permissions)}"
    assert_equal HrmKernel::Host.digest(frozen_permissions), done["permission_profile_digest"]
    assert_equal "gpt-5.6-sol", argv[argv.index("-m") + 1]
    refute_includes argv, "--ignore-rules"
    refute_includes argv, "--dangerously-bypass-approvals-and-sandbox"
  end

  def test_restart_and_duplicate_dispatch_do_not_launch_again
    spec = specification("duplicate", prompt: "slow")
    @jobs << "duplicate"
    @host.dispatch(spec)
    restarted = HrmKernel::Host.new(state_dir: @state_dir, codex_path: @fake)
    assert_equal "duplicate", restarted.dispatch(spec)["job_id"]
    await_job("duplicate")
    assert_equal THREAD, restarted.dispatch(spec)["thread_id"]
    events = File.readlines(@host.poll(job_id: "duplicate")["artifact_paths"]["events.jsonl"]).map { |line| JSON.parse(line) }
    assert_equal 1, events.count { |event| event["type"] == "thread.started" }
    assert_raises(HrmKernel::Error) { restarted.dispatch(spec.merge("prompt" => "different")) }
  end

  def test_stale_released_claim_rejects_collection
    dispatch("stale")
    await_job("stale")
    transact("work_order.release", "orchestrator", "astra", {
      "work_order_id" => "work", "revision" => 1, "claim_id" => "claim-stale", "reason" => "Changed assignment"
    })
    refute @host.poll(job_id: "stale")["claim_current"]
    error = assert_raises(HrmKernel::Error) { @host.collect(job_id: "stale") }
    assert_match(/stale host job/, error.message)
  end

  def test_exit_zero_without_completion_event_is_not_success
    dispatch("unfinished", prompt: "no-completion-event")
    assert_equal "failed", await_job("unfinished")["status"]
    assert_raises(HrmKernel::Error) { @host.collect(job_id: "unfinished") }
  end

  def test_nonzero_child_exit_and_bad_schema_do_not_forge_completion
    dispatch("failure", prompt: "fail")
    failed = await_job("failure")
    assert_equal "failed", failed["status"]
    assert_equal 1, failed.dig("completion", "exit_code")
    assert_raises(HrmKernel::Error) { @host.collect(job_id: "failure") }
    release("failure")
    dispatch("invalid", prompt: "invalid-result")
    assert_equal "failed", await_job("invalid")["status"]
    assert_raises(HrmKernel::Error) { @host.collect(job_id: "invalid") }
  end

  def test_result_tampering_and_unreported_artifact_changes_are_rejected
    dispatch("tamper")
    done = await_job("tamper")
    result = JSON.parse(File.read(done["artifact_paths"]["result.json"]))
    result["summary"] = "Forged after completion"
    File.write(done["artifact_paths"]["result.json"], JSON.generate(result))
    assert_raises(HrmKernel::Error) { @host.collect(job_id: "tamper") }
    release("tamper")
    dispatch("unreported", prompt: "unreported-edit")
    await_job("unreported")
    assert_raises(HrmKernel::Error) { @host.collect(job_id: "unreported") }
  end

  def test_resume_uses_exact_thread_and_same_actor_while_checker_is_fresh
    dispatch("first")
    await_job("first")
    resumed = dispatch("second", resume_job_id: "first")
    assert_equal "claim-first", resumed["claim_id"]
    done = await_job("second")
    assert_equal THREAD, done["thread_id"]
    argv = JSON.parse(File.readlines(done["artifact_paths"]["events.jsonl"]).first)["argv"]
    assert_equal THREAD, argv[argv.index("resume") + 1]
    refute_includes argv, "--last"
    complete_order
    reviewer_spec = specification("checker").merge("role" => "reviewer")
    reviewer_spec.delete("work_order_id")
    @jobs << "checker"
    reviewer = @host.dispatch(reviewer_spec)
    assert_equal "reviewer-checker", reviewer["actor_id"]
    checked = await_job("checker")
    schema = JSON.parse(File.read(File.join(@state_dir, "host-jobs", "checker", "schema.json")))
    assert_equal %w[reviewed blocked], schema.dig("properties", "status", "enum")
    assert_equal 0, schema.dig("properties", "changed_paths", "maxItems")
    refute_equal THREAD, checked["thread_id"]
    assert_equal "reviewed", @host.collect(job_id: "checker").dig("result", "status")
    check_argv = JSON.parse(File.readlines(checked["artifact_paths"]["events.jsonl"]).first)["argv"]
    assert_includes check_argv, 'default_permissions="hrm-reviewer"'
    refute_includes check_argv, "--sandbox"
    assert_raises(HrmKernel::Error) { @host.dispatch(reviewer_spec.merge("job_id" => "bad-checker", "resume_job_id" => "first")) }
    File.write(File.join(@project, "app.txt"), "changed after checker\n")
    assert_raises(HrmKernel::Error) { @host.collect(job_id: "checker") }
  end

  def test_orchestrator_uses_astra_read_only_profile_and_structured_result
    error = assert_raises(HrmKernel::Error) do
      @host.dispatch(orchestrator_specification("astra-wrong-model", model: "gpt-5.6-sol"))
    end
    assert_match(/role requires gpt-6-astra/, error.message)

    spec = orchestrator_specification("astra-one", context_paths: ["app.txt"])
    @jobs << "astra-one"
    job = @host.dispatch(spec)
    assert_equal "orchestrator", job["role"]
    assert_equal "astra-orchestrator", job["actor_id"]
    assert_nil job["work_order_id"]
    done = await_job("astra-one")
    assert_equal "succeeded", done["status"]
    assert_equal "continue", done["result_status"]
    result = @host.collect(job_id: "astra-one").fetch("result")
    assert_equal "continue", result["status"]
    assert_equal "status", result.fetch("requests").first["operation"]

    argv = JSON.parse(File.readlines(done["artifact_paths"]["events.jsonl"]).first).fetch("argv")
    assert_equal "gpt-6-astra", argv[argv.index("-m") + 1]
    assert_includes argv, 'default_permissions="hrm-orchestrator"'
    permissions = @host.job_record(job_id: "astra-one").fetch("permission_profile").fetch("filesystem")
    assert_equal "read", permissions.fetch(@project)
    refute_equal "write", permissions[File.join(@project, "app.txt")]
  end

  def test_orchestrator_resume_uses_exact_prior_session
    @jobs << "astra-first"
    @host.dispatch(orchestrator_specification("astra-first"))
    first = await_job("astra-first")
    @jobs << "astra-second"
    resumed = @host.dispatch(orchestrator_specification("astra-second", resume_job_id: "astra-first"))
    assert_equal "astra-orchestrator", resumed["actor_id"]
    second = await_job("astra-second")
    assert_equal first["thread_id"], second["thread_id"]
    argv = JSON.parse(File.readlines(second["artifact_paths"]["events.jsonl"]).first).fetch("argv")
    assert_equal ["resume", first["thread_id"]], argv.values_at(argv.index("resume"), argv.index("resume") + 1)
    refute_includes argv, "--last"
  end

  def test_orchestrator_rejects_sensitive_context_before_persisting_job
    File.write(File.join(@project, ".env"), "SECRET=fixture\n")
    error = assert_raises(HrmKernel::Error) do
      @host.dispatch(orchestrator_specification("astra-sensitive", context_paths: [".env"]))
    end
    assert_match(/sensitive files cannot be host context/, error.message)
    refute File.exist?(File.join(@state_dir, "host-jobs", "astra-sensitive"))
  end

  def test_invalid_context_budget_model_or_cross_order_resume_does_not_reassign
    assert_raises(HrmKernel::Error) { @host.dispatch(specification("wrong-model").merge("model" => "gpt-5.5")) }
    assert_raises(HrmKernel::Error) { @host.dispatch(specification("escape", context_paths: ["../fake-codex"])) }
    assert_raises(HrmKernel::Error) { @host.dispatch(specification("over-budget", max_context_bytes: 1024)) }
    assert_equal "queued", @store.read.dig("state", "work_orders", "work", "status")
    dispatch("original")
    await_job("original")
    create_order("other", "other.txt")
    error = assert_raises(HrmKernel::Error) do
      @host.dispatch(specification("cross-order", resume_job_id: "original").merge("work_order_id" => "other"))
    end
    assert_match(/preserve .*actor.*order/, error.message)
  end

  def test_native_profile_exclusion_is_effective_and_context_cannot_bypass_it
    forbidden = File.join(@temporary, "operator-data")
    FileUtils.mkdir_p(forbidden)
    marker = File.join(forbidden, "private.txt")
    File.write(marker, "private test fixture")
    dispatch("isolated", prompt: "read-forbidden:#{marker}", forbidden_roots: [forbidden])
    await_job("isolated")
    assert_equal "forbidden read denied", @host.collect(job_id: "isolated").dig("result", "summary")
    release("isolated")
    File.symlink(marker, File.join(@project, "secret-link"))
    assert_raises(HrmKernel::Error) { @host.dispatch(specification("link", context_paths: ["secret-link"], forbidden_roots: [forbidden])) }
  end

  def test_forbidden_executor_dependency_is_retained_for_checks_but_not_granted_to_model
    forbidden = File.join(@temporary, "private-executor-environment")
    FileUtils.mkdir_p(forbidden)
    marker = File.join(forbidden, "runtime.txt")
    File.write(marker, "trusted runner dependency")
    dispatch("executor-only", prompt: "read-forbidden:#{marker}", forbidden_roots: [forbidden],
      execution_read_roots: [forbidden])
    await_job("executor-only")
    assert_equal "forbidden read denied", @host.collect(job_id: "executor-only").dig("result", "summary")
    job = @host.job_record(job_id: "executor-only")
    assert_equal [forbidden], job["execution_read_roots"]
    assert_equal "deny", job.dig("permission_profile", "filesystem", forbidden)
  end

  def test_execution_uses_only_frozen_check_plan
    dispatch("checks")
    context = @host.check_context(job_id: "checks", check_id: "unit")
    assert_equal ["ruby", "test.rb"], context.dig("spec", "argv")
    assert_equal "fixture-env", context.dig("job", "check_plan", "environment_id")
    assert_raises(HrmKernel::Error) { @host.check_context(job_id: "checks", check_id: "new-command") }
    assert_equal [], context.dig("job", "execution_environment_allowlist")
  end

  def test_worker_cannot_write_another_orders_file_in_the_shared_candidate
    create_order("other", "other.txt")
    dispatch("bounded-write", prompt: "write-other-order")
    assert_equal "succeeded", await_job("bounded-write")["status"]
    result = @host.collect(job_id: "bounded-write")
    assert_equal "cross-order write denied", result.dig("result", "summary")
    refute File.exist?(File.join(@project, "other.txt"))
  end

  def test_write_grants_reject_existing_and_dangling_artifact_symlinks_before_claim
    File.unlink(File.join(@project, "app.txt"))
    File.write(File.join(@project, "other.txt"), "another order's artifact")
    ["other.txt", "missing.txt"].each_with_index do |target, index|
      File.symlink(target, File.join(@project, "app.txt"))
      error = assert_raises(HrmKernel::Error) { @host.dispatch(specification("linked-artifact-#{index}")) }
      assert_match(/artifact path contains a symlink/, error.message)
      assert_equal "queued", @store.read.dig("state", "work_orders", "work", "status")
      refute File.exist?(File.join(@state_dir, "host-jobs", "linked-artifact-#{index}"))
      File.unlink(File.join(@project, "app.txt"))
    end
    assert_equal "another order's artifact", File.read(File.join(@project, "other.txt"))
  end

  def test_write_grants_reject_symlinked_parent_of_a_missing_artifact
    FileUtils.mkdir_p(File.join(@project, "another-order"))
    File.symlink("another-order", File.join(@project, "owned"))
    create_order("nested", "owned/feature.txt")
    error = assert_raises(HrmKernel::Error) do
      @host.dispatch(specification("linked-parent").merge("work_order_id" => "nested"))
    end
    assert_match(/artifact path contains a symlink/, error.message)
    assert_equal "queued", @store.read.dig("state", "work_orders", "nested", "status")
    refute File.exist?(File.join(@project, "another-order", "feature.txt"))
    refute File.exist?(File.join(@state_dir, "host-jobs", "linked-parent"))
  end

  def test_missing_owned_file_parent_is_created_privately_without_parent_write_grant
    create_order("nested", "owned/feature.txt")
    @jobs << "nested-parent"
    @host.dispatch(specification("nested-parent").merge("work_order_id" => "nested"))
    done = await_job("nested-parent")
    assert_equal "succeeded", done["status"]

    parent = File.join(@project, "owned")
    target = File.join(parent, "feature.txt")
    assert File.directory?(parent)
    assert_equal 0o700, File.stat(parent).mode & 0o777
    filesystem = @host.job_record(job_id: "nested-parent").fetch("permission_profile").fetch("filesystem")
    assert_equal "write", filesystem[target]
    refute_equal "write", filesystem[parent]
  end

  def test_collection_rejects_artifact_replaced_by_a_symlink_after_dispatch
    dispatch("replaced-artifact")
    await_job("replaced-artifact")
    File.rename(File.join(@project, "app.txt"), File.join(@project, "other.txt"))
    File.symlink("other.txt", File.join(@project, "app.txt"))
    error = assert_raises(HrmKernel::Error) { @host.collect(job_id: "replaced-artifact") }
    assert_match(/artifact path contains a symlink/, error.message)
  end

  def test_worker_cannot_read_its_control_ledger_but_cli_reads_schema_and_writes_result
    dispatch("control-denied", prompt: "read-forbidden:#{File.join(@state_dir, 'events.jsonl')}")
    await_job("control-denied")
    assert_equal "forbidden read denied", @host.collect(job_id: "control-denied").dig("result", "summary")
  end

  def test_native_profile_keeps_transport_success_separate_from_blocked_work
    dispatch("blocked", prompt: "blocked")
    done = await_job("blocked")
    assert_equal "succeeded", done["status"]
    assert_equal "blocked", done["result_status"]
    assert_equal "blocked", done.dig("completion", "result_status")
    assert_equal "blocked", @host.collect(job_id: "blocked").dig("result", "status")
  end

  def test_native_profile_allows_private_scratch_without_reopening_protected_state
    dispatch("scratch", prompt: "scratch")
    await_job("scratch")
    assert_equal "scratch write succeeded", @host.collect(job_id: "scratch").dig("result", "summary")
    release("scratch")
    assert_raises(HrmKernel::Error) do
      @host.dispatch(specification("bad-read-root").merge("execution_read_roots" => [File.join(@state_dir, "host-jobs")]))
    end
  end

  private

  def transact(type, role, actor, data)
    @counter += 1
    @store.transact("command_id" => "command-#{@counter}", "type" => type,
                    "actor" => { "role" => role, "id" => actor }, "data" => data)
  end

  def create_order(id, path)
    transact("work_order.create", "orchestrator", "astra", {
      "work_order_id" => id, "intent_id" => "milestone_initial", "objective" => "Implement exact app behavior",
      "requirement_ids" => ["R1"], "paths" => [path], "check_ids" => ["unit"], "effect_class" => "local_repository"
    })
  end

  def specification(id, **overrides)
    {
      "job_id" => id, "role" => "worker", "work_order_id" => "work", "model" => "gpt-5.6-sol",
      "prompt" => "do work", "context_paths" => [], "max_context_bytes" => 64 * 1024,
      "check_plan" => { "environment_id" => "fixture-env", "checks" => [{ "id" => "unit", "environment_id" => "fixture-env", "argv" => ["ruby", "test.rb"] }] }
    }.merge(overrides.transform_keys(&:to_s))
  end

  def orchestrator_specification(id, **overrides)
    specification(id).merge(
      "role" => "orchestrator", "work_order_id" => nil, "model" => "gpt-6-astra",
      "check_plan" => {"environment_id" => "fixture-env", "checks" => []}
    ).merge(overrides.transform_keys(&:to_s))
  end

  def dispatch(id, **options)
    @jobs << id
    @host.dispatch(specification(id, **options))
  end

  def await_job(id)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 10
    loop do
      job = @host.poll(job_id: id)
      return job if %w[succeeded failed].include?(job["status"])
      raise "host fixture timed out: #{job}" if Process.clock_gettime(Process::CLOCK_MONOTONIC) > deadline
      sleep 0.025
    end
  end

  def release(id)
    order = @store.read.dig("state", "work_orders", "work")
    transact("work_order.release", "orchestrator", "astra", {
      "work_order_id" => "work", "revision" => order["revision"], "claim_id" => order["claim_id"], "reason" => "Fixture #{id} completed"
    })
  end

  def complete_order
    order = @store.read.dig("state", "work_orders", "work")
    artifacts = [{ "path" => "app.txt", "sha256" => Digest::SHA256.file(File.join(@project, "app.txt")).hexdigest }]
    report_path = File.join(@project, "unit-report.json")
    File.write(report_path, JSON.generate(
      "check_id" => "unit", "conclusion" => "passed", "work_order_id" => "work", "revision" => order["revision"], "artifacts" => artifacts
    ))
    transact("work_order.submit", "worker", "worker-work", {
      "work_order_id" => "work", "revision" => order["revision"], "claim_id" => order["claim_id"], "artifacts" => artifacts,
      "checks" => [{ "id" => "unit", "conclusion" => "passed", "artifact_path" => "unit-report.json", "sha256" => Digest::SHA256.file(report_path).hexdigest }]
    })
  end
end
