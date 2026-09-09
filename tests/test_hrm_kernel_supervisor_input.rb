# frozen_string_literal: true

require "fileutils"
require "json"
require "minitest/autorun"
require "tmpdir"

require_relative "../lib/hrm_kernel/store"
require_relative "../lib/hrm_kernel/supervisor_input"

class HrmKernelSupervisorInputTest < Minitest::Test
  def setup
    @temporary = File.realpath(Dir.mktmpdir("hrm-supervisor-input"))
    @store = HrmKernel::Store.new(File.join(@temporary, "state"))
    @driver_dir = File.join(@store.directory, "driver")
    HrmKernel::Host.private_directory!(@driver_dir)
    @inputs = HrmKernel::SupervisorInput.new(directory: @driver_dir)
  end

  def teardown
    FileUtils.remove_entry(@temporary)
  end

  def test_exact_contract_is_append_only_hash_chained_and_restart_safe
    first = @inputs.append(observation, observed_cursor: 0)
    assert_equal 1, first["cursor"]
    refute first["replayed"]
    assert_equal false, first.dig("provenance", "authenticated_human")
    assert_equal "non_authorizing_technical_evidence", first.dig("provenance", "authority")
    assert_equal 0, @store.read["cursor"], "technical input must not enter the operator ledger"

    replay = HrmKernel::SupervisorInput.new(directory: @driver_dir).append(observation, observed_cursor: 0)
    assert replay["replayed"]
    assert_equal first["input_record_hash"], replay["input_record_hash"]

    second = @inputs.append(interruption, observed_cursor: 1)
    records = HrmKernel::SupervisorInput.new(directory: @driver_dir).read_after(0).fetch("records")
    assert_equal [1, 2], records.map { |record| record["sequence"] }
    assert_nil records.first["previous_hash"]
    assert_equal records.first["record_hash"], records.last["previous_hash"]
    assert_equal "context_exhausted", records.last.dig("input", "interruption", "reason_code")
    assert_equal({"input_tokens" => 1200, "output_tokens" => 80}, records.last.dig("input", "usage"))
    assert_equal second["record_hash"], @inputs.snapshot["record_hash"]
  end

  def test_conflicting_id_is_rejected_without_an_append
    @inputs.append(observation, observed_cursor: 0)
    conflict = observation.merge("summary" => "Different assertion")
    error = assert_raises(HrmKernel::Error) { @inputs.append(conflict, observed_cursor: 0) }
    assert_match(/already used/, error.message)
    assert_equal 1, @inputs.snapshot["cursor"]
  end

  def test_invalid_authority_shapes_and_limits_are_rejected
    invalid = [
      observation.merge("operator" => {"id" => "human"}),
      observation.merge("summary" => "x" * (HrmKernel::SupervisorInput::MAX_SUMMARY_BYTES + 1)),
      observation.merge("facts" => Array.new(HrmKernel::SupervisorInput::MAX_FACTS + 1) { |i| {"name" => "fact-#{i}", "value" => "x"} }),
      interruption.merge("observed_job" => nil),
      interruption.merge("interruption" => {"failed" => false, "reason_code" => "context_exhausted"}),
      observation.merge("usage" => {"service_failure" => 1})
    ]
    invalid.each { |input| assert_raises(HrmKernel::Error) { @inputs.append(input, observed_cursor: 0) } }
    assert_equal 0, @inputs.snapshot["cursor"]
  end

  private

  # Exact public driver-input fixture used by the RC36 documentation.
  def observation
    {
      "input_id" => "supervisor-fact-1",
      "kind" => "technical_observation",
      "source" => {"adapter_id" => "rc36-supervisor", "reference" => "task:supervisor/turn:7"},
      "summary" => "The prior worker returned partial implementation evidence.",
      "facts" => [{"name" => "partial_files", "value" => "lib/example.rb"}],
      "observed_job" => {"job_id" => "worker-1", "status" => "succeeded"},
      "usage" => {"input_tokens" => 900, "output_tokens" => 120}
    }
  end

  def interruption
    {
      "input_id" => "supervisor-interruption-1",
      "kind" => "execution_interruption",
      "source" => {"adapter_id" => "rc36-supervisor", "reference" => "task:worker-1/turn:8"},
      "summary" => "The native worker turn ended before it could return its structured result.",
      "facts" => [],
      "observed_job" => {"job_id" => "worker-1", "status" => "failed"},
      "interruption" => {"failed" => true, "reason_code" => "context_exhausted", "detail" => "The trusted adapter observed context exhaustion."},
      "usage" => {"input_tokens" => 1200, "output_tokens" => 80}
    }
  end
end
