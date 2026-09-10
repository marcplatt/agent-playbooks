# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "minitest/autorun"
require "open3"
require "rbconfig"
require "tmpdir"

require_relative "../lib/hrm_kernel/driver"
require_relative "../lib/hrm_kernel/run_continuation"

class HrmKernelRunContinuationTest < Minitest::Test
  def setup
    @temporary = File.realpath(Dir.mktmpdir("hrm-run-continuation"))
    @project = File.join(@temporary, "project")
    Dir.mkdir(@project, 0o700)
    File.write(File.join(@project, "app.txt"), "unchanged\n")
    File.write(File.join(@project, "sibling.txt"), "baseline sibling\n")
    @kernel = File.join(@temporary, "source-kernel")
    Dir.mkdir(@kernel, 0o700)
    FileUtils.mkdir_p(File.join(@kernel, "playbooks"))
    File.write(File.join(@kernel, "kernel.txt"), "RC35\n")
    File.write(File.join(@kernel, "playbooks", "hrm-interaction-kernel.md"), <<~MARKDOWN)
      ---
      title: AP-INTERACT RC.35 - test source kernel
      ---
    MARKDOWN
    git(@kernel, "init", "--quiet")
    git(@kernel, "config", "user.email", "continuation-test@example.invalid")
    git(@kernel, "config", "user.name", "Continuation Test")
    git(@kernel, "add", "kernel.txt", "playbooks/hrm-interaction-kernel.md")
    git(@kernel, "commit", "--quiet", "-m", "frozen source kernel")
    @source_revision = git(@kernel, "rev-parse", "HEAD").strip
    @source = File.join(@temporary, "source-state")
    @destination = File.join(@temporary, "continued-state")
    create_source_state
  end

  def teardown
    FileUtils.chmod_R(0o700, @temporary) if File.exist?(@temporary)
    FileUtils.remove_entry(@temporary)
  end

  def test_copies_historical_state_unchanged_and_derives_only_new_driver_state
    before = byte_snapshot(@source)
    source_store = HrmKernel::Store.new(@source).read
    source_runtime = File.binread(File.join(@source, "driver", "runtime.json"))
    source_config = File.binread(File.join(@source, "driver", "config.json"))
    source_preflight = File.binread(File.join(@source, "driver", "preflight.json"))

    manifest = continue_run

    assert_equal before, byte_snapshot(@source)
    assert_equal File.binread(File.join(@source, "events.jsonl")), File.binread(File.join(@destination, "events.jsonl"))
    assert_equal source_store["state"], HrmKernel::Store.new(@destination).read["state"]
    assert_equal source_config, File.binread(File.join(@destination, "driver", "continuation", "source-config.json"))
    assert_equal source_runtime, File.binread(File.join(@destination, "driver", "continuation", "source-runtime.json"))
    assert_equal source_preflight, File.binread(File.join(@destination, "driver", "continuation", "source-preflight.json"))
    assert_equal source_preflight, File.binread(File.join(@destination, "driver", "preflight.json"))
    assert manifest["ledger_copied_unchanged"]
    assert manifest["historical_receipts_copied_unchanged"]
    assert manifest["source_preflight_is_historical"]
    refute manifest["target_preflight_is_fresh"]
    assert manifest["target_preflight_reverified_for_destination"]
    assert_equal @source_revision, manifest["source_kernel_revision"]
    assert_equal "AP-INTERACT RC.35", manifest["source_kernel_version"]
    assert_equal "AP-INTERACT RC.36", manifest["target_kernel_version"]
    driver = HrmKernel::Driver.new(state_dir: @destination)
    driver.send(:verify_environment!, read_json(File.join(@destination, "driver", "config.json")))
    assert_private_tree(@destination)
  end

  def test_is_idempotent_for_the_same_request_and_rejects_a_conflicting_destination
    first = continue_run
    second = continue_run
    assert_equal first, second

    error = assert_raises(HrmKernel::Error) { continue_run(new_run_id: "different-run") }
    assert_match(/conflicting continuation/, error.message)
  end

  def test_rejects_active_or_uncertain_jobs_and_pending_driver_operations
    %w[pending_dispatch pending_job_registration].each do |field|
      reset_source
      runtime = read_json(File.join(@source, "driver", "runtime.json"))
      runtime[field] = { "job_id" => "pending" }
      write_json(File.join(@source, "driver", "runtime.json"), runtime)
      error = assert_raises(HrmKernel::Error) { continue_run }
      assert_match(/pending/, error.message)
    end

    reset_source
    write_astra_job("active-astra", completion: false, live: true)
    runtime = read_json(File.join(@source, "driver", "runtime.json"))
    runtime["orchestrator_job"] = "active-astra"
    write_json(File.join(@source, "driver", "runtime.json"), runtime)
    error = assert_raises(HrmKernel::Error) { continue_run }
    assert_match(/running or uncertain native job/, error.message)

    reset_source
    write_astra_job("unknown-astra", completion: false, live: false)
    runtime = read_json(File.join(@source, "driver", "runtime.json"))
    runtime["orchestrator_job"] = "unknown-astra"
    write_json(File.join(@source, "driver", "runtime.json"), runtime)
    error = assert_raises(HrmKernel::Error) { continue_run }
    assert_match(/running or uncertain native job/, error.message)
  end

  def test_rejects_running_driver_unsafe_paths_and_false_stop_assertion
    lock_path = File.join(@source, "driver", ".lock")
    File.open(lock_path, File::RDWR) do |lock|
      assert lock.flock(File::LOCK_EX | File::LOCK_NB)
      error = assert_raises(HrmKernel::Error) { continue_run }
      assert_match(/Driver is still running/, error.message)
    end

    error = assert_raises(HrmKernel::Error) { continue_run(controller_stopped: false) }
    assert_match(/explicitly true/, error.message)

    nested = File.join(@source, "nested-destination")
    error = assert_raises(HrmKernel::Error) { continue_run(destination: nested) }
    assert_match(/overlap/, error.message)

    unsafe = File.join(@source, "driver", "unsafe-link")
    File.symlink(File.join(@source, "events.jsonl"), unsafe)
    error = assert_raises(HrmKernel::Error) { continue_run }
    assert_match(/symlink/, error.message)
  end

  def test_normalizes_effectively_private_execution_scratch_without_mutating_source
    run = File.join(@source, "execution", "a" * 64)
    scratch = File.join(run, "pytest-of-unknown", "pytest-0", "test-example")
    FileUtils.mkdir_p(scratch, mode: 0o755)
    File.chmod(0o700, run)
    authenticate_test_execution_run(run)
    [File.join(run, "pytest-of-unknown"), File.join(run, "pytest-of-unknown", "pytest-0"), scratch].each do |path|
      File.chmod(0o755, path)
    end
    scratch_file = File.join(scratch, "packet.md")
    write_bytes(scratch_file, "retained native scratch\n")
    File.chmod(0o644, scratch_file)
    relative_link = File.join(run, "pytest-of-unknown", "pytest-current")
    File.symlink("pytest-0", relative_link)
    absolute_target = File.join(scratch, "actual-target")
    FileUtils.mkdir_p(absolute_target, mode: 0o755)
    File.chmod(0o755, absolute_target)
    absolute_link = File.join(scratch, "test-examplecurrent")
    File.symlink(absolute_target, absolute_link)
    source_modes = mode_snapshot(@source)
    source_bytes = byte_snapshot(@source)

    continue_run

    assert_equal source_bytes, byte_snapshot(@source)
    assert_equal source_modes, mode_snapshot(@source)
    assert_equal "retained native scratch\n", File.binread(File.join(@destination,
      scratch_file.delete_prefix(@source + "/")))
    [relative_link, absolute_link].each do |source_link|
      refute File.exist?(File.join(@destination, source_link.delete_prefix(@source + "/")))
      refute File.symlink?(File.join(@destination, source_link.delete_prefix(@source + "/")))
    end
    manifest = read_json(File.join(@destination, "driver", "continuation", "manifest.json"))
    links = manifest.fetch("inert_execution_scratch_links")
    assert_equal [absolute_link, relative_link].map { |path| path.delete_prefix(@source + "/") }.sort,
      links.map { |entry| entry["path"] }.sort
    assert_equal "pytest-0", links.find { |entry| entry["path"].end_with?("pytest-current") }.fetch("target")
    assert_equal absolute_target, links.find { |entry| entry["path"].end_with?("test-examplecurrent") }.fetch("target")
    assert_equal "archived_as_inert_metadata_not_recreated_or_followed",
      manifest["execution_scratch_link_transformation"]
    assert_private_tree(@destination)
    assert_equal manifest, continue_run

    injected = File.join(@destination, "driver", "injected-link")
    File.symlink(File.join(@destination, "driver"), injected)
    error = assert_raises(HrmKernel::Error) { continue_run }
    assert_match(/symlink/, error.message)
    File.unlink(injected)

    manifest_path = File.join(@destination, "driver", "continuation", "manifest.json")
    changed = read_json(manifest_path)
    changed["inert_execution_scratch_links"][0]["target"] = "different-inert-target"
    write_json(manifest_path, changed)
    error = assert_raises(HrmKernel::Error) { continue_run }
    assert_match(/link attribution changed/, error.message)
  end

  def test_nonprivate_execution_control_file_still_fails_closed
    run = File.join(@source, "execution", "b" * 64)
    FileUtils.mkdir_p(run, mode: 0o700)
    control = File.join(run, "receipt.json")
    write_bytes(control, "{}\n")
    File.chmod(0o644, control)
    error = assert_raises(HrmKernel::Error) { continue_run }
    assert_match(/file is not private.*receipt/, error.message)

  end

  def test_nonprivate_execution_scratch_requires_an_authenticated_native_run
    run = File.join(@source, "execution", "e" * 64)
    scratch = File.join(run, "pytest", "test-example")
    FileUtils.mkdir_p(scratch, mode: 0o755)
    File.chmod(0o700, run)
    File.chmod(0o755, File.join(run, "pytest"))
    File.chmod(0o755, scratch)
    authenticate_test_execution_run(run)
    receipt = read_json(File.join(run, "receipt.json"))
    receipt["authentication"]["hmac_sha256"] = "0" * 64
    write_json(File.join(run, "receipt.json"), receipt)
    scratch_file = File.join(scratch, "intake.sqlite3")
    write_bytes(scratch_file, "untrusted scratch")
    File.chmod(0o644, scratch_file)
    source_bytes = byte_snapshot(@source)

    error = assert_raises(HrmKernel::Error) { continue_run }

    assert_match(/receipt authentication failed/, error.message)
    assert_equal source_bytes, byte_snapshot(@source)
    refute File.exist?(@destination)
  end

  def test_escaped_broken_and_control_namespace_symlinks_fail_closed
    run = File.join(@source, "execution", "c" * 64)
    scratch = File.join(run, "pytest-of-unknown")
    target = File.join(scratch, "pytest-0")
    FileUtils.mkdir_p(target, mode: 0o755)
    File.chmod(0o700, run)
    authenticate_test_execution_run(run)
    File.chmod(0o755, scratch)
    File.chmod(0o755, target)

    cases = {
      "escaped" => @project,
      "broken" => File.join(scratch, "missing"),
      "control" => target
    }
    cases.each do |kind, link_target|
      link = kind == "control" ? File.join(run, "control-current") : File.join(scratch, "#{kind}-current")
      File.symlink(link_target, link)
      error = assert_raises(HrmKernel::Error) { continue_run }
      if kind == "control"
        assert_match(/contains a symlink/, error.message)
      else
        assert_match(/same run|broken or unverifiable/, error.message)
      end
      File.unlink(link)
    end
  end

  def test_preserves_authority_ledger_and_exhausted_budget
    @store.transact(
      "command_id" => "decision", "type" => "decision.request",
      "actor" => { "id" => "astra-orchestrator", "role" => "orchestrator" },
      "data" => {
        "decision_id" => "send-authority", "revision" => 1,
        "kind" => "external_effect_authority", "exact_effect" => "Send the quote",
        "requirement_ids" => ["behavior"], "question" => "May the quote be sent?",
        "authority_gap" => { "reason" => "No send authority", "source_ref" => "initial" }
      }
    )
    runtime_path = File.join(@source, "driver", "runtime.json")
    runtime = read_json(runtime_path)
    runtime.merge!("round" => 3, "outcome" => "turn_limit")
    write_json(runtime_path, runtime)
    original_ledger = File.binread(File.join(@source, "events.jsonl"))

    continue_run

    config = read_json(File.join(@destination, "driver", "config.json"))
    continued = read_json(File.join(@destination, "driver", "runtime.json"))
    state = HrmKernel::Store.new(@destination).read.fetch("state")
    assert_equal 3, config["max_turns"]
    assert_equal 3, continued["round"]
    assert_equal "turn_limit", continued["outcome"]
    assert_equal "unresolved", state.dig("decisions", "send-authority", "status")
    assert_equal original_ledger, File.binread(File.join(@destination, "events.jsonl"))
    assert_equal 2, HrmKernel::Store.new(@destination).read["cursor"]
  end

  def test_discards_stale_astra_request_batch_but_preserves_safe_thread_resume_context
    write_astra_job("old-run-astra-2", completion: true, live: false)
    write_completed_worker_job("completed-worker")
    runtime_path = File.join(@source, "driver", "runtime.json")
    runtime = read_json(runtime_path)
    runtime.merge!("round" => 2, "orchestrator_job" => "old-run-astra-2",
      "jobs" => ["completed-worker"], "seen_jobs" => [],
      "observed_cursor" => @store.read["cursor"],
      "outcome" => "engineering_stalled", "pending_dispatch" => nil)
    runtime.delete("pending_dispatch")
    write_json(runtime_path, runtime)

    manifest = continue_run
    config = read_json(File.join(@destination, "driver", "config.json"))
    continued = read_json(File.join(@destination, "driver", "runtime.json"))

    assert_equal "new-run", config["run_id"]
    assert_includes config["forbidden_roots"], @source
    assert_includes config["forbidden_roots"], @destination
    assert_equal "active", continued["outcome"]
    assert_equal 2, continued["round"]
    assert_nil continued["orchestrator_job"]
    refute continued.key?("pending_dispatch")
    refute continued.key?("pending_job_registration")
    assert_equal "old-run-astra-2", continued["resume_job"]
    assert_equal 0, continued["observed_technical_input_cursor"]
    assert_equal "versioned_run_continuation", continued.dig("feedback", 0, "kind")
    assert_includes continued.dig("feedback", 0, "message"), "Do not replay requests"
    assert_equal "old-run-astra-2", manifest["resumed_astra_job_id"]
    assert_equal "11234567-89ab-cdef-0123-456789abcdef", manifest["resumed_astra_thread_id"]
    copied_result = read_json(File.join(@destination, "host-jobs", "old-run-astra-2", "result.json"))
    assert_equal "stale-request", copied_result.dig("requests", 0, "request_id")

    driver = HrmKernel::Driver.new(state_dir: @destination)
    prompt = JSON.parse(driver.send(:prompt, config, continued, { "cursor" => 0, "records" => [] }))
    assert_equal "Original task", prompt["task"]
    assert_equal({ "turn" => 2, "max_turns" => 3 }, prompt["budget"])
    assert_includes JSON.generate(prompt["feedback"]), "versioned_run_continuation"
    refute_includes JSON.generate(prompt), "stale-request"

    dispatched = nil
    host = driver.instance_variable_get(:@host)
    host.define_singleton_method(:dispatch) do |spec|
      dispatched = spec
      { "job_id" => spec.fetch("job_id"), "status" => "running" }
    end
    step = driver.step
    assert_equal "new-run-astra-3", step["orchestrator_job"]
    actual_prompt = JSON.parse(dispatched.fetch("prompt"))
    actual_feedback = JSON.generate(actual_prompt.fetch("feedback"))
    assert_includes actual_feedback, "versioned_run_continuation"
    assert_includes actual_feedback, "job_completed"
    refute_includes actual_feedback, "stale-request"
  end

  def test_rejects_wrong_source_pin_and_requires_clean_production_target
    error = assert_raises(HrmKernel::Error) { continue_run(source_revision: "0" * 40) }
    assert_match(/declared revision/, error.message)

    target_root = File.realpath(File.expand_path("..", __dir__))
    dirty = File.join(target_root, ".rc36-continuation-dirty-#{Process.pid}")
    File.write(dirty, "test-only\n")
    begin
      error = assert_raises(HrmKernel::Error) { continue_run(production: true) }
      assert_match(/executing target kernel checkout must be clean/, error.message)
    ensure
      File.unlink(dirty) if File.exist?(dirty)
    end
  end

  def test_cli_acceptance_creates_the_new_destination
    destination = File.join(@temporary, "cli-continuation")
    input = File.join(@temporary, "continuation-input.json")
    write_json(input, {
      "new_run_id" => "cli-run", "source_kernel_root" => @kernel,
      "source_kernel_revision" => @source_revision, "controller_stopped" => true,
      "supervisor_provenance" => {
        "schema_version" => "ap-hrm-supervisor-continuation/1",
        "supervisor_id" => "rc36-supervisor", "commission_id" => "cli-commission",
        "asserted_at" => "2026-09-09T12:00:00Z", "source" => "CLI acceptance"
      },
      "production" => false
    })
    script = File.realpath(File.join(__dir__, "..", "scripts", "hrm_kernel.rb"))
    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby, script, "driver-continue", "--state-dir", @source,
      "--destination-state-dir", destination, "--input", input
    )
    assert status.success?, stderr
    result = JSON.parse(stdout)
    assert_equal "cli-run", result["new_run_id"]
    assert_equal @source, result["source_state_dir"]
    assert_equal "cli-run", read_json(File.join(destination, "driver", "config.json"))["run_id"]
  end

  def test_rc36_to_rc37_replaces_environment_with_fresh_preflight_and_historical_jobs
    make_source_kernel_rc36
    prior = File.join(@source, "driver", "continuation")
    HrmKernel::Host.private_directory!(prior)
    write_bytes(File.join(prior, "manifest.json"), "prior RC35 attribution bytes\n")
    write_astra_job("old-run-astra-2", completion: true, live: false)
    write_completed_worker_job("completed-worker")
    supervisor = HrmKernel::SupervisorInput.new(directory: File.join(@source, "driver"))
    2.times do |index|
      supervisor.append({
        "input_id" => "observation-#{index + 1}", "kind" => "technical_observation",
        "source" => { "adapter_id" => "test-adapter", "reference" => "fixture-#{index + 1}" },
        "summary" => "Technical observation #{index + 1}"
      }, observed_cursor: index)
    end
    runtime_path = File.join(@source, "driver", "runtime.json")
    runtime = read_json(runtime_path)
    runtime.merge!(
      "round" => 2, "orchestrator_job" => "old-run-astra-2", "resume_job" => nil,
      "jobs" => ["completed-worker"], "seen_jobs" => [], "history" => [{ "old" => true }],
      "observed_technical_input_cursor" => 1, "orchestrator_technical_input_cursor" => nil,
      "outcome" => "engineering_stalled", "idle_turns" => 2
    )
    write_json(runtime_path, runtime)
    before = byte_snapshot(@source)
    journal = File.binread(File.join(@source, "driver", HrmKernel::SupervisorInput::LEDGER_NAME))

    replacement = replacement_environment
    manifest = continue_run(environment_replacement: replacement)

    assert_equal before, byte_snapshot(@source)
    assert_equal "ap-hrm-run-continuation/2", manifest["schema_version"]
    assert manifest["target_preflight_is_fresh"]
    refute manifest["target_preflight_reverified_for_destination"]
    assert_equal "driver/continuation/rc37", manifest["archive_root"]
    assert_equal journal, File.binread(File.join(@destination, "driver", HrmKernel::SupervisorInput::LEDGER_NAME))
    assert_equal "prior RC35 attribution bytes\n", File.binread(File.join(@destination, "driver", "continuation", "manifest.json"))
    assert_equal replacement, read_json(File.join(@destination, "driver", "config.json")).slice(*HrmKernel::RunContinuation::ENVIRONMENT_FIELDS)
    config = read_json(File.join(@destination, "driver", "config.json"))
    continued = read_json(File.join(@destination, "driver", "runtime.json"))
    assert_equal [], continued["jobs"]
    assert_equal [], continued["seen_jobs"]
    assert_equal [], continued["history"]
    assert_nil continued["orchestrator_job"]
    assert_equal "old-run-astra-2", continued["resume_job"]
    assert_equal "old-run-astra-2", continued["last_orchestrator_job"]
    assert_equal 1, continued["observed_technical_input_cursor"]
    assert_nil continued["orchestrator_technical_input_cursor"]
    assert_equal "active", continued["outcome"]
    historical = continued.fetch("historical_environment")
    assert_equal ["old-run-astra-2", "completed-worker"], historical["jobs"].map { |job| job["job_id"] }
    refute historical["old_checks_eligible_for_new_claims"]
    assert_equal ["completed-worker"], historical.dig("work_orders", 0, "historical_resume_job_ids")
    assert_equal "resume_same_claim_under_active_environment_or_release_then_rebind",
      historical.dig("work_orders", 0, "required_action")
    assert_equal historical.slice("source_environment_id", "active_environment_id", "source_environment_sha256",
      "active_environment_sha256", "old_checks_eligible_for_new_claims").merge(
        "historical_job_ids" => ["old-run-astra-2", "completed-worker"], "fresh_preflight_required" => true
      ), config.dig("continuation", "environment_transition")
    target_preflight = read_json(File.join(@destination, "driver", "preflight.json"))
    assert_equal false, target_preflight.dig(0, "execution", "reused")
    assert_equal "passed", target_preflight.dig(0, "execution", "conclusion")
    refute_equal read_json(File.join(@source, "driver", "preflight.json")).dig(0, "execution", "receipt_sha256"),
      target_preflight.dig(0, "execution", "receipt_sha256")
    assert_equal ["observation-2"], HrmKernel::SupervisorInput.new(
      directory: File.join(@destination, "driver")
    ).read_after(continued["observed_technical_input_cursor"]).fetch("records").map { |record| record.dig("input", "input_id") }
    HrmKernel::Driver.new(state_dir: @destination).send(:verify_environment!, config)
    assert_equal manifest, continue_run(environment_replacement: replacement)

    receipt_path = File.join(@destination, target_preflight.dig(0, "execution", "receipt_path"))
    write_bytes(receipt_path, File.binread(receipt_path).sub("passed", "failed"))
    error = assert_raises(HrmKernel::Error) { continue_run(environment_replacement: replacement) }
    assert_match(/authentication|receipt|preflight|digest/, error.message)
  end

  def test_rc36_to_rc37_environment_replacement_fails_closed
    make_source_kernel_rc36
    error = assert_raises(HrmKernel::Error) { continue_run }
    assert_match(/requires environment_replacement/, error.message)

    same = replacement_environment.merge("environment_id" => "test")
    same["preflight_checks"][0]["environment_id"] = "test"
    error = assert_raises(HrmKernel::Error) { continue_run(environment_replacement: same) }
    assert_match(/must differ/, error.message)

    unsafe = replacement_environment.merge("read_roots" => [@source])
    error = assert_raises(HrmKernel::Error) { continue_run(environment_replacement: unsafe) }
    assert_match(/protected continuation state/, error.message)

    widened = replacement_environment.merge("runner" => "untrusted")
    error = assert_raises(HrmKernel::Error) { continue_run(environment_replacement: widened) }
    assert_match(/fields are invalid/, error.message)

    state = @store.read.fetch("state")
    completed_state = JSON.parse(JSON.generate(state))
    completed_state["work_orders"]["old"] = { "id" => "old", "status" => "completed" }
    continuation = HrmKernel::RunContinuation.allocate
    error = assert_raises(HrmKernel::Error) { continuation.send(:reject_old_environment_completion!, completed_state) }
    assert_match(/completed work orders/, error.message)

    reviewed_state = JSON.parse(JSON.generate(state))
    reviewed_state["reviews"]["old"] = { "id" => "old" }
    error = assert_raises(HrmKernel::Error) { continuation.send(:reject_old_environment_completion!, reviewed_state) }
    assert_match(/review or assessment/, error.message)

    HrmKernel::Host.private_directory!(File.join(@source, "driver", "continuation", "rc37"))
    error = assert_raises(HrmKernel::Error) do
      continue_run(environment_replacement: replacement_environment)
    end
    assert_match(/archive already exists/, error.message)
  end

  def test_cli_accepts_explicit_rc37_environment_replacement
    make_source_kernel_rc36
    destination = File.join(@temporary, "cli-rc37-continuation")
    input = File.join(@temporary, "rc37-continuation-input.json")
    write_json(input, {
      "new_run_id" => "cli-rc37-run", "source_kernel_root" => @kernel,
      "source_kernel_revision" => @source_revision, "controller_stopped" => true,
      "supervisor_provenance" => {
        "schema_version" => "ap-hrm-supervisor-continuation/1",
        "supervisor_id" => "rc37-supervisor", "commission_id" => "cli-rc37-commission",
        "asserted_at" => "2026-09-09T12:00:00Z", "source" => "CLI RC37 acceptance"
      },
      "environment_replacement" => replacement_environment,
      "production" => false
    })
    script = File.realpath(File.join(__dir__, "..", "scripts", "hrm_kernel.rb"))
    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby, script, "driver-continue", "--state-dir", @source,
      "--destination-state-dir", destination, "--input", input
    )
    assert status.success?, stderr
    result = JSON.parse(stdout)
    assert_equal "ap-hrm-run-continuation/2", result["schema_version"]
    assert result["target_preflight_is_fresh"]
    assert_equal "test-rc37", read_json(File.join(destination, "driver", "config.json"))["environment_id"]
    assert File.file?(File.join(destination, "driver", "continuation", "rc37", "manifest.json"))
  end

  def test_failed_fresh_preflight_leaves_source_unchanged_and_no_destination
    make_source_kernel_rc36
    before = byte_snapshot(@source)
    replacement = replacement_environment
    replacement["preflight_checks"][0]["argv"] = [File.realpath(RbConfig.ruby), "-e", "exit 1"]

    error = assert_raises(HrmKernel::Error) { continue_run(environment_replacement: replacement) }

    assert_match(/preflight did not pass/, error.message)
    assert_equal before, byte_snapshot(@source)
    refute File.exist?(@destination)
  end

  def test_rc37_to_rc38_preserves_completed_submission_and_budget_but_requires_fresh_validation
    make_source_kernel_rc36
    rc37 = File.join(@temporary, "rc37-state")
    continue_run(destination: rc37, new_run_id: "rc37-run", environment_replacement: replacement_environment)
    @source = rc37
    @destination = File.join(@temporary, "rc38-state")
    historical = complete_rc37_contribution(unrelated_candidate: true)
    File.write(File.join(@project, "sibling.txt"), "later authorized order version\n")
    runtime_path = File.join(@source, "driver", "runtime.json")
    runtime = read_json(runtime_path)
    runtime.merge!("round" => 2, "outcome" => "active", "resume_job" => nil,
      "orchestrator_job" => nil, "last_orchestrator_job" => nil)
    write_json(runtime_path, runtime)
    make_source_kernel_rc37
    restored_source = byte_snapshot(@source)

    original_artifact = File.binread(File.join(@project, "app.txt"))
    File.write(File.join(@project, "app.txt"), "tampered owned artifact\n")
    own_error = assert_raises(HrmKernel::Error) do
      continue_run(destination: File.join(@temporary, "own-tamper-destination"), new_run_id: "own-tamper",
        environment_replacement: replacement_environment_rc38)
    end
    assert_match(/evidence digest mismatch/, own_error.message)
    File.binwrite(File.join(@project, "app.txt"), original_artifact)

    receipt_path = File.join(@source, historical.fetch("receipt_path"))
    original_receipt = File.binread(receipt_path)
    File.binwrite(receipt_path, original_receipt + " ")
    receipt_error = assert_raises(HrmKernel::Error) do
      continue_run(destination: File.join(@temporary, "receipt-tamper-destination"), new_run_id: "receipt-tamper",
        environment_replacement: replacement_environment_rc38)
    end
    assert_match(/digest mismatch/, receipt_error.message)
    File.binwrite(receipt_path, original_receipt)
    assert_equal restored_source, byte_snapshot(@source)
    before_ledger = File.binread(File.join(@source, "events.jsonl"))

    manifest = continue_run(new_run_id: "rc38-run", environment_replacement: replacement_environment_rc38)

    assert_equal "ap-hrm-run-continuation/3", manifest["schema_version"]
    assert_equal before_ledger, File.binread(File.join(@destination, "events.jsonl"))
    assert_equal "driver/continuation/rc38", manifest["archive_root"]
    assert_nil manifest["resumed_astra_job_id"]
    config = read_json(File.join(@destination, "driver", "config.json"))
    continued = read_json(File.join(@destination, "driver", "runtime.json"))
    assert_equal "test-rc38", config["environment_id"]
    assert_equal HrmKernel::Execution::LEGACY_REPOSITORY_VIEW_SCHEMA, config.dig("check_repository", "schema_version")
    assert_equal 2, continued["round"]
    assert_equal 3, config["max_turns"]
    assert_nil continued["resume_job"]
    assert_nil continued["last_orchestrator_job"]
    assert_equal [], continued["jobs"]
    order = HrmKernel::Store.new(@destination).read.dig("state", "work_orders", "submitted")
    assert_equal "completed", order["status"]
    assert_equal 1, order["revision"]
    assert_empty order["evidence_history"]
    transition = config.dig("continuation", "environment_transition")
    assert_equal ["submitted"], transition.fetch("completed_contributions").map { |item| item["work_order_id"] }
    projection = HrmKernel::Store.new(@destination).project(role: "orchestrator").fetch("projection")
    assert_equal ["submitted"], projection.dig("technical_validation", "pending_work_order_ids")
    assert_includes projection.dig("milestone", "readiness_blockers").map { |item| item["kind"] }, "fresh_environment_validation"
    assert_equal [], continued.dig("historical_environment", "work_orders", 0, "historical_resume_job_ids")
    assert_equal "fresh_native_revalidation_under_active_environment",
      continued.dig("historical_environment", "work_orders", 0, "required_action")
    assert_equal manifest, continue_run(new_run_id: "rc38-run", environment_replacement: replacement_environment_rc38)
  end

  def test_rc37_to_rc38_accepts_authenticated_explicit_pytest_basetemp_scratch_without_mutating_source
    make_source_kernel_rc36
    rc37 = File.join(@temporary, "scratch-source-rc37")
    continue_run(destination: rc37, new_run_id: "scratch-source-rc37", environment_replacement: replacement_environment)
    @source = rc37
    @destination = File.join(@temporary, "scratch-target-rc38")
    make_source_kernel_rc37

    run = File.join(@source, "execution", "d" * 64)
    test_root = File.join(run, "pytest", "test_binding_fails_closed_for_0")
    documents = File.join(run, "Documents")
    FileUtils.mkdir_p(test_root, mode: 0o700)
    FileUtils.mkdir_p(documents, mode: 0o755)
    File.chmod(0o700, run)
    File.chmod(0o700, File.join(run, "pytest"))
    File.chmod(0o700, test_root)
    File.chmod(0o755, documents)
    authenticate_test_execution_run(run)
    database = File.join(test_root, "intake.sqlite3")
    write_bytes(database, "historical sqlite scratch\0".b)
    File.chmod(0o644, database)
    executable = File.join(test_root, "fixture-command")
    write_bytes(executable, "#!/bin/sh\nexit 0\n")
    File.chmod(0o755, executable)
    current = File.join(test_root, "active-intake.sqlite3")
    File.symlink(database, current)
    source_bytes = byte_snapshot(@source)
    source_modes = mode_snapshot(@source)

    manifest = continue_run(new_run_id: "scratch-target-rc38", environment_replacement: replacement_environment_rc38)

    assert_equal source_bytes, byte_snapshot(@source)
    assert_equal source_modes, mode_snapshot(@source)
    assert_equal ["d" * 64], manifest.fetch("authenticated_execution_scratch_run_ids")
    assert_equal "source_modes_recorded_destination_files_0600_directories_0700",
      manifest.fetch("execution_scratch_mode_transformation")
    target_database = File.join(@destination, database.delete_prefix(@source + "/"))
    target_executable = File.join(@destination, executable.delete_prefix(@source + "/"))
    assert_equal "historical sqlite scratch\0".b, File.binread(target_database)
    assert_equal 0o600, File.stat(target_database).mode & 0o777
    assert_equal 0o600, File.stat(target_executable).mode & 0o777
    assert_equal 0o700, File.stat(File.join(@destination, documents.delete_prefix(@source + "/"))).mode & 0o777
    refute File.exist?(File.join(@destination, current.delete_prefix(@source + "/")))
    assert_includes manifest.fetch("inert_execution_scratch_links").map { |entry| entry["path"] },
      current.delete_prefix(@source + "/")
  end

  def test_cli_accepts_rc38_isolated_repository_environment
    make_source_kernel_rc36
    rc37 = File.join(@temporary, "cli-source-rc37")
    continue_run(destination: rc37, new_run_id: "cli-source-rc37", environment_replacement: replacement_environment)
    @source = rc37
    @destination = File.join(@temporary, "cli-target-rc38")
    make_source_kernel_rc37
    input = File.join(@temporary, "rc38-continuation-input.json")
    write_json(input, {
      "new_run_id" => "cli-target-rc38", "source_kernel_root" => @kernel,
      "source_kernel_revision" => @source_revision, "controller_stopped" => true,
      "supervisor_provenance" => {
        "schema_version" => "ap-hrm-supervisor-continuation/1", "supervisor_id" => "rc38-supervisor",
        "commission_id" => "cli-rc38-commission", "asserted_at" => "2026-09-10T12:00:00Z",
        "source" => "CLI RC38 acceptance"
      },
      "environment_replacement" => replacement_environment_rc38, "production" => false
    })
    script = File.realpath(File.join(__dir__, "..", "scripts", "hrm_kernel.rb"))
    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby, script, "driver-continue", "--state-dir", @source,
      "--destination-state-dir", @destination, "--input", input
    )
    assert status.success?, stderr
    result = JSON.parse(stdout)
    assert_equal "ap-hrm-run-continuation/3", result["schema_version"]
    assert_equal "test-rc38", read_json(File.join(@destination, "driver", "config.json"))["environment_id"]
    assert File.file?(File.join(@destination, "driver", "continuation", "rc38", "manifest.json"))
  end

  def test_rc38_to_rc39_archives_receiptless_pytest_failure_without_claiming_an_exit
    make_source_kernel_rc36
    rc37 = File.join(@temporary, "incomplete-source-rc37")
    continue_run(destination: rc37, new_run_id: "incomplete-source-rc37",
      environment_replacement: replacement_environment)
    @source = rc37
    rc38 = File.join(@temporary, "incomplete-source-rc38")
    @destination = rc38
    make_source_kernel_rc37
    complete_rc37_contribution
    continue_run(destination: rc38, new_run_id: "incomplete-source-rc38",
      environment_replacement: replacement_environment_rc38)
    @source = rc38
    @destination = File.join(@temporary, "incomplete-target-rc39")
    make_source_kernel_rc38

    runtime_path = File.join(@source, "driver", "runtime.json")
    runtime = read_json(runtime_path)
    runtime["round"] = 2
    write_json(runtime_path, runtime)
    request_id = "rc38-t20-revalidate-fixture"
    request_root = File.join(@source, "driver", "requests", request_id)
    FileUtils.mkdir_p(request_root, mode: 0o700)
    write_json(File.join(request_root, "request.json"), {
      "request_id" => request_id, "operation" => "revalidate", "input_json" => "{}"
    })
    write_json(File.join(request_root, "receipt.json"), {
      "request_id" => request_id, "operation" => "revalidate", "ok" => false,
      "error" => "execution scratch contains a symlink or special file"
    })
    run_id = "f" * 64
    run = File.join(@source, "execution", run_id)
    candidate = File.join(run, "candidate")
    test_root = File.join(run, "pytest-of-unknown", "pytest-0", "test_binding_fails_closed_for_0")
    FileUtils.mkdir_p(File.join(candidate, ".git"), mode: 0o700)
    FileUtils.mkdir_p(test_root, mode: 0o755)
    File.chmod(0o700, run)
    File.chmod(0o755, File.join(run, "pytest-of-unknown"))
    File.chmod(0o755, File.join(run, "pytest-of-unknown", "pytest-0"))
    database = File.join(test_root, "intake.sqlite3")
    write_bytes(database, "failed-attempt scratch\0".b)
    File.chmod(0o644, database)
    current = File.join(run, "pytest-of-unknown", "pytest-current")
    File.symlink(File.join(run, "pytest-of-unknown", "pytest-0"), current)
    source_bytes = byte_snapshot(@source)
    source_modes = mode_snapshot(@source)
    source_ledger = File.binread(File.join(@source, HrmKernel::Store::LEDGER_NAME))
    source_state = HrmKernel::Store.new(@source).read.fetch("state")

    input = File.join(@temporary, "rc39-continuation-input.json")
    write_json(input, {
      "new_run_id" => "incomplete-target-rc39", "source_kernel_root" => @kernel,
      "source_kernel_revision" => @source_revision, "controller_stopped" => true,
      "supervisor_provenance" => {
        "schema_version" => "ap-hrm-supervisor-continuation/1",
        "supervisor_id" => "rc39-supervisor", "commission_id" => "rc39-cli-commission",
        "asserted_at" => "2026-09-10T12:00:00Z", "source" => "RC39 CLI fixture"
      },
      "environment_replacement" => replacement_environment_rc39, "production" => false
    })
    script = File.realpath(File.join(__dir__, "..", "scripts", "hrm_kernel.rb"))
    stdout, stderr, status = Open3.capture3(
      RbConfig.ruby, script, "driver-continue", "--state-dir", @source,
      "--destination-state-dir", @destination, "--input", input
    )
    assert status.success?, stderr
    manifest = JSON.parse(stdout)

    assert_equal source_bytes, byte_snapshot(@source)
    assert_equal source_modes, mode_snapshot(@source)
    assert_equal source_ledger, File.binread(File.join(@destination, HrmKernel::Store::LEDGER_NAME))
    assert_equal source_state, HrmKernel::Store.new(@destination).read.fetch("state")
    assert_equal "ap-hrm-run-continuation/4", manifest.fetch("schema_version")
    assert_equal "driver/continuation/rc39", manifest.fetch("archive_root")
    assert_equal false, manifest.fetch("incomplete_execution_evidence_eligible")
    assert_equal [{
      "run_id" => run_id, "receipt_present" => false,
      "process_exit_known" => false, "evidence_eligible" => false
    }], manifest.fetch("incomplete_failed_execution_attempts")
    assert_equal [request_id], manifest.fetch("failed_scratch_driver_request_ids")
    target_database = File.join(@destination, database.delete_prefix(@source + "/"))
    assert_equal "failed-attempt scratch\0".b, File.binread(target_database)
    assert_equal 0o600, File.stat(target_database).mode & 0o777
    refute File.exist?(File.join(@destination, current.delete_prefix(@source + "/")))
    continued = read_json(File.join(@destination, "driver", "runtime.json"))
    continued_config = read_json(File.join(@destination, "driver", "config.json"))
    assert_equal 2, continued.fetch("round")
    assert_equal 3, continued_config.fetch("max_turns")
    assert_equal [], continued.fetch("jobs")
    assert_nil continued["resume_job"]
    assert_nil continued["last_orchestrator_job"]
    assert File.file?(File.join(@destination, "driver", "continuation", "rc39", "manifest.json"))

    @source = @destination
    @destination = File.join(@temporary, "incomplete-target-rc40")
    make_source_kernel_rc39
    rc40 = continue_run(new_run_id: "incomplete-target-rc40",
      environment_replacement: replacement_environment_rc40)
    assert_equal "ap-hrm-run-continuation/5", rc40.fetch("schema_version")
    assert_equal manifest.fetch("incomplete_failed_execution_attempts"),
      rc40.fetch("incomplete_failed_execution_attempts")
    assert_equal manifest.fetch("failed_scratch_driver_request_ids"),
      rc40.fetch("failed_scratch_driver_request_ids")
    assert_equal false, rc40.fetch("incomplete_execution_evidence_eligible")

    @source = @destination
    @destination = File.join(@temporary, "incomplete-target-rc41")
    make_source_kernel_rc40
    rc41 = continue_run(new_run_id: "incomplete-target-rc41",
      environment_replacement: replacement_environment_rc41)
    assert_equal "ap-hrm-run-continuation/6", rc41.fetch("schema_version")
    assert_equal rc40.fetch("incomplete_failed_execution_attempts"),
      rc41.fetch("incomplete_failed_execution_attempts")
    assert_equal rc40.fetch("failed_scratch_driver_request_ids"),
      rc41.fetch("failed_scratch_driver_request_ids")
  end

  def test_rc38_receiptless_nonprivate_scratch_requires_recorded_cleanup_failure
    make_source_kernel_rc36
    rc37 = File.join(@temporary, "unattributed-source-rc37")
    continue_run(destination: rc37, new_run_id: "unattributed-source-rc37",
      environment_replacement: replacement_environment)
    @source = rc37
    @destination = File.join(@temporary, "unattributed-source-rc38")
    make_source_kernel_rc37
    continue_run(destination: @destination, new_run_id: "unattributed-source-rc38",
      environment_replacement: replacement_environment_rc38)
    @source = @destination
    @destination = File.join(@temporary, "unattributed-target-rc39")
    make_source_kernel_rc38
    run = File.join(@source, "execution", "e" * 64)
    FileUtils.mkdir_p(File.join(run, "candidate", ".git"), mode: 0o700)
    scratch = File.join(run, "pytest-of-unknown", "pytest-0")
    FileUtils.mkdir_p(scratch, mode: 0o755)
    File.chmod(0o700, run)
    File.chmod(0o755, File.join(run, "pytest-of-unknown"))
    File.chmod(0o755, scratch)

    error = assert_raises(HrmKernel::Error) do
      continue_run(new_run_id: "unattributed-target-rc39",
        environment_replacement: replacement_environment_rc39)
    end
    assert_match(/recorded failed Driver cleanup request/, error.message)
    refute File.exist?(@destination)

    FileUtils.remove_entry(run)
    request_id = "rc38-cleanup-without-scratch"
    request_root = File.join(@source, "driver", "requests", request_id)
    FileUtils.mkdir_p(request_root, mode: 0o700)
    write_json(File.join(request_root, "request.json"), {
      "request_id" => request_id, "operation" => "revalidate", "input_json" => "{}"
    })
    write_json(File.join(request_root, "receipt.json"), {
      "request_id" => request_id, "operation" => "revalidate", "ok" => false,
      "error" => "execution scratch contains a symlink or special file"
    })
    error = assert_raises(HrmKernel::Error) do
      continue_run(new_run_id: "unattributed-target-rc39",
        environment_replacement: replacement_environment_rc39)
    end
    assert_match(/count differs/, error.message)
    refute File.exist?(@destination)
  end

  def test_rc39_to_rc40_preserves_amended_history_and_derives_lineage_after_later_amendments
    config_path = File.join(@source, "driver", "config.json")
    config = read_json(config_path)
    config["max_turns"] = 40
    write_json(config_path, config)
    make_source_kernel_rc36
    rc37 = File.join(@temporary, "history-source-rc37")
    continue_run(destination: rc37, new_run_id: "history-source-rc37",
      environment_replacement: replacement_environment)

    @source = rc37
    rc38 = File.join(@temporary, "history-source-rc38")
    @destination = rc38
    complete_rc37_contribution
    make_source_kernel_rc37
    continue_run(destination: rc38, new_run_id: "history-source-rc38",
      environment_replacement: replacement_environment_rc38)

    @source = rc38
    rc39 = File.join(@temporary, "history-source-rc39")
    @destination = rc39
    make_source_kernel_rc38
    continue_run(destination: rc39, new_run_id: "history-source-rc39",
      environment_replacement: replacement_environment_rc39)

    @source = rc39
    @destination = File.join(@temporary, "history-target-rc40")
    make_source_kernel_rc39
    store = HrmKernel::Store.new(@source)
    store.transact(
      "command_id" => "amend-submitted-r2", "type" => "work_order.amend",
      "actor" => { "id" => "astra-orchestrator", "role" => "orchestrator" },
      "data" => { "work_order_id" => "submitted", "intent_id" => "milestone_initial",
        "objective" => "Expand the completed contribution contract", "requirement_ids" => ["behavior"],
        "paths" => ["app.txt", "sibling.txt"], "check_ids" => ["check"], "expected_revision" => 1 }
    )
    runtime_path = File.join(@source, "driver", "runtime.json")
    runtime = read_json(runtime_path)
    supervisor = HrmKernel::SupervisorInput.new(directory: File.join(@source, "driver"))
    2.times do |index|
      supervisor.append({
        "input_id" => "rc40-observation-#{index + 1}", "kind" => "technical_observation",
        "source" => { "adapter_id" => "test-adapter", "reference" => "rc40-#{index + 1}" },
        "summary" => "RC40 technical observation #{index + 1}"
      }, observed_cursor: index.zero? ? 0 : 1)
    end
    runtime.merge!("round" => 22, "observed_technical_input_cursor" => 1,
      "orchestrator_technical_input_cursor" => nil)
    write_json(runtime_path, runtime)
    request_id = "failed-host-dispatch"
    request_root = File.join(@source, "driver", "requests", request_id)
    FileUtils.mkdir_p(request_root, mode: 0o700)
    write_json(File.join(request_root, "request.json"), {
      "request_id" => request_id, "operation" => "dispatch", "input_json" => "{}"
    })
    write_json(File.join(request_root, "receipt.json"), {
      "request_id" => request_id, "operation" => "dispatch", "ok" => false,
      "error" => "native host dispatch failed"
    })
    source_ledger = File.binread(File.join(@source, HrmKernel::Store::LEDGER_NAME))
    source_state = store.read.fetch("state")
    source_journal = File.binread(File.join(@source, "driver", HrmKernel::SupervisorInput::LEDGER_NAME))

    manifest = continue_run(new_run_id: "history-target-rc40",
      environment_replacement: replacement_environment_rc40)

    assert_equal "ap-hrm-run-continuation/5", manifest.fetch("schema_version")
    assert_equal "driver/continuation/rc40", manifest.fetch("archive_root")
    assert_equal source_ledger, File.binread(File.join(@destination, HrmKernel::Store::LEDGER_NAME))
    assert_equal source_state, HrmKernel::Store.new(@destination).read.fetch("state")
    assert_equal source_journal,
      File.binread(File.join(@destination, "driver", HrmKernel::SupervisorInput::LEDGER_NAME))
    assert File.file?(File.join(@destination, "driver", "requests", request_id, "receipt.json"))
    target_config = read_json(File.join(@destination, "driver", "config.json"))
    target_runtime = read_json(File.join(@destination, "driver", "runtime.json"))
    assert_equal 40, target_config.fetch("max_turns")
    assert_equal 22, target_runtime.fetch("round")
    assert_equal 1, target_runtime.fetch("observed_technical_input_cursor")
    assert_equal 2, manifest.fetch("supervisor_input_cursor")
    assert_equal 1, manifest.fetch("acknowledged_supervisor_input_cursor")
    assert_equal [], target_runtime.fetch("jobs")
    assert_nil target_runtime["resume_job"]
    contributions = target_config.dig("continuation", "environment_transition", "completed_contributions")
    assert_equal [1], contributions.map { |entry| entry.fetch("revision") }
    assert_equal HrmKernel::ContributionHistory::KEYS.sort, contributions.fetch(0).keys.sort

    driver = HrmKernel::Driver.new(state_dir: @destination)
    transition = driver.send(:environment_transition, target_config, target_runtime)
    status = transition.fetch("contribution_statuses").fetch(0)
    assert_equal "superseded_by_work_order_revision", status.fetch("current_disposition")
    assert_equal 2, status.fetch("current_revision")

    target_store = HrmKernel::Store.new(@destination)
    target_store.transact(
      "command_id" => "amend-submitted-r3", "type" => "work_order.amend",
      "actor" => { "id" => "astra-orchestrator", "role" => "orchestrator" },
      "data" => { "work_order_id" => "submitted", "intent_id" => "milestone_initial",
        "objective" => "Revise the active contract again", "requirement_ids" => ["behavior"],
        "paths" => ["app.txt", "sibling.txt"], "check_ids" => ["check"], "expected_revision" => 2 }
    )
    target_store.transact(
      "command_id" => "claim-submitted-r3", "type" => "work_order.claim",
      "actor" => { "id" => "worker-new-owner", "role" => "worker" },
      "data" => { "work_order_id" => "submitted", "revision" => 3, "claim_id" => "claim-submitted-r3" }
    )
    later = driver.send(:environment_transition, target_config, target_runtime)
    later_status = later.fetch("contribution_statuses").fetch(0)
    assert_equal "superseded_by_work_order_revision", later_status.fetch("current_disposition")
    assert_equal 3, later_status.fetch("current_revision")
    assert_equal "running", later_status.fetch("current_status")
    current = target_store.read.dig("state", "work_orders", "submitted")
    assert_nil current["evidence_digest"]
    assert_empty current["artifacts"]
    assert_equal "worker-new-owner", current["last_owner_id"]
    assert_equal [1, 2], current.fetch("amendments").map { |entry| entry.fetch("revision") }
    prompt = driver.send(:environment_transition_prompt, target_config, target_runtime)
    assert_equal "superseded_by_work_order_revision",
      prompt.fetch("historical_contribution_statuses").fetch(0).fetch("current_disposition")
    assert_match(/current amended revision/, prompt.fetch("required_handling"))

    tampered = JSON.parse(JSON.generate(contributions))
    tampered.fetch(0)["evidence_digest"] = "0" * 64
    error = assert_raises(HrmKernel::Error) do
      HrmKernel::ContributionHistory.verify!(tampered,
        state: target_store.read.fetch("state"), commands: target_store.verified_commands)
    end
    assert_match(/absent from the verified ledger/, error.message)

    @source = @destination
    @destination = File.join(@temporary, "history-target-rc41")
    make_source_kernel_rc40
    ledger_before_rc41 = File.binread(File.join(@source, HrmKernel::Store::LEDGER_NAME))
    state_before_rc41 = target_store.read.fetch("state")
    legacy_environment = replacement_environment_rc41
    legacy_environment.fetch("check_repository")["schema_version"] =
      HrmKernel::Execution::LEGACY_REPOSITORY_VIEW_SCHEMA
    error = assert_raises(HrmKernel::Error) do
      continue_run(destination: File.join(@temporary, "legacy-repository-rc41"),
        new_run_id: "legacy-repository-rc41", environment_replacement: legacy_environment)
    end
    assert_match(/repository schema is unsupported/, error.message)
    rc41 = continue_run(new_run_id: "history-target-rc41",
      environment_replacement: replacement_environment_rc41)
    assert_equal "ap-hrm-run-continuation/6", rc41.fetch("schema_version")
    assert_equal "driver/continuation/rc41", rc41.fetch("archive_root")
    assert_equal ledger_before_rc41, File.binread(File.join(@destination, HrmKernel::Store::LEDGER_NAME))
    assert_equal state_before_rc41, HrmKernel::Store.new(@destination).read.fetch("state")
    rc41_runtime = read_json(File.join(@destination, "driver", "runtime.json"))
    assert_equal 22, rc41_runtime.fetch("round")
    assert_equal [], rc41_runtime.fetch("jobs")
    assert_nil rc41_runtime["resume_job"]
  end

  def test_historical_attempt_order_uses_dispatch_order_not_job_names
    source = {
      "environment_replacement" => { "environment_id" => "new" },
      "config" => { "environment_id" => "old" },
      "runtime" => { "jobs" => %w[z-first a-latest] },
      "statuses" => {
        "a-latest" => { "job_id" => "a-latest" },
        "z-first" => { "job_id" => "z-first" }
      }
    }
    record = HrmKernel::RunContinuation.allocate.send(:environment_transition_record, source)
    assert_equal %w[z-first a-latest], record["historical_job_ids"]
    assert_equal "a-latest", record["historical_jobs"].last["job_id"]
  end

  def test_rc41_continuation_bound_accepts_measured_sustained_run_volume_and_remains_bounded
    continuation = HrmKernel::RunContinuation.allocate

    assert continuation.send(:validate_total_bytes!, 1_103_006_753)
    assert continuation.send(:validate_total_bytes!, HrmKernel::RunContinuation::MAX_TOTAL_BYTES)
    error = assert_raises(HrmKernel::Error) do
      continuation.send(:validate_total_bytes!, HrmKernel::RunContinuation::MAX_TOTAL_BYTES + 1)
    end
    assert_match(/continuation byte bound/, error.message)
    assert continuation.send(:validate_entry_count!, 54_018)
    assert continuation.send(:validate_entry_count!, HrmKernel::RunContinuation::MAX_ENTRIES)
    error = assert_raises(HrmKernel::Error) do
      continuation.send(:validate_entry_count!, HrmKernel::RunContinuation::MAX_ENTRIES + 1)
    end
    assert_match(/too many entries/, error.message)
    assert_equal 2 * 1024 * 1024 * 1024, HrmKernel::RunContinuation::MAX_TOTAL_BYTES
    assert_equal 100_000, HrmKernel::RunContinuation::MAX_ENTRIES
    assert continuation.send(:validate_generated_manifest_bytes!, 17_301_812)
    error = assert_raises(HrmKernel::Error) do
      continuation.send(:validate_generated_manifest_bytes!,
        HrmKernel::RunContinuation::MAX_GENERATED_MANIFEST_BYTES + 1)
    end
    assert_match(/generated source tree manifest/, error.message)
    assert_equal 64 * 1024 * 1024, HrmKernel::RunContinuation::MAX_GENERATED_MANIFEST_BYTES
    assert_equal HrmKernel::RunContinuation::MAX_FILE_BYTES,
      continuation.send(:source_entry_max_bytes, "untrusted/source-manifest.json")
  end

  def test_full_clone_authenticates_generated_manifest_above_ordinary_file_bound
    padding = File.join(@source, "driver", "bounded-manifest-fixture")
    FileUtils.mkdir_p(padding, mode: 0o700)
    800.times do |index|
      write_bytes(File.join(padding, "entry-#{index.to_s.rjust(4, '0')}-#{'x' * 64}.txt"), "x\n")
    end
    source_before = byte_snapshot(@source)
    ordinary_bound = 64 * 1024
    largest_source_file = source_before.keys.map { |relative| File.size(File.join(@source, relative)) }.max
    assert_operator largest_source_file, :<, ordinary_bound

    klass = HrmKernel::RunContinuation
    original = klass::MAX_FILE_BYTES
    klass.send(:remove_const, :MAX_FILE_BYTES)
    klass.const_set(:MAX_FILE_BYTES, ordinary_bound)
    begin
      manifest = continue_run
      source_manifest_path = File.join(@destination, manifest.fetch("source_manifest_path"))
      bytes = File.binread(source_manifest_path)
      assert_operator bytes.bytesize, :>, ordinary_bound
      assert_operator bytes.bytesize, :<=, klass::MAX_GENERATED_MANIFEST_BYTES
      assert_equal JSON.generate(JSON.parse(bytes)) + "\n", bytes
      assert_equal source_before, byte_snapshot(@source)
      assert_equal "x\n", File.binread(File.join(@destination,
        "driver", "bounded-manifest-fixture", "entry-0799-#{'x' * 64}.txt"))
      assert_equal manifest, continue_run
    ensure
      klass.send(:remove_const, :MAX_FILE_BYTES)
      klass.const_set(:MAX_FILE_BYTES, original)
    end
  end

  private

  def create_source_state
    @store = HrmKernel::Store.new(@source)
    @store.transact(
      "command_id" => "initial", "type" => "milestone.create",
      "actor" => { "id" => "human", "role" => "operator" },
      "data" => {
        "milestone_id" => "continuation-test", "outcome" => "Preserve behavior",
        "project_root" => @project, "mode" => "implementation",
        "requirements" => [{ "id" => "behavior", "text" => "Behavior remains correct" }],
        "allowed_paths" => ["app.txt", "sibling.txt"],
        "acceptance_scenarios" => [{ "id" => "scenario", "text" => "Behavior works",
          "requirement_ids" => ["behavior"], "check_ids" => ["check"] }]
      }
    )
    driver = File.join(@source, "driver")
    HrmKernel::Host.private_directory!(driver)
    File.open(File.join(driver, ".lock"), File::RDWR | File::CREAT, 0o600) {}
    sentinel = File.join(driver, "isolation-sentinel.txt")
    write_bytes(sentinel, "Private harmless preflight sentinel.\n")
    preflight_spec = {
      "id" => "ruby", "environment_id" => "test",
      "argv" => [File.realpath(RbConfig.ruby), "-e", 'puts "runtime ready"'],
      "env" => {}, "cwd" => @project, "timeout_seconds" => 10,
      "max_output_bytes" => 16_384, "configuration_paths" => []
    }
    config = {
      "run_id" => "old-run", "prompt" => "Original task", "project_root" => @project,
      "environment_id" => "test", "read_roots" => [], "environment_allowlist" => [],
      "forbidden_roots" => [@source], "preflight_checks" => [preflight_spec],
      "max_turns" => 3, "max_parallel_workers" => 1
    }
    runtime = {
      "round" => 1, "jobs" => [], "seen_jobs" => [], "history" => [],
      "orchestrator_job" => nil, "resume_job" => nil, "feedback" => [],
      "observed_cursor" => @store.read["cursor"], "idle_turns" => 0, "outcome" => "active"
    }
    write_json(File.join(driver, "config.json"), config)
    write_json(File.join(driver, "runtime.json"), runtime)
    execution = HrmKernel::Execution.new(
      project_root: @project, state_dir: @source,
      forbidden_read_path: sentinel, forbidden_write_path: sentinel
    )
    descriptor = execution.preflight(spec: preflight_spec)
    write_json(File.join(driver, "preflight.json"), [{ "id" => "ruby", "execution" => descriptor }])
    HrmKernel::Host.new(state_dir: @source)
  end

  def reset_source
    FileUtils.remove_entry(@source) if File.exist?(@source)
    FileUtils.remove_entry(@destination) if File.exist?(@destination)
    create_source_state
  end

  def write_astra_job(job_id, completion:, live:)
    directory = File.join(@source, "host-jobs", job_id)
    HrmKernel::Host.private_directory!(directory)
    state = @store.read.fetch("state")
    spec = {
      "job_id" => job_id, "role" => "orchestrator", "model" => "gpt-6-astra",
      "prompt" => "stale prompt", "context_paths" => [], "max_context_bytes" => 65_536,
      "check_plan" => { "environment_id" => "test", "checks" => [] },
      "forbidden_roots" => [@source], "execution_read_roots" => [],
      "execution_environment_allowlist" => []
    }
    binding = {
      "initial_contract_digest" => state.dig("milestone", "initial_contract_digest"),
      "milestone_id" => state.dig("milestone", "id")
    }
    check_digest = HrmKernel::Host.digest(spec["check_plan"])
    binding_digest = HrmKernel::Host.digest(binding)
    job = {
      "schema_version" => "ap-hrm-host/1", "job_id" => job_id, "spec" => spec,
      "spec_digest" => HrmKernel::Host.digest(spec), "role" => "orchestrator",
      "actor_id" => "astra-orchestrator", "work_order_id" => nil,
      "binding" => binding, "binding_digest" => binding_digest,
      "check_plan" => spec["check_plan"], "check_plan_digest" => check_digest,
      "model_requested" => "gpt-6-astra", "model_identity_evidence" => "requested_cli_argument",
      "project_root" => @project, "prompt_bytes" => 12, "created_at" => "2026-09-09T12:00:00Z"
    }
    write_json(File.join(directory, "job.json"), job)
    if completion
      thread_id = "11234567-89ab-cdef-0123-456789abcdef"
      result = {
        "status" => "continue", "summary" => "Old unconsumed result",
        "requests" => [{ "request_id" => "stale-request", "operation" => "status", "input_json" => "{}" }]
      }
      result_bytes = JSON.generate(result)
      write_bytes(File.join(directory, "result.json"), result_bytes)
      write_bytes(File.join(directory, "events.jsonl"),
        JSON.generate("type" => "thread.started", "thread_id" => thread_id) + "\n" +
        JSON.generate("type" => "turn.completed", "usage" => {}) + "\n")
      write_json(File.join(directory, "completion.json"), {
        "status" => "succeeded", "thread_id" => thread_id,
        "result_sha256" => Digest::SHA256.hexdigest(result_bytes),
        "binding_digest" => binding_digest, "check_plan_digest" => check_digest
      })
    elsif live
      write_json(File.join(directory, "launch.json"), { "helper_pid" => Process.pid })
    end
  end

  def write_completed_worker_job(job_id)
    @store.transact(
      "command_id" => "create-worker-order", "type" => "work_order.create",
      "actor" => { "id" => "astra-orchestrator", "role" => "orchestrator" },
      "data" => {
        "work_order_id" => "worker-order", "intent_id" => "milestone_initial",
        "objective" => "Inspect the unchanged fixture", "requirement_ids" => ["behavior"],
        "paths" => ["app.txt"], "check_ids" => ["check"], "effect_class" => "local_repository"
      }
    )
    @store.transact(
      "command_id" => "claim-worker-order", "type" => "work_order.claim",
      "actor" => { "id" => "worker-#{job_id}", "role" => "worker" },
      "data" => { "work_order_id" => "worker-order", "revision" => 1, "claim_id" => "claim-#{job_id}" }
    )
    state = @store.read.fetch("state")
    order = state.fetch("work_orders").fetch("worker-order")
    directory = File.join(@source, "host-jobs", job_id)
    HrmKernel::Host.private_directory!(directory)
    spec = {
      "job_id" => job_id, "role" => "worker", "work_order_id" => "worker-order",
      "model" => "gpt-5.6-sol", "prompt" => "completed diagnostic worker",
      "context_paths" => [], "max_context_bytes" => 65_536,
      "check_plan" => { "environment_id" => "test", "checks" => [] },
      "forbidden_roots" => [@source], "execution_read_roots" => [],
      "execution_environment_allowlist" => []
    }
    binding = {
      "initial_contract_digest" => state.dig("milestone", "initial_contract_digest"),
      "milestone_id" => state.dig("milestone", "id"),
      "order" => order.slice("id", "revision", "owner_id", "claim_id", "paths", "check_ids",
        "requirement_revisions", "intent_ids", "objective"),
      "current_requirements" => { "behavior" => state.dig("milestone", "requirements", "behavior") }
    }
    check_digest = HrmKernel::Host.digest(spec["check_plan"])
    binding_digest = HrmKernel::Host.digest(binding)
    job = {
      "schema_version" => "ap-hrm-host/1", "job_id" => job_id, "spec" => spec,
      "spec_digest" => HrmKernel::Host.digest(spec), "role" => "worker",
      "actor_id" => "worker-#{job_id}", "work_order_id" => "worker-order",
      "revision" => 1, "claim_id" => "claim-#{job_id}",
      "binding" => binding, "binding_digest" => binding_digest,
      "check_plan" => spec["check_plan"], "check_plan_digest" => check_digest,
      "model_requested" => "gpt-5.6-sol", "model_identity_evidence" => "requested_cli_argument",
      "project_root" => @project, "prompt_bytes" => 12, "created_at" => "2026-09-09T12:00:00Z",
      "baseline_artifacts" => { "app.txt" => Digest::SHA256.file(File.join(@project, "app.txt")).hexdigest }
    }
    result = {
      "status" => "blocked", "summary" => "Completed diagnostic result",
      "changed_paths" => [], "findings" => [], "scenario_dispositions" => [], "context_requests" => []
    }
    result_bytes = JSON.generate(result)
    thread_id = "31234567-89ab-cdef-0123-456789abcdef"
    write_json(File.join(directory, "job.json"), job)
    write_bytes(File.join(directory, "result.json"), result_bytes)
    write_bytes(File.join(directory, "events.jsonl"),
      JSON.generate("type" => "thread.started", "thread_id" => thread_id) + "\n" +
      JSON.generate("type" => "turn.completed", "usage" => {}) + "\n")
    write_json(File.join(directory, "completion.json"), {
      "status" => "succeeded", "thread_id" => thread_id,
      "result_sha256" => Digest::SHA256.hexdigest(result_bytes),
      "binding_digest" => binding_digest, "check_plan_digest" => check_digest
    })
  end

  def continue_run(destination: @destination, new_run_id: "new-run", source_revision: @source_revision,
                   controller_stopped: true, environment_replacement: nil, production: false)
    HrmKernel::RunContinuation.clone(
      source_state_dir: @source, destination_state_dir: destination,
      new_run_id: new_run_id, source_kernel_root: @kernel,
      source_kernel_revision: source_revision, controller_stopped: controller_stopped,
      supervisor_provenance: {
        "schema_version" => "ap-hrm-supervisor-continuation/1",
        "supervisor_id" => "rc36-supervisor", "commission_id" => "commission-1",
        "asserted_at" => "2026-09-09T12:00:00Z", "source" => "supervisor-owned task"
      },
      environment_replacement: environment_replacement,
      production: production
    )
  end

  def make_source_kernel_rc36
    File.write(File.join(@kernel, "kernel.txt"), "RC36\n")
    File.write(File.join(@kernel, "playbooks", "hrm-interaction-kernel.md"), <<~MARKDOWN)
      ---
      title: AP-INTERACT RC.36 - test source kernel
      ---
    MARKDOWN
    git(@kernel, "add", "kernel.txt", "playbooks/hrm-interaction-kernel.md")
    git(@kernel, "commit", "--quiet", "-m", "frozen RC36 source kernel")
    @source_revision = git(@kernel, "rev-parse", "HEAD").strip
  end

  def make_source_kernel_rc37
    File.write(File.join(@kernel, "kernel.txt"), "RC37\n")
    File.write(File.join(@kernel, "playbooks", "hrm-interaction-kernel.md"), <<~MARKDOWN)
      ---
      title: AP-INTERACT RC.37 - test source kernel
      ---
    MARKDOWN
    git(@kernel, "add", "kernel.txt", "playbooks/hrm-interaction-kernel.md")
    git(@kernel, "commit", "--quiet", "-m", "frozen RC37 source kernel")
    @source_revision = git(@kernel, "rev-parse", "HEAD").strip
  end

  def make_source_kernel_rc38
    File.write(File.join(@kernel, "kernel.txt"), "RC38\n")
    File.write(File.join(@kernel, "playbooks", "hrm-interaction-kernel.md"), <<~MARKDOWN)
      ---
      title: AP-INTERACT RC.38 - test source kernel
      ---
    MARKDOWN
    git(@kernel, "add", "kernel.txt", "playbooks/hrm-interaction-kernel.md")
    git(@kernel, "commit", "--quiet", "-m", "frozen RC38 source kernel")
    @source_revision = git(@kernel, "rev-parse", "HEAD").strip
  end

  def make_source_kernel_rc39
    File.write(File.join(@kernel, "kernel.txt"), "RC39\n")
    File.write(File.join(@kernel, "playbooks", "hrm-interaction-kernel.md"), <<~MARKDOWN)
      ---
      title: AP-INTERACT RC.39 - test source kernel
      ---
    MARKDOWN
    git(@kernel, "add", "kernel.txt", "playbooks/hrm-interaction-kernel.md")
    git(@kernel, "commit", "--quiet", "-m", "frozen RC39 source kernel")
    @source_revision = git(@kernel, "rev-parse", "HEAD").strip
  end

  def make_source_kernel_rc40
    File.write(File.join(@kernel, "kernel.txt"), "RC40\n")
    File.write(File.join(@kernel, "playbooks", "hrm-interaction-kernel.md"), <<~MARKDOWN)
      ---
      title: AP-INTERACT RC.40 - test source kernel
      ---
    MARKDOWN
    git(@kernel, "add", "kernel.txt", "playbooks/hrm-interaction-kernel.md")
    git(@kernel, "commit", "--quiet", "-m", "frozen RC40 source kernel")
    @source_revision = git(@kernel, "rev-parse", "HEAD").strip
  end

  def complete_rc37_contribution(unrelated_candidate: false)
    File.write(File.join(@project, ".gitignore"), "/.codex/hrm-runs/\n")
    File.write(File.join(@project, "check.rb"), 'abort unless File.read("app.txt") == "submitted\\n"')
    git(@project, "init", "--quiet")
    git(@project, "config", "user.email", "continuation-test@example.invalid")
    git(@project, "config", "user.name", "Continuation Test")
    git(@project, "add", ".")
    git(@project, "commit", "--quiet", "-m", "candidate baseline")
    store = HrmKernel::Store.new(@source)
    store.transact(
      "command_id" => "create-submitted", "type" => "work_order.create",
      "actor" => { "id" => "astra-orchestrator", "role" => "orchestrator" },
      "data" => { "work_order_id" => "submitted", "intent_id" => "milestone_initial",
        "objective" => "Submit preserved contribution", "requirement_ids" => ["behavior"],
        "paths" => ["app.txt"], "check_ids" => ["check"], "effect_class" => "local_repository" }
    )
    store.transact(
      "command_id" => "claim-submitted", "type" => "work_order.claim",
      "actor" => { "id" => "worker-submitted", "role" => "worker" },
      "data" => { "work_order_id" => "submitted", "revision" => 1, "claim_id" => "claim-submitted" }
    )
    File.write(File.join(@project, "app.txt"), "submitted\n")
    File.write(File.join(@project, "sibling.txt"), "concurrent other order version\n") if unrelated_candidate
    state = store.read.fetch("state")
    order = state.fetch("work_orders").fetch("submitted")
    spec = { "id" => "check", "environment_id" => "test-rc37",
      "argv" => [File.realpath(RbConfig.ruby), "check.rb"], "env" => {}, "cwd" => @project,
      "timeout_seconds" => 10, "max_output_bytes" => 16_384, "configuration_paths" => [] }
    runner = HrmKernel::Execution.new(project_root: @project, state_dir: @source,
      forbidden_read_path: File.join(@source, "driver", "isolation-sentinel.txt"),
      forbidden_write_path: File.join(@source, "driver", "isolation-sentinel.txt"))
    candidate = runner.capture_candidate(work_order: order, milestone: state.fetch("milestone"),
      claim_id: "claim-submitted", revision: 1, requirement_revisions: order.fetch("requirement_revisions"),
      check_plan: { "environment_id" => "test-rc37", "checks" => [spec] }, authorized_paths: ["app.txt", "sibling.txt"])
    outcome = runner.run(spec: spec, binding: candidate.fetch("binding"), candidate: candidate)
    artifacts = [{ "path" => "app.txt", "sha256" => Digest::SHA256.file(File.join(@project, "app.txt")).hexdigest }]
    relative = ".codex/hrm-runs/native-checks/submitted.json"
    report_path = File.join(@project, relative)
    FileUtils.mkdir_p(File.dirname(report_path))
    write_json(report_path, { "check_id" => "check", "conclusion" => "passed",
      "work_order_id" => "submitted", "revision" => 1, "artifacts" => artifacts,
      "execution" => outcome.slice("receipt_path", "receipt_sha256") })
    store.transact(
      "command_id" => "submit-preserved", "type" => "work_order.submit",
      "actor" => { "id" => "worker-submitted", "role" => "worker" },
      "data" => { "work_order_id" => "submitted", "revision" => 1, "claim_id" => "claim-submitted",
        "artifacts" => artifacts, "checks" => [{ "id" => "check", "conclusion" => "passed",
          "artifact_path" => relative, "sha256" => Digest::SHA256.file(report_path).hexdigest }] }
    )
    outcome.slice("receipt_path", "receipt_sha256")
  end

  def replacement_environment
    {
      "environment_id" => "test-rc37", "read_roots" => [], "environment_allowlist" => ["HOME"],
      "preflight_checks" => [{
        "id" => "ruby-rc37", "environment_id" => "test-rc37",
        "argv" => [File.realpath(RbConfig.ruby), "-e", 'abort if ENV.fetch("HOME").empty?'],
        "env" => { "HOME" => "{run_root}" }, "cwd" => @project, "timeout_seconds" => 10,
        "max_output_bytes" => 16_384, "configuration_paths" => []
      }]
    }
  end

  def replacement_environment_rc38
    git_executable = bundled_git_executable
    git_environment = {
      "PATH" => "#{File.dirname(git_executable)}:/usr/bin:/bin",
      "GIT_CONFIG_NOSYSTEM" => "1", "GIT_CONFIG_GLOBAL" => "/dev/null",
      "GIT_CONFIG_SYSTEM" => "/dev/null", "GIT_ATTR_NOSYSTEM" => "1",
      "GIT_OPTIONAL_LOCKS" => "0", "GIT_NO_LAZY_FETCH" => "1", "GIT_TERMINAL_PROMPT" => "0",
      "HOME" => "{run_root}", "PYTHONPYCACHEPREFIX" => "{run_root}/pycache"
    }
    smoke = <<~'RUBY'
      require "fileutils"
      root = ENV.fetch("HOME")
      repository = File.join(root, "git-fixture")
      FileUtils.mkdir_p(repository)
      git = "git"
      abort unless system(git, "-C", repository, "init", "--quiet")
      File.write(File.join(repository, "fixture.txt"), "ok\n")
      abort unless system(git, "-C", repository, "-c", "user.name=RC38", "-c", "user.email=rc38@example.invalid", "add", "fixture.txt")
      abort unless system(git, "-C", repository, "-c", "user.name=RC38", "-c", "user.email=rc38@example.invalid", "commit", "--quiet", "-m", "fixture")
      abort unless `#{git} -C #{repository} ls-files fixture.txt`.strip == "fixture.txt"
      abort unless `#{git} -C #{repository} show HEAD:fixture.txt` == "ok\n"
      puts "rc38-ready"
    RUBY
    {
      "environment_id" => "test-rc38", "read_roots" => [],
      "environment_allowlist" => git_environment.keys,
      "preflight_checks" => [{ "id" => "ruby-rc38", "environment_id" => "test-rc38",
        "argv" => [File.realpath(RbConfig.ruby), "-e", smoke], "env" => git_environment,
        "cwd" => @project, "timeout_seconds" => 10, "max_output_bytes" => 65_536,
        "configuration_paths" => [], "startup_success_marker" => "rc38-ready" }],
      "check_repository" => { "schema_version" => HrmKernel::Execution::LEGACY_REPOSITORY_VIEW_SCHEMA,
        "kind" => "isolated_head_candidate", "git_executable" => git_executable }
    }
  end

  def replacement_environment_rc39
    replacement = JSON.parse(JSON.generate(replacement_environment_rc38))
    replacement["environment_id"] = "test-rc39"
    replacement.fetch("preflight_checks").each { |check| check["environment_id"] = "test-rc39" }
    replacement
  end

  def replacement_environment_rc40
    replacement = JSON.parse(JSON.generate(replacement_environment_rc39))
    replacement["environment_id"] = "test-rc40"
    replacement.fetch("preflight_checks").each { |check| check["environment_id"] = "test-rc40" }
    replacement
  end

  def replacement_environment_rc41
    replacement = JSON.parse(JSON.generate(replacement_environment_rc40))
    replacement["environment_id"] = "test-rc41"
    replacement.fetch("preflight_checks").each { |check| check["environment_id"] = "test-rc41" }
    replacement.fetch("check_repository")["schema_version"] = HrmKernel::Execution::REPOSITORY_VIEW_SCHEMA
    replacement
  end

  def byte_snapshot(root)
    Dir.glob(File.join(root, "**", "*"), File::FNM_DOTMATCH).reject do |path|
      [".", ".."].include?(File.basename(path)) || (File.directory?(path) && !File.symlink?(path))
    end.to_h do |path|
      value = File.symlink?(path) ? "symlink:#{File.readlink(path)}" : Digest::SHA256.file(path).hexdigest
      [path.delete_prefix(root + "/"), value]
    end
  end

  def bundled_git_executable
    File.realpath(File.join(Dir.home, ".cache/codex-runtimes/codex-primary-runtime/dependencies/native/git/bin/git"))
  end

  def authenticate_test_execution_run(run)
    run_id = File.basename(run)
    body = { "schema_version" => HrmKernel::Execution::RECEIPT_SCHEMA, "receipt_id" => run_id }
    key = File.binread(File.join(@source, HrmKernel::Execution::KEY_NAME))
    canonical = JSON.generate(HrmKernel::Execution.canonical(body))
    body["authentication"] = {
      "algorithm" => "hmac-sha256",
      "hmac_sha256" => OpenSSL::HMAC.hexdigest("SHA256", key, canonical)
    }
    write_json(File.join(run, "receipt.json"), body)
  end

  def mode_snapshot(root)
    ([root] + Dir.glob(File.join(root, "**", "*"), File::FNM_DOTMATCH)).reject do |path|
      [".", ".."].include?(File.basename(path))
    end.to_h { |path| [path.delete_prefix(root), File.lstat(path).mode & 0o777] }
  end

  def assert_private_tree(root)
    Dir.glob(File.join(root, "**", "*"), File::FNM_DOTMATCH).each do |path|
      next if [".", ".."].include?(File.basename(path))
      mode = File.stat(path).mode & 0o777
      assert_equal(File.directory?(path) ? 0o700 : 0o600, mode, path)
    end
  end

  def read_json(path)
    JSON.parse(File.binread(path))
  end

  def write_json(path, value)
    write_bytes(path, JSON.pretty_generate(value) + "\n")
  end

  def write_bytes(path, bytes)
    File.open(path, "wb", 0o600) { |file| file.write(bytes) }
    File.chmod(0o600, path)
  end

  def git(root, *args)
    output, status = Open3.capture2e("git", "-C", root, *args)
    raise output unless status.success?
    output
  end
end
