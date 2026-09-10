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
    File.write(File.join(@project_root, ".env.example"), "EXAMPLE_ONLY=not-secret\n")
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
      from zoneinfo import ZoneInfo

      assert ZoneInfo("America/Vancouver").key == "America/Vancouver"

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
    if @temporary && File.exist?(@temporary)
      FileUtils.chmod_R(0o700, @temporary)
      FileUtils.remove_entry(@temporary)
    end
  end

  def test_project_configuration_rejection_explains_the_existing_readable_route
    execution = runner
    ["pyproject.toml", File.join(@project_root, "pyproject.toml")].each do |path|
      selected_spec = spec.merge("configuration_paths" => [path])
      candidate = capture(execution, authorized_paths: %w[app.txt other.txt], selected_spec: selected_spec)
      error = assert_raises(HrmKernel::Error) do
        execution.run(spec: selected_spec,
                      binding: candidate.fetch("binding"), candidate: candidate)
      end
      assert_includes error.message, "configuration_paths: []"
      assert_includes error.message, "argv"
    end
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
    assert_equal "blocked", receipt.dig("preflight", "network")
    stdout = private_log(receipt.dig("stdout", "path"))
    assert_includes stdout, '"worker_claim":"passed"'

    second = execution.run(spec: spec, binding: candidate.fetch("binding"), candidate: candidate)
    assert_equal true, second.fetch("reused")
    assert_equal first.fetch("receipt_sha256"), second.fetch("receipt_sha256")
  end

  def test_pytest_current_links_are_removed_and_bound_to_the_native_receipt
    File.write(File.join(@project_root, "check.rb"), <<~'RUBY')
      require "fileutils"
      root = ENV.fetch("RUN_ROOT")
      base = File.join(root, "pytest-of-unknown", "pytest-0")
      test = File.join(base, "test_binding_fails_closed_for_0")
      FileUtils.mkdir_p(test)
      File.write(File.join(test, "intake.sqlite3"), "scratch")
      File.symlink(base, File.join(root, "pytest-of-unknown", "pytest-current"))
      File.symlink(test, File.join(base, "test_binding_fails_closed_for_current"))
      puts "pytest-layout-ready"
    RUBY
    git("add", "check.rb")
    execution = runner
    candidate = capture(execution, paths: %w[app.txt check.rb],
      authorized_paths: %w[app.txt other.txt check.rb])

    result = execution.run(spec: spec, binding: candidate.fetch("binding"), candidate: candidate)
    descriptor = result.slice("receipt_path", "receipt_sha256")
    receipt = execution.verify_receipt!(descriptor, binding: candidate.fetch("binding"),
      candidate: candidate, current_exact: true)

    assert_equal "passed", receipt.fetch("conclusion")
    assert_equal "removed_after_process_group_termination_before_receipt",
      receipt.fetch("scratch_link_transformation")
    links = receipt.fetch("inert_scratch_links")
    assert_equal [
      "pytest-of-unknown/pytest-0/test_binding_fails_closed_for_current",
      "pytest-of-unknown/pytest-current"
    ], links.map { |entry| entry.fetch("path") }
    run_root = File.dirname(File.join(@state_dir, descriptor.fetch("receipt_path")))
    links.each do |entry|
      path = File.join(run_root, entry.fetch("path"))
      refute File.exist?(path)
      refute File.symlink?(path)
    end
    scratch = File.join(run_root, "pytest-of-unknown", "pytest-0", "test_binding_fails_closed_for_0")
    assert_equal 0o700, File.stat(scratch).mode & 0o777
    assert_equal 0o600, File.stat(File.join(scratch, "intake.sqlite3")).mode & 0o777

    File.symlink(File.join(run_root, "pytest-of-unknown", "pytest-0"),
      File.join(run_root, links.last.fetch("path")))
    error = assert_raises(HrmKernel::Error) do
      execution.verify_receipt!(descriptor, binding: candidate.fetch("binding"), candidate: candidate)
    end
    assert_match(/was recreated/, error.message)
  end

  def test_environment_preflight_authenticates_and_removes_pytest_current_links
    script = <<~'RUBY'
      require "fileutils"
      root = ENV.fetch("RUN_ROOT")
      base = File.join(root, "pytest", "pytest-0")
      test = File.join(base, "test_tmp_path_probe0")
      FileUtils.mkdir_p(test)
      File.symlink(base, File.join(root, "pytest", "pytest-current"))
      File.symlink(test, File.join(base, "test_tmp_path_probecurrent"))
      puts "preflight-pytest-ready"
    RUBY
    smoke = spec.merge(
      "id" => "preflight-pytest-links",
      "argv" => [File.realpath(RbConfig.ruby), "-e", script],
      "startup_success_marker" => "preflight-pytest-ready"
    )
    execution = runner

    result = execution.preflight(spec: smoke)
    receipt = execution.verify_preflight!(result.slice("receipt_path", "receipt_sha256"), spec: smoke)

    assert_equal "passed", result.fetch("conclusion")
    assert_equal true, receipt.fetch("startup_completed")
    assert_equal [
      "pytest/pytest-0/test_tmp_path_probecurrent",
      "pytest/pytest-current"
    ], receipt.fetch("inert_scratch_links").map { |entry| entry.fetch("path") }
    assert_equal "removed_after_process_group_termination_before_receipt",
      receipt.fetch("scratch_link_transformation")
  end

  def test_scratch_links_outside_the_run_and_in_its_control_root_fail_closed
    cases = {
      "escaped" => 'File.symlink(ENV.fetch("ESCAPE_TARGET"), File.join(root, "pytest", "escaped-current"))',
      "broken" => 'File.symlink(File.join(root, "pytest", "missing"), File.join(root, "pytest", "broken-current"))',
      "control" => 'File.symlink(File.join(root, "pytest"), File.join(root, "pytest-current"))'
    }
    cases.each do |kind, link_source|
      File.write(File.join(@project_root, "check.rb"), <<~RUBY)
        require "fileutils"
        root = ENV.fetch("RUN_ROOT")
        FileUtils.mkdir_p(File.join(root, "pytest"))
        #{link_source}
      RUBY
      git("add", "check.rb")
      selected = spec.merge("env" => {
        "RUN_ROOT" => "{run_root}", "ESCAPE_TARGET" => @project_root
      })
      execution = runner(environment_allowlist: %w[RUN_ROOT ESCAPE_TARGET])
      candidate = capture(execution, paths: %w[app.txt check.rb],
        authorized_paths: %w[app.txt other.txt check.rb], selected_spec: selected)
      error = assert_raises(HrmKernel::Error) do
        execution.run(spec: selected, binding: candidate.fetch("binding"), candidate: candidate)
      end
      expected = kind == "control" ? /nested scratch boundary/ : /same run|changed during cleanup/
      assert_match(expected, error.message)
    end
  end

  def test_special_scratch_entry_fails_before_a_safe_link_is_removed
    execution = runner
    candidate = capture(execution, authorized_paths: %w[app.txt other.txt])
    run_root = execution.prepare_run_root(spec: spec, binding: candidate.fetch("binding"), candidate: candidate)
    scratch = File.join(run_root, "pytest")
    target = File.join(scratch, "pytest-0")
    FileUtils.mkdir_p(target)
    link = File.join(scratch, "pytest-current")
    File.symlink(target, link)
    fifo = File.join(scratch, "control.fifo")
    system("/usr/bin/mkfifo", fifo, exception: true)

    error = assert_raises(HrmKernel::Error) do
      execution.send(:privatize_run_scratch!, run_root)
    end
    assert_match(/symlink or special file/, error.message)
    assert File.symlink?(link)
  end

  def test_scratch_link_may_not_target_the_isolated_candidate
    execution = runner
    candidate = capture(execution, authorized_paths: %w[app.txt other.txt])
    run_root = execution.prepare_run_root(spec: spec, binding: candidate.fetch("binding"), candidate: candidate)
    isolated = File.join(run_root, "candidate")
    scratch = File.join(run_root, "pytest")
    FileUtils.mkdir_p(isolated)
    FileUtils.mkdir_p(scratch)
    File.symlink(isolated, File.join(scratch, "candidate-current"))

    error = assert_raises(HrmKernel::Error) do
      execution.send(:privatize_run_scratch!, run_root, except: isolated)
    end
    assert_match(/may not target the isolated candidate/, error.message)
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

  def test_sensitive_file_metadata_is_visible_but_file_contents_are_blocked
    File.write(File.join(@project_root, "check.rb"), <<~RUBY)
      metadata = File.stat(".env.example")
      abort("sensitive example metadata unavailable") unless metadata.file? && metadata.size.positive?
      begin
        File.binread(".env.example")
        abort("sensitive example contents were readable")
      rescue Errno::EACCES, Errno::EPERM
        puts "metadata-visible-data-blocked"
      end
    RUBY
    git("add", "check.rb")
    execution = runner
    candidate = capture(
      execution,
      paths: %w[app.txt check.rb],
      authorized_paths: %w[app.txt other.txt check.rb]
    )
    result = execution.run(spec: spec, binding: candidate.fetch("binding"), candidate: candidate)
    descriptor = result.select { |key, _| %w[receipt_path receipt_sha256].include?(key) }
    receipt = execution.verify_receipt!(descriptor, binding: candidate.fetch("binding"), candidate: candidate)
    assert_equal "passed", result.fetch("conclusion"), private_log(receipt.dig("stderr", "path"))
    assert_includes private_log(receipt.dig("stdout", "path")), "metadata-visible-data-blocked"
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

  def test_explicit_disposable_home_supports_python_without_operator_home_access
    execution = runner(environment_allowlist: %w[HOME], read_roots: ["/Library/Developer/CommandLineTools"])
    smoke = spec.merge(
      "environment_id" => "python-disposable-home-v2",
      "argv" => [File.realpath("/usr/bin/python3"), "-S", "-c",
                 "from pathlib import Path; import os; p = Path.home(); assert str(p) == os.environ['HOME']; (p / 'scratch.txt').write_text('ok'); print('home-ready')"],
      "env" => { "HOME" => "{run_root}" },
      "configuration_paths" => [],
      "startup_success_marker" => "home-ready"
    )
    result = execution.preflight(spec: smoke)
    assert_equal "passed", result["conclusion"]
    refute result["reused"]
    receipt = execution.verify_preflight!(result.slice("receipt_path", "receipt_sha256"), spec: smoke)
    assert_equal true, receipt["startup_completed"]
    assert_equal "blocked", receipt.dig("isolation", "forbidden_read")
    assert_equal "blocked", receipt.dig("isolation", "forbidden_write")
  end

  def test_isolated_head_candidate_runs_real_git_without_history_and_rejects_metadata_injection
    File.write(File.join(@project_root, ".env"), "REAL_SECRET=must-stay-denied\n")
    git("add", ".env")
    git("commit", "--quiet", "-m", "tracked runtime secret fixture")
    original_head = Open3.capture2("/usr/bin/git", "-C", @project_root, "rev-parse", "HEAD").first.strip
    FileUtils.mkdir_p(File.join(@project_root, "nested"))
    File.write(File.join(@project_root, "nested", ".env.example"), "UNTRACKED_TEMPLATE=must-stay-denied\n")
    File.write(File.join(@project_root, "check.rb"), <<~'RUBY')
      require "open3"
      require "fileutils"
      head, status = Open3.capture2e("git", "rev-parse", "HEAD")
      abort("wrong isolated HEAD PATH=#{ENV['PATH'].inspect}: #{head.inspect}") unless status.success? && head.strip == ENV.fetch("EXPECTED_HEAD")
      _parent, parent_status = Open3.capture2e("git", "cat-file", "-e", "HEAD^")
      abort("parent history leaked") if parent_status.success?
      tracked, tracked_status = Open3.capture2e("git", "ls-files", "private-evidence")
      abort("root Git result changed") unless tracked_status.success? && tracked.empty?
      abort("public tracked template unavailable") unless File.binread(".env.example").include?("EXAMPLE_ONLY")
      [".env", "nested/.env.example"].each do |path|
        begin
          File.binread(path)
          abort("non-public environment file was readable: #{path}")
        rescue Errno::EPERM, Errno::EACCES
          nil
        end
      end
      [".git/config", ".git/objects/info/alternates", ".git/hooks/post-index-change", ".gitattributes"].each do |path|
        begin
          FileUtils.mkdir_p(File.dirname(path))
          File.chmod(0o600, path) if File.exist?(path)
          File.write(path, "malicious")
          abort("isolated candidate was writable: #{path}")
        rescue Errno::EPERM, Errno::EACCES
          nil
        end
      end
      FileUtils.mkdir_p(ENV.fetch("PYTHONPYCACHEPREFIX"))
      File.write(File.join(ENV.fetch("PYTHONPYCACHEPREFIX"), "scratch"), "ok")
      puts "isolated-git-ready"
    RUBY
    git("add", "check.rb")
    repository = {
      "schema_version" => HrmKernel::Execution::REPOSITORY_VIEW_SCHEMA,
      "kind" => "isolated_head_candidate",
      "git_executable" => bundled_git_executable
    }
    git_env = {
      "PATH" => "#{File.dirname(repository.fetch('git_executable'))}:/usr/bin:/bin",
      "GIT_CONFIG_NOSYSTEM" => "1", "GIT_CONFIG_GLOBAL" => "/dev/null",
      "GIT_CONFIG_SYSTEM" => "/dev/null", "GIT_ATTR_NOSYSTEM" => "1",
      "GIT_OPTIONAL_LOCKS" => "0", "GIT_NO_LAZY_FETCH" => "1", "GIT_TERMINAL_PROMPT" => "0",
      "EXPECTED_HEAD" => original_head, "PYTHONPYCACHEPREFIX" => "{run_root}/pycache"
    }
    isolated_spec = spec.merge("env" => git_env, "configuration_paths" => [])
    execution = HrmKernel::Execution.new(
      project_root: @project_root, state_dir: @state_dir,
      environment_allowlist: git_env.keys,
      forbidden_read_path: @forbidden_read, forbidden_write_path: @forbidden_write,
      repository_view: repository
    )
    candidate = capture(execution, paths: %w[app.txt check.rb nested/.env.example],
      authorized_paths: %w[app.txt other.txt check.rb nested/.env.example], selected_spec: isolated_spec)
    result = execution.run(spec: isolated_spec, binding: candidate.fetch("binding"), candidate: candidate)
    descriptor = result.slice("receipt_path", "receipt_sha256")
    receipt = execution.verify_receipt!(descriptor, candidate: candidate, current_exact: true)
    assert_equal "passed", receipt["conclusion"], private_log(receipt.dig("stderr", "path"))
    assert_equal "omitted", receipt.dig("repository_view", "parent_objects")
    assert_equal original_head, receipt.dig("repository_view", "head_sha")
    public_template = receipt.dig("repository_view", "public_tracked_templates", 0)
    assert_equal ".env.example", public_template.fetch("path")
    assert_equal Digest::SHA256.hexdigest("EXAMPLE_ONLY=not-secret\n"), public_template.fetch("sha256")
    assert_equal public_template.fetch("sha256"), public_template.fetch("source_sha256")
    assert_equal "preserve\n", File.read(@forbidden_write)

    isolated_root = File.join(@state_dir, receipt.dig("repository_view", "validation_root"))
    template = File.join(isolated_root, ".env.example")
    template_bytes = File.binread(template)
    File.unlink(template)
    File.symlink(@forbidden_read, template)
    error = assert_raises(HrmKernel::Error) { execution.verify_receipt!(descriptor, candidate: candidate) }
    assert_match(/regular unlinked file/, error.message)
    File.unlink(template)
    File.write(template, template_bytes)
    File.chmod(0o600, template)

    config = File.join(isolated_root, ".git", "config")
    File.chmod(0o600, config)
    File.write(config, "[core]\n\tfsmonitor = #{File.join(@temporary, 'escape')}\n")
    error = assert_raises(HrmKernel::Error) { execution.verify_receipt!(descriptor, candidate: candidate) }
    assert_match(/metadata changed/, error.message)
    refute File.exist?(File.join(@temporary, "escape"))
  end

  private

  def bundled_git_executable
    File.realpath(File.join(Dir.home, ".cache/codex-runtimes/codex-primary-runtime/dependencies/native/git/bin/git"))
  end

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
