# frozen_string_literal: true

require "minitest/autorun"
require "tmpdir"
require_relative "../scripts/project_api_skill_registry"

class ProjectApiSkillRegistryTest < Minitest::Test
  ROOT = File.expand_path("..", __dir__)
  CAPSULE = File.join(ROOT, "examples/hrm-execution-capsule.example.yaml")
  REGISTRY = File.join(ROOT, "examples/project-api-skill-registry.example.yaml")

  def test_reuses_an_apm_skill_across_hrms_and_kernel_versions
    capsule = HrmExperiment.load_yaml(CAPSULE)
    registry = HrmExperiment.load_yaml(REGISTRY)
    skill = registry.fetch("skills").first

    refute_equal capsule.dig("hrm", "id"), skill.dig("provenance", "source_hrm_id")
    refute_equal capsule.dig("playbook_pin", "kernel_version"),
                 skill.dig("provenance", "source_kernel_version")
    assert_equal %w[
      product-master.configuration.get
      product-master.catalog-price.get
    ], skill.fetch("calls").map { |call| call.fetch("call_id") }
    assert skill.fetch("calls").all? { |call| call["effect_class"] == "read_only" }

    coverage = ProjectApiSkillRegistry.coverage(capsule, registry)
    assert_equal ["product-master.catalog-price.read"], coverage["reusable_skill_ids"]
    assert_empty coverage["missing_skill_ids"]
  end

  def test_cross_repository_reuse_requires_master_plan_acceptance
    capsule = deep_copy(HrmExperiment.load_yaml(CAPSULE))
    capsule["system_reference"] = "SYS-CONSUMER-002"
    registry = deep_copy(HrmExperiment.load_yaml(REGISTRY))

    project_only = ProjectApiSkillRegistry.coverage(capsule, registry)
    assert_empty project_only["reusable_skill_ids"]
    assert_equal ["product-master.catalog-price.read"], project_only["missing_skill_ids"]

    portability = registry.dig("skills", 0, "portability")
    portability["transfer_status"] = "master_plan_accepted"
    portability["master_plan_intake_id"] = "MP-API-SKILL-0001"
    registry["registry_hash"] = ProjectApiSkillRegistry.registry_hash(registry)

    accepted = ProjectApiSkillRegistry.coverage(capsule, registry)
    assert_equal ["product-master.catalog-price.read"], accepted["reusable_skill_ids"]
    assert_empty accepted["missing_skill_ids"]
  end

  def test_changed_contract_fingerprint_requires_rediscovery
    capsule = deep_copy(HrmExperiment.load_yaml(CAPSULE))
    capsule.dig("project_api_skills", "required_skills", 0)["contract_fingerprint"] = "c" * 64

    coverage = ProjectApiSkillRegistry.coverage(
      capsule,
      HrmExperiment.load_yaml(REGISTRY)
    )

    assert_empty coverage["reusable_skill_ids"]
    assert_equal ["product-master.catalog-price.read"], coverage["missing_skill_ids"]
  end

  def test_registry_rejects_an_opaque_or_hand_entered_contract_fingerprint
    registry = deep_copy(HrmExperiment.load_yaml(REGISTRY))
    registry.dig("skills", 0)["contract_fingerprint"] = "e" * 64
    registry["registry_hash"] = ProjectApiSkillRegistry.registry_hash(registry)

    error = assert_raises(HrmExperiment::ValidationError) do
      ProjectApiSkillRegistry.validate_registry!(registry)
    end
    assert_includes error.message, "contract fingerprint mismatch"
  end

  def test_registry_rejects_secrets_customer_data_and_live_provider_state
    %w[contains_secrets contains_customer_data contains_live_provider_state].each do |field|
      registry = deep_copy(HrmExperiment.load_yaml(REGISTRY))
      registry.dig("skills", 0, "privacy")[field] = true
      registry["registry_hash"] = ProjectApiSkillRegistry.registry_hash(registry)

      assert_raises(HrmExperiment::ValidationError) do
        ProjectApiSkillRegistry.validate_registry!(registry)
      end
    end
  end

  def test_publication_requires_conclusive_skill_evidence_and_cannot_self_accept_transfer
    Dir.mktmpdir do |directory|
      FileUtils.mkdir_p(File.join(directory, ".git"))
      capsule = deep_copy(HrmExperiment.load_yaml(CAPSULE))
      capsule.dig("project_api_skills")["registry_path"] = "project-api-skills.yaml"
      capsule_path = File.join(directory, "capsule.yaml")
      File.write(capsule_path, YAML.dump(capsule), mode: "w", perm: 0o600)

      registry = {
        "schema_version" => "agent_playbooks.project_api_skill_registry.v0.1",
        "registry_id" => capsule.dig("project_api_skills", "registry_id"),
        "registry_scope" => "cross_repository",
        "registry_version" => 1,
        "updated_at" => "2026-08-25T00:00:00Z",
        "skills" => [],
        "registry_hash" => nil
      }
      registry["registry_hash"] = ProjectApiSkillRegistry.registry_hash(registry)
      registry_path = File.join(directory, "project-api-skills.yaml")
      File.write(registry_path, YAML.dump(registry), mode: "w", perm: 0o644)

      event = conclusive_skill_event(capsule)
      events_path = File.join(directory, "events.jsonl")
      File.write(events_path, "#{JSON.generate(event)}\n", mode: "w", perm: 0o600)
      record = source_record(capsule, event)

      receipt = ProjectApiSkillRegistry.publish(capsule_path, events_path, record)
      assert receipt["changed"]
      assert_equal 2, receipt["registry_version"]
      stored = HrmExperiment.load_yaml(registry_path)
      assert_equal [record["skill_id"]], stored.fetch("skills").map { |item| item["skill_id"] }

      unchanged = ProjectApiSkillRegistry.publish(capsule_path, events_path, record)
      refute unchanged["changed"]
      assert_equal receipt["registry_hash"], unchanged["registry_hash"]

      self_accepted = deep_copy(record)
      self_accepted.dig("portability")["transfer_status"] = "master_plan_accepted"
      self_accepted.dig("portability")["master_plan_intake_id"] = "MP-UNVERIFIED-0001"
      error = assert_raises(HrmExperiment::ValidationError) do
        ProjectApiSkillRegistry.publish(capsule_path, events_path, self_accepted)
      end
      assert_includes error.message, "cannot claim software-master-plan acceptance"
    end
  end

  private

  def deep_copy(value)
    Marshal.load(Marshal.dump(value))
  end

  def conclusive_skill_event(capsule)
    {
      "schema_version" => "agent_playbooks.hrm_run_event.v0.3",
      "session_id" => capsule.fetch("session_id"),
      "hrm_id" => capsule.dig("hrm", "id"),
      "sequence" => 1,
      "event_type" => "check_completed",
      "occurred_at" => "2026-08-27T12:00:00Z",
      "role" => "checker",
      "check" => {
        "name" => "project-api-skill:product-master.catalog-price.read",
        "environment_id" => "local:contract-test",
        "conclusion" => "passed",
        "duration_seconds" => 1,
        "conclusive" => true,
        "summary" => "The stable APM call contract passed its declared check.",
        "raw_artifact_path" => "artifacts/apm-contract-check.log",
        "raw_artifact_sha256" => "d" * 64,
        "raw_artifact_bytes" => 1
      }
    }
  end

  def source_record(capsule, event)
    record = deep_copy(HrmExperiment.load_yaml(REGISTRY).fetch("skills").first)
    record["record_id"] = "API-SKILL-PUBLISHED-001"
    record["provenance"] = {
      "source_session_id" => capsule.fetch("session_id"),
      "source_hrm_id" => capsule.dig("hrm", "id"),
      "source_project_id" => capsule.fetch("system_reference"),
      "source_repository" => capsule.dig("repository_bases", 0, "repository"),
      "source_kernel_id" => capsule.dig("playbook_pin", "kernel_id"),
      "source_kernel_version" => capsule.dig("playbook_pin", "kernel_version"),
      "evidence_event_sequence" => event.fetch("sequence"),
      "evidence_event_sha256" => HrmExperiment.object_sha256(event),
      "observed_at" => event.fetch("occurred_at")
    }
    record
  end
end
