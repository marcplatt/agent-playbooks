---
playbook_id: AP-SYSBUILD-001
title: System Build and Human Review Milestone Standard
version: "1.2"
status: active
owner: Alpine Structures
mode: hrm-directed-system-build
human_readable: true
machine_readable: true
required_inputs: [system_reference, target_hrm, milestone_outcome]
optional_inputs:
  - project_hrm_map
  - implementation_manifest
  - brownfield_capability_inventory
  - system_node_registry
  - project_root
  - current_hrm
  - review_questions
  - constraints
  - target_time_or_priority
  - authority_envelope
  - activation_posture
  - primary_checkout
  - completion_mode
  - operating_profile
  - manual_lane_constraint
controls:
  - project-rules-first
  - complete-hrm-map-published-at-inception
  - evidence-before-lanes
  - target-hrm-first
  - project-defined-milestones
  - milestone-contract-before-implementation
  - independently-closable-hrm
  - brownfield-capability-parity
  - first-class-standalone-system-nodes
  - explicit-input-boundary-disposition
  - manual-lane-constraint-cannot-suppress-planning
  - authority-and-provenance
  - scenario-and-test-matrix-before-decomposition
  - derived-lane-bundle
  - autonomous-contract-update-request
  - approval-before-material-hrm-or-contract-meaning-change
  - canonical-lane-publication
  - hotl-preview-not-milestone
  - append-only-findings
  - bounded-remediation
  - explicit-human-closure
  - operator-function-acceptance
  - quiet-execution-noisy-hrm-stop
  - activation-separation
  - project-scoped-cleanup
---

# System Build and Human Review Milestone Standard

Use this playbook when the operator wants to advance a system to a Human Review
Milestone (HRM). The operator names the system and target milestone from the complete
project HRM map, plus the outcome they need to review. The playbook resolves current
evidence, verifies the milestone contract, opens contract-update requests for missing
cross-system promises, derives the smallest lane bundle, delegates execution to the HRM
Bundle Coordination Standard, and keeps the same work session open through prepared
operator function review, findings, remediation, and explicit closure or deferral.

The target of the work session is the HRM, not a lane list. Lanes remain necessary as
bounded implementation, review, merge, and audit units, but they are execution detail
derived from the system plan, project-wide HRM map, and milestone gap analysis. Every
new project publishes all intended HRMs before implementation. Unknown milestone facts
remain explicit blockers or requests; they are never filled by inference.

## Operator model

The operator should normally need to know only:

- which system is changing;
- the complete project HRM journey and its current version;
- which HRM the session is targeting;
- what outcome or questions the milestone must make reviewable;
- the current authority and activation envelope; and
- any scope, time, or priority constraint.

Do not make the operator reconstruct dependencies or enumerate lanes. Keep routine lane
execution quiet and report progress through the HRM banner. A manual lane
list may constrain a legacy or recovery session, but it cannot replace the canonical
system plan, project HRM map, milestone contract, or gap analysis, and it cannot suppress
an input record, contract request, discovery, planning amendment, deferral, or blocker.

## Inputs

- **System or project:** `{{system_reference}}`
- **Project root:** `{{project_root_or_discover}}`
- **Project HRM map:** `{{project_hrm_map_or_discover}}`
- **Implementation manifest:** `{{implementation_manifest_or_discover}}`
- **Brownfield capability inventory:** `{{brownfield_capability_inventory_or_discover}}`
- **System-node registry:** `{{system_node_registry_or_discover}}`
- **Current HRM:** `{{current_hrm_or_discover}}`
- **Target HRM:** `{{target_hrm}}`
- **Milestone outcome:** `{{milestone_outcome}}`
- **Review questions:** `{{review_questions_or_derive}}`
- **Constraints:** `{{constraints_or_none}}`
- **Target time or priority:** `{{target_time_or_priority_or_none}}`
- **Authority envelope:** `{{authority_envelope_or_project_policy}}`
- **Activation posture:** `{{activation_posture_or_safe_current_state}}`
- **Primary checkout:** `{{primary_checkout_or_discover}}`
- **Completion mode:** `{{completion_mode_or_false}}`
- **Operating profile:** `{{operating_profile_or_one-human}}`
- **Manual lane constraint:** `{{manual_lane_constraint_or_none}}`

## Quick-start example

