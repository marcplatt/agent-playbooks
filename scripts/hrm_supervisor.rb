#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "securerandom"
require "set"
require "time"
require "yaml"
require_relative "hrm_experiment"

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
      refresh(capsule, events, events_path, "resume")
    end
  end

  def append(capsule_path, events_path, event)
    capsule = HrmExperiment.load_yaml(capsule_path)
    with_run_lock(events_path, capsule) do
      events = load_and_validate_run(capsule, events_path)
      prepared = prepare_event(capsule, events, event)
      if prepared["event_type"] == "stop_reason" && prepared.dig("details", "stop_reason") == "superseded"
        raise HrmExperiment::ValidationError,
              "use the supervisor supersede command so the stop is bound to a validated successor"
      end
      append_prepared(capsule, events, events_path, prepared, "append")
    end
  end

  def guard(capsule_path, events_path, action, role, now = Time.now.utc)
    capsule = HrmExperiment.load_yaml(capsule_path)
    with_run_lock(events_path, capsule) do
      events = load_and_validate_run(capsule, events_path)
      event = HrmExperiment.guard_action(capsule, events, action, role, now)
      append_prepared(capsule, events, events_path, event, "guard")
    end
  end

  def supersede(predecessor_path, events_path, successor_path, now = Time.now.utc)
    predecessor = HrmExperiment.load_yaml(predecessor_path)
    with_run_lock(events_path, predecessor) do
      events = load_and_validate_run(predecessor, events_path)
      event = HrmExperiment.supersession_event(
        predecessor,
        events,
        HrmExperiment.load_yaml(successor_path),
        now
      )
      append_prepared(predecessor, events, events_path, event, "supersede")
    end
  end

  def projection_path(capsule, events_path)
    safe_session = capsule.fetch("session_id").gsub(/[^A-Za-z0-9_.-]/, "_")
    File.join(File.dirname(File.expand_path(events_path)), "#{safe_session}.supervisor.json")
  end

  def artifact_paths(capsule, events_path)
    expanded_events = File.expand_path(events_path)
    expected_events = File.basename(capsule.dig("metrics", "event_log_path"))
    unless File.basename(expanded_events) == expected_events
      raise HrmExperiment::ValidationError,
            "events path basename must match capsule metrics.event_log_path #{expected_events.inspect}"
    end

    directory = File.dirname(expanded_events)
    {
      "events" => expanded_events,
      "state" => File.join(directory, File.basename(capsule.dig("metrics", "session_state_path"))),
      "scorecard" => File.join(directory, File.basename(capsule.dig("metrics", "scorecard_path"))),
      "projection" => projection_path(capsule, expanded_events)
    }
  end

  def load_and_validate_run(capsule, events_path)
    HrmExperiment.validate_capsule!(capsule)
    paths = artifact_paths(capsule, events_path)
    events = File.exist?(paths["events"]) ? HrmExperiment.load_events(paths["events"]) : []
    validate_run_identity!(capsule, events)
    events
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

  def append_prepared(capsule, events, events_path, event, action)
    prepared = prepare_event(capsule, events, event)
    updated_events = events + [prepared]
    validate_run_identity!(capsule, updated_events)

    File.open(events_path, File::WRONLY | File::CREAT | File::APPEND, 0o600) do |file|
      file.write(JSON.generate(prepared))
      file.write("\n")
      file.flush
      file.fsync
    end
    File.chmod(0o600, events_path)

    refresh(capsule, updated_events, events_path, action).merge(
      "event_sequence" => prepared["sequence"],
      "event_type" => prepared["event_type"]
    )
  end

  def refresh(capsule, events, events_path, action)
    paths = artifact_paths(capsule, events_path)
    before = stored_projection_status(paths, capsule)
    ledger_cursor = events.length
    if before && before["max_cursor"] > ledger_cursor
      raise HrmExperiment::ValidationError,
            "stored projection cursor #{before['max_cursor']} is ahead of ledger cursor #{ledger_cursor}"
    end

    state = HrmExperiment.derive_session_state(capsule, events)
    scorecard = HrmExperiment.evaluate(capsule, events)
    projection = derive_projection(capsule, events, state, scorecard)
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
      "next_action" => projection["next_action"],
      "state_hash" => state["state_hash"],
      "projection_hash" => projection["projection_hash"]
    }
  end

  def derive_projection(capsule, events, state, scorecard)
    attention = derive_attention(events, state)
    if attention.length > MAX_ATTENTION_ITEMS
      raise HrmExperiment::ValidationError,
            "attention projection has #{attention.length} items; consolidate before supervisor continuation"
    end

    next_action = if state.dig("terminal", "state") != "active"
                    "terminal"
                  elsif attention.empty?
                    "continue_routine_workflow"
                  else
                    {
                      "operator_action" => "await_operator_action",
                      "decision" => "await_operator_decision",
                      "blocking_finding" => "route_blocking_finding",
                      "operator_review" => "await_operator_review"
                    }.fetch(attention.first["kind"])
                  end

    projection = {
      "schema_version" => "agent_playbooks.hrm_supervisor_projection.v0.1",
      "session_id" => capsule["session_id"],
      "hrm_id" => capsule.dig("hrm", "id"),
      "capsule_sha256" => HrmExperiment.object_sha256(capsule),
      "ledger_cursor" => events.length,
      "state_hash" => state["state_hash"],
      "scorecard_event_count" => scorecard.dig("run_identity", "event_count"),
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

  def stored_projection_status(paths, capsule)
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
                       projection["capsule_sha256"] == capsule_sha
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
