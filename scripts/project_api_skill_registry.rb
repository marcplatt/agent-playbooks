#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "securerandom"
require "set"
require "yaml"
require_relative "hrm_experiment"

module ProjectApiSkillRegistry
  MAX_REQUIRED_SKILLS = 64
  MAX_REGISTRY_SKILLS = 256

  module_function

  def validate_registry!(registry)
    HrmExperiment.validator("project-api-skill-registry.schema.json").validate!(registry)
    expected_hash = HrmExperiment.object_sha256(
      registry.reject { |key, _value| key == "registry_hash" }
    )
    unless registry["registry_hash"] == expected_hash
      raise HrmExperiment::ValidationError, "project API skill registry hash mismatch"
    end

    skills = registry.fetch("skills")
    if skills.length > MAX_REGISTRY_SKILLS
      raise HrmExperiment::ValidationError,
            "project API skill registry exceeds #{MAX_REGISTRY_SKILLS} skills"
    end

    record_ids = skills.map { |record| record.fetch("record_id") }
    unless record_ids.uniq.length == record_ids.length
      raise HrmExperiment::ValidationError, "project API skill record_id must be unique"
    end

    active = skills.select { |record| record["status"] == "active" }
    active_ids = active.map { |record| record.fetch("skill_id") }
    unless active_ids.uniq.length == active_ids.length
      raise HrmExperiment::ValidationError, "only one active record is allowed per API skill"
    end

    skills.each do |record|
      unless record["contract_fingerprint"] == contract_fingerprint(record)
        raise HrmExperiment::ValidationError,
              "project API skill #{record['skill_id']} contract fingerprint mismatch"
      end
      call_ids = record.fetch("calls").map { |call| call.fetch("call_id") }
      unless call_ids.uniq.length == call_ids.length
        raise HrmExperiment::ValidationError,
              "project API skill #{record['skill_id']} call_id must be unique"
      end
      portability = record.fetch("portability")
      accepted = portability["transfer_status"] == "master_plan_accepted"
      intake_id = portability["master_plan_intake_id"]
      if accepted != !intake_id.nil?
        raise HrmExperiment::ValidationError,
              "master-plan-accepted API skill must carry exactly one intake ID"
      end
    end

    known_ids = record_ids.to_set
    skills.each do |record|
      predecessor = record["supersedes_record_id"]
      next if predecessor.nil?

      unless known_ids.include?(predecessor)
        raise HrmExperiment::ValidationError,
              "project API skill #{record['record_id']} supersedes an unknown record"
      end
    end
    true
  end

  def registry_hash(registry)
    HrmExperiment.object_sha256(registry.reject { |key, _value| key == "registry_hash" })
  end

  def contract_fingerprint(record)
    HrmExperiment.object_sha256(
      {
        "provider_system" => record.fetch("provider_system"),
        "skill_kind" => record.fetch("skill_kind"),
        "contract_version" => record.fetch("contract_version"),
        "calls" => record.fetch("calls")
      }
    )
  end

  def repository_root(capsule_path)
    directory = File.dirname(File.expand_path(capsule_path))
    loop do
      return directory if File.exist?(File.join(directory, ".git"))

      parent = File.dirname(directory)
      break if parent == directory

      directory = parent
    end
    raise HrmExperiment::ValidationError, "cannot resolve repository root from capsule path #{capsule_path}"
  end

  def registry_path(capsule, capsule_path)
    root = repository_root(capsule_path)
    relative = capsule.dig("project_api_skills", "registry_path")
    expanded = File.expand_path(relative, root)
    unless expanded.start_with?("#{root}#{File::SEPARATOR}")
      raise HrmExperiment::ValidationError, "project API skill registry must remain inside the project repository"
    end
    expanded
  end

  def load_registry_for_capsule(capsule, capsule_path)
    path = registry_path(capsule, capsule_path)
    registry = HrmExperiment.load_yaml(path)
    validate_registry!(registry)
    unless registry["registry_id"] == capsule.dig("project_api_skills", "registry_id")
      raise HrmExperiment::ValidationError,
            "project API skill registry_id must equal the capsule registry_id"
    end
    [registry, path]
  end

  def coverage(capsule, registry)
    validate_registry!(registry)
    required = capsule.dig("project_api_skills", "required_skills") || []
    if required.length > MAX_REQUIRED_SKILLS
      raise HrmExperiment::ValidationError,
            "capsule exceeds #{MAX_REQUIRED_SKILLS} required project API skills"
    end

    active = registry.fetch("skills").select { |record| record["status"] == "active" }
    active_by_id = active.to_h { |record| [record.fetch("skill_id"), record] }
    reusable = []
    missing = []
    required.each do |requirement|
      record = active_by_id[requirement.fetch("skill_id")]
      portable = record && (
        record.dig("provenance", "source_project_id") == capsule["system_reference"] ||
        record.dig("portability", "transfer_status") == "master_plan_accepted"
      )
      if portable && record["contract_fingerprint"] == requirement["contract_fingerprint"]
        reusable << requirement.fetch("skill_id")
      else
        missing << requirement.fetch("skill_id")
      end
    end

    {
      "registry_hash" => registry.fetch("registry_hash"),
      "required_count" => required.length,
      "reusable_skill_ids" => reusable.sort,
      "missing_skill_ids" => missing.sort
    }
  end

  def coverage_for_capsule(capsule, capsule_path)
    registry, = load_registry_for_capsule(capsule, capsule_path)
    coverage(capsule, registry)
  end

  def publish(capsule_path, events_path, record)
    capsule = HrmExperiment.load_yaml(capsule_path)
    HrmExperiment.validate_capsule!(capsule)
    events = HrmExperiment.load_events(events_path)
    HrmExperiment.validate_events!(events)
    validate_source_record!(capsule, events, record)

    registry, path = load_registry_for_capsule(capsule, capsule_path)
    updated = Marshal.load(Marshal.dump(registry))
    active = updated.fetch("skills").find do |candidate|
      candidate["skill_id"] == record["skill_id"] && candidate["status"] == "active"
    end

    if active && active["contract_fingerprint"] == record["contract_fingerprint"]
      return publish_receipt(path, updated, active, false)
    end

    if active
      unless record["supersedes_record_id"] == active["record_id"]
        raise HrmExperiment::ValidationError,
              "changed API skill must supersede active record #{active['record_id']}"
      end
      active["status"] = "superseded"
    elsif record["supersedes_record_id"]
      raise HrmExperiment::ValidationError, "new API skill cannot supersede a missing active record"
    end

    updated.fetch("skills") << Marshal.load(Marshal.dump(record))
    updated["registry_version"] += 1
    updated["updated_at"] = record.dig("provenance", "observed_at")
    updated["registry_hash"] = registry_hash(updated)
    validate_registry!(updated)
    write_registry(path, updated)
    publish_receipt(path, updated, record, true)
  end

  def validate_source_record!(capsule, events, record)
    unless record.is_a?(Hash)
      raise HrmExperiment::ValidationError, "API skill publication input must be a JSON object"
    end
    candidate = {
      "schema_version" => "agent_playbooks.project_api_skill_registry.v0.1",
      "registry_id" => capsule.dig("project_api_skills", "registry_id"),
      "registry_scope" => "cross_repository",
      "registry_version" => 1,
      "updated_at" => record.dig("provenance", "observed_at"),
      "skills" => [record],
      "registry_hash" => "0" * 64
    }
    candidate["registry_hash"] = registry_hash(candidate)
    validate_registry!(candidate)

    provenance = record.fetch("provenance")
    portability = record.fetch("portability")
    unless portability["transfer_status"] == "project_verified" &&
           portability["master_plan_intake_id"].nil?
      raise HrmExperiment::ValidationError,
            "project publication cannot claim software-master-plan acceptance"
    end
    unless provenance["source_session_id"] == capsule["session_id"] &&
           provenance["source_hrm_id"] == capsule.dig("hrm", "id") &&
           provenance["source_project_id"] == capsule["system_reference"]
      raise HrmExperiment::ValidationError, "API skill provenance must match the active capsule"
    end
    repositories = capsule.fetch("repository_bases").map { |binding| binding.fetch("repository") }
    unless repositories.include?(provenance["source_repository"])
      raise HrmExperiment::ValidationError, "API skill source_repository must be bound by the active capsule"
    end
    unless provenance["source_kernel_id"] == capsule.dig("playbook_pin", "kernel_id") &&
           provenance["source_kernel_version"] == capsule.dig("playbook_pin", "kernel_version")
      raise HrmExperiment::ValidationError, "API skill provenance must match the active kernel pin"
    end

    event = events.find { |candidate| candidate["sequence"] == provenance["evidence_event_sequence"] }
    unless event && event["event_type"] == "check_completed" && event.dig("check", "conclusion") == "passed" &&
           event.dig("check", "conclusive") == true
      raise HrmExperiment::ValidationError, "API skill publication requires a conclusive passed check event"
    end
    expected_name = "project-api-skill:#{record.fetch('skill_id')}"
    unless event.dig("check", "name") == expected_name
      raise HrmExperiment::ValidationError, "API skill check name must equal #{expected_name}"
    end
    unless provenance["evidence_event_sha256"] == HrmExperiment.object_sha256(event)
      raise HrmExperiment::ValidationError, "API skill evidence event hash mismatch"
    end

  end

  def publish_receipt(path, registry, record, changed)
    {
      "registry_path" => path,
      "registry_version" => registry.fetch("registry_version"),
      "registry_hash" => registry.fetch("registry_hash"),
      "skill_id" => record.fetch("skill_id"),
      "contract_fingerprint" => record.fetch("contract_fingerprint"),
      "changed" => changed
    }
  end

  def write_registry(path, registry)
    temporary = "#{path}.tmp-#{Process.pid}-#{SecureRandom.hex(6)}"
    File.open(temporary, File::WRONLY | File::CREAT | File::EXCL, 0o644) do |file|
      file.write(YAML.dump(registry))
      file.flush
      file.fsync
    end
    File.rename(temporary, path)
    File.chmod(0o644, path)
    File.open(File.dirname(path), File::RDONLY) { |directory| directory.fsync }
  rescue Errno::EINVAL, Errno::EISDIR
    nil
  ensure
    FileUtils.rm_f(temporary) if defined?(temporary)
  end

  def usage
    <<~TEXT
      Usage:
        ruby scripts/project_api_skill_registry.rb validate REGISTRY.yaml
        ruby scripts/project_api_skill_registry.rb coverage CAPSULE.yaml
        ruby scripts/project_api_skill_registry.rb publish CAPSULE.yaml EVENTS.jsonl < API_SKILL.json
    TEXT
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    command = ARGV.shift
    result = case command
             when "validate"
               path = ARGV.shift or raise HrmExperiment::ValidationError, ProjectApiSkillRegistry.usage
               registry = HrmExperiment.load_yaml(path)
               ProjectApiSkillRegistry.validate_registry!(registry)
               {"registry_path" => File.expand_path(path), "registry_hash" => registry.fetch("registry_hash")}
             when "coverage"
               capsule_path = ARGV.shift or raise HrmExperiment::ValidationError, ProjectApiSkillRegistry.usage
               capsule = HrmExperiment.load_yaml(capsule_path)
               HrmExperiment.validate_capsule!(capsule)
               ProjectApiSkillRegistry.coverage_for_capsule(capsule, capsule_path)
             when "publish"
               capsule_path = ARGV.shift or raise HrmExperiment::ValidationError, ProjectApiSkillRegistry.usage
               events_path = ARGV.shift or raise HrmExperiment::ValidationError, ProjectApiSkillRegistry.usage
               ProjectApiSkillRegistry.publish(capsule_path, events_path, JSON.parse($stdin.read))
             else
               raise HrmExperiment::ValidationError, ProjectApiSkillRegistry.usage
             end
    puts JSON.generate(result)
  rescue HrmExperiment::ValidationError, JSON::ParserError, Errno::ENOENT, ArgumentError => e
    warn e.message
    exit 2
  end
end
