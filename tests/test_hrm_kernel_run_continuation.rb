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

  def test_escaped_broken_and_control_namespace_symlinks_fail_closed
    run = File.join(@source, "execution", "c" * 64)
    scratch = File.join(run, "pytest-of-unknown")
    target = File.join(scratch, "pytest-0")
    FileUtils.mkdir_p(target, mode: 0o755)
    File.chmod(0o700, run)
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
        "allowed_paths" => ["app.txt"],
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

  def byte_snapshot(root)
    Dir.glob(File.join(root, "**", "*"), File::FNM_DOTMATCH).reject do |path|
      [".", ".."].include?(File.basename(path)) || (File.directory?(path) && !File.symlink?(path))
    end.to_h do |path|
      value = File.symlink?(path) ? "symlink:#{File.readlink(path)}" : Digest::SHA256.file(path).hexdigest
      [path.delete_prefix(root + "/"), value]
    end
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