```text
Use the System Build and Human Review Milestone Standard.
System: SYS-EXAMPLE-001 in the current project.
Project HRM map: milestones/index.yaml.
Target HRM: HRM-2.
Milestone outcome: the operator can complete the full local workflow, correct inputs,
understand failures, and inspect provenance without provider or production writes.
Activation posture: read-only.
```

## HRM identifiers and archetypes

Milestone identifiers are project-defined stable IDs. `HRM-0` through `HRM-4` are useful
archetypes, not a mandatory universal sequence. A project may define `HRM-O`, repeat a
workflow milestone, or use a qualified ID when its system plan records the outcome,
activation posture, closure authority, prerequisites, closure effect, and downstream
release effect unambiguously.

All intended project HRMs must appear in one versioned map at inception, before
implementation lanes begin. Publication means the control structure is complete; it
does not mean every prerequisite is known or implemented. Record incomplete evidence as
`unknown-blocked` with an owner, safe posture, and resolution path. A later map change is
a versioned rebaseline with supersession and downstream impact, not a rewritten history.

| Archetype | Typical review outcome |
|---|---|
| Plan and contract | Outcome, authority, lifecycle, boundaries, contracts, requirements, test architecture, lane map, and milestone schedule are approved. |
| Read-only vertical slice | Real inputs, interpretation, provenance, safe failure, and missing functions are reviewable without external writes. |
| Operator workflow | A human can perform realistic work, correct it, and understand controls, states, explanations, and failures. |
| Activation readiness | Permissions, monitoring, privacy, recovery, runbook, support ownership, residual risk, and the separate activation decision are reviewable. |
| Controlled canary | One explicitly authorized effect reaches the exact destination and has read-back, reconciliation, receipt, retry, and rollback evidence. |
| Production observation | A separately activated, bounded production window has current health, reconciliation, operator-impact, and rollback evidence. |
| Autonomy readiness | Lifecycle policy, eligibility, confidence, escalation, monitoring, audit, disablement, and human override are reviewable after sufficient production evidence exists. |

## Prompt

