#!/usr/bin/env ruby
# frozen_string_literal: true

require "date"
require "digest"
require "json"
require "time"
require "yaml"

module HrmExperiment
  class ValidationError < StandardError; end

  SUPERVISOR_OWNED_KERNEL_VERSION = "0.1.0-rc.6"

  STANDARD_OPERATOR_GATES = %w[
    business_meaning
    operator_function_review
    exact_head_merge_release
    external_effect_authority
    hrm_closure
  ].freeze

  EXTERNAL_EFFECT_CLASSES = %w[
    provider_mutation
    customer_transmission
    money_movement
    credential_mutation
    permission_mutation
    deployment
    activation
    canary_execution
    destructive_action
    autonomy
  ].freeze

  OPERATOR_ACTION_KINDS = %w[
    sign_in
    mfa
    credential_unlock
    private_value_entry
    physical_presence
  ].freeze

  WORKER_REQUIRED_ACTIONS = {
    "implement_frozen_slice" => "builder",
    "commit_in_scope_changes" => "builder",
    "correct_within_budget" => "builder",
    "run_declared_checks" => "checker",
    "inspect_provider_read_only" => "provider_observer",
    "discover_project_api_skills" => "provider_observer",
    "prepare_private_inputs" => "provider_observer",
    "record_operational_evidence" => "provider_observer"
  }.freeze

  RUNTIME_BUILD_ACTIONS = %w[
    inspect_read_only
    inspect_provider_read_only
    discover_project_api_skills
    manage_task_branch_worktree
    implement_frozen_slice
    commit_in_scope_changes
    publish_or_update_review_pr
    run_declared_checks
    correct_within_budget
    wait_for_declared_checks
    post_authorized_merge_readback
  ].freeze

  PRODUCTION_OBSERVATION_ACTIONS = %w[
    inspect_read_only
    inspect_provider_read_only
    discover_project_api_skills
    prepare_private_inputs
    run_declared_checks
    wait_for_declared_checks
    record_operational_evidence
  ].freeze

  RUNTIME_WORKFLOW_AUTHORITY = {
    "inspect_read_only" => true,
    "inspect_provider_read_only" => true,
    "manage_task_branch_worktree" => true,
    "implement_allowed_paths" => true,
    "commit_changes" => true,
    "publish_review_pr" => true,
    "bounded_ci_correction" => true,
    "run_declared_checks" => true,
    "wait_for_declared_checks" => true,
    "prepare_private_inputs" => false,
    "record_operational_evidence" => false,
    "post_authorized_merge_readback" => true,
    "merge_without_grant" => false
  }.freeze

  PRODUCTION_WORKFLOW_AUTHORITY = {
    "inspect_read_only" => true,
    "inspect_provider_read_only" => true,
    "manage_task_branch_worktree" => false,
    "implement_allowed_paths" => false,
    "commit_changes" => false,
    "publish_review_pr" => false,
    "bounded_ci_correction" => false,
    "run_declared_checks" => true,
    "wait_for_declared_checks" => true,
    "prepare_private_inputs" => true,
    "record_operational_evidence" => true,
    "post_authorized_merge_readback" => false,
    "merge_without_grant" => false
  }.freeze

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
        "max_context_redundancy_ratio" => 0.15,
        "max_context_compactions_before_expected_value" => 0,
        "max_inline_raw_log_bytes" => 2000,
        "max_state_artifact_echo_bytes" => 1000
      },
      "routine_actions" => RUNTIME_BUILD_ACTIONS,
      "workflow_authority" => RUNTIME_WORKFLOW_AUTHORITY,
      "aftercare_window_days" => 14
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
        "max_context_redundancy_ratio" => 0.10,
        "max_context_compactions_before_expected_value" => 0,
        "max_inline_raw_log_bytes" => 2000,
        "max_state_artifact_echo_bytes" => 1000
      },
      "routine_actions" => PRODUCTION_OBSERVATION_ACTIONS,
      "workflow_authority" => PRODUCTION_WORKFLOW_AUTHORITY,
      "aftercare_window_days" => 14
    }
  }.freeze

  SUPPORTED_DELIVERABLES_BY_MODE = {
    "runtime_build" => %w[runtime_change executable_contract],
    "production_observation" => %w[operational_evidence],
    "discovery" => %w[review_packet executable_contract],
    "rollout" => %w[operational_evidence]
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

  def canonical_value(value)
    case value
    when Hash
      value.keys.sort.each_with_object({}) { |key, memo| memo[key] = canonical_value(value[key]) }
    when Array
      value.map { |item| canonical_value(item) }
    else
      value
    end
  end

  def object_sha256(value)
    Digest::SHA256.hexdigest(JSON.generate(canonical_value(value)))
  end

  def validate_capsule!(capsule)
    validator("hrm-execution-capsule.schema.json").validate!(capsule)

    resolution = capsule.fetch("target_resolution")
    resolved_hrm = resolution.fetch("resolved_hrm_id")
    target_errors = []
    target_errors << "resolved_hrm_id must equal hrm.id" unless resolved_hrm == capsule.dig("hrm", "id")
    if resolution["method"] == "derived_current"
      target_errors << "derived_current must resolve current_target_hrm" unless resolved_hrm == resolution["current_target_hrm"]
      target_errors << "derived_current cannot carry explicit_hrm_id" unless resolution["explicit_hrm_id"].nil?
    else
      target_errors << "explicit_exact_override must carry the exact resolved HRM ID" unless resolution["explicit_hrm_id"] == resolved_hrm
      target_errors << "current HRM must use derived_current, not an override" if resolved_hrm == resolution["current_target_hrm"]
    end
    raise ValidationError, "target resolution invalid: #{target_errors.join(', ')}" unless target_errors.empty?

    lineage = capsule.fetch("session_lineage")
    lineage_errors = []
    if lineage["continuation_reason"] == "initial"
      lineage_errors << "initial capsule_sequence must be 1" unless lineage["capsule_sequence"] == 1
      lineage_errors << "initial session cannot have a predecessor" unless lineage["predecessor_session_id"].nil?
      lineage_errors << "initial session cannot inherit state" unless lineage["inherited_state_path"].nil?
    else
      lineage_errors << "continuation capsule_sequence must be greater than 1" unless lineage["capsule_sequence"] > 1
      lineage_errors << "continuation requires predecessor_session_id" if lineage["predecessor_session_id"].nil?
      lineage_errors << "continuation requires inherited_state_path" if lineage["inherited_state_path"].nil?
    end
    raise ValidationError, "session lineage invalid: #{lineage_errors.join(', ')}" unless lineage_errors.empty?

    unless capsule.dig("function_slice", "accepted_scenarios") == capsule.dig("hrm", "accepted_scenarios")
      raise ValidationError, "function_slice.accepted_scenarios must equal hrm.accepted_scenarios"
    end

    required_skill_ids = capsule.dig("project_api_skills", "required_skills").map do |skill|
      skill.fetch("skill_id")
    end
    unless required_skill_ids.uniq.length == required_skill_ids.length
      raise ValidationError, "project_api_skills.required_skills must contain unique skill_id values"
    end

    lease = capsule.fetch("workflow_lease")
    unless lease["operator_gate_classes"].sort == STANDARD_OPERATOR_GATES.sort
      raise ValidationError, "workflow_lease.operator_gate_classes must equal the five genuine human gates"
    end

    entry_condition = capsule.fetch("entry_condition")
    supported_deliverables = SUPPORTED_DELIVERABLES_BY_MODE.fetch(capsule["execution_mode"], [])
    incompatible = entry_condition.fetch("known_missing_deliverable_types") - supported_deliverables
    unless incompatible.empty?
      raise ValidationError,
            "execution mode cannot produce known missing deliverable(s) #{incompatible.join(', ')}; " \
            "start a successor capsule with continuation_reason execution_mode_changed or stop blocked_input"
    end

    role_topology = capsule.fetch("role_topology")
    unless role_topology["worker_required_actions"] == WORKER_REQUIRED_ACTIONS
      raise ValidationError, "role_topology.worker_required_actions must match the kernel worker isolation contract"
    end
    missing_fresh_roles = WORKER_REQUIRED_ACTIONS.values.uniq - role_topology.fetch("fresh_context_roles")
    unless missing_fresh_roles.empty?
      raise ValidationError, "fresh context is required for #{missing_fresh_roles.join(', ')}"
    end

    action_authority = {
      "inspect_read_only" => "inspect_read_only",
      "inspect_provider_read_only" => "inspect_provider_read_only",
      "discover_project_api_skills" => "inspect_provider_read_only",
      "manage_task_branch_worktree" => "manage_task_branch_worktree",
      "implement_frozen_slice" => "implement_allowed_paths",
      "commit_in_scope_changes" => "commit_changes",
      "publish_or_update_review_pr" => "publish_review_pr",
      "run_declared_checks" => "run_declared_checks",
      "correct_within_budget" => "bounded_ci_correction",
      "wait_for_declared_checks" => "wait_for_declared_checks",
      "prepare_private_inputs" => "prepare_private_inputs",
      "record_operational_evidence" => "record_operational_evidence",
      "post_authorized_merge_readback" => "post_authorized_merge_readback"
    }
    unauthorized_routine_actions = lease["permitted_routine_actions"].map do |action|
      authority_key = action_authority[action]
      action if authority_key && !capsule.dig("authority", "workflow", authority_key)
    end.compact
    unless unauthorized_routine_actions.empty?
      raise ValidationError, "workflow lease exceeds workflow authority: #{unauthorized_routine_actions.join(', ')}"
    end

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
    mismatches << "workflow_lease.permitted_routine_actions" unless lease["permitted_routine_actions"].sort == contract["routine_actions"].sort
    mismatches << "authority.workflow" unless capsule.dig("authority", "workflow") == contract["workflow_authority"]
    operational_authority = capsule.dig("authority", "operational")
    mismatches << "authority.operational" unless operational_authority.values.none?
    mismatches << "metrics.aftercare_window_days" unless capsule.dig("metrics", "aftercare_window_days") == contract["aftercare_window_days"]
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
      details = event.fetch("details", {})
      case event["event_type"]
      when "decision_requested"
        missing = %w[decision_id decision_kind exact_effect].reject { |key| details.key?(key) }
        raise ValidationError, "decision_requested missing #{missing.join(', ')}" unless missing.empty?
        unless STANDARD_OPERATOR_GATES.include?(details["decision_kind"])
          raise ValidationError, "decision_requested is not a genuine human gate"
        end
        if details["decision_kind"] == "external_effect_authority" &&
           !EXTERNAL_EFFECT_CLASSES.include?(details["effect_class"])
          raise ValidationError, "external-effect decision requires a mutation or transmission effect_class"
        end
      when "decision_received"
        missing = %w[decision_id decision_kind exact_effect].reject { |key| details.key?(key) }
        raise ValidationError, "decision_received missing #{missing.join(', ')}" unless missing.empty?
        if details["decision_kind"] == "external_effect_authority" &&
           !EXTERNAL_EFFECT_CLASSES.include?(details["effect_class"])
          raise ValidationError, "external-effect decision requires a mutation or transmission effect_class"
        end
      when "operator_action_required", "operator_action_completed"
        missing = %w[action_id operator_action_kind exact_action].reject { |key| details.key?(key) }
        raise ValidationError, "#{event['event_type']} missing #{missing.join(', ')}" unless missing.empty?
        unless OPERATOR_ACTION_KINDS.include?(details["operator_action_kind"])
          raise ValidationError, "unsupported operator action kind #{details['operator_action_kind'].inspect}"
        end
      when "context_snapshot"
        raise ValidationError, "context_snapshot requires context" unless event["context"]
        raise ValidationError, "context_snapshot requires a role" if event["role"].nil?
      when "action_guard_passed"
        missing = %w[action guarded_role].reject { |key| details.key?(key) }
        raise ValidationError, "action_guard_passed missing #{missing.join(', ')}" unless missing.empty?
        raise ValidationError, "guarded_role must equal event role" unless details["guarded_role"] == event["role"]
        required_role = WORKER_REQUIRED_ACTIONS[details["action"]]
        if required_role && event["role"] != required_role
          raise ValidationError, "#{details['action']} guard requires role #{required_role}"
        end
      when "first_executable_delta"
        unless details["deliverable_type"] == "runtime_change" && details["material_progress"] == true
          raise ValidationError, "first_executable_delta must record a material runtime_change"
        end
        raise ValidationError, "first_executable_delta requires builder role" unless event["role"] == "builder"
      when "first_operational_evidence"
        unless details["deliverable_type"] == "operational_evidence" && details["material_progress"] == true
          raise ValidationError, "first_operational_evidence must record material operational_evidence"
        end
        raise ValidationError, "first_operational_evidence requires provider_observer role" unless event["role"] == "provider_observer"
      when "authority_granted", "authority_consumed"
        missing = %w[grant_id decision_kind exact_effect].reject { |key| details.key?(key) }
        raise ValidationError, "#{event['event_type']} missing #{missing.join(', ')}" unless missing.empty?
        raise ValidationError, "routine workflow cannot require an authority grant" unless STANDARD_OPERATOR_GATES.include?(details["decision_kind"])
      when "check_completed"
        raise ValidationError, "check_completed requires checker role" unless event["role"] == "checker"
        if event.dig("check", "conclusive")
          check = event.fetch("check")
          missing = %w[summary raw_artifact_path raw_artifact_sha256 raw_artifact_bytes].reject { |key| check.key?(key) }
          raise ValidationError, "conclusive check missing #{missing.join(', ')}" unless missing.empty?
          if check["raw_artifact_bytes"].positive? && (check["raw_artifact_path"].nil? || check["raw_artifact_sha256"].nil?)
            raise ValidationError, "conclusive check raw artifact requires path and digest"
          end
        end
      when "integration_read_back"
        raise ValidationError, "integration_read_back requires candidate_sha" if event["candidate_sha"].nil?
        raise ValidationError, "integration_read_back requires integration_verified" unless details["integration_verified"] == true
      when "stop_reason"
        next unless details["stop_reason"] == "superseded"

        missing = %w[
          successor_session_id
          successor_capsule_sha256
          newly_missing_deliverable_types
        ].reject { |key| details.key?(key) }
        raise ValidationError, "superseded stop missing #{missing.join(', ')}" unless missing.empty?
        if details["newly_missing_deliverable_types"].empty?
          raise ValidationError, "superseded stop requires a newly missing deliverable"
        end
      end
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

  def validate_session_state!(state)
    validator("hrm-session-state.schema.json").validate!(state)
    expected_hash = object_sha256(state.reject { |key, _value| key == "state_hash" })
    raise ValidationError, "session state hash mismatch" unless state["state_hash"] == expected_hash

    true
  end

  def derive_session_state(capsule, events)
    validate_capsule!(capsule)
    validate_events!(events)
    events.each do |event|
      raise ValidationError, "session state event session_id mismatch" unless event["session_id"] == capsule["session_id"]
      raise ValidationError, "session state event hrm_id mismatch" unless event["hrm_id"] == capsule.dig("hrm", "id")
    end

    phase = "planned"
    events.each do |event|
      case event["event_type"]
      when "semantic_readiness_requested"
        phase = "semantic_readiness"
      when "semantic_ready", "integration_read_back"
        phase = "ready"
      when "change_unit_started", "first_executable_delta", "first_operational_evidence"
        phase = capsule["execution_mode"] == "production_observation" ? "observing" : "building"
      when "candidate_frozen"
        phase = "candidate_frozen"
      when "check_started", "check_completed"
        phase = "checking"
      when "review_ready", "operator_review_started", "operator_review_completed"
        phase = "review_ready"
      when "hrm_closed"
        phase = event.dig("details", "closure_decision")
      when "stop_reason"
        stop_reason = event.dig("details", "stop_reason")
        phase = "review_ready" if stop_reason == "review_ready"
        phase = "ready" if stop_reason == "done_verified"
        phase = "blocked" if %w[blocked_input blocked_external scope_divergence governance_loop no_progress budget_exhausted superseded].include?(stop_reason)
      end
    end

    last_change_event = events.reverse.find { |event| event["change_unit_id"] }
    change_unit_id = last_change_event && last_change_event["change_unit_id"]
    change_unit_start = events.reverse.find do |event|
      event["event_type"] == "change_unit_started" && event["change_unit_id"] == change_unit_id
    end
    last_candidate = events.reverse.find { |event| event["candidate_sha"] }
    last_material = events.reverse.find { |event| event.dig("details", "material_progress") }
    correction_rounds = Array(events.group_by { |event| event["change_unit_id"] }.values).map do |group|
      [[group.count { |event| event["event_type"] == "candidate_frozen" } - 1, 0].max, 0].max
    end.max || 0

    granted_ids = events.select { |event| event["event_type"] == "authority_granted" }.map { |event| event.dig("details", "grant_id") }
    consumed_ids = events.select { |event| event["event_type"] == "authority_consumed" }.map { |event| event.dig("details", "grant_id") }

    terminal_event = events.reverse.find { |event| %w[hrm_closed stop_reason].include?(event["event_type"]) }
    terminal_details = terminal_event ? terminal_event.fetch("details", {}) : {}
    stop_reason = terminal_event && terminal_event["event_type"] == "stop_reason" ? terminal_details["stop_reason"] : nil
    terminal_state = if terminal_event&.dig("event_type") == "hrm_closed"
                       terminal_details["closure_decision"]
                     elsif stop_reason == "superseded"
                       "superseded"
                     elsif %w[blocked_input blocked_external scope_divergence governance_loop no_progress budget_exhausted].include?(stop_reason)
                       "blocked"
                     else
                       "active"
                     end

    state = {
      "schema_version" => "agent_playbooks.hrm_session_state.v0.2",
      "session_id" => capsule["session_id"],
      "hrm_id" => capsule.dig("hrm", "id"),
      "capsule_sha256" => object_sha256(capsule),
      "phase" => phase,
      "current_change_unit" => {
        "id" => change_unit_id,
        "deliverable_type" => change_unit_start&.dig("details", "deliverable_type"),
        "candidate_sha" => last_candidate && last_candidate["candidate_sha"]
      },
      "progress" => {
        "last_material_event_sequence" => last_material ? last_material["sequence"] : 0,
        "last_material_progress_at" => last_material && last_material["occurred_at"],
        "correction_rounds" => correction_rounds
      },
      "terminal" => {
        "state" => terminal_state,
        "stop_reason" => stop_reason,
        "evidence" => [terminal_details["note"]].compact
      },
      "active_grant_ids" => (granted_ids - consumed_ids).uniq,
      "last_event_sequence" => events.empty? ? 0 : events.last["sequence"],
      "last_event_at" => events.empty? ? nil : events.last["occurred_at"]
    }
    state["state_hash"] = object_sha256(state)
    validate_session_state!(state)
    state
  end

  def validate_authority_grant!(grant, capsule)
    validator("hrm-authority-grant.schema.json").validate!(grant)
    validate_capsule!(capsule)

    errors = []
    errors << "session_id mismatch" unless grant["session_id"] == capsule["session_id"]
    errors << "hrm_id mismatch" unless grant["hrm_id"] == capsule.dig("hrm", "id")

    issued_at = Time.iso8601(grant.fetch("issued_at"))
    expires_at = grant["expires_at"] && Time.iso8601(grant["expires_at"])
    errors << "expires_at must be later than issued_at" if expires_at && expires_at <= issued_at

    expected_effects = {
      "operator_function_acceptance" => ["operator_function_acceptance"],
      "merge_release" => ["merge_exact_head"],
      "hrm_closure" => ["hrm_closure"]
    }
    if expected_effects.key?(grant["grant_type"])
      errors << "allowed_effects do not match grant_type" unless grant["allowed_effects"] == expected_effects[grant["grant_type"]]
    end

    case grant["grant_type"]
    when "operator_function_acceptance", "merge_release", "hrm_closure"
      errors << "candidate_sha is required" if grant["candidate_sha"].nil?
    when "external_effect_authority"
      errors << "external-effect grant requires an expiry" if expires_at.nil?
      errors << "external-effect grant requires repository" if grant["repository"].nil?
      errors << "external-effect grant requires candidate_sha" if grant["candidate_sha"].nil?
      unless (grant["allowed_effects"] - EXTERNAL_EFFECT_CLASSES).empty?
        errors << "external-effect grant contains a read-only or non-operational effect"
      end
    end
    errors << "merge grant requires repository" if grant["grant_type"] == "merge_release" && grant["repository"].nil?

    raise ValidationError, "authority grant invalid: #{errors.join(', ')}" unless errors.empty?

    true
  rescue ArgumentError => e
    raise ValidationError, "authority grant time invalid: #{e.message}"
  end

  def append_event!(path, event, validated_supersession: false)
    if event["event_type"] == "stop_reason" && event.dig("details", "stop_reason") == "superseded" && !validated_supersession
      raise ValidationError, "use supersede-with-successor so the terminal event is bound to a validated successor capsule"
    end

    File.open(path, File::RDWR | File::CREAT, 0o600) do |file|
      file.flock(File::LOCK_EX)
      prior_events = load_events(path)
      expected_sequence = prior_events.length + 1
      unless event["sequence"] == expected_sequence
        raise ValidationError, "event sequence must be #{expected_sequence}, got #{event['sequence'].inspect}"
      end

      validate_events!(prior_events + [event])
      file.seek(0, IO::SEEK_END)
      file.write(JSON.generate(event))
      file.write("\n")
      file.flush
      file.fsync
    end
    File.chmod(0o600, path)
    "event appended: #{event['session_id']} sequence=#{event['sequence']} type=#{event['event_type']}"
  end

  def validate_successor!(predecessor, events, successor)
    validate_capsule!(predecessor)
    validate_events!(events)
    validate_capsule!(successor)

    errors = []
    events.each do |event|
      errors << "predecessor event session_id mismatch" unless event["session_id"] == predecessor["session_id"]
      errors << "predecessor event hrm_id mismatch" unless event["hrm_id"] == predecessor.dig("hrm", "id")
    end
    if events.any? { |event| %w[hrm_closed stop_reason].include?(event["event_type"]) }
      errors << "predecessor session is already terminal"
    end

    lineage = successor.fetch("session_lineage")
    errors << "successor predecessor_session_id mismatch" unless lineage["predecessor_session_id"] == predecessor["session_id"]
    unless lineage["capsule_sequence"] == predecessor.dig("session_lineage", "capsule_sequence") + 1
      errors << "successor capsule_sequence must increment by one"
    end
    errors << "successor continuation_reason must be execution_mode_changed" unless lineage["continuation_reason"] == "execution_mode_changed"
    unless lineage["inherited_state_path"] == predecessor.dig("metrics", "session_state_path")
      errors << "successor inherited_state_path must equal the predecessor session_state_path"
    end

    %w[playbook_pin system_reference project_root repository_bases target_resolution hrm].each do |key|
      errors << "successor #{key} mismatch" unless successor[key] == predecessor[key]
    end
    %w[function_ids accepted_scenarios].each do |key|
      unless successor.dig("function_slice", key) == predecessor.dig("function_slice", key)
        errors << "successor function_slice.#{key} mismatch"
      end
    end
    if successor["execution_mode"] == predecessor["execution_mode"]
      errors << "successor execution_mode must change"
    end

    predecessor_supported = SUPPORTED_DELIVERABLES_BY_MODE.fetch(predecessor["execution_mode"], [])
    newly_missing = successor.dig("entry_condition", "known_missing_deliverable_types") -
                    predecessor.dig("entry_condition", "known_missing_deliverable_types")
    mode_incompatible = newly_missing - predecessor_supported
    if mode_incompatible.empty?
      errors << "successor must carry a newly missing deliverable that the predecessor mode cannot produce"
    end

    raise ValidationError, "successor capsule invalid: #{errors.join(', ')}" unless errors.empty?

    mode_incompatible
  end

  def supersession_event(predecessor, events, successor, now = Time.now.utc)
    newly_missing = validate_successor!(predecessor, events, successor)
    raise ValidationError, "supersede-with-successor requires a session_started event" if events.empty?

    {
      "schema_version" => "agent_playbooks.hrm_run_event.v0.3",
      "session_id" => predecessor["session_id"],
      "hrm_id" => predecessor.dig("hrm", "id"),
      "sequence" => events.length + 1,
      "event_type" => "stop_reason",
      "occurred_at" => now.utc.iso8601,
      "caused_by_sequence" => events.last["sequence"],
      "role" => "orchestrator",
      "details" => {
        "stop_reason" => "superseded",
        "material_progress" => true,
        "successor_session_id" => successor["session_id"],
        "successor_capsule_sha256" => object_sha256(successor),
        "newly_missing_deliverable_types" => newly_missing,
        "note" => "Superseded by validated successor #{successor['session_id']}."
      }
    }
  end

  def compactions_before(events, boundary_sequence, role: nil)
    snapshots = events.select do |event|
      event["event_type"] == "context_snapshot" &&
        (boundary_sequence.nil? || event["sequence"] < boundary_sequence) &&
        (role.nil? || event["role"] == role)
    end
    snapshots.group_by { |event| event.dig("context", "turn_id") }.values.sum do |turn_events|
      turn_events.map { |event| event.dig("context", "context_compactions") }.max || 0
    end
  end

  def guard_action(capsule, events, action, role, now = Time.now.utc)
    validate_capsule!(capsule)
    validate_events!(events)
    raise ValidationError, "guard-action requires a session_started event" if events.empty?

    events.each do |event|
      raise ValidationError, "guard-action session_id mismatch" unless event["session_id"] == capsule["session_id"]
      raise ValidationError, "guard-action hrm_id mismatch" unless event["hrm_id"] == capsule.dig("hrm", "id")
    end
    if events.any? { |event| %w[hrm_closed stop_reason].include?(event["event_type"]) }
      raise ValidationError, "guard-action cannot advance a terminal session"
    end
    unless capsule.dig("workflow_lease", "permitted_routine_actions").include?(action)
      raise ValidationError, "action #{action.inspect} is outside the workflow lease"
    end

    required_role = capsule.dig("role_topology", "worker_required_actions", action)
    if required_role && role != required_role
      raise ValidationError, "action #{action.inspect} requires a fresh #{required_role} context, not #{role}"
    end

    latest_context = events.reverse.find do |event|
      event["event_type"] == "context_snapshot" && event["role"] == role
    end
    raise ValidationError, "fresh context_snapshot required for #{role} before #{action}" unless latest_context
    unless latest_context["sequence"] == events.last["sequence"]
      raise ValidationError, "context_snapshot for #{role} must immediately precede guard-action"
    end

    context_budget = capsule.dig("budgets", "context_bytes_by_role", role)
    raise ValidationError, "no context budget declared for role #{role.inspect}" unless context_budget

    first_executable = events.find { |event| event["event_type"] == "first_executable_delta" }
    first_operational = events.find { |event| event["event_type"] == "first_operational_evidence" }
    expected_value = capsule["deliverable_type"] == "runtime_change" ? first_executable : first_operational
    compactions = compactions_before(events, expected_value && expected_value["sequence"], role: "orchestrator")
    last_progress = events.reverse.find { |event| event.dig("details", "material_progress") } || events.first
    elapsed = (now - Time.iso8601(last_progress.fetch("occurred_at"))).to_i

    stop_reason = nil
    stop_note = nil
    if elapsed > capsule.dig("budgets", "no_material_progress_minutes") * 60
      stop_reason = "no_progress"
      stop_note = "online guard stopped before #{action}: no material progress for #{elapsed} seconds"
    elsif latest_context.dig("context", "active_context_bytes") > context_budget
      stop_reason = "budget_exhausted"
      stop_note = "online guard stopped before #{action}: #{role} context budget exceeded"
    elsif expected_value.nil? &&
          compactions > capsule.dig("budgets", "max_context_compactions_before_expected_value")
      stop_reason = "budget_exhausted"
      stop_note = "online guard stopped before #{action}: orchestrator compacted before expected executable or operational value"
    end

    details = if stop_reason
                {"stop_reason" => stop_reason, "material_progress" => false, "note" => stop_note}
              else
                {"action" => action, "guarded_role" => role, "material_progress" => false}
              end
    {
      "schema_version" => "agent_playbooks.hrm_run_event.v0.3",
      "session_id" => capsule["session_id"],
      "hrm_id" => capsule.dig("hrm", "id"),
      "sequence" => events.length + 1,
      "event_type" => stop_reason ? "stop_reason" : "action_guard_passed",
      "occurred_at" => now.utc.iso8601,
      "caused_by_sequence" => events.last["sequence"],
      "role" => stop_reason ? "orchestrator" : role,
      "details" => details
    }
  end

  def evaluate(capsule, events)
    validate_capsule!(capsule)
    validate_events!(events)

    identity_errors = []
    events.each do |event|
      identity_errors << "session_id mismatch at event #{event['sequence']}" unless event["session_id"] == capsule["session_id"]
      identity_errors << "hrm_id mismatch at event #{event['sequence']}" unless event["hrm_id"] == capsule.dig("hrm", "id")
    end

    decision_requests_by_id = events.select { |event| event["event_type"] == "decision_requested" }.group_by do |event|
      event.dig("details", "decision_id")
    end
    decision_requests_by_id.each do |decision_id, requests|
      identity_errors << "duplicate decision request #{decision_id}" if requests.length > 1
    end
    events.select { |event| event["event_type"] == "decision_received" }.each do |response|
      decision_id = response.dig("details", "decision_id")
      request = Array(decision_requests_by_id[decision_id]).first
      if request.nil? || request["sequence"] >= response["sequence"]
        identity_errors << "unbound decision response #{decision_id} at event #{response['sequence']}"
      elsif request.dig("details", "decision_kind") != response.dig("details", "decision_kind")
        identity_errors << "decision kind mismatch #{decision_id} at event #{response['sequence']}"
      elsif request.dig("details", "effect_class") != response.dig("details", "effect_class")
        identity_errors << "decision effect class mismatch #{decision_id} at event #{response['sequence']}"
      end
    end
    operator_actions_by_id = events.select { |event| event["event_type"] == "operator_action_required" }.group_by do |event|
      event.dig("details", "action_id")
    end
    operator_actions_by_id.each do |action_id, requests|
      identity_errors << "duplicate operator action request #{action_id}" if requests.length > 1
    end
    events.select { |event| event["event_type"] == "operator_action_completed" }.each do |completion|
      action_id = completion.dig("details", "action_id")
      request = Array(operator_actions_by_id[action_id]).first
      if request.nil? || request["sequence"] >= completion["sequence"]
        identity_errors << "unbound operator action completion #{action_id} at event #{completion['sequence']}"
      elsif request.dig("details", "operator_action_kind") != completion.dig("details", "operator_action_kind")
        identity_errors << "operator action kind mismatch #{action_id} at event #{completion['sequence']}"
      end
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
      expected_value_event = capsule["deliverable_type"] == "runtime_change" ? "first_executable_delta" : "first_operational_evidence"
      required_event_types.concat(["semantic_ready", "context_snapshot", "worker_handoff_started", "action_guard_passed", expected_value_event, "review_ready", "hrm_closed"])
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
    first_executable = first.call("first_executable_delta")
    first_operational = first.call("first_operational_evidence")
    expected_value = capsule["deliverable_type"] == "runtime_change" ? first_executable : first_operational
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
      expected_value && event["sequence"] < expected_value["sequence"] && event.dig("details", "deliverable_type") != capsule["deliverable_type"]
    end

    correction_rounds = Array(by_type["candidate_frozen"]).group_by do |event|
      event["change_unit_id"] || "unbound"
    end.values.map { |items| [items.length - 1, 0].max }

    context_events = events.select { |event| event["event_type"] == "context_snapshot" }
    peak_active_context_bytes = context_events.map { |event| event.dig("context", "active_context_bytes") }.max || 0
    orchestrator_peak_context_bytes = context_events.select { |event| event["role"] == "orchestrator" }
                                                    .map { |event| event.dig("context", "active_context_bytes") }.max || 0
    artifact_bytes = context_events.sum { |event| event.dig("context", "artifact_bytes") }
    repeated_artifact_bytes = context_events.sum { |event| event.dig("context", "repeated_artifact_bytes") }
    context_redundancy_ratio = artifact_bytes.zero? ? 0.0 : (repeated_artifact_bytes.to_f / artifact_bytes).round(4)
    inline_raw_log_bytes = context_events.sum { |event| event.dig("context", "inline_raw_log_bytes") }
    state_artifact_echo_bytes = context_events.sum { |event| event.dig("context", "state_artifact_echo_bytes") }
    context_compactions_before_executable = compactions_before(events, first_executable && first_executable["sequence"], role: "orchestrator")
    context_compactions_before_operational = compactions_before(events, first_operational && first_operational["sequence"], role: "orchestrator")
    scope_escape_files = context_events.sum { |event| event.dig("context", "files_outside_declared_dependencies") }
    context_budget_violations = context_events.count do |event|
      role = event["role"]
      budget = capsule.dig("budgets", "context_bytes_by_role", role)
      next false unless budget

      context = event["context"]
      context["active_context_bytes"] > budget
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

    final_candidate_sha = terminal_event&.dig("candidate_sha")
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

    decision_requests = Array(by_type["decision_requested"])
    genuine_human_gate_requests = decision_requests.count do |event|
      STANDARD_OPERATOR_GATES.include?(event.dig("details", "decision_kind"))
    end
    operator_action_requests = Array(by_type["operator_action_required"])
    operator_action_completions = Array(by_type["operator_action_completed"])

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
    expected_compactions = capsule["deliverable_type"] == "runtime_change" ? context_compactions_before_executable : context_compactions_before_operational
    if expected_compactions > capsule.dig("budgets", "max_context_compactions_before_expected_value")
      process_reasons << "pre-expected-value context-compaction budget exceeded"
    end
    if inline_raw_log_bytes > capsule.dig("budgets", "max_inline_raw_log_bytes")
      process_reasons << "inline raw-log budget exceeded"
    end
    if state_artifact_echo_bytes > capsule.dig("budgets", "max_state_artifact_echo_bytes")
      process_reasons << "state-artifact echo budget exceeded"
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
      "schema_version" => "agent_playbooks.hrm_run_scorecard.v0.3",
      "run_identity" => {
        "session_id" => capsule["session_id"],
        "hrm_id" => capsule.dig("hrm", "id"),
        "experiment_profile" => capsule["experiment_profile"],
        "execution_mode" => capsule["execution_mode"],
        "playbook_source_sha" => capsule.dig("playbook_pin", "source_sha"),
        "capsule_sequence" => capsule.dig("session_lineage", "capsule_sequence"),
        "continuation_reason" => capsule.dig("session_lineage", "continuation_reason"),
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
        "first_executable_delta_from_semantic_ready_seconds" => duration.call(semantic_ready, first_executable),
        "first_operational_evidence_from_semantic_ready_seconds" => duration.call(semantic_ready, first_operational),
        "review_ready_from_semantic_ready_seconds" => duration.call(semantic_ready, review_ready),
        "total_elapsed_seconds" => duration.call(session_started, terminal_event),
        "maximum_no_progress_seconds" => maximum_no_progress_seconds,
        "nonmatching_units_before_expected_value" => change_units_before_value.length,
        "maximum_correction_rounds" => correction_rounds.max || 0
      },
      "decisions" => {
        "decision_requests" => decision_requests.length,
        "genuine_human_gate_requests" => genuine_human_gate_requests,
        "operator_action_requests" => operator_action_requests.length,
        "operator_action_completions" => operator_action_completions.length,
        "late_s0_s1_findings" => late_s0_s1
      },
      "context" => {
        "peak_active_context_bytes" => peak_active_context_bytes,
        "orchestrator_peak_active_context_bytes" => orchestrator_peak_context_bytes,
        "repeated_artifact_bytes" => repeated_artifact_bytes,
        "context_redundancy_ratio" => context_redundancy_ratio,
        "inline_raw_log_bytes" => inline_raw_log_bytes,
        "state_artifact_echo_bytes" => state_artifact_echo_bytes,
        "orchestrator_context_compactions_before_first_executable_delta" => context_compactions_before_executable,
        "orchestrator_context_compactions_before_first_operational_evidence" => context_compactions_before_operational,
        "context_snapshots" => context_events.length,
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
        ruby scripts/hrm_experiment.rb validate-state STATE.yaml
        ruby scripts/hrm_experiment.rb derive-state CAPSULE.yaml EVENTS.jsonl
        ruby scripts/hrm_experiment.rb validate-grant GRANT.yaml CAPSULE.yaml
        ruby scripts/hrm_experiment.rb evaluate CAPSULE.yaml EVENTS.jsonl

      rc.6 mutations are supervisor-owned. Use scripts/hrm_supervisor.rb append, guard, or supersede.
    TEXT
  end

  def reject_legacy_mutation_cli!(command, capsule = nil)
    kernel_version = capsule&.dig("playbook_pin", "kernel_version")
    return if capsule && kernel_version != SUPERVISOR_OWNED_KERNEL_VERSION

    version = kernel_version || SUPERVISOR_OWNED_KERNEL_VERSION
    supervisor_command = {
      "append-event" => "append",
      "guard-action" => "guard",
      "supersede-with-successor" => "supersede"
    }.fetch(command)
    raise ValidationError,
          "legacy hrm_experiment.rb #{command} is disabled for #{version}; " \
          "use scripts/hrm_supervisor.rb #{supervisor_command} so the ledger and projection advance together"
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
    when "validate-state"
      path = ARGV.shift or raise HrmExperiment::ValidationError, HrmExperiment.usage
      HrmExperiment.validate_session_state!(HrmExperiment.load_yaml(path))
      puts "session state valid: #{path}"
    when "derive-state"
      capsule_path = ARGV.shift or raise HrmExperiment::ValidationError, HrmExperiment.usage
      events_path = ARGV.shift or raise HrmExperiment::ValidationError, HrmExperiment.usage
      state = HrmExperiment.derive_session_state(
        HrmExperiment.load_yaml(capsule_path),
        HrmExperiment.load_events(events_path)
      )
      puts YAML.dump(state)
    when "validate-grant"
      grant_path = ARGV.shift or raise HrmExperiment::ValidationError, HrmExperiment.usage
      capsule_path = ARGV.shift or raise HrmExperiment::ValidationError, HrmExperiment.usage
      HrmExperiment.validate_authority_grant!(
        HrmExperiment.load_yaml(grant_path),
        HrmExperiment.load_yaml(capsule_path)
      )
      puts "authority grant valid: #{grant_path}"
    when "append-event"
      HrmExperiment.reject_legacy_mutation_cli!(command)
    when "guard-action"
      capsule_path = ARGV.shift or raise HrmExperiment::ValidationError, HrmExperiment.usage
      events_path = ARGV.shift or raise HrmExperiment::ValidationError, HrmExperiment.usage
      action = ARGV.shift or raise HrmExperiment::ValidationError, HrmExperiment.usage
      role = ARGV.shift or raise HrmExperiment::ValidationError, HrmExperiment.usage
      now_arg = ARGV.shift
      now = now_arg ? Time.iso8601(now_arg) : Time.now.utc
      capsule = HrmExperiment.load_yaml(capsule_path)
      HrmExperiment.validate_capsule!(capsule)
      HrmExperiment.reject_legacy_mutation_cli!(command, capsule)
      event = HrmExperiment.guard_action(
        capsule,
        HrmExperiment.load_events(events_path),
        action,
        role,
        now
      )
      puts HrmExperiment.append_event!(events_path, event)
      exit 3 if event["event_type"] == "stop_reason"
    when "supersede-with-successor"
      predecessor_path = ARGV.shift or raise HrmExperiment::ValidationError, HrmExperiment.usage
      events_path = ARGV.shift or raise HrmExperiment::ValidationError, HrmExperiment.usage
      successor_path = ARGV.shift or raise HrmExperiment::ValidationError, HrmExperiment.usage
      now_arg = ARGV.shift
      now = now_arg ? Time.iso8601(now_arg) : Time.now.utc
      predecessor = HrmExperiment.load_yaml(predecessor_path)
      HrmExperiment.validate_capsule!(predecessor)
      HrmExperiment.reject_legacy_mutation_cli!(command, predecessor)
      event = HrmExperiment.supersession_event(
        predecessor,
        HrmExperiment.load_events(events_path),
        HrmExperiment.load_yaml(successor_path),
        now
      )
      puts HrmExperiment.append_event!(events_path, event, validated_supersession: true)
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
  rescue HrmExperiment::ValidationError, JSON::ParserError, Errno::ENOENT, ArgumentError => e
    warn e.message
    exit 2
  end
end
