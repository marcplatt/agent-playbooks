# frozen_string_literal: true

require "fileutils"
require "json"
require "minitest/autorun"
require "rbconfig"
require "tmpdir"

require_relative "../lib/hrm_kernel/execution"

class HrmKernelPreflightTest < Minitest::Test
  def setup
    @temporary = File.realpath(Dir.mktmpdir("hrm-kernel-preflight-"))
    @project_root = File.join(@temporary, "project")
    @state_dir = File.join(@temporary, "state")
    Dir.mkdir(@project_root, 0o700)
    Dir.mkdir(@state_dir, 0o700)
    @forbidden_read = File.join(@temporary, "private.sqlite3")
    @forbidden_write = File.join(@temporary, "outside.txt")
    File.write(@forbidden_read, "private\n")
    File.write(@forbidden_write, "preserve\n")
  end

  def teardown
    FileUtils.remove_entry(@temporary) if @temporary && File.exist?(@temporary)
  end

  def test_preflight_runs_without_git_changes_and_binds_environment_policy_and_executable
    execution = runner
    result = execution.preflight(spec: spec)
    descriptor = result.slice("receipt_path", "receipt_sha256")
    receipt = execution.verify_preflight!(descriptor, spec: spec)

    assert_equal "passed", result.fetch("conclusion"), private_log(receipt.dig("stderr", "path"))
    assert_equal "sandbox-env-v1", receipt.fetch("environment_id")
    assert_equal spec, receipt.fetch("declared_environment")
    assert_equal execution.send(:policy_manifest), receipt.fetch("execution_policy")
    profile = execution.send(:sandbox_profile, File.join(@state_dir, "execution", "profile-fixture"))
    assert_includes profile, '(allow iokit-open (iokit-user-client-class "RootDomainUserClient"))'
    refute_includes profile, "(allow iokit*)"
    assert_includes profile, '(allow mach-register (global-name-prefix "org.chromium.Chromium.MachPortRendezvousServer."))'
    assert_includes profile, '(allow mach-lookup (global-name-prefix "org.chromium.Chromium.MachPortRendezvousServer."))'
    assert_equal File.realpath(RbConfig.ruby), receipt.dig("executable_identity", "path")
    assert_equal({"forbidden_read" => "blocked", "forbidden_write" => "blocked", "network" => "blocked"}, receipt.fetch("isolation"))
    assert_equal "preserve\n", File.read(@forbidden_write)

    reused = execution.preflight(spec: spec)
    assert_equal true, reused.fetch("reused")
    assert_equal result.fetch("receipt_sha256"), reused.fetch("receipt_sha256")
  end

  def test_preflight_nonzero_is_failed_and_signal_is_startup_failed
    failed = spec.merge("id" => "failed", "argv" => [File.realpath(RbConfig.ruby), "-e", "exit 7"])
    result = runner.preflight(spec: failed)
    receipt = runner.verify_preflight!(result.slice("receipt_path", "receipt_sha256"), spec: failed)
    assert_equal "failed", receipt.fetch("conclusion")
    assert_equal 7, receipt.fetch("exit_status")
    assert_nil receipt.fetch("term_signal")

    signaled = spec.merge("id" => "signaled", "argv" => [File.realpath(RbConfig.ruby), "-e", 'Process.kill("KILL", Process.pid)'])
    result = runner.preflight(spec: signaled)
    receipt = runner.verify_preflight!(result.slice("receipt_path", "receipt_sha256"), spec: signaled)
    assert_equal "startup_failed", receipt.fetch("conclusion")
    assert_equal 9, receipt.fetch("term_signal")
  end

  def test_declared_startup_marker_separates_launcher_failure_from_smoke_failure
    startup = spec.merge(
      "id" => "launcher-failed",
      "argv" => [File.realpath(RbConfig.ruby), "-e", "warn 'launcher died'; exit 1"],
      "startup_success_marker" => "ENVIRONMENT_STARTED"
    )
    result = runner.preflight(spec: startup)
    receipt = runner.verify_preflight!(result.slice("receipt_path", "receipt_sha256"), spec: startup)
    assert_equal "startup_failed", receipt.fetch("conclusion")
    assert_equal false, receipt.fetch("startup_completed")

    silent = startup.merge("id" => "missing-marker", "argv" => [File.realpath(RbConfig.ruby), "-e", "exit 0"])
    result = runner.preflight(spec: silent)
    receipt = runner.verify_preflight!(result.slice("receipt_path", "receipt_sha256"), spec: silent)
    assert_equal "startup_failed", receipt.fetch("conclusion")

    smoke = startup.merge(
      "id" => "smoke-failed",
      "argv" => [File.realpath(RbConfig.ruby), "-e", "puts 'ENVIRONMENT_STARTED'; exit 2"]
    )
    result = runner.preflight(spec: smoke)
    receipt = runner.verify_preflight!(result.slice("receipt_path", "receipt_sha256"), spec: smoke)
    assert_equal "failed", receipt.fetch("conclusion")
    assert_equal true, receipt.fetch("startup_completed")
  end

  def test_preflight_verification_rejects_environment_and_executable_drift
    execution = runner
    result = execution.preflight(spec: spec)
    descriptor = result.slice("receipt_path", "receipt_sha256")
    changed = spec.merge("environment_id" => "different")
    assert_raises(HrmKernel::Error) { execution.verify_preflight!(descriptor, spec: changed) }

    executable = File.join(@project_root, "startup")
    File.write(executable, "#!/bin/sh\nexit 0\n")
    File.chmod(0o700, executable)
    local_spec = spec.merge("id" => "mutable-launcher", "argv" => [executable])
    result = execution.preflight(spec: local_spec)
    descriptor = result.slice("receipt_path", "receipt_sha256")
    assert_equal "passed", execution.verify_preflight!(descriptor, spec: local_spec)["conclusion"]
    File.write(executable, "#!/bin/sh\nexit 9\n")
    error = assert_raises(HrmKernel::Error) { execution.verify_preflight!(descriptor, spec: local_spec) }
    assert_match(/executable identity drifted/, error.message)
  end

  private

  def runner
    HrmKernel::Execution.new(
      project_root: @project_root,
      state_dir: @state_dir,
      environment_allowlist: %w[RUN_ROOT],
      forbidden_read_path: @forbidden_read,
      forbidden_write_path: @forbidden_write
    )
  end

  def spec
    {
      "id" => "ruby-startup",
      "environment_id" => "sandbox-env-v1",
      "argv" => [File.realpath(RbConfig.ruby), "-e", 'puts "started"'],
      "env" => {"RUN_ROOT" => "{run_root}"},
      "cwd" => @project_root,
      "timeout_seconds" => 10,
      "max_output_bytes" => 4096,
      "configuration_paths" => ["{run_root}"]
    }
  end

  def private_log(relative)
    File.binread(File.join(@state_dir, relative))
  end
end
