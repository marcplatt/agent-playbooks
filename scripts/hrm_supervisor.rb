#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "pathname"
require "securerandom"
require "set"
require "time"
require "yaml"
require_relative "hrm_experiment"
require_relative "project_api_skill_registry"

module HrmSupervisor
  MAX_PROJECTION_BYTES = 4096
  MAX_DISPATCH_BYTES = 12_288
  MAX_ATTENTION_ITEMS = 12
  RC9_KERNEL_VERSION = "0.1.0-rc.9"
  CONTEXT_REPORT_INTEGER_FIELDS = %w[
    tool_output_bytes
    omitted_tool_output_bytes
    inline_raw_log_bytes
    state_artifact_echo_bytes
    context_compactions
  ].freeze

  module_function

  def validate_projection!(projection)
    HrmExperiment.validator("hrm-supervisor-projection.schema.json").validate!(projection)
    expected_hash = HrmExperiment.object_sha256(
      projection.reject { |key, _value| key == "projection_hash" }
    )
    unless projection["projection_hash"] == expected_hash
      raise HrmExperiment::ValidationError, "supervisor projection hash mismatch"
    end

    true
  end

  def validate_dispatch!(dispatch)
    HrmExperiment.validator("hrm-dispatch-envelope.schema.json").validate!(dispatch)
    expected_hash = HrmExperiment.object_sha256(
      dispatch.reject { |key, _value| key == "dispatch_hash" }
    )
    unless dispatch["dispatch_hash"] == expected_hash
      raise HrmExperiment::ValidationError, "dispatch envelope hash mismatch"
    end
    if JSON.generate(dispatch).bytesize > MAX_DISPATCH_BYTES
      raise HrmExperiment::ValidationError, "dispatch envelope exceeds #{MAX_DISPATCH_BYTES} bytes"
    end
    true
  end

  def resume(capsule_path, events_path, now = Time.now.utc)
    capsule = HrmExperiment.load_yaml(capsule_path)
    with_run_lock(events_path, capsule) do
      events = load_and_validate_run(capsule, events_path)
      if events.empty?
        append_prepared(capsule, events, events_path, {
          "event_type" => "session_started",
          "occurred_at" => now.iso8601,
          "role" => "orchestrator"
        }, "start", capsule_path)
      elsif current_dispatch_at_cursor?(capsule, events, events_path) &&
            (stop = resume_stop_event(capsule, events, now))
        append_prepared(capsule, events, events_path, stop, "terminalize", capsule_path)
      else
        refresh(capsule, events, events_path, "resume", capsule_path)
      end
    end
  end

  def validate_release(capsule_path, events_path)
    capsule = HrmExperiment.load_yaml(capsule_path)
    HrmExperiment.validate_capsule!(capsule)
    paths = artifact_paths(capsule, events_path)
    present = paths.values.select { |path| File.exist?(path) }
    unless present.empty?
      raise HrmExperiment::ValidationError,
            "release requires an unstarted session with no runtime artifacts: #{present.join(', ')}"
    end

    {
      "action" => "release_check",
      "session_id" => capsule["session_id"],
      "release_ready" => true,
      "event_log_path" => paths["events"]
    }
  end

  def append(capsule_path, events_path, event)
    capsule = HrmExperiment.load_yaml(capsule_path)
    with_run_lock(events_path, capsule) do
      events = load_and_validate_run(capsule, events_path)
      ensure_run_writable!(capsule, events) unless events.empty?
      prepared = prepare_event(capsule, events, event)
      if rc9?(capsule) && prepared["event_type"] == "context_snapshot"
        raise HrmExperiment::ValidationError,
              "rc.9 context snapshots are supervisor-measured; use the context command"
      end
      if prepared["event_type"] == "stop_reason" && prepared.dig("details", "stop_reason") == "superseded"
        raise HrmExperiment::ValidationError,
              "use the supervisor supersede command so the stop is bound to a validated successor"
      end
      append_prepared(capsule, events, events_path, prepared, "append", capsule_path)
    end
  end

  def record_context(capsule_path, events_path, role, report)
    capsule = HrmExperiment.load_yaml(capsule_path)
    unless rc9?(capsule)
      raise HrmExperiment::ValidationError, "the supervisor context command requires an rc.9 capsule"
    end
    with_run_lock(events_path, capsule) do
      events = load_and_validate_run(capsule, events_path)
      ensure_run_writable!(capsule, events)
      paths = artifact_paths(capsule, events_path)
      dispatch = HrmExperiment.load_json(paths["dispatch"])
      validate_dispatch!(dispatch)
      unless dispatch["ledger_cursor"] == events.length
        raise HrmExperiment::ValidationError, "context command requires the current dispatch cursor"
      end
      unless dispatch.dig("assignment", "role") == role
        raise HrmExperiment::ValidationError,
              "context role #{role.inspect} does not match dispatched role #{dispatch.dig('assignment', 'role').inspect}"
      end

      normalized = normalize_context_report!(report)
      required_ids = dispatch.dig("assignment", "required_dependency_ids")
      loaded_ids = normalized.fetch("loaded_dependency_ids")
      unless loaded_ids.sort == required_ids.sort
        raise HrmExperiment::ValidationError,
              "loaded dependency IDs must exactly match the current assignment: #{required_ids.join(', ')}"
      end
      measurements = measure_declared_dependencies(capsule, loaded_ids)
      prior_ids = events.select do |event|
        event["event_type"] == "context_snapshot" && event["role"] == role
      end.flat_map { |event| event.dig("context", "loaded_dependency_ids") || [] }.to_set
      repeated_bytes = measurements.fetch("by_id").sum do |dependency_id, bytes|
        prior_ids.include?(dependency_id) ? bytes : 0
      end
      active_context_bytes = measurements.fetch("artifact_bytes") +
                             normalized.fetch("tool_output_bytes") +
                             normalized.fetch("state_artifact_echo_bytes")
      event = {
        "event_type" => "context_snapshot",
        "occurred_at" => Time.now.utc.iso8601,
        "role" => role,
        "context" => {
          "turn_id" => normalized.fetch("turn_id"),
          "measurement_scope" => "turn_cumulative",
          "active_context_bytes" => active_context_bytes,
          "instruction_bytes" => measurements.fetch("instruction_bytes"),
          "artifact_bytes" => measurements.fetch("artifact_bytes"),
          "repeated_artifact_bytes" => repeated_bytes,
          "tool_output_bytes" => normalized.fetch("tool_output_bytes"),
          "omitted_tool_output_bytes" => normalized.fetch("omitted_tool_output_bytes"),
          "inline_raw_log_bytes" => normalized.fetch("inline_raw_log_bytes"),
          "state_artifact_echo_bytes" => normalized.fetch("state_artifact_echo_bytes"),
          "context_compactions" => normalized.fetch("context_compactions"),
          "files_loaded" => measurements.fetch("files_loaded"),
          "files_outside_declared_dependencies" => 0,
          "loaded_dependency_ids" => loaded_ids,
          "outside_declared_dependency_ids" => []
        }
      }
      append_prepared(capsule, events, events_path, event, "context", capsule_path)
    end
  end

  def guard(capsule_path, events_path, action, role, now = Time.now.utc)
    capsule = HrmExperiment.load_yaml(capsule_path)
    with_run_lock(events_path, capsule) do
      events = load_and_validate_run(capsule, events_path)
      ensure_run_writable!(capsule, events)
      if action == "discover_project_api_skills"
        coverage = ProjectApiSkillRegistry.coverage_for_capsule(capsule, capsule_path)
        if coverage["missing_skill_ids"].empty?
          raise HrmExperiment::ValidationError,
                "all required project API skills are reusable; do not repeat API discovery"
        end
      end
      event = HrmExperiment.guard_action(capsule, events, action, role, now)
      append_prepared(capsule, events, events_path, event, "guard", capsule_path)
    end
  end

  def supersede(predecessor_path, events_path, successor_path, now = Time.now.utc)
    predecessor = HrmExperiment.load_yaml(predecessor_path)
    with_run_lock(events_path, predecessor) do
      events = load_and_validate_run(predecessor, events_path)
      ensure_run_writable!(predecessor, events)
      event = HrmExperiment.supersession_event(
        predecessor,
        events,
        HrmExperiment.load_yaml(successor_path),
        now
      )
      append_prepared(predecessor, events, events_path, event, "supersede", predecessor_path)
    end
  end

  def transition(predecessor_path, events_path, successor_path, session_id, execution_mode, now = Time.now.utc)
    predecessor = HrmExperiment.load_yaml(predecessor_path)
    with_run_lock(events_path, predecessor) do
      events = load_and_validate_run(predecessor, events_path)
      ensure_run_writable!(predecessor, events)
      successor = derive_successor_capsule(predecessor, successor_path, session_id, execution_mode)
      HrmExperiment.validate_successor!(predecessor, events, successor)
      write_new_capsule!(predecessor, successor_path, successor)
      event = HrmExperiment.supersession_event(predecessor, events, successor, now)
      append_prepared(predecessor, events, events_path, event, "transition", predecessor_path).merge(
        "successor_session_id" => successor["session_id"],
        "successor_capsule_path" => File.expand_path(successor_path),
        "successor_capsule_sha256" => HrmExperiment.object_sha256(successor)
      )
    end
  end

  def derive_successor_capsule(predecessor, successor_path, session_id, execution_mode)
    profiles = {
      "runtime_build" => "runtime_build_fast_feedback",
      "production_observation" => "production_observation_fail_closed"
    }
    profile_name = profiles[execution_mode]
    unless profile_name
      raise HrmExperiment::ValidationError,
            "automatic transition supports runtime_build or production_observation"
    end
    if execution_mode == predecessor["execution_mode"]
      raise HrmExperiment::ValidationError, "automatic transition requires an execution-mode change"
    end

    successor = Marshal.load(Marshal.dump(predecessor))
    profile = HrmExperiment::PROFILE_CONTRACTS.fetch(profile_name)
    successor["schema_version"] = "agent_playbooks.hrm_execution_capsule.v0.7"
    successor["session_id"] = session_id
    successor["session_lineage"] = {
      "predecessor_session_id" => predecessor["session_id"],
      "capsule_sequence" => predecessor.dig("session_lineage", "capsule_sequence") + 1,
      "continuation_reason" => "execution_mode_changed",
      "inherited_state_path" => predecessor.dig("metrics", "session_state_path"),
      "predecessor_event_log_path" => nil,
      "predecessor_event_log_sha256" => nil,
      "decision_receipts" => []
    }
    successor["entry_condition"] = {
      "known_missing_deliverable_types" => [profile.fetch("deliverable_type")],
      "on_mode_mismatch" => "start_successor_capsule_or_stop_blocked_input"
    }
    successor["experiment_profile"] = profile_name
    successor["execution_mode"] = execution_mode
    successor["deliverable_type"] = profile.fetch("deliverable_type")
    successor.dig("workflow_lease")["permitted_routine_actions"] = profile.fetch("routine_actions")
    successor.dig("workflow_lease", "read_only_diagnostic_scope")["scope_id"] =
      "#{successor.dig('hrm', 'id')}-#{session_id}-READONLY".gsub(/[^A-Za-z0-9_.:-]/, "-")
    successor.dig("authority")["workflow"] = profile.fetch("workflow_authority")
    successor.dig("authority")["operational"].keys.each do |key|
      successor.dig("authority", "operational")[key] = false
    end
    profile.fetch("budgets").each { |key, value| successor.dig("budgets")[key] = value }
    successor.dig("verification")["profile"] = profile.fetch("verification_profile")
    successor.dig("metrics")["aftercare_window_days"] = profile.fetch("aftercare_window_days")

    root = File.realpath(File.expand_path(predecessor.fetch("project_root")))
    expanded_successor = File.expand_path(successor_path)
    unless expanded_successor.start_with?("#{root}#{File::SEPARATOR}")
      raise HrmExperiment::ValidationError, "successor capsule must remain under capsule project_root"
    end
    successor_relative = expanded_successor.delete_prefix("#{root}#{File::SEPARATOR}")
    capsule_dependency = successor.fetch("context_dependencies").find do |dependency|
      dependency["kind"] == "execution_capsule"
    end
    raise HrmExperiment::ValidationError, "execution capsule context dependency is missing" unless capsule_dependency
    capsule_dependency["source_path"] = successor_relative
    capsule_dependency["binding"] = "capsule_sha256"

    inherited_source = predecessor.dig("session_lineage", "inherited_state_path")
    predecessor_state_dependency = successor.fetch("context_dependencies").find do |dependency|
      dependency["kind"] == "run_state" &&
        (dependency["source_path"] == inherited_source || dependency["dependency_id"].include?("predecessor"))
    end
    unless predecessor_state_dependency
      dependency_id = "ap.predecessor-run-state"
      used_ids = successor.fetch("context_dependencies").map { |dependency| dependency["dependency_id"] }
      dependency_id = "#{dependency_id}-#{successor.dig('session_lineage', 'capsule_sequence')}" if used_ids.include?(dependency_id)
      predecessor_state_dependency = {
        "dependency_id" => dependency_id,
        "kind" => "run_state",
        "source_path" => predecessor.dig("metrics", "session_state_path"),
        "binding" => "supervisor_validated_execution_mode_transition"
      }
      successor.fetch("context_dependencies") << predecessor_state_dependency
    end
    predecessor_state_dependency["source_path"] = predecessor.dig("metrics", "session_state_path")
    predecessor_state_dependency["binding"] = "supervisor_validated_execution_mode_transition"

    metrics_directory = File.dirname(predecessor.dig("metrics", "event_log_path"))
    safe_session = session_id.gsub(/[^A-Za-z0-9_.-]/, "_")
    artifact = lambda do |suffix|
      name = "#{safe_session}.#{suffix}"
      metrics_directory == "." ? name : File.join(metrics_directory, name)
    end
    successor.dig("metrics")["event_log_path"] = artifact.call("events.jsonl")
    successor.dig("metrics")["session_state_path"] = artifact.call("state.yaml")
    successor.dig("metrics")["scorecard_path"] = artifact.call("scorecard.yaml")
    HrmExperiment.validate_capsule!(successor)
    successor
  end

  def write_new_capsule!(predecessor, successor_path, successor)
    expanded = File.expand_path(successor_path)
    project_relative_artifact_path(predecessor, expanded, "successor capsule")
    raise HrmExperiment::ValidationError, "successor capsule already exists: #{expanded}" if File.exist?(expanded)
    unless File.directory?(File.dirname(expanded))
      raise HrmExperiment::ValidationError, "successor capsule directory does not exist: #{File.dirname(expanded)}"
    end
    File.open(expanded, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
      file.write(YAML.dump(successor))
      file.flush
      file.fsync
    end
    File.chmod(0o600, expanded)
    fsync_directory(File.dirname(expanded))
  end

  def projection_path(capsule, events_path)
    safe_session = capsule.fetch("session_id").gsub(/[^A-Za-z0-9_.-]/, "_")
    File.join(File.dirname(File.expand_path(events_path)), "#{safe_session}.supervisor.json")
  end

  def dispatch_path(capsule, events_path)
    safe_session = capsule.fetch("session_id").gsub(/[^A-Za-z0-9_.-]/, "_")
    File.join(File.dirname(File.expand_path(events_path)), "#{safe_session}.dispatch.json")
  end

  def project_relative_path(capsule, relative_path, field)
    unless HrmExperiment.clean_relative_path?(relative_path)
      raise HrmExperiment::ValidationError, "#{field} must be a clean project-root-relative path"
    end

    configured_root = File.expand_path(capsule.fetch("project_root"))
    unless Dir.exist?(configured_root)
      raise HrmExperiment::ValidationError, "capsule project_root does not exist: #{configured_root}"
    end
    root = File.realpath(configured_root)
    expanded = File.expand_path(relative_path, root)
    unless expanded.start_with?("#{root}#{File::SEPARATOR}")
      raise HrmExperiment::ValidationError, "#{field} must remain under capsule project_root"
    end

    existing_parent = File.dirname(expanded)
    existing_parent = File.dirname(existing_parent) until File.exist?(existing_parent)
    resolved_parent = File.realpath(existing_parent)
    unless resolved_parent == root || resolved_parent.start_with?("#{root}#{File::SEPARATOR}")
      raise HrmExperiment::ValidationError, "#{field} resolves through a path outside capsule project_root"
    end
    expanded
  end

  def artifact_paths(capsule, events_path)
    expanded_events = File.expand_path(events_path)
    expected_events = project_relative_path(capsule, capsule.dig("metrics", "event_log_path"), "metrics.event_log_path")
    unless expanded_events == expected_events
      raise HrmExperiment::ValidationError,
            "events path must equal project-root-bound metrics.event_log_path #{expected_events.inspect}"
    end

    {
      "events" => expanded_events,
      "state" => project_relative_path(capsule, capsule.dig("metrics", "session_state_path"), "metrics.session_state_path"),
      "scorecard" => project_relative_path(capsule, capsule.dig("metrics", "scorecard_path"), "metrics.scorecard_path"),
      "projection" => projection_path(capsule, expanded_events),
      "dispatch" => dispatch_path(capsule, expanded_events)
    }
  end

  def load_and_validate_run(capsule, events_path)
    HrmExperiment.validate_capsule!(capsule)
    paths = artifact_paths(capsule, events_path)
    events = File.exist?(paths["events"]) ? HrmExperiment.load_events(paths["events"]) : []
    validate_run_identity!(capsule, events)
    validate_lineage_receipts!(capsule)
    events
  end

  def validate_lineage_receipts!(capsule)
    lineage = capsule.fetch("session_lineage")
    receipts = lineage.fetch("decision_receipts")
    return true if receipts.empty?

    predecessor_path = project_relative_path(
      capsule,
      lineage.fetch("predecessor_event_log_path"),
      "session_lineage.predecessor_event_log_path"
    )
    unless File.file?(predecessor_path)
      raise HrmExperiment::ValidationError, "predecessor event log is missing: #{predecessor_path}"
    end
    actual_sha = Digest::SHA256.file(predecessor_path).hexdigest
    unless actual_sha == lineage.fetch("predecessor_event_log_sha256")
      raise HrmExperiment::ValidationError, "predecessor event log hash mismatch"
    end

    predecessor_events = HrmExperiment.load_events(predecessor_path)
    HrmExperiment.validate_events!(predecessor_events)
    expected_sequences = (1..predecessor_events.length).to_a
    unless predecessor_events.map { |event| event["sequence"] } == expected_sequences
      raise HrmExperiment::ValidationError, "predecessor event ledger sequence is not contiguous"
    end
    predecessor_times = predecessor_events.map { |event| Time.iso8601(event.fetch("occurred_at")) }
    unless predecessor_times.each_cons(2).all? { |earlier, later| later >= earlier }
      raise HrmExperiment::ValidationError, "predecessor event ledger time is not monotonic"
    end
    unless predecessor_events.all? { |event| event["session_id"] == lineage["predecessor_session_id"] }
      raise HrmExperiment::ValidationError, "predecessor event ledger session_id mismatch"
    end
    receipts.each do |receipt|
      request = predecessor_events.find do |event|
        event["session_id"] == receipt["request_session_id"] &&
          event["sequence"] == receipt["request_sequence"] &&
          event["event_type"] == "decision_requested" &&
          event.dig("details", "decision_id") == receipt["decision_id"]
      end
      unless request && request["hrm_id"] == capsule.dig("hrm", "id") &&
             HrmExperiment.object_sha256(request) == receipt["request_event_sha256"]
        raise HrmExperiment::ValidationError,
              "inherited decision receipt #{receipt['decision_id']} does not match the predecessor ledger"
      end
      unless request.dig("details", "decision_kind") == receipt["decision_kind"] &&
             request.dig("details", "effect_class") == receipt["effect_class"]
        raise HrmExperiment::ValidationError,
              "inherited decision receipt #{receipt['decision_id']} changes the requested authority"
      end
    end
    true
  end

  def ensure_run_writable!(capsule, events)
    verdict = HrmExperiment.evaluate(capsule, events).fetch("verdict")
    unless verdict["run_valid"]
      raise HrmExperiment::ValidationError, "supervisor refuses to advance a run-invalid ledger"
    end
    if verdict["process_envelope"] == "fail"
      raise HrmExperiment::ValidationError, "supervisor refuses to advance a failed process envelope"
    end
    true
  end

  def rc9?(capsule)
    capsule.dig("playbook_pin", "kernel_version") == RC9_KERNEL_VERSION
  end

  def terminal_event?(event)
    %w[hrm_closed stop_reason].include?(event["event_type"])
  end

  def resume_stop_event(capsule, events, now)
    return nil unless rc9?(capsule)
    return nil if terminal_event?(events.last)

    scorecard = HrmExperiment.evaluate(capsule, events)
    return process_failure_stop_event(capsule, events, scorecard, now) if scorecard.dig("verdict", "process_envelope") == "fail"
    return nil unless scorecard.dig("verdict", "run_valid")

    last_progress = events.reverse.find { |event| event.dig("details", "material_progress") } || events.first
    elapsed = (now - Time.iso8601(last_progress.fetch("occurred_at"))).to_i
    limit = capsule.dig("budgets", "no_material_progress_minutes") * 60
    return nil unless elapsed > limit

    stop_event(capsule, events, now, "no_progress", "resume stopped a stale active run after #{elapsed} seconds without material progress")
  end

  def current_dispatch_at_cursor?(capsule, events, events_path)
    path = dispatch_path(capsule, events_path)
    return false unless File.file?(path)

    dispatch = HrmExperiment.load_json(path)
    validate_dispatch!(dispatch)
    dispatch["session_id"] == capsule["session_id"] && dispatch["ledger_cursor"] == events.length
  rescue HrmExperiment::ValidationError, JSON::ParserError
    false
  end

  def process_failure_stop_event(capsule, events, scorecard, now = Time.now.utc)
    reasons = scorecard.dig("verdict", "reasons") || []
    reason = if reasons.any? { |item| item.include?("scope") }
               "scope_divergence"
             elsif reasons.any? { |item| item.match?(/duplicate conclusive CI|governance|non-runtime unit/) }
               "governance_loop"
             elsif reasons.any? { |item| item.include?("no-material-progress") }
               "no_progress"
             else
               "budget_exhausted"
             end
    summary = reasons.first(3).join("; ")
    stop_event(capsule, events, now, reason, "supervisor terminalized process failure: #{summary}")
  end

  def stop_event(capsule, events, now, reason, note)
    {
      "schema_version" => HrmExperiment.event_schema_version(capsule),
      "session_id" => capsule["session_id"],
      "hrm_id" => capsule.dig("hrm", "id"),
      "sequence" => events.length + 1,
      "event_type" => "stop_reason",
      "occurred_at" => now.utc.iso8601,
      "caused_by_sequence" => events.last["sequence"],
      "role" => "orchestrator",
      "details" => {"stop_reason" => reason, "material_progress" => false, "note" => note}
    }
  end

  def normalize_context_report!(report)
    unless report.is_a?(Hash)
      raise HrmExperiment::ValidationError, "context report must be a JSON object"
    end
    allowed = ["turn_id", "loaded_dependency_ids"] + CONTEXT_REPORT_INTEGER_FIELDS
    unknown = report.keys - allowed
    unless unknown.empty?
      raise HrmExperiment::ValidationError, "context report has unsupported fields: #{unknown.join(', ')}"
    end
    turn_id = report["turn_id"]
    unless turn_id.is_a?(String) && !turn_id.empty?
      raise HrmExperiment::ValidationError, "context report requires a non-empty turn_id"
    end
    loaded = report["loaded_dependency_ids"]
    unless loaded.is_a?(Array) && loaded.all? { |item| item.is_a?(String) && !item.empty? } && loaded.uniq == loaded
      raise HrmExperiment::ValidationError, "context report requires unique loaded_dependency_ids"
    end
    normalized = {"turn_id" => turn_id, "loaded_dependency_ids" => loaded}
    CONTEXT_REPORT_INTEGER_FIELDS.each do |field|
      value = report.fetch(field, 0)
      unless value.is_a?(Integer) && value >= 0
        raise HrmExperiment::ValidationError, "context report #{field} must be a non-negative integer"
      end
      normalized[field] = value
    end
    normalized
  end

  def measure_declared_dependencies(capsule, dependency_ids)
    dependencies = capsule.fetch("context_dependencies").to_h do |dependency|
      [dependency.fetch("dependency_id"), dependency]
    end
    by_id = dependency_ids.to_h do |dependency_id|
      dependency = dependencies.fetch(dependency_id) do
        raise HrmExperiment::ValidationError, "unknown declared dependency #{dependency_id.inspect}"
      end
      [dependency_id, dependency_bytes(capsule, dependency)]
    end
    instruction_bytes = dependency_ids.sum do |dependency_id|
      dependencies.fetch(dependency_id)["kind"] == "repository_dispatcher" ? by_id.fetch(dependency_id) : 0
    end
    {
      "artifact_bytes" => by_id.values.sum,
      "instruction_bytes" => instruction_bytes,
      "files_loaded" => dependency_ids.length,
      "by_id" => by_id
    }
  end

  def dependency_bytes(capsule, dependency)
    source = dependency.fetch("source_path")
    return JSON.generate(capsule.dig("verification", "exact_checks")).bytesize if source == "verification.exact_checks"

    file_source = source.split("#", 2).first
    path = if Pathname.new(file_source).absolute?
             File.expand_path(file_source)
           else
             project_relative_path(capsule, file_source, "context dependency #{dependency.fetch('dependency_id')}")
           end
    unless File.file?(path)
      raise HrmExperiment::ValidationError,
            "assigned context dependency is not a measurable file: #{dependency.fetch('dependency_id')}"
    end
    File.size(path)
  end

  def validate_run_identity!(capsule, events)
    HrmExperiment.validate_events!(events)
    expected_sequences = (1..events.length).to_a
    actual_sequences = events.map { |event| event["sequence"] }
    unless actual_sequences == expected_sequences
      raise HrmExperiment::ValidationError, "event ledger sequence is not contiguous"
    end

    prior_time = nil
    events.each do |event|
      unless event["session_id"] == capsule["session_id"]
        raise HrmExperiment::ValidationError, "event #{event['sequence']} session_id mismatch"
      end
      unless event["hrm_id"] == capsule.dig("hrm", "id")
        raise HrmExperiment::ValidationError, "event #{event['sequence']} hrm_id mismatch"
      end
      cause = event["caused_by_sequence"]
      if cause && (cause < 1 || cause >= event["sequence"])
        raise HrmExperiment::ValidationError, "event #{event['sequence']} has invalid causal sequence"
      end
      occurred_at = Time.iso8601(event.fetch("occurred_at"))
      if prior_time && occurred_at < prior_time
        raise HrmExperiment::ValidationError, "event #{event['sequence']} occurred_at precedes the prior event"
      end
      prior_time = occurred_at
    end
    true
  rescue ArgumentError => e
    raise HrmExperiment::ValidationError, "event ledger time invalid: #{e.message}"
  end

  def prepare_event(capsule, events, event)
    unless event.is_a?(Hash)
      raise HrmExperiment::ValidationError, "event input must be a JSON object"
    end

    prepared = Marshal.load(Marshal.dump(event))
    required_schema = HrmExperiment.event_schema_version(capsule)
    prepared["schema_version"] ||= required_schema
    unless prepared["schema_version"] == required_schema
      raise HrmExperiment::ValidationError,
            "#{capsule.dig('playbook_pin', 'kernel_version')} supervisor writes require #{required_schema}"
    end
    expected_sequence = events.length + 1
    if prepared.key?("sequence") && prepared["sequence"] != expected_sequence
      raise HrmExperiment::ValidationError,
            "event sequence must be #{expected_sequence}, got #{prepared['sequence'].inspect}"
    end
    prepared["sequence"] = expected_sequence
    prepared["session_id"] ||= capsule["session_id"]
    prepared["hrm_id"] ||= capsule.dig("hrm", "id")
    prepared["caused_by_sequence"] ||= events.last["sequence"] unless events.empty?
    prepared
  end

  def append_prepared(capsule, events, events_path, event, action, capsule_path)
    prepared = prepare_event(capsule, events, event)
    updated_events = events + [prepared]
    validate_run_identity!(capsule, updated_events)
    prospective_scorecard = HrmExperiment.evaluate(capsule, updated_events)
    prospective_verdict = prospective_scorecard.fetch("verdict")
    unless prospective_verdict["run_valid"]
      raise HrmExperiment::ValidationError, "supervisor refuses an event that makes the ledger run-invalid"
    end

    appended = [prepared]
    if rc9?(capsule) && prospective_verdict["process_envelope"] == "fail" && !terminal_event?(prepared)
      terminal_time = [Time.now.utc, Time.iso8601(prepared.fetch("occurred_at"))].max
      terminal = process_failure_stop_event(capsule, updated_events, prospective_scorecard, terminal_time)
      updated_events << terminal
      appended << terminal
      validate_run_identity!(capsule, updated_events)
      unless HrmExperiment.evaluate(capsule, updated_events).dig("verdict", "run_valid")
        raise HrmExperiment::ValidationError, "supervisor refuses process-failure terminalization that makes the ledger run-invalid"
      end
    end

    File.open(events_path, File::WRONLY | File::CREAT | File::APPEND, 0o600) do |file|
      payload = appended.map { |item| JSON.generate(item) }.join("\n") + "\n"
      file.write(payload)
      file.flush
      file.fsync
    end
    File.chmod(0o600, events_path)

    receipt = refresh(capsule, updated_events, events_path, action, capsule_path).merge(
      "event_sequence" => appended.last["sequence"],
      "event_type" => appended.last["event_type"]
    )
    if appended.length > 1
      receipt.merge!(
        "accepted_event_sequence" => prepared["sequence"],
        "accepted_event_type" => prepared["event_type"],
        "auto_terminalized" => true
      )
    end
    receipt
  end

  def refresh(capsule, events, events_path, action, capsule_path)
    paths = artifact_paths(capsule, events_path)
    api_skill_coverage = ProjectApiSkillRegistry.coverage_for_capsule(capsule, capsule_path)
    before = stored_projection_status(paths, capsule, api_skill_coverage)
    ledger_cursor = events.length
    if before && before["max_cursor"] > ledger_cursor
      raise HrmExperiment::ValidationError,
            "stored projection cursor #{before['max_cursor']} is ahead of ledger cursor #{ledger_cursor}"
    end

    state = HrmExperiment.derive_session_state(capsule, events)
    scorecard = HrmExperiment.evaluate(capsule, events)
    projection, dispatch = derive_projection_set(
      capsule,
      events,
      state,
      scorecard,
      api_skill_coverage,
      paths,
      capsule_path
    )
    write_projection_set(paths, state, scorecard, projection, dispatch)

    {
      "action" => action,
      "session_id" => capsule["session_id"],
      "ledger_cursor" => ledger_cursor,
      "projection_lag_events_before" => before ? ledger_cursor - before["cursor"] : ledger_cursor,
      "projection_lag_events_after" => 0,
      "projection_repaired" => before.nil? || !before["coherent"] || before["cursor"] != ledger_cursor,
      "projection_bytes" => JSON.generate(projection).bytesize,
      "dispatch_bytes" => JSON.generate(dispatch).bytesize,
      "attention_count" => projection["attention"].length,
      "reusable_api_skill_count" => api_skill_coverage["reusable_skill_ids"].length,
      "missing_api_skill_count" => api_skill_coverage["missing_skill_ids"].length,
      "next_action" => projection["next_action"],
      "state_hash" => state["state_hash"],
      "projection_hash" => projection["projection_hash"]
    }
  end

  def derive_projection_set(capsule, events, state, scorecard, api_skill_coverage, paths, capsule_path)
    attention = derive_attention(events, state)
    if attention.length > MAX_ATTENTION_ITEMS
      raise HrmExperiment::ValidationError,
            "attention projection has #{attention.length} items; consolidate before supervisor continuation"
    end

    verdict = scorecard.fetch("verdict")
    next_action = if !verdict["run_valid"]
                    "stop_run_invalid"
                  elsif verdict["process_envelope"] == "fail"
                    "stop_process_envelope"
                  elsif state.dig("terminal", "state") != "active"
                    "terminal"
                  elsif !attention.empty?
                    {
                      "operator_action" => "await_operator_action",
                      "decision" => "await_operator_decision",
                      "blocking_finding" => "route_blocking_finding",
                      "operator_review" => "await_operator_review"
                    }.fetch(attention.first["kind"])
                  elsif !api_skill_coverage["missing_skill_ids"].empty?
                    "discover_missing_project_api_skills"
                  else
                    derive_routine_next_action(capsule, events)
                  end

    dispatch = derive_dispatch_envelope(capsule, events, next_action, api_skill_coverage, paths, capsule_path)
    relative_dispatch = project_relative_artifact_path(capsule, paths.fetch("dispatch"), "dispatch")
    operator_projection = derive_operator_projection(capsule, state, attention)

    projection = {
      "schema_version" => "agent_playbooks.hrm_supervisor_projection.v0.4",
      "session_id" => capsule["session_id"],
      "hrm_id" => capsule.dig("hrm", "id"),
      "capsule_sha256" => HrmExperiment.object_sha256(capsule),
      "ledger_cursor" => events.length,
      "state_hash" => state["state_hash"],
      "scorecard_event_count" => scorecard.dig("run_identity", "event_count"),
      "scorecard_verdict" => {
        "run_valid" => verdict.fetch("run_valid"),
        "process_envelope" => verdict.fetch("process_envelope"),
        "overall" => verdict.fetch("overall"),
        "reason_count" => verdict.fetch("reasons").length
      },
      "project_api_skills" => api_skill_coverage,
      "phase" => state["phase"],
      "terminal_state" => state.dig("terminal", "state"),
      "attention" => attention,
      "next_action" => next_action,
      "operator_projection" => operator_projection,
      "dispatch_ref" => {
        "path" => relative_dispatch,
        "sha256" => dispatch["dispatch_hash"],
        "cache_key" => dispatch.dig("cache", "cache_key")
      }
    }
    projection["projection_hash"] = HrmExperiment.object_sha256(projection)
    validate_projection!(projection)

    bytes = JSON.generate(projection).bytesize
    if bytes > MAX_PROJECTION_BYTES
      raise HrmExperiment::ValidationError,
            "supervisor projection is #{bytes} bytes; maximum is #{MAX_PROJECTION_BYTES}"
    end
    [projection, dispatch]
  end

  def derive_routine_next_action(capsule, events)
    latest_guard = events.reverse.find { |event| event["event_type"] == "action_guard_passed" }
    latest_worker_result = events.reverse.find { |event| event["event_type"] == "worker_result_received" }
    if latest_guard && (!latest_worker_result || latest_worker_result["sequence"] < latest_guard["sequence"])
      return "await_worker_result"
    end

    if capsule["execution_mode"] == "production_observation"
      guarded_actions = events.select { |event| event["event_type"] == "action_guard_passed" }
                              .map { |event| event.dig("details", "action") }
      return "prepare_private_inputs" unless guarded_actions.include?("prepare_private_inputs")
      return "inspect_provider_read_only" unless guarded_actions.include?("inspect_provider_read_only")
      return "record_operational_evidence" unless events.any? { |event| event["event_type"] == "first_operational_evidence" }

      return "prepare_review"
    end
    return "continue_routine_workflow" unless capsule["execution_mode"] == "runtime_build"

    inventory = events.reverse.find { |event| event["event_type"] == "runtime_binding_inventory" }
    first_executable = events.find { |event| event["event_type"] == "first_executable_delta" }
    candidate = events.reverse.find { |event| event["event_type"] == "candidate_frozen" }
    checks = events.select { |event| event["event_type"] == "check_completed" }
    return "inventory_runtime_bindings" unless inventory
    return "implement_frozen_slice" unless first_executable
    return "freeze_candidate" unless candidate

    required = capsule.dig("verification", "exact_checks")
    completed = checks.select do |event|
      event.dig("check", "conclusive") &&
        event.dig("check", "conclusion") == "passed" &&
        event["candidate_sha"] == candidate["candidate_sha"] &&
        event["ci_plan_hash"] == capsule.dig("verification", "ci_plan_hash") &&
        event.dig("check", "environment_id") == capsule.dig("verification", "environment_id")
    end.map { |event| event.dig("check", "name") }.compact
    return "run_declared_checks" unless (required - completed).empty?

    "prepare_review"
  end

  def derive_dispatch_envelope(capsule, events, next_action, api_skill_coverage, paths, capsule_path)
    action_roles = {
      "discover_missing_project_api_skills" => ["discover_project_api_skills", "provider_observer"],
      "inventory_runtime_bindings" => ["inventory_runtime_bindings", "provider_observer"],
      "prepare_private_inputs" => ["prepare_private_inputs", "provider_observer"],
      "inspect_provider_read_only" => ["inspect_provider_read_only", "provider_observer"],
      "record_operational_evidence" => ["record_operational_evidence", "provider_observer"],
      "implement_frozen_slice" => ["implement_frozen_slice", "builder"],
      "freeze_candidate" => [nil, "orchestrator"],
      "run_declared_checks" => ["run_declared_checks", "checker"],
      "prepare_review" => [nil, "reviewer"]
    }
    action, role = action_roles.fetch(next_action, [nil, nil])
    dependency_kinds_by_action = {
      "discover_project_api_skills" => %w[project_api_skill_registry],
      "inventory_runtime_bindings" => %w[implementation_source run_state],
      "prepare_private_inputs" => %w[run_state],
      "inspect_provider_read_only" => %w[project_api_skill_registry run_state],
      "record_operational_evidence" => %w[project_api_skill_registry run_state],
      "implement_frozen_slice" => %w[implementation_source run_state],
      "run_declared_checks" => %w[implementation_source declared_check]
    }
    assignment_dependency_kinds = dependency_kinds_by_action.fetch(action, [])
    assignment_dependency_ids = capsule.fetch("context_dependencies").each_with_object([]) do |dependency, ids|
      ids << dependency["dependency_id"] if assignment_dependency_kinds.include?(dependency["kind"])
    end
    declared_dependency_ids = capsule.fetch("context_dependencies").map { |item| item["dependency_id"] }
    latest_inventory = events.reverse.find { |event| event["event_type"] == "runtime_binding_inventory" }
    required_seams = capsule.dig("function_slice", "required_real_seams")
    bound_seams = Array(latest_inventory&.dig("details", "runtime_readiness", "bound_real_seams"))
    enabled_effects = capsule.dig("authority", "operational").select { |_key, enabled| enabled }.keys.sort
    kernel_key = HrmExperiment.object_sha256(capsule.fetch("playbook_pin"))
    target_key = HrmExperiment.object_sha256(
      capsule.fetch("target_resolution").merge("hrm" => capsule.fetch("hrm"))
    )
    cache_key = HrmExperiment.object_sha256(
      "kernel_key" => kernel_key,
      "target_contract_key" => target_key,
      "capsule_sha256" => HrmExperiment.object_sha256(capsule)
    )
    dispatch = {
      "schema_version" => "agent_playbooks.hrm_dispatch_envelope.v0.2",
      "session_id" => capsule["session_id"],
      "hrm_id" => capsule.dig("hrm", "id"),
      "capsule_sha256" => HrmExperiment.object_sha256(capsule),
      "ledger_cursor" => events.length,
      "cache" => {
        "cache_key" => cache_key,
        "kernel_key" => kernel_key,
        "target_contract_key" => target_key,
        "load_policy" => "hashes_only_unless_changed"
      },
      "assignment" => {
        "next_action" => next_action,
        "action" => action,
        "role" => role,
        "required_dependency_ids" => assignment_dependency_ids
      },
      "scope" => {
        "execution_mode" => capsule["execution_mode"],
        "deliverable_type" => capsule["deliverable_type"],
        "required_dependency_ids" => assignment_dependency_ids,
        "declared_dependency_ids" => declared_dependency_ids,
        "required_skill_ids" => capsule.dig("project_api_skills", "required_skills").map { |item| item["skill_id"] },
        "missing_skill_ids" => api_skill_coverage["missing_skill_ids"],
        "required_real_seams" => required_seams,
        "missing_runtime_bindings" => required_seams - bound_seams,
        "allowed_paths" => capsule.dig("function_slice", "allowed_paths"),
        "proof_obligations" => capsule.dig("function_slice", "proof_obligations"),
        "exact_checks" => capsule.dig("verification", "exact_checks")
      },
      "authority" => {
        "routine_action_authorized" => action.nil? || capsule.dig("workflow_lease", "permitted_routine_actions").include?(action),
        "enabled_operational_effects" => enabled_effects
      },
      "protocol" => {
        "context_command" => role ? [
          "ruby",
          File.expand_path(__FILE__),
          "context",
          File.expand_path(capsule_path),
          paths.fetch("events"),
          role
        ] : nil,
        "guard_command" => action ? [
          "ruby",
          File.expand_path(__FILE__),
          "guard",
          File.expand_path(capsule_path),
          paths.fetch("events"),
          action,
          role
        ] : nil,
        "context_report" => {
          "stdin" => "json",
          "required_fields" => %w[turn_id loaded_dependency_ids],
          "optional_nonnegative_integer_fields" => CONTEXT_REPORT_INTEGER_FIELDS,
          "measurement_scope" => "declared_artifact_bytes_plus_worker_reported_tool_output",
          "platform_instructions" => "excluded",
          "machine_parsed_dispatch_echo_bytes" => 0
        },
        "result_contract" => "append_compact_events_only"
      }
    }
    dispatch["dispatch_hash"] = HrmExperiment.object_sha256(dispatch)
    validate_dispatch!(dispatch)
    dispatch
  end

  def derive_operator_projection(capsule, state, attention)
    terminal = state.dig("terminal", "state") != "active"
    visibility = if terminal
                   "terminal"
                 elsif attention.any? { |item| item["kind"] == "operator_review" }
                   "review"
                 elsif !attention.empty?
                   "attention"
                 else
                   "silent"
                 end
    summary = capsule.dig("hrm", "outcome").to_s.gsub(/\s+/, " ").strip
    summary = "#{summary[0, 237]}..." if summary.length > 240
    {"visibility" => visibility, "status" => state["phase"], "summary" => summary}
  end

  def project_relative_artifact_path(capsule, path, field)
    root = File.realpath(File.expand_path(capsule.fetch("project_root")))
    expanded = File.expand_path(path)
    unless expanded.start_with?("#{root}#{File::SEPARATOR}")
      raise HrmExperiment::ValidationError, "#{field} must remain under capsule project_root"
    end
    expanded.delete_prefix("#{root}#{File::SEPARATOR}")
  end

  def derive_attention(events, state)
    completed_actions = events.map do |event|
      event.dig("details", "action_id") if event["event_type"] == "operator_action_completed"
    end.compact.to_set
    received_decisions = events.map do |event|
      event.dig("details", "decision_id") if event["event_type"] == "decision_received"
    end.compact.to_set
    dispositioned_findings = events.map do |event|
      event.dig("details", "finding_id") if event["event_type"] == "finding_dispositioned"
    end.compact.to_set

    attention = events.map do |event|
      details = event.fetch("details", {})
      case event["event_type"]
      when "operator_action_required"
        next if completed_actions.include?(details["action_id"])

        attention_item(event, "operator_action", details["action_id"], details["exact_action"])
      when "decision_requested"
        next if received_decisions.include?(details["decision_id"])

        attention_item(event, "decision", details["decision_id"], details["exact_effect"])
      when "finding_opened"
        next if dispositioned_findings.include?(details["finding_id"])
        next unless details["blocking"] && %w[S0 S1].include?(details["interrupt_class"])

        attention_item(event, "blocking_finding", details["finding_id"], details["note"])
      end
    end.compact

    review_ready = events.reverse.find { |event| event["event_type"] == "review_ready" }
    review_completed = events.reverse.find { |event| event["event_type"] == "operator_review_completed" }
    if state.dig("terminal", "state") == "active" && review_ready &&
       (!review_completed || review_completed["sequence"] < review_ready["sequence"])
      attention << attention_item(
        review_ready,
        "operator_review",
        "review-ready-#{review_ready['sequence']}",
        review_ready.dig("details", "note") || "Review the exact candidate function and UI/UX surface."
      )
    end

    attention.sort_by { |item| item["event_sequence"] }
  end

  def attention_item(event, kind, id, summary)
    clean_summary = summary.to_s.gsub(/\s+/, " ").strip
    clean_summary = event["event_type"] if clean_summary.empty?
    clean_summary = "#{clean_summary[0, 237]}..." if clean_summary.length > 240
    {
      "key" => "#{kind}:#{id}",
      "kind" => kind,
      "interrupt_class" => event.dig("details", "interrupt_class"),
      "event_sequence" => event["sequence"],
      "summary" => clean_summary
    }
  end

  def stored_projection_status(paths, capsule, api_skill_coverage)
    required = %w[state scorecard projection dispatch]
    return nil unless required.all? { |name| File.exist?(paths[name]) }

    state = HrmExperiment.load_yaml(paths["state"])
    HrmExperiment.validate_session_state!(state)
    scorecard = HrmExperiment.load_yaml(paths["scorecard"])
    HrmExperiment.validate_scorecard!(scorecard)
    projection = HrmExperiment.load_json(paths["projection"])
    validate_projection!(projection)
    dispatch = HrmExperiment.load_json(paths["dispatch"])
    validate_dispatch!(dispatch)

    capsule_sha = HrmExperiment.object_sha256(capsule)
    identities_match = state["session_id"] == capsule["session_id"] &&
                       state["capsule_sha256"] == capsule_sha &&
                       scorecard.dig("run_identity", "session_id") == capsule["session_id"] &&
                       projection["session_id"] == capsule["session_id"] &&
                       projection["capsule_sha256"] == capsule_sha &&
                       projection["project_api_skills"] == api_skill_coverage &&
                       dispatch["capsule_sha256"] == capsule_sha
    return nil unless identities_match

    cursors = [
      state["last_event_sequence"],
      scorecard.dig("run_identity", "event_count"),
      projection["ledger_cursor"],
      dispatch["ledger_cursor"]
    ]
    coherent = cursors.uniq.length == 1 &&
               projection["state_hash"] == state["state_hash"] &&
               projection["scorecard_event_count"] == scorecard.dig("run_identity", "event_count") &&
               projection.dig("dispatch_ref", "sha256") == dispatch["dispatch_hash"]
    {"cursor" => cursors.min, "max_cursor" => cursors.max, "coherent" => coherent}
  rescue HrmExperiment::ValidationError, JSON::ParserError
    nil
  end

  def write_projection_set(paths, state, scorecard, projection, dispatch)
    payloads = {
      paths["state"] => YAML.dump(state),
      paths["scorecard"] => YAML.dump(scorecard),
      paths["projection"] => "#{JSON.generate(projection)}\n",
      paths["dispatch"] => "#{JSON.generate(dispatch)}\n"
    }
    temporary_paths = []
    payloads.each do |path, payload|
      temporary = "#{path}.tmp-#{Process.pid}-#{SecureRandom.hex(6)}"
      temporary_paths << temporary
      File.open(temporary, File::WRONLY | File::CREAT | File::EXCL, 0o600) do |file|
        file.write(payload)
        file.flush
        file.fsync
      end
    end
    payloads.keys.each_with_index do |path, index|
      File.rename(temporary_paths[index], path)
      File.chmod(0o600, path)
    end
    fsync_directory(File.dirname(paths["events"]))
  ensure
    Array(temporary_paths).each { |path| FileUtils.rm_f(path) }
  end

  def with_run_lock(events_path, capsule)
    HrmExperiment.validate_capsule!(capsule)
    directory = File.dirname(File.expand_path(events_path))
    unless File.directory?(directory)
      raise HrmExperiment::ValidationError, "event artifact directory does not exist: #{directory}"
    end
    artifact_paths(capsule, events_path)

    File.open(events_path, File::RDWR | File::CREAT, 0o600) do |lock|
      File.chmod(0o600, events_path)
      lock.flock(File::LOCK_EX)
      yield
    ensure
      lock.flock(File::LOCK_UN)
    end
  end

  def fsync_directory(directory)
    File.open(directory, File::RDONLY) { |file| file.fsync }
  rescue Errno::EINVAL, Errno::EISDIR
    nil
  end

  def usage
    <<~TEXT
      Usage:
        ruby scripts/hrm_supervisor.rb release-check CAPSULE.yaml EVENTS.jsonl
        ruby scripts/hrm_supervisor.rb resume CAPSULE.yaml EVENTS.jsonl
        ruby scripts/hrm_supervisor.rb context CAPSULE.yaml EVENTS.jsonl ROLE < CONTEXT-REPORT.json
        ruby scripts/hrm_supervisor.rb append CAPSULE.yaml EVENTS.jsonl < EVENT.json
        ruby scripts/hrm_supervisor.rb guard CAPSULE.yaml EVENTS.jsonl ACTION ROLE [ISO8601_NOW]
        ruby scripts/hrm_supervisor.rb supersede PREDECESSOR.yaml EVENTS.jsonl SUCCESSOR.yaml [ISO8601_NOW]
        ruby scripts/hrm_supervisor.rb transition PREDECESSOR.yaml EVENTS.jsonl SUCCESSOR.yaml SESSION_ID EXECUTION_MODE [ISO8601_NOW]
    TEXT
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    command = ARGV.shift
    receipt = case command
              when "release-check"
                capsule_path = ARGV.shift or raise HrmExperiment::ValidationError, HrmSupervisor.usage
                events_path = ARGV.shift or raise HrmExperiment::ValidationError, HrmSupervisor.usage
                HrmSupervisor.validate_release(capsule_path, events_path)
              when "resume"
                capsule_path = ARGV.shift or raise HrmExperiment::ValidationError, HrmSupervisor.usage
                events_path = ARGV.shift or raise HrmExperiment::ValidationError, HrmSupervisor.usage
                HrmSupervisor.resume(capsule_path, events_path)
              when "context"
                capsule_path = ARGV.shift or raise HrmExperiment::ValidationError, HrmSupervisor.usage
                events_path = ARGV.shift or raise HrmExperiment::ValidationError, HrmSupervisor.usage
                role = ARGV.shift or raise HrmExperiment::ValidationError, HrmSupervisor.usage
                HrmSupervisor.record_context(capsule_path, events_path, role, JSON.parse($stdin.read))
              when "append"
                capsule_path = ARGV.shift or raise HrmExperiment::ValidationError, HrmSupervisor.usage
                events_path = ARGV.shift or raise HrmExperiment::ValidationError, HrmSupervisor.usage
                HrmSupervisor.append(capsule_path, events_path, JSON.parse($stdin.read))
              when "guard"
                capsule_path = ARGV.shift or raise HrmExperiment::ValidationError, HrmSupervisor.usage
                events_path = ARGV.shift or raise HrmExperiment::ValidationError, HrmSupervisor.usage
                action = ARGV.shift or raise HrmExperiment::ValidationError, HrmSupervisor.usage
                role = ARGV.shift or raise HrmExperiment::ValidationError, HrmSupervisor.usage
                now_arg = ARGV.shift
                HrmSupervisor.guard(
                  capsule_path,
                  events_path,
                  action,
                  role,
                  now_arg ? Time.iso8601(now_arg) : Time.now.utc
                )
              when "supersede"
                predecessor_path = ARGV.shift or raise HrmExperiment::ValidationError, HrmSupervisor.usage
                events_path = ARGV.shift or raise HrmExperiment::ValidationError, HrmSupervisor.usage
                successor_path = ARGV.shift or raise HrmExperiment::ValidationError, HrmSupervisor.usage
                now_arg = ARGV.shift
                HrmSupervisor.supersede(
                  predecessor_path,
                  events_path,
                  successor_path,
                  now_arg ? Time.iso8601(now_arg) : Time.now.utc
                )
              when "transition"
                predecessor_path = ARGV.shift or raise HrmExperiment::ValidationError, HrmSupervisor.usage
                events_path = ARGV.shift or raise HrmExperiment::ValidationError, HrmSupervisor.usage
                successor_path = ARGV.shift or raise HrmExperiment::ValidationError, HrmSupervisor.usage
                session_id = ARGV.shift or raise HrmExperiment::ValidationError, HrmSupervisor.usage
                execution_mode = ARGV.shift or raise HrmExperiment::ValidationError, HrmSupervisor.usage
                now_arg = ARGV.shift
                HrmSupervisor.transition(
                  predecessor_path,
                  events_path,
                  successor_path,
                  session_id,
                  execution_mode,
                  now_arg ? Time.iso8601(now_arg) : Time.now.utc
                )
              else
                raise HrmExperiment::ValidationError, HrmSupervisor.usage
              end
    puts JSON.generate(receipt)
    exit 3 if receipt["event_type"] == "stop_reason"
  rescue HrmExperiment::ValidationError, JSON::ParserError, Errno::ENOENT, ArgumentError => e
    warn e.message
    exit 2
  end
end
