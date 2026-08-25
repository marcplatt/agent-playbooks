#!/usr/bin/env ruby
# frozen_string_literal: true

require "date"
require "json"
require "time"
require "yaml"

module HrmExperiment
  class ValidationError < StandardError; end

  PROFILE_CONTRACTS = {
    "runtime_build_fast_feedback" => {
      "execution_mode" => "runtime_build",
      "deliverable_type" => "runtime_change",
      "verification_profile" => "standard",
      "budgets" => {
        "max_consecutive_nonruntime_units" => 1,
        "max_correction_rounds" => 2,
        "no_material_progress_minutes" => 45,
        "max_ci_minutes" => 30,
        "max_context_redundancy_ratio" => 0.15
      }
    },
    "production_observation_fail_closed" => {
      "execution_mode" => "production_observation",
      "deliverable_type" => "operational_evidence",
      "verification_profile" => "standard",
      "budgets" => {
        "max_consecutive_nonruntime_units" => 1,
        "max_correction_rounds" => 1,
        "no_material_progress_minutes" => 30,
        "max_ci_minutes" => 20,
        "max_context_redundancy_ratio" => 0.10
      }
    }
  }.freeze

  class SchemaValidator
    def initialize(schema)
      @root = schema
    end

    def validate!(value)
      errors = []
      validate_node(value, @root, "$", errors)
      raise ValidationError, errors.join("\n") unless errors.empty?

      true
    end

    private

    def validate_node(value, schema, path, errors)
      schema = resolve_ref(schema)
      validate_type(value, schema["type"], path, errors) if schema.key?("type")
      return unless type_matches?(value, schema["type"])

      if schema.key?("const") && value != schema["const"]
        errors << "#{path}: expected constant #{schema['const'].inspect}, got #{value.inspect}"
      end
      if schema.key?("enum") && !schema["enum"].include?(value)
        errors << "#{path}: expected one of #{schema['enum'].inspect}, got #{value.inspect}"
      end
      if value.is_a?(String)
        errors << "#{path}: must have at least #{schema['minLength']} characters" if schema["minLength"] && value.length < schema["minLength"]
        if schema["pattern"] && !Regexp.new(schema["pattern"]).match?(value)
          errors << "#{path}: does not match #{schema['pattern'].inspect}"
        end
      end
      if value.is_a?(Numeric) && schema.key?("minimum") && value < schema["minimum"]
        errors << "#{path}: must be >= #{schema['minimum']}"
      end
      if value.is_a?(Numeric) && schema.key?("maximum") && value > schema["maximum"]
        errors << "#{path}: must be <= #{schema['maximum']}"
      end
      validate_object(value, schema, path, errors) if value.is_a?(Hash)
      validate_array(value, schema, path, errors) if value.is_a?(Array)
    end

    def validate_type(value, expected, path, errors)
      return if type_matches?(value, expected)

      errors << "#{path}: expected type #{Array(expected).join(' or ')}, got #{json_type(value)}"
    end

    def type_matches?(value, expected)
      return true if expected.nil?

      Array(expected).any? do |type|
        case type
        when "object" then value.is_a?(Hash)
        when "array" then value.is_a?(Array)
        when "string" then value.is_a?(String)
        when "integer" then value.is_a?(Integer)
        when "number" then value.is_a?(Numeric) && !value.is_a?(TrueClass) && !value.is_a?(FalseClass)
        when "boolean" then value == true || value == false
        when "null" then value.nil?
        else false
        end
      end
    end

    def json_type(value)
      return "null" if value.nil?
      return "boolean" if value == true || value == false
      return "integer" if value.is_a?(Integer)
      return "number" if value.is_a?(Numeric)
      return "object" if value.is_a?(Hash)
      return "array" if value.is_a?(Array)
      return "string" if value.is_a?(String)

      value.class.name
    end

    def validate_object(value, schema, path, errors)
      Array(schema["required"]).each do |key|
        errors << "#{path}: missing required property #{key.inspect}" unless value.key?(key)
      end

      properties = schema.fetch("properties", {})
      value.each do |key, child|
        child_path = "#{path}.#{key}"
        if properties.key?(key)
          validate_node(child, properties[key], child_path, errors)
        elsif schema["additionalProperties"] == false
          errors << "#{child_path}: additional property is not allowed"
        elsif schema["additionalProperties"].is_a?(Hash)
          validate_node(child, schema["additionalProperties"], child_path, errors)
        end
      end
    end

    def validate_array(value, schema, path, errors)
      if schema["minItems"] && value.length < schema["minItems"]
        errors << "#{path}: must contain at least #{schema['minItems']} items"
      end
      if schema["uniqueItems"] && value.map { |item| JSON.generate(item) }.uniq.length != value.length
        errors << "#{path}: items must be unique"
      end
      return unless schema["items"]

      value.each_with_index do |child, index|
        validate_node(child, schema["items"], "#{path}[#{index}]", errors)
      end
    end

    def resolve_ref(schema)
      return schema unless schema["$ref"]

      ref = schema["$ref"]
      raise ValidationError, "unsupported schema reference #{ref.inspect}" unless ref.start_with?("#/")

      ref.delete_prefix("#/").split("/").reduce(@root) do |node, token|
        node.fetch(token.gsub("~1", "/").gsub("~0", "~"))
      end
    end
  end

  module_function

  def load_yaml(path)
    YAML.safe_load(
      File.read(path, encoding: "UTF-8"),
      permitted_classes: [Date, Time],
      aliases: false
    )
  rescue Psych::Exception => e
    raise ValidationError, "#{path}: invalid YAML: #{e.message}"
  end

  def load_json(path)
    JSON.parse(File.read(path, encoding: "UTF-8"))
  rescue JSON::ParserError => e
    raise ValidationError, "#{path}: invalid JSON: #{e.message}"
  end

  def load_events(path)
    events = []
    File.foreach(path, encoding: "UTF-8").with_index(1) do |line, number|
      next if line.strip.empty?

      events << JSON.parse(line)
    rescue JSON::ParserError => e
      raise ValidationError, "#{path}:#{number}: invalid JSON: #{e.message}"
    end
    events
  end

  def schema_path(name)
    File.expand_path("../schemas/#{name}", __dir__)
  end

  def validator(name)
    SchemaValidator.new(load_json(schema_path(name)))
  end

  def validate_capsule!(capsule)
    validator("hrm-execution-capsule.schema.json").validate!(capsule)
    profile = capsule["experiment_profile"]
    contract = PROFILE_CONTRACTS[profile]
    return true unless contract

    mismatches = []
    mismatches << "execution_mode" unless capsule["execution_mode"] == contract["execution_mode"]
    mismatches << "deliverable_type" unless capsule["deliverable_type"] == contract["deliverable_type"]
    mismatches << "verification.profile" unless capsule.dig("verification", "profile") == contract["verification_profile"]
    contract["budgets"].each do |key, expected|
      mismatches << "budgets.#{key}" unless capsule.dig("budgets", key) == expected
    end
    mismatches << "verification.ci_plan_hash" if capsule.dig("verification", "ci_plan_hash").nil?
    mismatches << "verification.exact_checks" if capsule.dig("verification", "exact_checks").empty?
    unless mismatches.empty?
      raise ValidationError,
            "experiment_profile #{profile.inspect} does not match: #{mismatches.join(', ')}; use custom for an intentional override"
    end

    true
  end

  def validate_events!(events)
    event_validator = validator("hrm-run-event.schema.json")
    events.each_with_index do |event, index|
      event_validator.validate!(event)
      Time.iso8601(event.fetch("occurred_at"))
    rescue ArgumentError => e
      raise ValidationError, "event #{index + 1}: invalid occurred_at: #{e.message}"
    rescue ValidationError => e
      raise ValidationError, "event #{index + 1}: #{e.message}"
    end
    true
  end

  def validate_scorecard!(scorecard)
    validator("hrm-run-scorecard.schema.json").validate!(scorecard)
  end

  def evaluate(capsule, events)
    validate_capsule!(capsule)
    validate_events!(events)

    identity_errors = []
    events.each do |event|
      identity_errors << "session_id mismatch at event #{event['sequence']}" unless event["session_id"] == capsule["session_id"]
      identity_errors << "hrm_id mismatch at event #{event['sequence']}" unless event["hrm_id"] == capsule.dig("hrm", "id")
    end

    parsed_times = events.map { |event| Time.iso8601(event.fetch("occurred_at")) }
    expected_sequences = (1..events.length).to_a
    actual_sequences = events.map { |event| event["sequence"] }
    causal_sequence_valid = events.all? do |event|
      cause = event["caused_by_sequence"]
      cause.nil? || (cause.positive? && cause < event["sequence"])
    end
    sequence_valid = actual_sequences == expected_sequences &&
                     parsed_times.each_cons(2).all? { |a, b| b >= a } &&
                     causal_sequence_valid

    by_type = events.group_by { |event| event["event_type"] }
    first = lambda { |type| Array(by_type[type]).first }
    terminal_event = first.call("hrm_closed") || Array(by_type["stop_reason"]).last
    closure_details = terminal_event ? terminal_event.fetch("details", {}) : {}
    closure_decision = closure_details["closure_decision"]

    required_event_types = ["session_started"]
    case closure_decision
    when "closed"
      required_event_types.concat(["semantic_ready", "first_value_artifact", "review_ready", "hrm_closed"])
    when "blocked", "deferred"
      required_event_types.concat(["hrm_closed", "stop_reason"])
    end
    missing_required_events = required_event_types.uniq.reject { |type| by_type.key?(type) }

    conclusive_checks_without_identity = Array(by_type["check_completed"]).select do |event|
      event.dig("check", "conclusive") && (event["candidate_sha"].nil? || event["ci_plan_hash"].nil?)
    end
    conclusive_checks_without_identity.each do |event|
      missing_required_events << "check_identity:event_#{event['sequence']}"
    end

    session_started = first.call("session_started")
    semantic_ready = first.call("semantic_ready")
    first_value = first.call("first_value_artifact")
    review_ready = first.call("review_ready")
    review_started = first.call("operator_review_started")
    review_completed = first.call("operator_review_completed")
    aftercare_observed = first.call("aftercare_observed")

    duration = lambda do |start_event, end_event|
      next nil unless start_event && end_event

      (Time.iso8601(end_event["occurred_at"]) - Time.iso8601(start_event["occurred_at"])).to_i
    end

    material_progress_events = events.select do |event|
      event.dig("details", "material_progress") &&
        (!terminal_event || event["sequence"] <= terminal_event["sequence"])
    end
    progress_anchors = ([session_started] + material_progress_events + [terminal_event]).compact.uniq
    maximum_no_progress_seconds = progress_anchors.each_cons(2).map do |start_event, end_event|
      duration.call(start_event, end_event)
    end.compact.max

    change_units_before_value = Array(by_type["change_unit_started"]).select do |event|
      first_value && event["sequence"] < first_value["sequence"] && event.dig("details", "deliverable_type") != "runtime_change"
    end

    correction_rounds = Array(by_type["candidate_frozen"]).group_by do |event|
      event["change_unit_id"] || "unbound"
    end.values.map { |items| [items.length - 1, 0].max }

    context_events = events.select { |event| event["context"] }
    active_context_bytes = context_events.sum do |event|
      context = event["context"]
      context["instruction_bytes"] + context["artifact_bytes"] + context["tool_output_bytes"]
    end
    artifact_bytes = context_events.sum { |event| event.dig("context", "artifact_bytes") }
    repeated_artifact_bytes = context_events.sum { |event| event.dig("context", "repeated_artifact_bytes") }
    context_redundancy_ratio = artifact_bytes.zero? ? 0.0 : (repeated_artifact_bytes.to_f / artifact_bytes).round(4)
    scope_escape_files = context_events.sum { |event| event.dig("context", "files_outside_declared_dependencies") }
    context_budget_violations = context_events.count do |event|
      role = event["role"]
      budget = capsule.dig("budgets", "context_bytes_by_role", role)
      next false unless budget

      context = event["context"]
      context["instruction_bytes"] + context["artifact_bytes"] + context["tool_output_bytes"] > budget
    end

    completed_checks = Array(by_type["check_completed"])
    conclusive_seen = {}
    duplicate_checks = completed_checks.count do |event|
      next false unless event.dig("check", "conclusive") && event["candidate_sha"] && event["ci_plan_hash"]

      key = [
        event["candidate_sha"],
        event["ci_plan_hash"],
        event.dig("check", "environment_id"),
        event.dig("check", "name")
      ]
      duplicate = conclusive_seen.key?(key)
      conclusive_seen[key] = true
      duplicate
    end
    ci_minutes = (completed_checks.sum { |event| event.dig("check", "duration_seconds") }.to_f / 60).round(2)

    final_candidate_sha = terminal_event&.dig("candidate_sha") || capsule.dig("current_change_unit", "candidate_sha")
    final_ci_plan_hash = capsule.dig("verification", "ci_plan_hash")
    required_checks = capsule.dig("verification", "exact_checks")
    required_checks_passed = required_checks.all? do |check_name|
      completed_checks.any? do |event|
        event.dig("check", "name") == check_name &&
          event.dig("check", "conclusive") &&
          event.dig("check", "conclusion") == "passed" &&
          event["candidate_sha"] == final_candidate_sha &&
          event["ci_plan_hash"] == final_ci_plan_hash &&
          event.dig("check", "environment_id") == capsule.dig("verification", "environment_id")
      end
    end

    opened_findings = Array(by_type["finding_opened"])
    disposition_events = Array(by_type["finding_dispositioned"])
    dispositions = disposition_events.each_with_object({}) do |event, memo|
      memo[event.dig("details", "finding_id")] = event.dig("details", "disposition")
    end
    scope_additions = opened_findings.select { |event| event.dig("details", "scope_addition") }
    undispositioned_scope_additions = scope_additions.count do |event|
      !dispositions.key?(event.dig("details", "finding_id"))
    end
    nonblocking_absorbed = scope_additions.count do |event|
      !event.dig("details", "blocking") && dispositions[event.dig("details", "finding_id")] == "accepted_current_scope"
    end
    late_s0_s1 = opened_findings.count do |event|
      %w[S0 S1].include?(event.dig("details", "interrupt_class")) && event.dig("details", "after_non_disposable_work")
    end

    scenario_results = closure_details.fetch("scenario_results", {})
    accepted_scenarios = capsule.dig("hrm", "accepted_scenarios")
    scenarios_dispositioned = accepted_scenarios.all? { |scenario| scenario_results.key?(scenario) }
    scenarios_passed = accepted_scenarios.all? { |scenario| scenario_results[scenario] == "passed" }
    escaped_p0_p1 = Array(by_type["escaped_defect_recorded"]).count do |event|
      %w[P0 P1].include?(event.dig("details", "severity"))
    end

    explicit_terminal = %w[closed blocked deferred].include?(closure_decision)
    aftercare_window_seconds = capsule.dig("metrics", "aftercare_window_days") * 86_400
    aftercare_elapsed_seconds = duration.call(terminal_event, aftercare_observed)
    aftercare_complete = aftercare_observed&.dig("details", "aftercare_complete") == true &&
                         !aftercare_elapsed_seconds.nil? &&
                         aftercare_elapsed_seconds >= aftercare_window_seconds
    unauthorized_effects = closure_details.fetch("unauthorized_external_effects", 0)
    ambiguous_mutations = closure_details.fetch("unresolved_ambiguous_mutations", 0)
    capability_regressions = closure_details.fetch("capability_regressions_without_approval", 0)

    process_reasons = []
    process_reasons << "late S0/S1 finding" if late_s0_s1.positive?
    if change_units_before_value.length > capsule.dig("budgets", "max_consecutive_nonruntime_units")
      process_reasons << "non-runtime unit budget exceeded"
    end
    if (correction_rounds.max || 0) > capsule.dig("budgets", "max_correction_rounds")
      process_reasons << "correction-round budget exceeded"
    end
    process_reasons << "duplicate conclusive CI" if duplicate_checks.positive?
    process_reasons << "CI-minute budget exceeded" if ci_minutes > capsule.dig("budgets", "max_ci_minutes")
    if maximum_no_progress_seconds && maximum_no_progress_seconds > capsule.dig("budgets", "no_material_progress_minutes") * 60
      process_reasons << "no-material-progress budget exceeded"
    end
    process_reasons << "context budget exceeded" if context_budget_violations.positive?
    if context_redundancy_ratio > capsule.dig("budgets", "max_context_redundancy_ratio")
      process_reasons << "context-redundancy budget exceeded"
    end
    process_reasons << "context scope escape" if scope_escape_files.positive?
    process_reasons << "undispositioned scope addition" if undispositioned_scope_additions.positive?
    process_reasons << "non-blocking scope absorbed" if nonblocking_absorbed.positive?
    stop_reasons = Array(by_type["stop_reason"]).map { |event| event.dig("details", "stop_reason") }
    process_reasons << "liveness stop triggered" if (stop_reasons & %w[governance_loop no_progress budget_exhausted]).any?

    safety_failed = unauthorized_effects.positive? || ambiguous_mutations.positive? || capability_regressions.positive? || escaped_p0_p1.positive? || scenario_results.value?("failed")
    outcome_and_safety = if !explicit_terminal
                           "pending"
                         elsif closure_decision == "blocked"
                           "blocked"
                         elsif closure_decision == "deferred"
                           "deferred"
                         elsif safety_failed || !scenarios_dispositioned || !scenarios_passed || !required_checks_passed
                           "fail"
                         elsif !aftercare_complete
                           "pending"
                         else
                           "pass"
                         end

    required_events_present = missing_required_events.empty?
    run_valid = sequence_valid && required_events_present && identity_errors.empty?
    process_envelope = terminal_event.nil? ? "pending" : (process_reasons.empty? ? "pass" : "fail")
    reasons = identity_errors + missing_required_events.map { |item| "missing #{item}" } + process_reasons
    reasons << "outcome or safety gate failed" if outcome_and_safety == "fail"
    reasons << "aftercare pending" if outcome_and_safety == "pending" && explicit_terminal

    overall = if !run_valid
                "run_invalid"
              elsif outcome_and_safety == "blocked"
                "blocked"
              elsif outcome_and_safety == "deferred"
                "deferred"
              elsif outcome_and_safety == "pending" || process_envelope == "pending"
                "pending"
              elsif outcome_and_safety == "pass" && process_envelope == "pass"
                "pass"
              else
                "fail"
              end

    scorecard = {
      "schema_version" => "agent_playbooks.hrm_run_scorecard.v0.1",
      "run_identity" => {
        "session_id" => capsule["session_id"],
        "hrm_id" => capsule.dig("hrm", "id"),
        "experiment_profile" => capsule["experiment_profile"],
        "execution_mode" => capsule["execution_mode"],
        "playbook_source_sha" => capsule.dig("playbook_pin", "source_sha"),
        "event_count" => events.length
      },
      "instrumentation" => {
        "sequence_valid" => sequence_valid,
        "required_events_present" => required_events_present,
        "missing_required_events" => missing_required_events,
        "aftercare_complete" => aftercare_complete
      },
      "hard_gates" => {
        "explicit_terminal_decision" => explicit_terminal,
        "accepted_scenarios_dispositioned" => scenarios_dispositioned,
        "accepted_scenarios_passed" => scenarios_passed,
        "required_checks_passed" => required_checks_passed,
        "unauthorized_external_effects" => unauthorized_effects,
        "unresolved_ambiguous_mutations" => ambiguous_mutations,
        "capability_regressions_without_approval" => capability_regressions,
        "escaped_p0_p1_defects" => escaped_p0_p1
      },
      "flow" => {
        "semantic_readiness_seconds" => duration.call(session_started, semantic_ready),
        "first_value_from_semantic_ready_seconds" => duration.call(semantic_ready, first_value),
        "review_ready_from_semantic_ready_seconds" => duration.call(semantic_ready, review_ready),
        "total_elapsed_seconds" => duration.call(session_started, terminal_event),
        "maximum_no_progress_seconds" => maximum_no_progress_seconds,
        "nonruntime_units_before_first_value" => change_units_before_value.length,
        "maximum_correction_rounds" => correction_rounds.max || 0
      },
      "decisions" => {
        "decision_requests" => Array(by_type["decision_requested"]).length,
        "late_s0_s1_findings" => late_s0_s1
      },
      "context" => {
        "active_context_bytes" => active_context_bytes,
        "repeated_artifact_bytes" => repeated_artifact_bytes,
        "context_redundancy_ratio" => context_redundancy_ratio,
        "files_outside_declared_dependencies" => scope_escape_files,
        "budget_violations" => context_budget_violations
      },
      "validation" => {
        "completed_checks" => completed_checks.length,
        "ci_minutes" => ci_minutes,
        "duplicate_conclusive_checks" => duplicate_checks
      },
      "scope" => {
        "scope_additions" => scope_additions.length,
        "undispositioned_scope_additions" => undispositioned_scope_additions,
        "nonblocking_additions_absorbed" => nonblocking_absorbed
      },
      "operator" => {
        "review_seconds" => duration.call(review_started, review_completed),
        "review_completed_unassisted" => review_completed&.dig("details", "review_completed_unassisted"),
        "confidence_1_to_5" => review_completed&.dig("details", "confidence_1_to_5"),
        "lane_level_questions_exposed" => review_completed&.dig("details", "lane_level_questions_exposed")
      },
      "verdict" => {
        "run_valid" => run_valid,
        "outcome_and_safety" => outcome_and_safety,
        "process_envelope" => process_envelope,
        "overall" => overall,
        "reasons" => reasons.uniq
      }
    }

    validate_scorecard!(scorecard)
    scorecard
  end

  def usage
    <<~TEXT
      Usage:
        ruby scripts/hrm_experiment.rb validate-capsule CAPSULE.yaml
        ruby scripts/hrm_experiment.rb validate-events EVENTS.jsonl
        ruby scripts/hrm_experiment.rb validate-scorecard SCORECARD.yaml
        ruby scripts/hrm_experiment.rb evaluate CAPSULE.yaml EVENTS.jsonl
    TEXT
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    command = ARGV.shift
    case command
    when "validate-capsule"
      path = ARGV.shift or raise HrmExperiment::ValidationError, HrmExperiment.usage
      HrmExperiment.validate_capsule!(HrmExperiment.load_yaml(path))
      puts "capsule valid: #{path}"
    when "validate-events"
      path = ARGV.shift or raise HrmExperiment::ValidationError, HrmExperiment.usage
      HrmExperiment.validate_events!(HrmExperiment.load_events(path))
      puts "events valid: #{path}"
    when "validate-scorecard"
      path = ARGV.shift or raise HrmExperiment::ValidationError, HrmExperiment.usage
      HrmExperiment.validate_scorecard!(HrmExperiment.load_yaml(path))
      puts "scorecard valid: #{path}"
    when "evaluate"
      capsule_path = ARGV.shift or raise HrmExperiment::ValidationError, HrmExperiment.usage
      events_path = ARGV.shift or raise HrmExperiment::ValidationError, HrmExperiment.usage
      scorecard = HrmExperiment.evaluate(
        HrmExperiment.load_yaml(capsule_path),
        HrmExperiment.load_events(events_path)
      )
      puts YAML.dump(scorecard)
    else
      raise HrmExperiment::ValidationError, HrmExperiment.usage
    end
  rescue HrmExperiment::ValidationError, Errno::ENOENT => e
    warn e.message
    exit 2
  end
end
