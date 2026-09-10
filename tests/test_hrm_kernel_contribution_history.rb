# frozen_string_literal: true

require "minitest/autorun"

require_relative "../lib/hrm_kernel/contribution_history"

class HrmKernelContributionHistoryTest < Minitest::Test
  def test_captures_submit_amended_before_continuation_and_derives_later_lineage
    commands = [submission]
    state = state_for(revision: 2, status: "queued", amendments: [contract(1)])

    records = HrmKernel::ContributionHistory.build(previous: [], state: state, commands: commands)

    assert_equal 1, records.length
    assert_equal HrmKernel::ContributionHistory::KEYS.sort, records.first.keys.sort
    assert_equal 1, records.first.fetch("revision")
    status = HrmKernel::ContributionHistory.verify!(records, state: state, commands: commands).first
    assert_equal "superseded_by_work_order_revision", status.fetch("current_disposition")
    assert_equal 2, status.fetch("current_revision")

    state = state_for(revision: 3, status: "running", amendments: [contract(1), contract(2)],
      last_owner_id: "worker-new", claim_history: %w[claim-old claim-new])
    later = HrmKernel::ContributionHistory.verify!(records, state: state, commands: commands).first
    assert_equal "superseded_by_work_order_revision", later.fetch("current_disposition")
    assert_equal 3, later.fetch("current_revision")
    assert_equal "running", later.fetch("current_status")
  end

  def test_rejects_tampered_provenance_and_missing_amendment_lineage
    state = state_for(revision: 2, status: "queued", amendments: [contract(1)])
    records = HrmKernel::ContributionHistory.build(previous: [], state: state, commands: [submission])
    tampered = Marshal.load(Marshal.dump(records))
    tampered.first["check_ids"] = ["different-check"]

    error = assert_raises(HrmKernel::Error) do
      HrmKernel::ContributionHistory.verify!(tampered, state: state, commands: [submission])
    end
    assert_match(/verified ledger/, error.message)

    no_lineage = state_for(revision: 2, status: "queued", amendments: [])
    error = assert_raises(HrmKernel::Error) do
      HrmKernel::ContributionHistory.verify!(records, state: no_lineage, commands: [submission])
    end
    assert_match(/amendment history/, error.message)
  end

  private

  def artifacts
    [{ "path" => "src/provider.rb", "sha256" => "1" * 64 }]
  end

  def checks
    [{ "id" => "provider-check", "conclusion" => "passed",
      "artifact_path" => ".codex/hrm-runs/native-checks/provider.json", "sha256" => "2" * 64 }]
  end

  def submission
    {
      "command_id" => "submit-provider-r1", "type" => "work_order.submit",
      "actor" => { "id" => "worker-old", "role" => "worker" },
      "data" => { "work_order_id" => "provider", "revision" => 1, "claim_id" => "claim-old",
        "artifacts" => artifacts, "checks" => checks }
    }
  end

  def contract(revision)
    { "revision" => revision, "intent_ids" => ["milestone_initial"],
      "requirement_ids" => ["behavior"], "paths" => ["src/provider.rb"],
      "check_ids" => ["provider-check"] }
  end

  def state_for(revision:, status:, amendments:, last_owner_id: "worker-old", claim_history: ["claim-old"])
    {
      "work_orders" => {
        "provider" => contract(revision).merge(
          "id" => "provider", "revision" => revision, "status" => status,
          "claim_history" => claim_history, "last_owner_id" => last_owner_id,
          "amendments" => amendments
        )
      }
    }
  end
end