```text
Advance this system to one Human Review Milestone.

System: {{system_reference}}.
Project root: {{project_root_or_discover}}.
Project HRM map: {{project_hrm_map_or_discover}}.
Implementation manifest: {{implementation_manifest_or_discover}}.
Brownfield capability inventory: {{brownfield_capability_inventory_or_discover}}.
System-node registry: {{system_node_registry_or_discover}}.
Current HRM: {{current_hrm_or_discover}}.
Target HRM: {{target_hrm}}.
Milestone outcome: {{milestone_outcome}}.
Review questions: {{review_questions_or_derive}}.
Constraints: {{constraints_or_none}}.
Target time or priority: {{target_time_or_priority_or_none}}.
Authority envelope: {{authority_envelope_or_project_policy}}.
Activation posture: {{activation_posture_or_safe_current_state}}.
Primary checkout: {{primary_checkout_or_discover}}.
Completion mode: {{completion_mode_or_false}}.
Operating profile: {{operating_profile_or_one-human}}.
Manual lane constraint: {{manual_lane_constraint_or_none}}.

The target HRM is the work session's controlling objective and must resolve from the
published complete project HRM map. Do not ask the operator for a lane list. Derive the
execution bundle only after resolving the milestone contract,
current evidence, required capabilities, acceptance scenarios, dependency reach, and
test architecture. Keep lanes visible as auditable implementation units, but keep
routine execution quiet and report progress primarily as milestone readiness, contract
requests, decisions, findings, function acceptance, and closure.

AUTHORITY AND ROLES

1. Obey every applicable AGENTS.md and approved system, requirement, contract, decision,
   milestone, and activation record. Repository policy at current main is the durable
   automation authority. Record contradictions; do not silently choose among them.
2. The system-build coordinator owns target-HRM resolution, evidence and gap analysis,
   project-HRM-map verification, milestone contract, contract-update request creation,
   lane derivation/rebaselining, findings classification, remediation scope, downstream
   HRM rebaseline, review package, and closure record.
3. The lane coordinator owns execution of the published bundle: lane readiness, exact
   tests, worktrees, assignments, reviews, deterministic integration, exact-head evidence,
   and cleanup. Lane workers cannot redefine the HRM or enlarge their lanes.
4. The human operator owns unresolved product or authority decisions, prepared milestone
   function/UI/UX review and acceptance, closure or deferral, and action-time authority for provider/customer/money,
   canary, deployment, credentials, irreversible migration, or production effects.
   Agents never count as human approvers.

RESOLVE THE TARGET HRM

5. Fetch and reconcile current main and inspect project rules, worktrees, branches, PRs,
   CI, running revisions, system plan, requirements, invariants, policies, contracts,
   decisions, scenarios, tests, the project-wide HRM map, milestone records, implementation
   manifest, brownfield capability/parity inventory, system-node registry, contract-update
   requests, input records, findings, lanes, and handoffs. Classify
   material claims as verified-current, historical-needs-revalidation, proposed, or
   unknown-blocked.
6. Treat milestone IDs as project-defined opaque identifiers. Verify that one canonical,
   versioned map publishes all intended HRMs from planning through activation, with each
   milestone's outcome, prerequisites, review questions/scenarios, evidence freshness,
   in-scope requirements/contracts, activation posture, closure criteria and authority,
   closure effect, downstream release effect, and finding/rebaseline policy. Resolve the
   exact target from that map; do not infer a universal numbered sequence. Reject or split
   an umbrella objective such as `production ready`, `complete`, or `fully autonomous`
   when it combines operator workflow, activation readiness, canary, production
   observation, or later autonomy. One operator decision must be able to close the HRM.
7. If the complete map is absent, the target is missing/inadequate, or a future HRM is
   only an informal lane label, stop implementation. The same stop applies when the
   system plan, target milestone contract, requirements ledger, implementation manifest,
   `CTRQ` surface, affected brownfield capability inventory, or system-node registry is
   absent. Propose one consolidated planning amendment that publishes or repairs the
   canonical package and full HRM journey. Preserve unknowns as `unknown-blocked`. Obtain
   required operator approval and publish the package before deriving implementation
   lanes. For an existing project, apply this prospectively and do not manufacture
   historical HRM evidence.
8. Determine the last explicitly closed or deferred milestone from durable records. A
   review meeting, merged lane, local preview, green suite, or completed implementation
   is not evidence that an HRM closed.

CREATE THE MILESTONE SESSION CONTRACT

9. Create one stable milestone-session ID and contract containing:

   - system and repository references;
   - project HRM map path, version, and target entry;
   - current and target HRM;
   - operator-visible outcome and review questions;
   - independently closable decision, prerequisites, closure criteria, closure effect,
     and downstream release effect;
   - requirements, invariants, policies, contracts, and acceptance scenarios in scope;
   - authority envelope and exact activation posture;
   - evidence freshness requirements and authoritative sources;
   - expected review artifact and configuration;
   - finding classifications and remediation rules;
   - open, resolved, and blocking contract-update requests;
   - open input requirements and primary dispositions;
   - brownfield parity obligations and affected system nodes;
   - provisional downstream effects; and
   - primary checkout and cleanup policy.

10. Maintain an operator-facing session banner: current HRM, target HRM, why it matters,
    capabilities complete, capabilities remaining, blockers, decisions requested,
    contract requests, function/UI/UX review state, activation posture, integrated
    revision, and next action. Lane counts and IDs are secondary execution details.
11. Use the lifecycle `resolving -> defining -> bundle_derivation -> executing ->
    review_ready -> in_review -> remediation -> awaiting_closure -> closed|deferred|
    blocked`. `review_ready` is a hard human stop: no autonomous remediation or attempt
    to reinterpret the outcome begins until the operator reviews the prepared function.
    Keep the same session and target through remediation. Do not automatically begin the
    next HRM when this one closes.
12. For an existing project adopting this standard, use completion mode prospectively.
    Record one adoption SHA, preserve established IDs and history, build a contradiction
    register, and map every named lane or change unit to complete, deferred, cancelled,
    blocked_external, or active. Apply the new session contract to open and future work.
    Do not rewrite historical merges or manufacture missing evidence. Before changing an
    established operator surface, inventory every current control, journey, disclosure,
    correction/recovery path, and audit surface as required operator workflow, advanced
    operator capability, developer/audit capability, intentionally superseded, or unknown.
    Bind the target HRM to a required parity set and approved removals/relocations.

ANALYZE THE SYSTEM BEFORE LANES

13. Trace the outcome end to end through actors, authority, provenance, states, storage,
    APIs/providers, failure/retry/recovery, privacy, observability, and activation. Map
    every relevant requirement and invariant to a human-readable positive, negative,
    and boundary scenario where applicable. Register every executable component as a
    first-class system node even when it is local, standalone, manually installed,
    outside Git, or governed by a non-PR workflow. Record contract and deployment owners,
    canonical location/workflow, versioned interfaces, readiness/compatibility evidence,
    topology, configuration, start/restart, health, monitoring, recovery, rollback, and
    read-back/reconciliation. Never model a standalone bridge as a consumer worktree.
14. Compare the target contract with verified current behavior and evidence. Record each
    gap as already satisfied, implementation needed, discovery needed, human decision
    needed, contract update needed, blocked external, or accepted limitation. Resolve
    unknown provider facts in read-only discovery while writes remain structurally
    disabled. For a missing or inadequate inter-system promise, create a stable `CTRQ`
    contract-update request addressed to the owning system. The request may state the
    observed gap, affected HRMs, required decision, safe default, and evidence needed; it
    must not invent or adopt the missing answer. For every input requirement, freeze the
    smallest boundary and record a stable input ID, exact observation, affected HRM and
    requirement/scenario, safe posture, evidence, owner, consequence, and proven-
    independent permitted work. Assign one primary disposition: human decision, `CTRQ`,
    read-only discovery, planning amendment/rebaseline, accepted limitation, named-HRM
    deferral, or `blocked_external`.
15. Freeze only affected boundaries when evidence changes. A new product outcome, policy,
    schema meaning, persistence model, provider mutation, public contract, or activation
    step requires a planning amendment; it is not an implementation inference. The
    coordinator may publish a documentation-only `CTRQ` under standing repository rules,
    but adoption of new business meaning, authority, compatibility, or external effects
    remains an operator decision. A manual or legacy lane constraint cannot suppress any
    required input record or disposition and cannot force a later observation/autonomy
    lane to remain active before its prerequisites exist. An exact-head review that
    reproduces a real defect and fails closed is healthy implementation review; preserve
    that stop while separately assessing any contributing planning or decomposition gap.

DESIGN TEST COVERAGE BEFORE DECOMPOSITION

16. Build the scenario-and-test matrix before creating lanes. For each changed behavior,
    record affected consumers, invariants, risk modifiers, exact repository-native command
    or deterministic scenario, phase, expected signal, fixture/environment, artifact,
    timeout, and mutation safety. Map every acceptance criterion to positive, negative,
    boundary, recovery, and accessibility/security coverage where applicable.
17. Use behavior and dependency reach, not filenames alone:

    - UI presentation: build/lint, responsive visual smoke, overflow/wrapping/visibility,
      keyboard order/focus, and automated accessibility; add contrast, motion, zoom,
      print, theme, or supported-browser checks only when affected.
    - UI interaction and local JavaScript: pointer and keyboard scenarios, intended
      action invocation, removed-control reachability, state/disclosure behavior,
      duplicate handlers/submissions, clean console/network, and normal/empty/invalid/
      boundary unit coverage for pure logic.
    - Async JavaScript, forms, routes, or stores: success, validation failure, server or
      network failure, timeout/cancel, retry, stale response, serialization, navigation,
      and double-submit behavior where those states exist.
    - Backend/domain logic: changed branches and invariants, representative/boundary/
      invalid/denied inputs, state transitions, error mapping, repository/gateway
      integration, affected package suite, and direct-consumer smoke.
    - Data manipulation: schema; representative, empty/null, malformed, duplicate,
      boundary, and realistic-volume inputs; domain invariants; deterministic order;
      deduplication; precision/rounding/locale/time-zone behavior; reversible round-trip;
      and property tests for combinatorial spaces.
    - Reference/generated/bulk data: provenance, uniqueness/referential integrity,
      expected count/range, stable digest/diff, generator reproducibility, and at least
      one real consumer smoke in addition to applicable data-manipulation checks.
    - Persistence/schema/migration: disposable-store integration, atomicity, idempotent
      replay, duplicates, concurrency, partial failure, restart/recovery, exact read-back,
      forward compatibility, and rollback or approved recovery with before/after evidence.
    - Shared core, public API, state-machine structure, authentication, dependency,
      lockfile, build configuration, or routing: public compatibility contracts, core
      invariants, all direct consumers, clean startup/build/install, and full suite.
    - Provider or external-write paths: success and applicable invalid/auth/conflict/
      timeout/rate-limit/replay/partial-failure paths using fakes or mutation-disabled dry
      runs, followed by idempotency, reconcile-before-retry, exact read-back, full suite,
      and separately authorized canary/rollback gates before live effects.
    - Documentation/configuration/contracts: parse/schema, links or configured lint,
      executable examples, canonical/mirror search, defaults, missing/malformed/conflicting
      values, safe-off behavior, secret/PII non-disclosure, and affected-mode startup.

18. Apply the union of all applicable checks and use the highest-risk changed surface as
    the provisional validation class. Required check categories may be marked not
    applicable only with a bounded reason. A mandatory checker remains binding unless an
    explicit approved lane-doc amendment changes it.
19. A repository-wide suite is required when shared domain, contract, persistence,
    authentication, provider, public API, schema, state transition, dependency, or core
    structure changes; the affected surface cannot be bounded; targeted checks expose
    unexpected coupling; a mandatory checker requires it; or the exact head is prepared
    for canary, deployment, or release. A multi-lane lighter-weight bundle receives one
    combined regression run at the integrated milestone head. Run the full suite again
    before production canary or release. Isolated CSS, wording, spacing, layout, and
    bounded control simplification do not independently trigger a full suite.

DERIVE AND PUBLISH THE LANE BUNDLE

20. Derive the smallest coherent bundle that can satisfy the target HRM. Each lane must
    declare requirement and scenario coverage, milestone contribution, in/out of scope,
    authority and activation posture, dependencies and exact base, owned files, state or
    data changes, migration/recovery posture, exact checker/test plan, human-readable
    acceptance, hard stops, handoff, and assigned target HRM.
21. Use dependency and file-ownership evidence to mark lanes serial or safely parallel.
    A manual lane constraint may narrow the proposal, but if it leaves the HRM outcome
    unsatisfied, report the gap rather than pretending the milestone is reachable. Do not
    stuff missing planning, contract, bridge readiness, or later-HRM work into a catch-all
    lane merely to preserve the supplied queue. Reclassify, defer, block, or add bounded
    lanes and records through the system-build contract as required.
22. When the bundle preserves the published HRM outcome, contract meaning, authority,
    activation posture, and review surface, derive and publish its canonical lane records
    through the repository-approved integration path under standing planning authority;
    do not interrupt the operator for lane enumeration or routine decomposition. If the
    bundle would materially change any of those HRM-level facts, present one consolidated
    approval packet and stop. Record current evidence, the target-HRM gap, proposed change,
    affected contracts/tests/downstream HRMs, alternatives, safe default, and exact
    operator decision requested.
23. Pass the published milestone-session contract and derived bundle to the HRM Bundle
    Coordination Standard. Do not translate the session back into an operator-maintained
    lane queue.

RUN PREVIEWS AND THE FORMAL REVIEW

24. During active HOTL UI/UX design, keep one preview live and batch operator feedback.
    These are informal checkpoints. Do not freeze, spawn independent reviewers, push a
    candidate, or rerun a repository-wide suite after each presentational adjustment.
    Freeze only when the operator declares the design batch ready. Informal feedback does
    not replace the formal HRM function/UI/UX acceptance.
25. When all published bundle lanes are integrated and applicable integrated-head checks
    pass, publish the HRM review package and move to REVIEW READY. The package contains:

    - project HRM map version, current and target HRM, outcome, and decisions requested;
    - capabilities completed in operator language, mapped to requirements and lanes;
    - exact integrated revision, configuration, data window, and activation posture;
    - live preview or deterministic review scenarios and expected outcomes;
    - test evidence aggregated by change and risk class;
    - brownfield capability/parity evidence and approved exceptions;
    - affected standalone/local system-node readiness and deployment boundaries;
    - known limitations, blockers, and unresolved questions;
    - open input requirements and their primary dispositions;
    - open, resolved, and blocking contract-update requests;
    - external-mutation count and boundary/read-back evidence;
    - cleanup and integration receipt;
    - provisional downstream impact and rebaseline state;
    - explicit operator function/UI/UX acceptance fields; and
    - the exact authority or bundle released by closure.

26. Pause for operator review and make the stop conspicuous. A review package, visible
    feature, green test, merged bundle, or ended meeting is not function acceptance or
    milestone closure. Do not silently diagnose around a failed operator journey, change
    requirements, or begin remediation before the finding is recorded and the operator
    has reviewed or dispositioned it.

CLASSIFY FINDINGS AND REMEDIATE

27. Record findings append-only with stable FND IDs, time, evidence, classification,
    affected requirements/contracts/scenarios, blocking status, owner, disposition,
    remediation lane, and status.
28. After operator review or explicit finding disposition, a verified defect against an
    already-approved requirement may be converted into a bounded remediation lane,
    published to main, and executed in the same milestone session without another scope
    decision. Do not silently enlarge the original lane or preempt the review stop.
29. A missing function, changed outcome, policy or authority decision, new persistence
    or provider effect, changed test oracle/contract, or downstream rebaseline requiring
    product judgment receives one batched approval before remediation. Unknown provider
    facts become read-only discovery work and, when a cross-system promise is missing,
    a `CTRQ`; neither supplies the answer. Future enhancements do not block closure unless
    the operator explicitly promotes them.
30. Pause downstream milestones, update requirements/contracts/scenarios/tests, publish
    approved remediation lanes, execute them through the lane coordinator, revalidate
    affected and integrated evidence, rebaseline downstream specs, and republish the HRM
    package. Keep the original session ID and target HRM.

CLOSE WITHOUT ACTIVATING

31. Ask for one explicit operator decision to close or defer the HRM only when every
    finding has classification, owner, blocking status, disposition, and evidence; every
    must-fix item is verified or explicitly deferred with rationale; canonical planning
    records represent what was learned; downstream specs are rebaselined; and the
    operator's function/UI/UX acceptance is recorded as accepted, accepted with findings,
    or rejected.
32. Record who decided, when, rationale, exact review head, residual risks, deferred
    findings, and the next bundle made eligible. Closure releases eligibility only; it
    does not automatically begin another milestone session.
33. Keep implementation completion, HRM readiness, HRM closure, canary authority,
    deployment, provider/customer/money effects, irreversible migration, and production
    activation as distinct states. Require explicit action-time authority and exact
    read-back/reconciliation for every external effect.
34. Delegate project-scoped worktree cleanup to the lane coordinator. Remove safely
    merged lane worktrees as they become eligible, retain any active milestone preview
    until its evidence is durable and review is complete, preserve every dirty/ambiguous
    worktree, and return the designated primary checkout to clean current main at closure
    or deferral. Report the target HRM first and lane/cleanup detail second.
```

