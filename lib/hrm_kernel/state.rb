# frozen_string_literal: true

require "digest"
require "json"
require "pathname"
require_relative "error"

module HrmKernel
  module State
    ROLES = %w[operator orchestrator worker reviewer].freeze
    COMMAND_ROLES = {
      "milestone.create" => "operator",
      "intent.record" => "operator",
      "work_order.create" => "orchestrator",
      "work_order.amend" => "orchestrator",
      "work_order.claim" => "worker",
      "work_order.submit" => "worker",
      "work_order.release" => "orchestrator",
      "work_order.cancel" => "orchestrator",
      "milestone.review_ready" => "orchestrator",
      "milestone.review" => "operator",
      "decision.request" => "orchestrator",
      "decision.withdraw" => "orchestrator",
      "decision.respond" => "operator",
      "decision.reopen" => "operator",
      "decision.revise" => "orchestrator"
    }.freeze
    INTENT_KINDS = %w[presentation_adjustment milestone_change clarification].freeze
    DECISION_KINDS = %w[business_meaning external_effect_authority].freeze
    DISPOSITIONS = %w[accepted rejected deferred].freeze
    SHA256 = /\A[0-9a-f]{64}\z/.freeze
    GLOB_CHARS = /[*?\[\]{}]/.freeze

    module_function

    def initial
      {
        "schema_version" => 1,
        "milestone" => nil,
        "intents" => {},
        "work_orders" => {},
        "reviews" => {},
        "decisions" => {},
        "source_records" => {},
        "ledger" => []
      }
    end

    def apply(state, command)
      next_state = normalize(state.nil? ? initial : state)
      validate_state!(next_state)
      string_keys!(command, "command")
      cmd = normalize(command)
      exact_keys!(cmd, %w[command_id type actor data])
      command_id = identifier!(cmd["command_id"], "command_id")
      type = string!(cmd["type"], "type")
      actor = cmd["actor"]
      exact_keys!(actor, %w[id role])
      actor_id = identifier!(actor["id"], "actor.id")
      role = enum!(actor["role"], ROLES, "actor.role")
      expected_role = COMMAND_ROLES[type]
      error!("invalid_command", "unknown command type #{type.inspect}") unless expected_role
      error!("forbidden", "#{type} requires role #{expected_role}") unless role == expected_role
      error!("conflict", "command_id already applied") if next_state["ledger"].any? { |event| event["command_id"] == command_id }

      data = hash!(cmd["data"], "data")
      dispatch!(next_state, type, actor_id, data)
      next_state["ledger"] << ledger_event(next_state, command_id, type, actor_id, data)
      next_state
    end

    def project(state, role: "orchestrator", actor_id: nil)
      current = normalize(state.nil? ? initial : state)
      validate_state!(current)
      role = enum!(role, ROLES, "role")
      actor_id = identifier!(actor_id, "actor_id") if actor_id

      visible_order_ids = visible_work_order_ids(current, role, actor_id)
      visible_orders = current["work_orders"].select { |id, _order| visible_order_ids.include?(id) }
      related_requirement_ids = visible_orders.values.flat_map { |order| order["requirement_ids"] }.uniq
      related_intent_ids = visible_orders.values.map { |order| order["intent_id"] }.uniq
      if %w[operator orchestrator reviewer].include?(role)
        related_intent_ids.concat(current["intents"].values.select { |intent| intent["status"] == "pending" }.map { |intent| intent["id"] })
      end
      milestone = current["milestone"] && project_milestone(current, role, related_requirement_ids)
      intents = current["intents"].each_with_object({}) do |(id, intent), projected|
        next unless related_intent_ids.include?(id)
        next if intent["status"] == "superseded"
        current_requirement_ids = current_intent_requirement_ids(intent, current["milestone"])
        projected[id] = {
          "id" => id,
          "kind" => intent["kind"],
          "status" => intent["status"],
          "desired_behavior" => intent["text"],
          "requirement_ids" => clone_value(current_requirement_ids),
          "current_requirement_ids" => clone_value(current_requirement_ids),
          "superseded_requirement_ids" => clone_value(intent["superseded_requirement_ids"]),
          "scope_note" => intent["superseded_requirement_ids"].empty? ? nil : "Only current_requirement_ids remain authoritative.",
          "work_order_id" => intent["work_order_id"],
          "milestone_revision" => intent["milestone_revision"],
          "requirement_revisions" => clone_value(intent["requirement_revisions"])
        }.compact
      end

      work_orders = visible_orders.each_with_object({}) do |(id, order), projected|
        projected[id] = project_work_order(order, role, actor_id)
      end

      reviews = current["reviews"].each_with_object({}) do |(id, review), projected|
        next if role == "worker"
        next unless visible_review_id(current) == id
        projected[id] = clone_value(review).tap do |copy|
          copy.delete("source")
          copy["feedback"] = copy.delete("text") if copy.key?("text")
        end
      end

      decisions = current["decisions"].each_with_object({}) do |(id, decision), projected|
        if role == "worker"
          next unless decision_current?(decision, current["milestone"])
          next if (decision["requirement_ids"] & related_requirement_ids).empty?
        elsif !visible_decision_ids(current).include?(id)
          next
        end
        projected[id] = clone_value(decision).tap do |copy|
          copy.delete("history")
          if copy["response"]
            copy["response"].delete("source")
            copy["response"]["answer"] = copy["response"].delete("text")
          end
          copy["authority_gap"].delete("source_ref") if copy["authority_gap"]
          copy["withdrawal"].delete("source_ref") if copy["withdrawal"]
          copy.delete("reopening")
        end
      end

      {
        "schema_version" => current["schema_version"],
        "milestone" => milestone,
        "intents" => intents,
        "work_orders" => work_orders,
        "reviews" => reviews,
        "decisions" => decisions,
        "history_counts" => {
          "intents" => current["intents"].length,
          "work_orders" => current["work_orders"].length,
          "reviews" => current["reviews"].length,
          "decisions" => current["decisions"].length,
          "events" => current["ledger"].length
        }
      }
    end

    def dispatch!(state, type, actor_id, data)
      case type
      when "milestone.create" then milestone_create!(state, data)
      when "intent.record" then intent_record!(state, data)
      when "work_order.create" then work_order_create!(state, data)
      when "work_order.amend" then work_order_amend!(state, data)
      when "work_order.claim" then work_order_claim!(state, actor_id, data)
      when "work_order.submit" then work_order_submit!(state, actor_id, data)
      when "work_order.release" then work_order_release!(state, data)
      when "work_order.cancel" then work_order_cancel!(state, data)
      when "milestone.review_ready" then milestone_review_ready!(state, data)
      when "milestone.review" then milestone_review!(state, data)
      when "decision.request" then decision_request!(state, data)
      when "decision.withdraw" then decision_withdraw!(state, data)
      when "decision.respond" then decision_respond!(state, data)
      when "decision.reopen" then decision_reopen!(state, data)
      when "decision.revise" then decision_revise!(state, data)
      end
    end

    def milestone_create!(state, data)
      exact_keys!(data, %w[milestone_id outcome project_root requirements allowed_paths])
      error!("conflict", "a milestone already exists") if state["milestone"]
      id = identifier!(data["milestone_id"], "milestone_id")
      outcome = nonempty_string!(data["outcome"], "outcome")
      project_root = absolute_path!(data["project_root"], "project_root")
      requirements = requirement_entries!(data["requirements"], allow_empty: false)
      allowed_paths = array!(data["allowed_paths"], "allowed_paths").map { |path| relative_path!(path, "allowed_paths", glob: true) }
      unique!(allowed_paths, "allowed_paths")
      error!("invalid_command", "allowed_paths cannot be empty") if allowed_paths.empty?

      state["milestone"] = {
        "id" => id,
        "outcome" => outcome,
        "project_root" => project_root,
        "requirements" => requirements.each_with_object({}) do |requirement, index|
          index[requirement["id"]] = requirement.merge("revision" => 1, "origin" => "initial")
        end,
        "allowed_paths" => allowed_paths,
        "revision" => 1,
        "phase" => "executing",
        "models" => {
          "orchestrator" => "gpt-6-astra",
          "worker" => "gpt-5.6-sol",
          "reviewer" => "gpt-5.6-sol"
        },
        "effects" => ["local_repository"],
        "current_review_id" => nil,
        "last_changes_requested_digest" => nil
      }
    end

    def intent_record!(state, data)
      exact_keys!(data, %w[intent_id kind text source requirement_ids], %w[work_order_id requirements])
      milestone = mutable_milestone!(state)
      id = identifier!(data["intent_id"], "intent_id")
      error!("conflict", "intent_id already exists") if state["intents"].key?(id)
      kind = enum!(data["kind"], INTENT_KINDS, "kind")
      text = nonempty_string!(data["text"], "text")
      source = source!(data["source"])
      requirement_ids = identifiers!(data["requirement_ids"], "requirement_ids", allow_empty: false)
      work_order_id = data.key?("work_order_id") ? identifier!(data["work_order_id"], "work_order_id") : nil

      if data.key?("requirements")
        error!("invalid_command", "requirements are only valid for milestone_change") unless kind == "milestone_change"
        changes = requirement_entries!(data["requirements"], allow_empty: false)
        changed = false
        changes.each do |entry|
          error!("invalid_command", "changed requirement must appear in requirement_ids") unless requirement_ids.include?(entry["id"])
          current = milestone["requirements"][entry["id"]]
          next if current && current["text"] == entry["text"]
          milestone["requirements"][entry["id"]] = entry.merge(
            "revision" => current ? current["revision"] + 1 : 1,
            "origin" => current ? current["origin"] : id
          )
          changed = true
        end
        if changed
          milestone["revision"] += 1
          invalidate_review!(milestone, remediation: true)
        end
      elsif kind == "milestone_change"
        error!("invalid_command", "milestone_change requires requirements")
      end

      unknown_requirements!(milestone, requirement_ids)
      if work_order_id
        order = fetch!(state["work_orders"], work_order_id, "work order")
        error!("conflict", "intent work_order_id requirements do not match") unless same_set?(order["requirement_ids"], requirement_ids)
      end
      record_source!(state, source, text)
      state["intents"][id] = {
        "id" => id,
        "kind" => kind,
        "status" => "pending",
        "text" => text,
        "source" => source,
        "requirement_ids" => requirement_ids,
        "superseded_requirement_ids" => [],
        "work_order_id" => work_order_id,
        "milestone_revision" => milestone["revision"],
        "requirement_revisions" => requirement_ids.each_with_object({}) do |rid, memo|
          memo[rid] = milestone["requirements"][rid]["revision"]
        end
      }
      refresh_intent_statuses!(state)
      invalidate_review!(milestone, remediation: milestone["last_changes_requested_digest"] != nil)
    end

    def work_order_create!(state, data)
      exact_keys!(data, %w[work_order_id intent_id objective requirement_ids paths check_ids effect_class])
      milestone = mutable_milestone!(state)
      id = identifier!(data["work_order_id"], "work_order_id")
      error!("conflict", "work_order_id already exists") if state["work_orders"].key?(id)
      attrs = work_order_attributes!(state, milestone, id, data)
      state["work_orders"][id] = attrs.merge(
        "id" => id, "revision" => 1, "status" => "queued",
        "owner_id" => nil, "claim_id" => nil, "claim_history" => [],
        "last_owner_id" => nil,
        "artifacts" => [], "checks" => [], "evidence_digest" => nil
      )
      refresh_intent_statuses!(state)
      invalidate_review!(milestone, remediation: milestone["last_changes_requested_digest"] != nil)
    end

    def work_order_amend!(state, data)
      exact_keys!(data, %w[work_order_id intent_id objective requirement_ids paths check_ids expected_revision], %w[effect_class])
      milestone = mutable_milestone!(state)
      id = identifier!(data["work_order_id"], "work_order_id")
      order = fetch!(state["work_orders"], id, "work order")
      revision!(order, data["expected_revision"])
      error!("invalid_transition", "cancelled work order cannot be amended") if order["status"] == "cancelled"
      old_intent_id = order["intent_id"]
      old_requirement_ids = clone_value(order["requirement_ids"])
      if data.key?("effect_class") && data["effect_class"] != "local_repository"
        error!("invalid_command", "work orders are limited to local_repository effects")
      end
      attrs = work_order_attributes!(state, milestone, id, data.merge("effect_class" => "local_repository"))
      old_history = order["claim_history"]
      state["work_orders"][id] = attrs.merge(
        "id" => id, "revision" => order["revision"] + 1, "status" => "queued",
        "owner_id" => nil, "claim_id" => nil, "claim_history" => old_history,
        "last_owner_id" => order["last_owner_id"],
        "artifacts" => [], "checks" => [], "evidence_digest" => nil
      )
      if old_intent_id != attrs["intent_id"] && old_intent_id != "milestone_initial"
        old_intent = state["intents"][old_intent_id]
        displaced = old_requirement_ids & attrs["requirement_ids"]
        old_intent["superseded_requirement_ids"] = (old_intent["superseded_requirement_ids"] + displaced).uniq
      end
      refresh_intent_statuses!(state)
      invalidate_review!(milestone, remediation: milestone["last_changes_requested_digest"] != nil)
    end

    def work_order_attributes!(state, milestone, id, data)
      intent_id = identifier!(data["intent_id"], "intent_id")
      requirement_ids = identifiers!(data["requirement_ids"], "requirement_ids", allow_empty: false)
      unknown_requirements!(milestone, requirement_ids)
      authorize_requirements!(state, milestone, intent_id, id, requirement_ids)
      paths = array!(data["paths"], "paths").map { |path| relative_path!(path, "paths", glob: false) }
      unique!(paths, "paths")
      error!("invalid_command", "paths cannot be empty") if paths.empty?
      paths.each do |path|
        error!("invalid_path", "path #{path.inspect} is outside milestone allowed_paths") unless allowed_path?(path, milestone["allowed_paths"])
      end
      check_ids = identifiers!(data["check_ids"], "check_ids", allow_empty: false)
      effect_class = string!(data["effect_class"], "effect_class")
      error!("invalid_command", "work orders are limited to local_repository effects") unless effect_class == "local_repository"
      {
        "intent_id" => intent_id,
        "objective" => nonempty_string!(data["objective"], "objective"),
        "requirement_ids" => requirement_ids,
        "requirement_revisions" => requirement_ids.each_with_object({}) { |rid, memo| memo[rid] = milestone["requirements"][rid]["revision"] },
        "paths" => paths,
        "check_ids" => check_ids,
        "effect_class" => effect_class
      }
    end

    def work_order_claim!(state, actor_id, data)
      exact_keys!(data, %w[work_order_id revision claim_id])
      mutable_milestone!(state)
      order = fetch_order!(state, data)
      error!("invalid_transition", "work order is not queued") unless order["status"] == "queued"
      current_order_authority!(state, order)
      blocked = blocking_decisions(state, order["requirement_ids"])
      error!("authority_gap", "requirements have unresolved operator decisions", details: { "decision_ids" => blocked.map { |item| item["id"] } }) unless blocked.empty?
      claim_id = identifier!(data["claim_id"], "claim_id")
      if state["work_orders"].values.any? { |candidate| candidate["claim_history"].include?(claim_id) }
        error!("conflict", "claim_id already exists")
      end
      conflicting = state["work_orders"].values.find do |candidate|
        candidate["status"] == "running" && paths_overlap?(order["paths"], candidate["paths"])
      end
      error!("conflict", "paths overlap active work order #{conflicting['id']}") if conflicting
      order["status"] = "running"
      order["owner_id"] = actor_id
      order["last_owner_id"] = actor_id
      order["claim_id"] = claim_id
      order["claim_history"] << claim_id
    end

    def work_order_submit!(state, actor_id, data)
      exact_keys!(data, %w[work_order_id revision claim_id artifacts checks])
      milestone = mutable_milestone!(state)
      order = fetch_order!(state, data)
      claim_matches!(order, actor_id, data["claim_id"])
      current_order_authority!(state, order)
      artifacts = artifact_entries!(data["artifacts"])
      checks = check_entries!(data["checks"])
      error!("invalid_command", "artifacts cannot be empty") if artifacts.empty?
      unique!(artifacts.map { |entry| entry["path"] }, "artifact paths")
      artifacts.each do |artifact|
        error!("invalid_path", "artifact path is not in the work order") unless order["paths"].include?(artifact["path"])
      end
      check_ids = checks.map { |entry| entry["id"] }
      unique!(check_ids, "check ids")
      error!("invalid_command", "checks must exactly match required check_ids") unless same_set?(check_ids, order["check_ids"])
      unique!(checks.map { |entry| entry["artifact_path"] }, "check artifact paths")
      checks.each do |check|
        error!("invalid_command", "all checks must pass") unless check["conclusion"] == "passed"
        if artifacts.any? { |artifact| artifact["path"] == check["artifact_path"] }
          error!("invalid_command", "check report must be separate from submitted artifacts")
        end
      end
      order["artifacts"] = artifacts
      order["checks"] = checks
      order["evidence_digest"] = digest({ "revision" => order["revision"], "artifacts" => artifacts, "checks" => checks })
      order["status"] = "completed"
      order["owner_id"] = nil
      order["claim_id"] = nil
      milestone["phase"] = "remediation" if milestone["last_changes_requested_digest"]
    end

    def work_order_release!(state, data)
      exact_keys!(data, %w[work_order_id revision claim_id reason])
      milestone = mutable_milestone!(state)
      order = fetch_order!(state, data)
      claim_matches!(order, nil, data["claim_id"], owner_required: false)
      nonempty_string!(data["reason"], "reason")
      order["status"] = "queued"
      order["owner_id"] = nil
      order["claim_id"] = nil
      invalidate_review!(milestone, remediation: milestone["last_changes_requested_digest"] != nil)
    end

    def work_order_cancel!(state, data)
      exact_keys!(data, %w[work_order_id revision reason])
      milestone = mutable_milestone!(state)
      order = fetch_order!(state, data)
      nonempty_string!(data["reason"], "reason")
      error!("invalid_transition", "work order already cancelled") if order["status"] == "cancelled"
      order["status"] = "cancelled"
      order["owner_id"] = nil
      order["claim_id"] = nil
      order["artifacts"] = []
      order["checks"] = []
      order["evidence_digest"] = nil
      refresh_intent_statuses!(state)
      invalidate_review!(milestone, remediation: milestone["last_changes_requested_digest"] != nil)
    end

    def milestone_review_ready!(state, data)
      exact_keys!(data, %w[review_id])
      milestone = mutable_milestone!(state)
      review_id = identifier!(data["review_id"], "review_id")
      error!("conflict", "review_id already exists") if state["reviews"].key?(review_id)
      orders = state["work_orders"].values.reject { |order| order["status"] == "cancelled" }
      error!("invalid_transition", "at least one work order is required") if orders.empty?
      error!("invalid_transition", "all current work orders must be completed") unless orders.all? { |order| order["status"] == "completed" }
      stale_orders = orders.reject { |order| order_authority_current?(state, order) }.map { |order| order["id"] }
      error!("stale_revision", "work orders require authority reconciliation", details: { "work_order_ids" => stale_orders }) unless stale_orders.empty?
      uncovered = milestone["requirements"].keys.reject do |requirement_id|
        orders.any? { |order| order_covers?(state, order, milestone, requirement_id) }
      end
      error!("work_remaining", "requirements are not covered", details: { "requirement_ids" => uncovered }) unless uncovered.empty?
      blocked = blocking_decisions(state, milestone["requirements"].keys)
      error!("authority_gap", "operator decisions remain unresolved", details: { "decision_ids" => blocked.map { |item| item["id"] } }) unless blocked.empty?
      pending = pending_intent_ids(state)
      error!("work_remaining", "operator intents remain uncommissioned", details: { "intent_ids" => pending }) unless pending.empty?
      snapshot = candidate_snapshot(milestone, orders)
      if milestone["last_changes_requested_digest"] == snapshot["candidate_digest"]
        error!("invalid_transition", "changes_requested candidate has not changed")
      end
      review = snapshot.merge("id" => review_id, "status" => "pending", "decision" => nil)
      state["reviews"][review_id] = review
      milestone["current_review_id"] = review_id
      milestone["phase"] = "review_ready"
    end

    def milestone_review!(state, data)
      exact_keys!(data, %w[review_id decision text source])
      milestone = mutable_milestone!(state)
      review_id = identifier!(data["review_id"], "review_id")
      review = fetch!(state["reviews"], review_id, "review")
      error!("stale_revision", "review is not the current pending review") unless milestone["current_review_id"] == review_id && review["status"] == "pending"
      decision = enum!(data["decision"], %w[changes_requested accepted deferred], "decision")
      text = nonempty_string!(data["text"], "text")
      source = source!(data["source"])
      orders = state["work_orders"].values.reject { |order| order["status"] == "cancelled" }
      current = candidate_snapshot(milestone, orders)
      error!("stale_revision", "review candidate is stale") unless review["candidate_digest"] == current["candidate_digest"]
      blocked = blocking_decisions(state, milestone["requirements"].keys)
      if decision == "accepted" && !blocked.empty?
        error!("authority_gap", "operator decisions remain unresolved", details: { "decision_ids" => blocked.map { |item| item["id"] } })
      end
      pending = pending_intent_ids(state)
      if decision == "accepted" && !pending.empty?
        error!("work_remaining", "operator intents remain uncommissioned", details: { "intent_ids" => pending })
      end
      record_source!(state, source, text)
      review["status"] = "decided"
      review["decision"] = decision
      review["text"] = text
      review["source"] = source
      milestone["current_review_id"] = nil
      case decision
      when "accepted"
        milestone["phase"] = "closed"
      when "changes_requested"
        milestone["phase"] = "remediation"
        milestone["last_changes_requested_digest"] = review["candidate_digest"]
      when "deferred"
        milestone["phase"] = "deferred"
      end
    end

    def decision_request!(state, data)
      exact_keys!(data, %w[decision_id revision kind exact_effect requirement_ids question authority_gap], %w[intent_id])
      milestone = mutable_milestone!(state)
      id = identifier!(data["decision_id"], "decision_id")
      error!("conflict", "decision_id already exists") if state["decisions"].key?(id)
      revision = positive_integer!(data["revision"], "revision")
      error!("invalid_command", "initial decision revision must be 1") unless revision == 1
      attrs = decision_attributes!(state, milestone, data)
      duplicate = state["decisions"].values.find do |decision|
        decision["status"] != "withdrawn" &&
          decision["kind"] == attrs["kind"] &&
          decision["exact_effect"] == attrs["exact_effect"] &&
          same_set?(decision["requirement_ids"], attrs["requirement_ids"]) &&
          decision["requirement_revisions"] == attrs["requirement_revisions"]
      end
      error!("conflict", "equivalent decision request already exists as #{duplicate['id']}") if duplicate
      state["decisions"][id] = attrs.merge("id" => id, "revision" => 1, "status" => "unresolved", "response" => nil, "history" => [])
      invalidate_review!(milestone, remediation: milestone["last_changes_requested_digest"] != nil) if milestone["current_review_id"]
    end

    def decision_revise!(state, data)
      exact_keys!(data, %w[decision_id expected_revision kind exact_effect requirement_ids question authority_gap], %w[intent_id])
      milestone = mutable_milestone!(state)
      id = identifier!(data["decision_id"], "decision_id")
      decision = fetch!(state["decisions"], id, "decision")
      revision!(decision, data["expected_revision"])
      error!("invalid_transition", "only an unresolved decision request may be revised") unless decision["status"] == "unresolved"
      attrs = decision_attributes!(state, milestone, data)
      duplicate = state["decisions"].values.find do |candidate|
        candidate["id"] != id && candidate["status"] != "withdrawn" &&
          candidate["kind"] == attrs["kind"] &&
          candidate["exact_effect"] == attrs["exact_effect"] &&
          same_set?(candidate["requirement_ids"], attrs["requirement_ids"]) &&
          candidate["requirement_revisions"] == attrs["requirement_revisions"]
      end
      error!("conflict", "equivalent decision request already exists as #{duplicate['id']}") if duplicate
      history = decision["history"] + [clone_value(decision).tap { |entry| entry.delete("history") }]
      state["decisions"][id] = attrs.merge("id" => id, "revision" => decision["revision"] + 1, "status" => "unresolved", "response" => nil, "history" => history)
      invalidate_review!(milestone, remediation: milestone["last_changes_requested_digest"] != nil) if milestone["current_review_id"]
    end

    def decision_withdraw!(state, data)
      exact_keys!(data, %w[decision_id revision reason source_ref])
      milestone = mutable_milestone!(state)
      id = identifier!(data["decision_id"], "decision_id")
      decision = fetch!(state["decisions"], id, "decision")
      revision!(decision, data["revision"])
      error!("invalid_transition", "only an unresolved decision request may be withdrawn") unless decision["status"] == "unresolved"
      reason = nonempty_string!(data["reason"], "reason")
      source_ref = nonempty_string!(data["source_ref"], "source_ref")
      decision["status"] = "withdrawn"
      decision["withdrawal"] = { "reason" => reason, "source_ref" => source_ref }
      invalidate_review!(milestone, remediation: milestone["last_changes_requested_digest"] != nil) if milestone["current_review_id"]
    end

    def decision_attributes!(state, milestone, data)
      kind = enum!(data["kind"], DECISION_KINDS, "kind")
      exact_effect = nonempty_string!(data["exact_effect"], "exact_effect")
      requirement_ids = identifiers!(data["requirement_ids"], "requirement_ids", allow_empty: false)
      unknown_requirements!(milestone, requirement_ids)
      question = nonempty_string!(data["question"], "question")
      gap = hash!(data["authority_gap"], "authority_gap")
      exact_keys!(gap, %w[reason source_ref])
      gap = { "reason" => nonempty_string!(gap["reason"], "authority_gap.reason"), "source_ref" => nonempty_string!(gap["source_ref"], "authority_gap.source_ref") }
      intent_id = data.key?("intent_id") ? identifier!(data["intent_id"], "intent_id") : nil
      fetch!(state["intents"], intent_id, "intent") if intent_id
      supplying_intent = state["intents"].values.find do |intent|
        intent["text"] == exact_effect &&
          (requirement_ids - current_intent_requirement_ids(intent, milestone)).empty?
      end
      error!("redundant_decision", "operator intent #{supplying_intent['id']} already supplies this exact effect") if supplying_intent
      {
        "kind" => kind, "exact_effect" => exact_effect,
        "requirement_ids" => requirement_ids,
        "requirement_revisions" => requirement_ids.each_with_object({}) do |rid, memo|
          memo[rid] = milestone["requirements"][rid]["revision"]
        end,
        "question" => question,
        "authority_gap" => gap, "intent_id" => intent_id
      }.compact
    end

    def decision_respond!(state, data)
      exact_keys!(data, %w[decision_id revision kind exact_effect disposition source text])
      mutable_milestone!(state)
      id = identifier!(data["decision_id"], "decision_id")
      decision = fetch!(state["decisions"], id, "decision")
      revision!(decision, data["revision"])
      error!("stale_revision", "decision references changed requirements") unless decision_current?(decision, state["milestone"])
      error!("invalid_transition", "decision is already resolved") unless decision["status"] == "unresolved"
      kind = enum!(data["kind"], DECISION_KINDS, "kind")
      exact_effect = nonempty_string!(data["exact_effect"], "exact_effect")
      error!("stale_revision", "decision kind or exact_effect does not match") unless kind == decision["kind"] && exact_effect == decision["exact_effect"]
      disposition = enum!(data["disposition"], DISPOSITIONS, "disposition")
      source = source!(data["source"])
      text = nonempty_string!(data["text"], "text")
      record_source!(state, source, text)
      decision["status"] = disposition
      decision["response"] = {
        "revision" => decision["revision"], "kind" => kind,
        "exact_effect" => exact_effect, "disposition" => disposition,
        "text" => text, "source" => source
      }
    end

    def decision_reopen!(state, data)
      exact_keys!(data, %w[decision_id revision text source])
      milestone = mutable_milestone!(state)
      id = identifier!(data["decision_id"], "decision_id")
      decision = fetch!(state["decisions"], id, "decision")
      revision!(decision, data["revision"])
      error!("stale_revision", "decision references changed requirements") unless decision_current?(decision, milestone)
      unless %w[accepted rejected deferred].include?(decision["status"]) && decision["response"]
        error!("invalid_transition", "only an answered decision may be reopened")
      end
      text = nonempty_string!(data["text"], "text")
      source = source!(data["source"])
      record_source!(state, source, text)
      decision["history"] << clone_value(decision).tap { |entry| entry.delete("history") }
      decision["revision"] += 1
      decision["status"] = "unresolved"
      decision["response"] = nil
      decision["reopening"] = { "text" => text, "source" => source }
      invalidate_review!(milestone, remediation: milestone["last_changes_requested_digest"] != nil) if milestone["current_review_id"]
    end

    def project_milestone(state, role, related_requirement_ids)
      milestone = state["milestone"]
      clone_value(milestone).tap do |copy|
        copy["requirements"].each_value { |requirement| requirement.delete("origin") }
        if role == "worker"
          copy["requirements"].select! { |id, _requirement| related_requirement_ids.include?(id) }
          copy.delete("last_changes_requested_digest")
        end
        copy["readiness_blockers"] = readiness_blockers(state) unless role == "worker"
        copy["status"] = copy["phase"]
      end
    end

    def visible_work_order_ids(state, role, actor_id)
      return state["work_orders"].select { |_id, order| order["status"] != "cancelled" }.keys unless role == "worker"
      active = state["work_orders"].values.select { |order| order["status"] == "running" && order["owner_id"] == actor_id }
      return active.map { |order| order["id"] } unless active.empty?
      latest_event = state["ledger"].reverse.find do |event|
        event["type"] == "work_order.claim" && state.dig("work_orders", event["work_order_id"], "last_owner_id") == actor_id
      end
      latest_event ? [latest_event["work_order_id"]] : []
    end

    def visible_review_id(state)
      state.dig("milestone", "current_review_id") || state["reviews"].values.reverse.find { |review| review["status"] == "decided" }&.fetch("id")
    end

    def visible_decision_ids(state)
      milestone = state["milestone"]
      state["decisions"].values.select { |decision| decision_current?(decision, milestone) }.map { |decision| decision["id"] }
    end

    def project_work_order(order, role, actor_id)
      clone_value(order).tap do |copy|
        copy.delete("claim_history")
        copy["claim"] = copy["claim_id"] && { "id" => copy["claim_id"], "worker_id" => copy["owner_id"] }
        if role == "worker" && copy["owner_id"] != actor_id
          copy.delete("artifacts")
          copy.delete("checks")
        end
      end
    end

    def candidate_snapshot(milestone, orders)
      order_snapshot = orders.sort_by { |order| order["id"] }.map do |order|
        { "work_order_id" => order["id"], "revision" => order["revision"], "evidence_digest" => order["evidence_digest"] }
      end
      base = { "milestone_revision" => milestone["revision"], "work_orders" => order_snapshot }
      base.merge("candidate_digest" => digest(base))
    end

    def order_covers?(state, order, milestone, requirement_id)
      order["status"] == "completed" &&
        order_authority_current?(state, order) &&
        order["requirement_ids"].include?(requirement_id) &&
        order["requirement_revisions"][requirement_id] == milestone["requirements"][requirement_id]["revision"]
    end

    def authorize_requirements!(state, milestone, intent_id, work_order_id, requirement_ids)
      if intent_id == "milestone_initial"
        valid = requirement_ids.all? do |id|
          requirement = milestone["requirements"][id]
          requirement["origin"] == "initial" && requirement["revision"] == 1
        end
        error!("authority_gap", "milestone_initial cannot authorize changed requirements") unless valid
        return
      end
      intent = fetch!(state["intents"], intent_id, "intent")
      superseded = requirement_ids & intent["superseded_requirement_ids"]
      error!("stale_revision", "operator intent requirements were superseded", details: { "requirement_ids" => superseded }) unless superseded.empty?
      unless (requirement_ids - intent["requirement_ids"]).empty?
        error!("authority_gap", "work order requirements exceed operator intent")
      end
      stale = (requirement_ids & intent["requirement_ids"]).reject do |id|
        intent["requirement_revisions"][id] == milestone["requirements"][id]["revision"]
      end
      error!("stale_revision", "operator intent references changed requirements", details: { "requirement_ids" => stale }) unless stale.empty?
      if intent["work_order_id"] && intent["work_order_id"] != work_order_id
        error!("authority_gap", "intent is bound to another work order")
      end
    end

    def invalidate_review!(milestone, remediation: false)
      milestone["current_review_id"] = nil
      milestone["phase"] = remediation ? "remediation" : "executing"
    end

    def active_milestone!(state)
      milestone = state["milestone"]
      error!("invalid_state", "milestone has not been created") unless milestone
      milestone
    end

    def mutable_milestone!(state)
      milestone = active_milestone!(state)
      if %w[closed deferred].include?(milestone["phase"])
        error!("invalid_transition", "#{milestone['phase']} milestone is immutable in this pilot")
      end
      milestone
    end

    def current_requirement_revisions!(order, milestone)
      stale = order["requirement_ids"].reject do |id|
        milestone["requirements"].key?(id) && order["requirement_revisions"][id] == milestone["requirements"][id]["revision"]
      end
      error!("stale_revision", "work order references changed requirements", details: { "requirement_ids" => stale }) unless stale.empty?
    end

    def current_order_authority!(state, order)
      current_requirement_revisions!(order, state["milestone"])
      return if order["intent_id"] == "milestone_initial"
      intent = fetch!(state["intents"], order["intent_id"], "intent")
      superseded = order["requirement_ids"] & intent["superseded_requirement_ids"]
      error!("stale_revision", "work order uses superseded intent requirements", details: { "requirement_ids" => superseded }) unless superseded.empty?
    end

    def order_authority_current?(state, order)
      return false unless order["requirement_ids"].all? do |id|
        state.dig("milestone", "requirements", id, "revision") == order["requirement_revisions"][id]
      end
      return true if order["intent_id"] == "milestone_initial"
      intent = state["intents"][order["intent_id"]]
      intent && (order["requirement_ids"] & intent["superseded_requirement_ids"]).empty?
    end

    def blocking_decisions(state, requirement_ids)
      state["decisions"].values.select do |decision|
        decision["kind"] == "business_meaning" &&
          !%w[accepted withdrawn].include?(decision["status"]) &&
          decision_current?(decision, state["milestone"]) &&
          !(decision["requirement_ids"] & requirement_ids).empty?
      end
    end

    def decision_current?(decision, milestone)
      decision["requirement_revisions"] == decision["requirement_ids"].each_with_object({}) do |id, revisions|
        revisions[id] = milestone.dig("requirements", id, "revision")
      end
    end

    def readiness_blockers(state)
      milestone = state["milestone"]
      return [] unless milestone
      orders = state["work_orders"].values.reject { |order| order["status"] == "cancelled" }
      blockers = []
      blockers << { "kind" => "no_work_orders" } if orders.empty?
      incomplete = orders.reject { |order| order["status"] == "completed" }.map { |order| order["id"] }
      blockers << { "kind" => "incomplete_work_orders", "work_order_ids" => incomplete } unless incomplete.empty?
      uncovered = milestone["requirements"].keys.reject { |rid| orders.any? { |order| order_covers?(state, order, milestone, rid) } }
      blockers << { "kind" => "uncovered_requirements", "requirement_ids" => uncovered } unless uncovered.empty?
      stale_orders = orders.reject { |order| order_authority_current?(state, order) }.map { |order| order["id"] }
      blockers << { "kind" => "stale_work_orders", "work_order_ids" => stale_orders } unless stale_orders.empty?
      blocked = blocking_decisions(state, milestone["requirements"].keys).map { |decision| decision["id"] }
      blockers << { "kind" => "operator_decisions", "decision_ids" => blocked } unless blocked.empty?
      pending = pending_intent_ids(state)
      blockers << { "kind" => "pending_intents", "intent_ids" => pending } unless pending.empty?
      blockers
    end

    def refresh_intent_statuses!(state)
      current_orders = state["work_orders"].values.reject { |order| order["status"] == "cancelled" }
      state["intents"].each_value do |intent|
        next if intent["status"] == "superseded"
        current_requirement_ids = current_intent_requirement_ids(intent, state["milestone"])
        if current_requirement_ids.empty?
          intent["status"] = "superseded"
          next
        end
        covered = current_orders.select { |order| order["intent_id"] == intent["id"] }.flat_map do |order|
          order["requirement_ids"].select do |requirement_id|
            order["requirement_revisions"][requirement_id] == intent["requirement_revisions"][requirement_id] &&
              state.dig("milestone", "requirements", requirement_id, "revision") == intent["requirement_revisions"][requirement_id]
          end
        end.uniq
        intent["status"] = (current_requirement_ids - covered).empty? ? "commissioned" : "pending"
      end
    end

    def current_intent_requirement_ids(intent, milestone)
      intent["requirement_ids"].select do |id|
        !intent["superseded_requirement_ids"].include?(id) &&
          intent["requirement_revisions"][id] == milestone.dig("requirements", id, "revision")
      end
    end

    def pending_intent_ids(state)
      state["intents"].values.select { |intent| intent["status"] == "pending" }.map { |intent| intent["id"] }
    end

    def fetch_order!(state, data)
      id = identifier!(data["work_order_id"], "work_order_id")
      order = fetch!(state["work_orders"], id, "work order")
      revision!(order, data["revision"])
      order
    end

    def claim_matches!(order, actor_id, claim_id, owner_required: true)
      error!("invalid_transition", "work order is not running") unless order["status"] == "running"
      claim_id = identifier!(claim_id, "claim_id")
      error!("stale_revision", "claim does not match active work") unless order["claim_id"] == claim_id
      if owner_required && order["owner_id"] != actor_id
        error!("forbidden", "only the owning worker may submit")
      end
    end

    def revision!(record, supplied)
      supplied = positive_integer!(supplied, "revision")
      error!("stale_revision", "expected revision #{record['revision']}, got #{supplied}") unless record["revision"] == supplied
    end

    def requirement_entries!(value, allow_empty:)
      entries = array!(value, "requirements").map do |entry|
        exact_keys!(entry, %w[id text])
        { "id" => identifier!(entry["id"], "requirement.id"), "text" => nonempty_string!(entry["text"], "requirement.text") }
      end
      error!("invalid_command", "requirements cannot be empty") if !allow_empty && entries.empty?
      unique!(entries.map { |entry| entry["id"] }, "requirement ids")
      entries
    end

    def artifact_entries!(value)
      array!(value, "artifacts").map do |entry|
        exact_keys!(entry, %w[path sha256])
        { "path" => relative_path!(entry["path"], "artifact.path", glob: false), "sha256" => sha256!(entry["sha256"], "artifact.sha256") }
      end
    end

    def check_entries!(value)
      array!(value, "checks").map do |entry|
        exact_keys!(entry, %w[id conclusion artifact_path sha256])
        {
          "id" => identifier!(entry["id"], "check.id"),
          "conclusion" => nonempty_string!(entry["conclusion"], "check.conclusion"),
          "artifact_path" => relative_path!(entry["artifact_path"], "check.artifact_path", glob: false),
          "sha256" => sha256!(entry["sha256"], "check.sha256")
        }
      end
    end

    def source!(value)
      source = hash!(value, "source")
      exact_keys!(source, %w[thread_id message_id])
      { "thread_id" => identifier!(source["thread_id"], "source.thread_id"), "message_id" => identifier!(source["message_id"], "source.message_id") }
    end

    def record_source!(state, source, original_text)
      key = source["thread_id"] + "\u0000" + source["message_id"]
      fingerprint = digest({ "original_text" => original_text })
      existing = state["source_records"][key]
      error!("conflict", "source identifier was already used with different contents") if existing && existing != fingerprint
      state["source_records"][key] = fingerprint
    end

    def unknown_requirements!(milestone, ids)
      unknown = ids.reject { |id| milestone["requirements"].key?(id) }
      error!("not_found", "unknown requirements", details: { "requirement_ids" => unknown }) unless unknown.empty?
    end

    def allowed_path?(path, allowed_paths)
      allowed_paths.any? do |pattern|
        recursive_prefix = pattern.end_with?("/**") && path.start_with?(pattern[0...-2])
        pattern == path || recursive_prefix || File.fnmatch?(pattern, path, File::FNM_PATHNAME | File::FNM_EXTGLOB)
      end
    end

    def paths_overlap?(left, right)
      left.any? do |a|
        right.any? { |b| a == b || a.start_with?(b + "/") || b.start_with?(a + "/") }
      end
    end

    def relative_path!(value, field, glob:)
      path = nonempty_string!(value, field)
      invalid = path.start_with?("/") || path.include?("\\") || path.include?("\u0000") || path.include?("//")
      segments = path.split("/", -1)
      invalid ||= segments.any? { |segment| segment.empty? || segment == "." || segment == ".." }
      invalid ||= !glob && path.match?(GLOB_CHARS)
      error!("invalid_path", "#{field} must be a clean relative #{glob ? 'path or glob' : 'path'}") if invalid
      path
    end

    def absolute_path!(value, field)
      path = nonempty_string!(value, field)
      parsed = Pathname.new(path)
      error!("invalid_path", "#{field} must be an absolute clean path") unless parsed.absolute? && parsed.cleanpath.to_s == path && !path.include?("\u0000")
      path
    end

    def validate_state!(state)
      exact_keys!(state, %w[schema_version milestone intents work_orders reviews decisions source_records ledger])
      error!("invalid_state", "unsupported schema version") unless state["schema_version"] == 1
      %w[intents work_orders reviews decisions source_records].each { |key| hash!(state[key], key) }
      array!(state["ledger"], "ledger")
    end

    def string_keys!(value, field)
      case value
      when Hash
        value.each do |key, child|
          error!("invalid_command", "#{field} keys must be strings") unless key.is_a?(String)
          string_keys!(child, "#{field}.#{key}")
        end
      when Array
        value.each { |child| string_keys!(child, field) }
      end
    end

    def ledger_event(state, command_id, type, actor_id, data)
      event = { "command_id" => command_id, "type" => type, "actor_id" => actor_id }
      %w[milestone_id intent_id work_order_id review_id decision_id claim_id].each do |key|
        event[key] = data[key] if data.key?(key)
      end
      event["milestone_revision"] = state["milestone"]["revision"] if state["milestone"]
      event
    end

    def normalize(value)
      clone_value(value, stringify_keys: true)
    end

    def clone_value(value, stringify_keys: false)
      case value
      when Hash
        value.each_with_object({}) do |(key, child), copy|
          normalized_key = stringify_keys ? key.to_s : key
          error!("invalid_command", "duplicate normalized key #{normalized_key.inspect}") if copy.key?(normalized_key)
          copy[normalized_key] = clone_value(child, stringify_keys: stringify_keys)
        end
      when Array
        value.map { |child| clone_value(child, stringify_keys: stringify_keys) }
      when String
        value.dup
      when Integer, Float, TrueClass, FalseClass, NilClass
        value
      else
        error!("invalid_command", "value #{value.class} is not serializable")
      end
    end

    def exact_keys!(value, required, optional = [])
      object = hash!(value, "object")
      missing = required - object.keys
      extra = object.keys - required - optional
      error!("invalid_command", "missing keys: #{missing.join(', ')}") unless missing.empty?
      error!("invalid_command", "unknown keys: #{extra.join(', ')}") unless extra.empty?
      object
    end

    def hash!(value, field)
      error!("invalid_command", "#{field} must be an object") unless value.is_a?(Hash)
      value
    end

    def array!(value, field)
      error!("invalid_command", "#{field} must be an array") unless value.is_a?(Array)
      value
    end

    def string!(value, field)
      error!("invalid_command", "#{field} must be a string") unless value.is_a?(String)
      value
    end

    def nonempty_string!(value, field)
      string = string!(value, field)
      error!("invalid_command", "#{field} cannot be empty") if string.strip.empty?
      string
    end

    def identifier!(value, field)
      id = nonempty_string!(value, field)
      error!("invalid_command", "#{field} contains a control character") if id.match?(/[[:cntrl:]]/)
      id
    end

    def identifiers!(value, field, allow_empty:)
      ids = array!(value, field).map { |item| identifier!(item, field) }
      error!("invalid_command", "#{field} cannot be empty") if !allow_empty && ids.empty?
      unique!(ids, field)
      ids
    end

    def positive_integer!(value, field)
      error!("invalid_command", "#{field} must be a positive integer") unless value.is_a?(Integer) && value.positive?
      value
    end

    def enum!(value, allowed, field)
      string = string!(value, field)
      error!("invalid_command", "#{field} must be one of #{allowed.join(', ')}") unless allowed.include?(string)
      string
    end

    def sha256!(value, field)
      string = string!(value, field)
      error!("invalid_command", "#{field} must be a lowercase SHA-256") unless string.match?(SHA256)
      string
    end

    def unique!(values, field)
      error!("invalid_command", "#{field} contains duplicates") unless values.uniq.length == values.length
    end

    def same_set?(left, right)
      left.sort == right.sort
    end

    def fetch!(collection, id, label)
      collection[id] || error!("not_found", "#{label} #{id.inspect} was not found")
    end

    def digest(value)
      Digest::SHA256.hexdigest(JSON.generate(canonical(value)))
    end

    def canonical(value)
      case value
      when Hash
        value.keys.sort.each_with_object({}) { |key, result| result[key] = canonical(value[key]) }
      when Array
        value.map { |entry| canonical(entry) }
      else
        value
      end
    end

    def error!(code, message, details: nil)
      raise Error.new(code, message, details: details)
    end
  end
end
