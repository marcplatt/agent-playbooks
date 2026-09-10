# frozen_string_literal: true

require_relative "error"
require_relative "host"

module HrmKernel
  module ContributionHistory
    KEYS = %w[artifacts_sha256 check_ids claim_id evidence_digest last_owner_id required_action revision work_order_id].freeze
    MAX_RECORDS = 256

    module_function

    def build(previous:, state:, commands:)
      prior = Array(previous).map { |entry| normalize(entry) }
      ledger = Array(commands).map { |command| record_from_command(command, state) }.compact
      records = (prior + ledger).uniq do |entry|
        [entry["work_order_id"], entry["revision"], entry["claim_id"], entry["evidence_digest"]]
      end.sort_by { |entry| [entry.fetch("work_order_id"), entry.fetch("revision"), entry.fetch("evidence_digest")] }
      verify!(records, state: state, commands: commands)
      records
    end

    def record_from_command(command, state)
      return nil unless command.is_a?(Hash) && %w[work_order.submit work_order.refresh_evidence].include?(command["type"])
      data = command["data"]
      actor = command["actor"]
      return nil unless data.is_a?(Hash) && actor.is_a?(Hash) && actor["role"] == "worker"
      order = state.fetch("work_orders")[data["work_order_id"]]
      return nil unless order.is_a?(Hash)
      revision = data["revision"]
      contract = lineage_contract(order, revision)
      return nil unless contract
      artifacts = data["artifacts"]
      checks = data["checks"]
      return nil unless artifacts.is_a?(Array) && checks.is_a?(Array)
      {
        "work_order_id" => data["work_order_id"], "revision" => revision,
        "claim_id" => data["claim_id"], "last_owner_id" => actor["id"],
        "evidence_digest" => Host.digest({ "revision" => revision, "artifacts" => artifacts, "checks" => checks }),
        "check_ids" => contract["check_ids"],
        "artifacts_sha256" => Host.digest(artifacts),
        "required_action" => "fresh_native_revalidation_under_active_environment"
      }
    end

    def verify!(records, state:, commands:)
      fail!("completed contribution registry is malformed") unless records.is_a?(Array) && records.length <= MAX_RECORDS
      identities = []
      records.map do |entry|
        validate_shape!(entry)
        identity = [entry["work_order_id"], entry["revision"], entry["claim_id"], entry["evidence_digest"]]
        fail!("completed contribution registry contains a duplicate") if identities.include?(identity)
        identities << identity
        submission = matching_submission(entry, commands)
        fail!("completed contribution is absent from the verified ledger") unless submission
        validate_current_lineage!(entry, state.fetch("work_orders")[entry["work_order_id"]], submission.fetch("data"))
      end
    end

    def normalize(entry)
      fail!("completed contribution registry is malformed") unless entry.is_a?(Hash) && entry.keys.sort == KEYS.sort
      entry.slice(*KEYS)
    end

    def validate_shape!(entry)
      valid = entry.is_a?(Hash) && entry.keys.sort == KEYS.sort &&
        Host::IDENTIFIER.match?(entry["work_order_id"].to_s) &&
        Host::IDENTIFIER.match?(entry["claim_id"].to_s) &&
        Host::IDENTIFIER.match?(entry["last_owner_id"].to_s) &&
        entry["revision"].is_a?(Integer) && entry["revision"].positive? &&
        Host.strings?(entry["check_ids"]) && entry["check_ids"].uniq == entry["check_ids"] &&
        entry["evidence_digest"].is_a?(String) && entry["evidence_digest"].match?(/\A[0-9a-f]{64}\z/) &&
        entry["artifacts_sha256"].is_a?(String) && entry["artifacts_sha256"].match?(/\A[0-9a-f]{64}\z/)
      fail!("completed contribution registry is malformed") unless valid
      fail!("completed contribution action is malformed") unless
        entry["required_action"] == "fresh_native_revalidation_under_active_environment"
    end

    def matching_submission(entry, commands)
      Array(commands).find do |command|
        next false unless command.is_a?(Hash) && %w[work_order.submit work_order.refresh_evidence].include?(command["type"])
        data = command["data"]
        actor = command["actor"]
        next false unless data.is_a?(Hash) && actor.is_a?(Hash) &&
          data["work_order_id"] == entry["work_order_id"] && data["revision"] == entry["revision"] &&
          data["claim_id"] == entry["claim_id"] && actor["role"] == "worker" && actor["id"] == entry["last_owner_id"]
        artifacts = data["artifacts"]
        checks = data["checks"]
        artifacts.is_a?(Array) && checks.is_a?(Array) &&
          Host.digest(artifacts) == entry["artifacts_sha256"] &&
          Host.digest({ "revision" => data["revision"], "artifacts" => artifacts, "checks" => checks }) == entry["evidence_digest"] &&
          checks.map { |check| check["id"] }.sort == entry["check_ids"].sort
      end
    end

    def validate_current_lineage!(entry, order, data)
      fail!("completed contribution work order is missing") unless order.is_a?(Hash)
      fail!("completed contribution claim left work-order history") unless Array(order["claim_history"]).include?(entry["claim_id"])
      current = order["revision"] == entry["revision"] && order["status"] == "completed"
      contract = lineage_contract(order, entry["revision"])
      fail!("completed contribution revision left amendment history") unless contract.is_a?(Hash)
      fail!("completed contribution check contract changed") unless contract["check_ids"] == entry["check_ids"]
      artifact_paths = data.fetch("artifacts").map { |artifact| artifact["path"] }
      fail!("completed contribution paths left revision history") unless (artifact_paths - Array(contract["paths"])).empty?
      {
        "work_order_id" => entry.fetch("work_order_id"),
        "evidence_revision" => entry.fetch("revision"),
        "current_revision" => order.fetch("revision"),
        "current_status" => order.fetch("status"),
        "current_disposition" => current ? "completed_pending_revalidation" : "superseded_by_work_order_revision",
        "required_action" => current ? "fresh_native_revalidation_under_active_environment" :
          "historical_only_complete_current_revision_then_validate"
      }
    rescue KeyError
      fail!("completed contribution ledger evidence is malformed")
    end

    def lineage_contract(order, revision)
      return order if order["revision"] == revision && order["status"] == "completed"
      return nil unless order["revision"].is_a?(Integer) && revision.is_a?(Integer) && order["revision"] > revision
      Array(order["amendments"]).find { |amendment| amendment["revision"] == revision }
    end

    def fail!(message)
      raise HrmKernel::Error.new("invalid_driver_state", message)
    end
  end
end
