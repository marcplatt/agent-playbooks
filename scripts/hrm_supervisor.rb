#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "securerandom"
require "set"
require "time"
require "yaml"
require_relative "hrm_experiment"
require_relative "project_api_skill_registry"

module HrmSupervisor
  MAX_PROJECTION_BYTES = 4096
  MAX_ATTENTION_ITEMS = 12

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

  def resume(capsule_path, events_path)
    capsule = HrmExperiment.load_yaml(capsule_path)
    with_run_lock(events_path, capsule) do
      events = load_and_validate_run(capsule, events_path)
      refresh(capsule, events, events_path, "resume", capsule_path)
    end
  end

  def append(capsule_path, events_path, event)
    capsule = HrmExperiment.load_yaml(capsule_path)
    with_run_lock(events_path, capsule) do
      events = load_and_validate_run(capsule, events_path)
      ensure_run_writable!(capsule, events) unless events.empty?
      prepared = prepare_event(capsule, events, event)
      if prepared["event_type"] == "stop_reason" && prepared.dig("details", "stop_reason") == "superseded"
        raise HrmExperiment::ValidationError,
              "use the supervisor supersede command so the stop is bound to a validated successor"
      end
      append_prepared(capsule, events, events_path, prepared, "append", capsule_path)
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

  def projection_path(capsule, events_path)
    safe_session = capsule.fetch("session_id").gsub(/[^A-Za-z0-9_.-]/, "_")
    File.join(File.dirname(File.expand_path(events_path)), "#{safe_session}.supervisor.json")
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
      "projection" => projection_path(capsule, expanded_events)
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
    prepared["schema_version"] ||= "agent_playbooks.hrm_run_event.v0.4"
    unless prepared["schema_version"] == "agent_playbooks.hrm_run_event.v0.4"
      raise HrmExperiment::ValidationError, "rc.7 supervisor writes require hrm_run_event.v0.4"
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
    prospective_verdict = HrmExperiment.evaluate(capsule, updated_events).fetch("verdict")
    unless prospective_verdict["run_valid"]
      raise HrmExperiment::ValidationError, "supervisor refuses an event that makes the ledger run-invalid"
    end

    File.open(events_path, File::WRONLY | File::CREAT | File::APPEND, 0o600) do |file|
      file.write(JSON.generate(prepared))
      file.write("\n")
      file.flush
      file.fsync
    end
    File.chmod(0o600, events_path)

    refresh(capsule, updated_events, events_path, action, capsule_path).merge(
      "event_sequence" => prepared["sequence"],
      "event_type" => prepared["event_type"]
    )
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
    projection = derive_projection(capsule, events, state, scorecard, api_skill_coverage)
    write_projection_set(paths, state, scorecard, projection)

    {
      "action" => action,
      "session_id" => capsule["session_id"],
      "ledger_cursor" => ledger_cursor,
      "projection_lag_events_before" => before ? ledger_cursor - before["cursor"] : ledger_cursor,
      "projection_lag_events_after" => 0,
      "projection_repaired" => before.nil? || !before["coherent"] || before["cursor"] != ledger_cursor,
      "projection_bytes" => JSON.generate(projection).bytesize,
      "attention_count" => projection["attention"].length,
      "reusable_api_skill_count" => api_skill_coverage["reusable_skill_ids"].length,
      "missing_api_skill_count" => api_skill_coverage["missing_skill_ids"].length,
      "next_action" => projection["next_action"],
      "state_hash" => state["state_hash"],
      "projection_hash" => projection["projection_hash"]
    }
  end

  def derive_projection(capsule, events, state, scorecard, api_skill_coverage)
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
                    "continue_routine_workflow"
                  end

    projection = {
      "schema_version" => "agent_playbooks.hrm_supervisor_projection.v0.3",
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
      "next_action" => next_action
    }
    projection["projection_hash"] = HrmExperiment.object_sha256(projection)
    validate_projection!(projection)

    bytes = JSON.generate(projection).bytesize
    if bytes > MAX_PROJECTION_BYTES
      raise HrmExperiment::ValidationError,
            "supervisor projection is #{bytes} bytes; maximum is #{MAX_PROJECTION_BYTES}"
    end
    projection
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
        next unless details["blocking"] || %w[S0 S1].include?(details["interrupt_class"])

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
    required = %w[state scorecard projection]
    return nil unless required.all? { |name| File.exist?(paths[name]) }

    state = HrmExperiment.load_yaml(paths["state"])
    HrmExperiment.validate_session_state!(state)
    scorecard = HrmExperiment.load_yaml(paths["scorecard"])
    HrmExperiment.validate_scorecard!(scorecard)
    projection = HrmExperiment.load_json(paths["projection"])
    validate_projection!(projection)

    capsule_sha = HrmExperiment.object_sha256(capsule)
    identities_match = state["session_id"] == capsule["session_id"] &&
                       state["capsule_sha256"] == capsule_sha &&
                       scorecard.dig("run_identity", "session_id") == capsule["session_id"] &&
                       projection["session_id"] == capsule["session_id"] &&
                       projection["capsule_sha256"] == capsule_sha &&
                       projection["project_api_skills"] == api_skill_coverage
    return nil unless identities_match

    cursors = [
      state["last_event_sequence"],
      scorecard.dig("run_identity", "event_count"),
      projection["ledger_cursor"]
    ]
    coherent = cursors.uniq.length == 1 &&
               projection["state_hash"] == state["state_hash"] &&
               projection["scorecard_event_count"] == scorecard.dig("run_identity", "event_count")
    {"cursor" => cursors.min, "max_cursor" => cursors.max, "coherent" => coherent}
  rescue HrmExperiment::ValidationError, JSON::ParserError
    nil
  end

  def write_projection_set(paths, state, scorecard, projection)
    payloads = {
      paths["state"] => YAML.dump(state),
      paths["scorecard"] => YAML.dump(scorecard),
      paths["projection"] => "#{JSON.generate(projection)}\n"
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
        ruby scripts/hrm_supervisor.rb resume CAPSULE.yaml EVENTS.jsonl
        ruby scripts/hrm_supervisor.rb append CAPSULE.yaml EVENTS.jsonl < EVENT.json
        ruby scripts/hrm_supervisor.rb guard CAPSULE.yaml EVENTS.jsonl ACTION ROLE [ISO8601_NOW]
        ruby scripts/hrm_supervisor.rb supersede PREDECESSOR.yaml EVENTS.jsonl SUCCESSOR.yaml [ISO8601_NOW]
    TEXT
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    command = ARGV.shift
    receipt = case command
              when "resume"
                capsule_path = ARGV.shift or raise HrmExperiment::ValidationError, HrmSupervisor.usage
                events_path = ARGV.shift or raise HrmExperiment::ValidationError, HrmSupervisor.usage
                HrmSupervisor.resume(capsule_path, events_path)
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
              else
                raise HrmExperiment::ValidationError, HrmSupervisor.usage
              end
    puts JSON.generate(receipt)
    exit 3 if command == "guard" && receipt["event_type"] == "stop_reason"
  rescue HrmExperiment::ValidationError, JSON::ParserError, Errno::ENOENT, ArgumentError => e
    warn e.message
    exit 2
  end
end