## Machine-readable session contract

```yaml
system_build_session:
  id: "{{stable_session_id}}"
  system_reference: "{{system_reference}}"
  project_root: "{{absolute_path}}"
  source_documents:
    system_plan: null
    implementation_manifest: null
    brownfield_capability_inventory: null
    system_node_registry: null
    requirements: []
    contracts: []
    decisions: []
    milestones: []
    findings: []
    input_records: []
  hrm_map:
    path: "{{path}}"
    version: "{{version}}"
    complete_at_inception: true
    target_entry_verified: false
  current_hrm:
    id: null
    status: "unknown|open|closed|deferred"
    evidence: []
  target_hrm:
    id: "{{target_hrm}}"
    title: "{{title}}"
    milestone_contract: "{{path}}"
    outcome: "{{milestone_outcome}}"
    closability:
      independently_closable: false
      composite_states: []
    review_questions: []
    prerequisites: []
    closure_criteria: []
    closure_authority: human_operator
    closure_effect: null
    release_effect: null
  status: "resolving|defining|bundle_derivation|executing|review_ready|in_review|remediation|awaiting_closure|closed|deferred|blocked"
  authority_envelope:
    planning_changes: false
    routine_code_integration: false
    provider_writes: false
    canary: false
    deployment: false
    production_activation: false
    destructive_migration: false
    credential_or_permission_change: false
  activation_posture: "local|read_only|shadow|canary|enabled"
  completion_mode:
    enabled: false
    adoption_sha: null
    legacy_baseline_sha: null
    contradictions: []
    completion_manifest:
      complete: []
      deferred: []
      cancelled: []
      blocked_external: []
      active: []
  brownfield_parity:
    required_operator_capabilities: []
    advanced_operator_capabilities: []
    developer_or_audit_capabilities: []
    intentionally_superseded: []
    unknown: []
    approved_removals_or_relocations: []
  system_nodes:
    - id: "{{system_node_id}}"
      kind: "repository|local_bridge|daemon|desktop_process|provider|manual_service|other"
      contract_owner: null
      deployment_owner: null
      canonical_location: null
      workflow: "git|non_git|provider_managed|manual|unknown"
      provided_interfaces: []
      consumed_interfaces: []
      readiness_evidence: []
      topology: null
      restart_health_recovery_rollback: []
  evidence_gap_analysis:
    verified_satisfied: []
    implementation_needed: []
    discovery_needed: []
    human_decision_needed: []
    contract_update_needed: []
    blocked_external: []
    accepted_limitations: []
  acceptance_matrix:
    - acceptance_id: "ACC-###"
      requirement_ids: []
      positive_scenarios: []
      negative_scenarios: []
      boundary_scenarios: []
      recovery_scenarios: []
      validation_class: "ui_presentation|ui_interaction|application_behavior|critical_integration|release_bundle"
      exact_checks: []
      full_suite_triggers: []
  lane_bundle:
    source: "derived|approved_existing|manual_constraint"
    planning_authority: "standing_hrm_contract|operator_approved_change|blocked"
    approval_evidence: null
    lanes:
      - id: "{{lane_id}}"
        milestone_contribution: []
        requirement_ids: []
        dependencies: []
        classification: "quick|serial|parallel|critical"
        validation_class: "ui_presentation|ui_interaction|application_behavior|critical_integration|release_bundle"
        contract: "{{path}}"
        publication_sha: null
        state: "proposed|approved|executing|integrated|blocked|complete"
  operator_banner:
    capabilities_complete: []
    capabilities_remaining: []
    blockers: []
    decisions_requested: []
    contract_requests: []
    input_requirements: []
    function_review_state: "not_ready|review_ready|in_review|accepted|accepted_with_findings|rejected"
    integrated_head_sha: null
    next_action: null
  review_package:
    status: "not_started|draft|published|superseded|accepted|deferred"
    path_or_url: null
    review_head_sha: null
    configuration_profile: null
    scenarios: []
    test_evidence: []
    brownfield_parity_evidence: []
    system_node_readiness: []
    input_requirements: []
    known_limitations: []
    external_mutations: 0
    cleanup_receipt: null
    closure_effect: null
  findings:
    ledger: null
    open: []
    blocking: []
    remediation_bundle: []
  contract_update_requests:
    open: []
    resolved: []
    blocking: []
  input_requirements:
    - id: "INP-###"
      observation: null
      affected_hrm: "{{target_hrm}}"
      affected_requirement_or_scenario: []
      frozen_boundary: null
      safe_posture: null
      owner: null
      consequence_if_unresolved: null
      permitted_continuation: []
      disposition: "human_decision|ctrq|read_only_discovery|planning_amendment|accepted_limitation|deferred_to_hrm|blocked_external"
      disposition_reference: null
  noise_posture:
    routine_lane_updates: quiet
    hrm_stop: noisy
    last_operator_interrupt_reason: null
  closure:
    decision: "pending|closed|deferred"
    decided_by: null
    decided_at: null
    rationale: null
    exact_review_head_sha: null
    residual_risks: []
    released_next_bundle: []
    operator_function_acceptance:
      decision: "pending|accepted|accepted_with_findings|rejected"
      decided_by: null
      decided_at: null
      evidence: []
```

## Change note

- **1.2 — 2026-08-22:** Adds an independently-closable HRM gate that rejects composite
  `production ready` objectives; requires brownfield capability/parity inventory and
  first-class standalone/local system-node records; defines stable input-boundary
  dispositions; prevents manual lane constraints from suppressing planning records; and
  distinguishes healthy fail-closed exact-head review from upstream planning weakness.
- **1.1 — 2026-08-21:** Makes the complete project HRM map the inception-time control
  surface; permits autonomous, non-adopting `CTRQ` contract-update requests and routine
  lane derivation under unchanged HRM meaning; keeps lane execution quiet; makes
  `review_ready` a conspicuous stop; and requires explicit operator function/UI/UX
  acceptance before HRM closure and downstream rebaseline release.
- **1.0 — 2026-08-21:** Establishes HRM-directed system-building: operators target a
  milestone outcome rather than enumerate lanes; the playbook resolves evidence and
  milestone contracts, designs acceptance and test coverage, derives and publishes the
  smallest approved lane bundle, delegates execution, supports informal HOTL previews,
  keeps findings/remediation in one session, requires explicit human closure, and keeps
  closure separate from canary, deployment, provider-write, migration, and activation
  authority.
