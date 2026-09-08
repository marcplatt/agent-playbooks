# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "minitest/autorun"
require "rbconfig"
require "tmpdir"

require_relative "../lib/hrm_kernel/evidence"
require_relative "../lib/hrm_kernel/execution"

class HrmKernelExecutionTest < Minitest::Test
  def setup
    @temporary = File.realpath(Dir.mktmpdir("hrm-kernel-execution-"))
    @project_root = File.join(@temporary, "project")
    @state_dir = File.join(@temporary, "state")
    Dir.mkdir(@project_root, 0o700)
    Dir.mkdir(@state_dir, 0o700)
    @forbidden_read = File.join(@temporary, "existing-user.sqlite3")
    @forbidden_write = File.join(@temporary, "outside-write.txt")
    File.write(@forbidden_read, "private-existing-data\n")
    File.write(@forbidden_write, "preserve\n")
    File.write(File.join(@project_root, ".gitignore"), "/.checks/\n")
    File.write(File.join(@project_root, "app.txt"), "before\n")
    File.write(File.join(@project_root, "other.txt"), "other-before\n")
    File.write(File.join(@project_root, "check.rb"), <<~RUBY)
      require "json"
      run_root = ENV.fetch("RUN_ROOT")
      File.write(File.join(run_root, "new-check.sqlite3"), "temporary\n")
      abort("temporary database unreadable") unless File.read(File.join(run_root, "new-check.sqlite3")) == "temporary\n"
      puts JSON.generate("worker_claim" => "passed")
    RUBY
    File.write(File.join(@project_root, "check.py"), <<~PYTHON)
      import json
      import os
      import socket
      import sqlite3

      root = os.environ["RUN_ROOT"]
      database = os.path.join(root, "python-check.sqlite3")
      connection = sqlite3.connect(database)
      connection.execute("create table result (value text)")
      connection.execute("insert into result values ('ok')")
      connection.commit()
      assert connection.execute("select value from result").fetchone() == ("ok",)
      left, right = socket.socketpair()
      left.sendall(b"ok")
      assert right.recv(2) == b"ok"
      left.close()
      right.close()
      print(json.dumps({"sqlite": "temporary", "socketpair": "local"}, sort_keys=True))
    PYTHON
    git("init", "--quiet")
    git("config", "user.email", "kernel-test@example.invalid")
    git("config", "user.name", "Kernel Test")
    git("add", ".")
    git("commit", "--quiet", "-m", "baseline")
    File.write(File.join(@project_root, "app.txt"), "after\n")
    File.write(File.join(@project_root, "other.txt"), "other-after\n")
  end

  def teardown
    FileUtils.remove_entry(@temporary) if @temporary && File.exist?(@temporary)
  end

  def test_runner_executes_frozen_plan_in_sandbox_and_reuses_conclusive_receipt
    execution = runner
    candidate = capture(execution, authorized_paths: %w[app.txt other.txt])
    assert_equal %w[app.txt other.txt], candidate.fetch("changes").map { |entry| entry.fetch("path") }

    first = execution.run(spec: spec, binding: candidate.fetch("binding"), candidate: candidate)
    descriptor = first.select { |key, _| %w[receipt_path receipt_sha256].include?(key) }
    receipt = execution.verify_receipt!(descriptor, binding: candidate.fetch("binding"), candidate: candidate, current_exact: true)
    failure_detail = {
      "receipt" => receipt.reject { |key, _| %w[candidate authentication].include?(key) },
      "stdout" => private_log(receipt.dig("stdout", "path")),
      "stderr" => private_log(receipt.dig("stderr", "path"))
    }
    assert_equal "passed", first.fetch("conclusion"), JSON.pretty_generate(failure_detail)
    assert_equal false, first.fetch("reused")
    assert_equal "preserve\n", File.read(@forbidden_write)
    assert_equal 0, receipt.fetch("exit_status")
    assert_equal "passed", receipt.fetch("conclusion")
    assert_equal "blocked", receipt.dig("preflight", "forbidden_read")
    stdout = private_log(receipt.dig("stdout", "path"))
    assert_includes stdout, '"worker_claim":"passed"'

    second = execution.run(spec: spec, binding: candidate.fetch("binding"), candidate: candidate)
    assert_equal true, second.fetch("reused")
    assert_equal first.fetch("receipt_sha256"), second.fetch("receipt_sha256")
  end

  def test_declared_write_scope_does_not_force_changes_to_every_allowed_file
    candidate = capture(runner, paths: %w[app.txt check.rb], authorized_paths: %w[app.txt other.txt check.rb])
    assert_equal %w[app.txt other.txt], candidate.fetch("changes").map { |entry| entry["path"] }
    assert_raises(HrmKernel::Error) do
      capture(runner, paths: %w[check.rb], authorized_paths: %w[app.txt other.txt check.rb])
    end
  end

  def test_nonzero_process_cannot_claim_pass_by_printing_passing_json
    File.write(File.join(@project_root, "check.rb"), <<~RUBY)
      require "json"
      puts JSON.generate("conclusion" => "passed")
      exit 7
    RUBY
    git("add", "check.rb")
    candidate = capture(runner, paths: %w[app.txt check.rb], authorized_paths: %w[app.txt other.txt check.rb])
    result = runner.run(spec: spec, binding: candidate.fetch("binding"), candidate: candidate)
    assert_equal "failed", result.fetch("conclusion")
    descriptor = result.select { |key, _| %w[receipt_path receipt_sha256].include?(key) }
    receipt = runner.verify_receipt!(descriptor, binding: candidate.fetch("binding"), candidate: candidate)
    assert_equal 7, receipt.fetch("exit_status")
    assert_equal "failed", receipt.fetch("conclusion")
  end

  def test_python_sqlite_and_local_testclient_socket_primitives_stay_in_run_root
    python = File.realpath("/usr/bin/python3")
    python_root = "/Library/Developer/CommandLineTools"
    python_spec = spec.merge(
      "argv" => [python, "-S", "check.py"],
      "env" => {
        "RUN_ROOT" => "{run_root}",
        "HOME" => "{run_root}",
        "PYTHONDONTWRITEBYTECODE" => "1"
      }
    )
    execution = runner(
      environment_allowlist: %w[RUN_ROOT HOME PYTHONDONTWRITEBYTECODE],
      read_roots: [python_root]
    )
    candidate = capture(execution, authorized_paths: %w[app.txt other.txt], selected_spec: python_spec)
    result = execution.run(spec: python_spec, binding: candidate.fetch("binding"), candidate: candidate)
    descriptor = result.select { |key, _| %w[receipt_path receipt_sha256].include?(key) }
    receipt = execution.verify_receipt!(descriptor, binding: candidate.fetch("binding"), candidate: candidate)
    detail = private_log(receipt.dig("stderr", "path"))
    assert_equal "passed", result.fetch("conclusion"), detail
    assert_includes private_log(receipt.dig("stdout", "path")), '"socketpair": "local"'
  end

  def test_actual_check_cannot_read_or_write_forbidden_sentinels
    File.write(File.join(@project_root, "check.rb"), <<~RUBY)
      File.binread(ENV.fetch("FORBIDDEN_READ"))
      File.open(ENV.fetch("FORBIDDEN_WRITE"), "ab") { |file| file.write("changed") }
    RUBY
    git("add", "check.rb")
    isolated_spec = spec.merge(
      "env" => {
        "RUN_ROOT" => "{run_root}",
        "FORBIDDEN_READ" => @forbidden_read,
        "FORBIDDEN_WRITE" => @forbidden_write
      }
    )
    execution = runner(environment_allowlist: %w[RUN_ROOT FORBIDDEN_READ FORBIDDEN_WRITE])
    candidate = capture(
      execution,
      paths: %w[app.txt check.rb],
      authorized_paths: %w[app.txt other.txt check.rb],
      selected_spec: isolated_spec
    )
    result = execution.run(spec: isolated_spec, binding: candidate.fetch("binding"), candidate: candidate)
    assert_equal "failed", result.fetch("conclusion")
    assert_equal "preserve\n", File.read(@forbidden_write)
  end

  def test_candidate_capture_covers_add_delete_and_rejects_scope_or_symlink_escape
    File.write(File.join(@project_root, "new.txt"), "new\n")
    File.delete(File.join(@project_root, "other.txt"))
    candidate = capture(runner, authorized_paths: %w[app.txt other.txt new.txt])
    statuses = candidate.fetch("changes").each_with_object({}) { |entry, memo| memo[entry["path"]] = entry["status"] }
    assert_equal({"app.txt" => "M", "new.txt" => "?", "other.txt" => "D"}, statuses)

    File.write(File.join(@project_root, "outside.txt"), "outside\n")
    assert_raises(HrmKernel::Error) { capture(runner, authorized_paths: %w[app.txt other.txt new.txt]) }
    File.delete(File.join(@project_root, "outside.txt"))

    File.symlink(@forbidden_read, File.join(@project_root, "linked.txt"))
    assert_raises(HrmKernel::Error) do
      capture(runner, authorized_paths: %w[app.txt other.txt new.txt linked.txt])
    end
  end

  def test_candidate_drift_blocks_execution
    execution = runner
    candidate = capture(execution, authorized_paths: %w[app.txt other.txt])
    File.write(File.join(@project_root, "app.txt"), "drifted\n")
    error = assert_raises(HrmKernel::Error) do
      execution.run(spec: spec, binding: candidate.fetch("binding"), candidate: candidate)
    end
    assert_match(/candidate Git changes drifted/, error.message)
  end

  def test_check_executable_identity_is_frozen_with_candidate
    dependency_root = File.join(@temporary, "dependency")
    Dir.mkdir(dependency_root, 0o700)
    executable = File.join(dependency_root, "check-executable")
    FileUtils.cp("/bin/echo", executable)
    File.chmod(0o700, executable)
    external_spec = spec.merge(
      "argv" => [executable, "ok"],
      "env" => {},
      "configuration_paths" => []
    )
    execution = runner(environment_allowlist: [], read_roots: [dependency_root])
    candidate = capture(execution, authorized_paths: %w[app.txt other.txt], selected_spec: external_spec)
    original = candidate.dig("executable_identities", "check-1", "sha256")
    refute_nil original

    File.open(executable, "ab") { |file| file.write("drift") }
    error = assert_raises(HrmKernel::Error) do
      execution.run(spec: external_spec, binding: candidate.fetch("binding"), candidate: candidate)
    end
    assert_match(/executable identity drifted/, error.message)
  end

  def test_forged_runner_receipt_and_legacy_report_cannot_satisfy_implementation_mode
    execution = runner
    candidate = capture(execution, authorized_paths: %w[app.txt other.txt])
    result = execution.run(spec: spec, binding: candidate.fetch("binding"), candidate: candidate)
    descriptor = result.select { |key, _| %w[receipt_path receipt_sha256].include?(key) }
    artifacts = [{"path" => "app.txt", "sha256" => Digest::SHA256.file(File.join(@project_root, "app.txt")).hexdigest}]
    report_path = write_report(artifacts, descriptor)
    state = state_for(candidate)
    command = submit_command(artifacts, report_path)

    assert HrmKernel::Evidence.verify!(state, command, state_dir: @state_dir)

    forged = File.join(@state_dir, "execution", "forged.json")
    File.open(forged, "w", 0o600) { |file| file.write(JSON.generate("conclusion" => "passed")) }
    forged_descriptor = {
      "receipt_path" => "execution/forged.json",
      "receipt_sha256" => Digest::SHA256.file(forged).hexdigest
    }
    forged_report = write_report(artifacts, forged_descriptor)
    forged_command = submit_command(artifacts, forged_report)
    assert_raises(HrmKernel::Error) do
      HrmKernel::Evidence.verify!(state, forged_command, state_dir: @state_dir)
    end

    legacy_report = write_report(artifacts, nil)
    legacy_command = submit_command(artifacts, legacy_report)
    assert_raises(HrmKernel::Error) do
      HrmKernel::Evidence.verify!(state, legacy_command, state_dir: @state_dir)
    end
  end

  def test_completed_work_transitions_reject_any_new_candidate_drift
    execution = runner
    candidate = capture(execution, authorized_paths: %w[app.txt other.txt])
    result = execution.run(spec: spec, binding: candidate.fetch("binding"), candidate: candidate)
    descriptor = result.select { |key, _| %w[receipt_path receipt_sha256].include?(key) }
    artifacts = [{"path" => "app.txt", "sha256" => Digest::SHA256.file(File.join(@project_root, "app.txt")).hexdigest}]
    report_path = write_report(artifacts, descriptor)
    submission = submit_command(artifacts, report_path)
    completed = work_order.merge(
      "status" => "completed",
      "claim_id" => nil,
      "artifacts" => artifacts,
      "checks" => submission.dig("data", "checks")
    )
    state = {"milestone" => milestone, "work_orders" => {"work-1" => completed}}

    File.write(File.join(@project_root, "rogue.txt"), "late drift\n")
    commands = [
      {"type" => "milestone.assess", "data" => {}},
      {"type" => "finding.resolve", "data" => {}},
      {"type" => "milestone.review_ready", "data" => {}},
      {"type" => "milestone.review", "data" => {"decision" => "accepted"}}
    ]
    commands.each do |command|
      error = assert_raises(HrmKernel::Error) do
        HrmKernel::Evidence.verify!(state, command, state_dir: @state_dir)
      end
      assert_match(/candidate Git changes drifted/, error.message)
    end
  end

  private

  def runner(environment_allowlist: %w[RUN_ROOT], read_roots: [])
    HrmKernel::Execution.new(
      project_root: @project_root,
      state_dir: @state_dir,
      read_roots: read_roots,
      environment_allowlist: environment_allowlist,
      forbidden_read_path: @forbidden_read,
      forbidden_write_path: @forbidden_write
    )
  end

  def milestone
    {
      "id" => "HRM-TEST",
      "revision" => 1,
      "mode" => "implementation",
      "outcome" => "Exercise native execution",
      "allowed_paths" => ["*.txt", "check.rb"],
      "requirements" => {
        "req-1" => {"id" => "req-1", "revision" => 1, "text" => "Run the check"}
      },
      "project_root" => @project_root
    }
  end

  def work_order(paths = ["app.txt"])
    {
      "id" => "work-1",
      "revision" => 1,
      "objective" => "Change the assigned file",
      "requirement_ids" => ["req-1"],
      "requirement_revisions" => {"req-1" => 1},
      "paths" => paths,
      "check_ids" => ["check-1"],
      "effect_class" => "local_repository",
      "claim_id" => "claim-1",
      "claim_history" => ["claim-1"]
    }
  end

  def spec
    {
      "id" => "check-1",
      "environment_id" => "sandbox-test",
      "argv" => [File.realpath(RbConfig.ruby), "check.rb"],
      "env" => {"RUN_ROOT" => "{run_root}"},
      "cwd" => @project_root,
      "timeout_seconds" => 10,
      "max_output_bytes" => 1024 * 1024,
      "configuration_paths" => ["{run_root}"]
    }
  end

  def capture(execution, paths: ["app.txt"], authorized_paths:, selected_spec: spec)
    order = work_order(paths)
    execution.capture_candidate(
      work_order: order,
      milestone: milestone,
      claim_id: "claim-1",
      revision: 1,
      requirement_revisions: {"req-1" => 1},
      check_plan: {"environment_id" => selected_spec.fetch("environment_id"), "checks" => [selected_spec]},
      authorized_paths: authorized_paths
    )
  end

  def state_for(_candidate)
    {
      "milestone" => milestone,
      "work_orders" => {"work-1" => work_order.merge("status" => "running", "artifacts" => [], "checks" => [])}
    }
  end

  def submit_command(artifacts, report_path)
    report_relative = Pathname.new(report_path).relative_path_from(Pathname.new(@project_root)).to_s
    {
      "type" => "work_order.submit",
      "data" => {
        "work_order_id" => "work-1",
        "revision" => 1,
        "claim_id" => "claim-1",
        "artifacts" => artifacts,
        "checks" => [{
          "id" => "check-1",
          "conclusion" => "passed",
          "artifact_path" => report_relative,
          "sha256" => Digest::SHA256.file(report_path).hexdigest
        }]
      }
    }
  end

  def write_report(artifacts, descriptor)
    directory = File.join(@project_root, ".checks")
    FileUtils.mkdir_p(directory)
    path = File.join(directory, "check.json")
    report = {
      "check_id" => "check-1",
      "conclusion" => "passed",
      "work_order_id" => "work-1",
      "revision" => 1,
      "artifacts" => artifacts
    }
    report["execution"] = descriptor if descriptor
    File.write(path, JSON.generate(report))
    path
  end

  def private_log(relative)
    File.binread(File.join(@state_dir, relative))
  end

  def git(*arguments)
    system("/usr/bin/git", "-C", @project_root, *arguments, exception: true)
  end
end
