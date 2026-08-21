---
playbook_id: AP-SYSBUILD-001
title: System Build and Human Review Milestone Standard
version: "1.0"
status: active
owner: Alpine Structures
mode: hrm-directed-system-build
human_readable: true
machine_readable: true
required_inputs: [system_reference, target_hrm, milestone_outcome]
optional_inputs:
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
  - evidence-before-lanes
  - target-hrm-first
  - project-defined-milestones
  - milestone-contract-before-implementation
  - authority-and-provenance
  - scenario-and-test-matrix-before-decomposition
  - derived-lane-bundle
  - approval-before-material-scope-change
  - canonical-lane-publication
  - hotl-preview-not-milestone
  - append-only-findings
  - bounded-remediation
  - explicit-human-closure
  - activation-separation
  - project-scoped-cleanup
---

# System Build and Human Review Milestone Standard

Use this playbook when the operator wants to advance a system to a Human Review
Milestone (HRM). The operator names the system, the target milestone, and the outcome
they need to review. The playbook resolves current evidence, defines or verifies the
milestone contract, derives the smallest approved lane bundle, delegates execution to
the HRM Bundle Coordination Standard, and keeps the same work session open through
human review, findings, remediation, and explicit milestone closure or deferral.

The target of the work session is the HRM, not a lane list. Lanes remain necessary as
bounded implementation, review, merge, and audit units, but they are execution detail
derived from the system plan and milestone gap analysis.

## Operator model

The operator should normally need to know only:

- which system is changing;
- which HRM the session is targeting;
- what outcome or questions the milestone must make reviewable;
- the current authority and activation envelope; and
- any scope, time, or priority constraint.

Do not make the operator reconstruct dependencies or enumerate lanes. A manual lane
list may constrain a legacy or recovery session, but it cannot replace the canonical
system plan, milestone contract, or gap analysis.

## Inputs

- **System or project:** `{{system_reference}}`
- **Project root:** `{{project_root_or_discover}}`
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
Target HRM: HRM-2.
Milestone outcome: the operator can complete the full local workflow, correct inputs,
understand failures, and inspect provenance without provider or production writes.
Activation posture: read-only.
```

## HRM identifiers and archetypes

Milestone identifiers are project-defined stable IDs. `HRM-0` through `HRM-4` are useful
archetypes, not a mandatory universal sequence. A project may define `HRM-O`, repeat a
workflow milestone, or use a qualified ID when its system plan records the outcome,
closure authority, prerequisites, and release effect unambiguously.

| Archetype | Typical review outcome |
|---|---|
| Plan and contract | Outcome, authority, lifecycle, boundaries, contracts, requirements, test architecture, lane map, and milestone schedule are approved. |
| Read-only vertical slice | Real inputs, interpretation, provenance, safe failure, and missing functions are reviewable without external writes. |
| Operator workflow | A human can perform realistic work, correct it, and understand controls, states, explanations, and failures. |
| Controlled canary | One explicitly authorized effect reaches the exact destination and has read-back, reconciliation, receipt, retry, and rollback evidence. |
| Activation readiness | Permissions, monitoring, privacy, recovery, runbook, support ownership, residual risk, and the separate activation decision are reviewable. |

## Prompt

```text
Advance this system to one Human Review Milestone.

System: {{system_reference}}.
Project root: {{project_root_or_discover}}.
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

The target HRM is the work session's controlling objective. Do not ask the operator for
a lane list. Derive the execution bundle only after resolving the milestone contract,
current evidence, required capabilities, acceptance scenarios, dependency reach, and
test architecture. Keep lanes visible as auditable implementation units, but report
progress primarily as milestone readiness, decisions, findings, and closure.

AUTHORITY AND ROLES

1. Obey every applicable AGENTS.md and approved system, requirement, contract, decision,
   milestone, and activation record. Repository policy at current main is the durable
   automation authority. Record contradictions; do not silently choose among them.
2. The system-build coordinator owns target-HRM resolution, evidence and gap analysis,
   milestone contract, lane derivation/rebaselining, findings classification, remediation
   scope, downstream rebaseline, review package, and closure record.
3. The lane coordinator owns execution of the approved bundle: lane readiness, exact
   tests, worktrees, assignments, reviews, deterministic integration, exact-head evidence,
   and cleanup. Lane workers cannot redefine the HRM or enlarge their lanes.
4. The human operator owns unresolved product or authority decisions, prepared milestone
   review, closure or deferral, and action-time authority for provider/customer/money,
   canary, deployment, credentials, irreversible migration, or production effects.
   Agents never count as human approvers.

RESOLVE THE TARGET HRM

5. Fetch and reconcile current main and inspect project rules, worktrees, branches, PRs,
   CI, running revisions, system plan, requirements, invariants, policies, contracts,
   decisions, scenarios, tests, milestone records, findings, lanes, and handoffs. Classify
   material claims as verified-current, historical-needs-revalidation, proposed, or
   unknown-blocked.
6. Treat milestone IDs as project-defined opaque identifiers. Resolve the exact target
   from the canonical system plan. Do not infer that every project uses the same numbered
   sequence, and do not confuse `HRM-0` with a similarly named project-specific milestone.
7. If the target HRM is missing or inadequately defined, stop implementation and propose
   one canonical planning amendment containing its purpose, operator-visible outcome,
   prerequisites, review questions, closure criteria, closure authority, activation
   posture, downstream release effect, and finding/remediation policy. Obtain approval
   and publish the amendment before deriving implementation lanes.
8. Determine the last explicitly closed or deferred milestone from durable records. A
   review meeting, merged lane, local preview, green suite, or completed implementation
   is not evidence that an HRM closed.

CREATE THE MILESTONE SESSION CONTRACT

9. Create one stable milestone-session ID and contract containing:

   - system and repository references;
   - current and target HRM;
   - operator-visible outcome and review questions;
   - prerequisites and closure criteria;
   - requirements, invariants, policies, contracts, and acceptance scenarios in scope;
   - authority envelope and exact activation posture;
   - evidence freshness requirements and authoritative sources;
   - expected review artifact and configuration;
   - finding classifications and remediation rules;
   - provisional downstream effects; and
   - primary checkout and cleanup policy.

10. Maintain an operator-facing session banner: current HRM, target HRM, why it matters,
    capabilities complete, capabilities remaining, blockers, decisions requested,
    activation posture, integrated revision, and next action. Lane counts and IDs are
    secondary execution details.
11. Use the lifecycle `resolving -> defining -> awaiting_bundle_approval -> executing ->
    review_ready -> in_review -> remediation -> awaiting_closure -> closed|deferred|
    blocked`. Keep the same session and target through remediation. Do not automatically
    begin the next HRM when this one closes.
12. For an existing project adopting this standard, use completion mode prospectively.
    Record one adoption SHA, preserve established IDs and history, build a contradiction
    register, and map every named lane or change unit to complete, deferred, cancelled,
    blocked_external, or active. Apply the new session contract to open and future work.
    Do not rewrite historical merges or manufacture missing evidence.

ANALYZE THE SYSTEM BEFORE LANES

13. Trace the outcome end to end through actors, authority, provenance, states, storage,
    APIs/providers, failure/retry/recovery, privacy, observability, and activation. Map
    every relevant requirement and invariant to a human-readable positive, negative,
    and boundary scenario where applicable.
14. Compare the target contract with verified current behavior and evidence. Record each
    gap as already satisfied, implementation needed, discovery needed, human decision
    needed, blocked external, or accepted limitation. Resolve unknown provider facts in
    read-only discovery while writes remain structurally disabled.
15. Freeze only affected boundaries when evidence changes. A new product outcome, policy,
    schema meaning, persistence model, provider mutation, public contract, or activation
    step requires a planning amendment; it is not an implementation inference.

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

DERIVE AND APPROVE THE LANE BUNDLE

20. Derive the smallest coherent bundle that can satisfy the target HRM. Each lane must
    declare requirement and scenario coverage, milestone contribution, in/out of scope,
    authority and activation posture, dependencies and exact base, owned files, state or
    data changes, migration/recovery posture, exact checker/test plan, human-readable
    acceptance, hard stops, handoff, and assigned target HRM.
21. Use dependency and file-ownership evidence to mark lanes serial or safely parallel.
    A manual lane constraint may narrow the proposal, but if it leaves the HRM outcome
    unsatisfied, report the gap rather than pretending the milestone is reachable.
22. If the bundle introduces or materially revises lanes, present one approval packet:
    current evidence, target-HRM gap, proposed lanes/order, contracts and tests affected,
    authority/activation effects, alternatives, safe default, and recommendation. After
    approval, publish the canonical milestone and lane documents to main through the
    repository-approved integration path before implementation begins. Unchanged already-
    approved lanes may proceed without another planning approval.
23. Pass the approved milestone-session contract and derived bundle to the HRM Bundle
    Coordination Standard. Do not translate the session back into an operator-maintained
    lane queue.

RUN PREVIEWS AND THE FORMAL REVIEW

24. During active HOTL UI/UX design, keep one preview live and batch operator feedback.
    These are informal checkpoints. Do not freeze, spawn independent reviewers, push a
    candidate, or rerun a repository-wide suite after each presentational adjustment.
    Freeze only when the operator declares the design batch ready.
25. When all approved bundle lanes are integrated and applicable integrated-head checks
    pass, publish the HRM review package and move to REVIEW READY. The package contains:

    - current and target HRM, outcome, and decisions requested;
    - capabilities completed in operator language, mapped to requirements and lanes;
    - exact integrated revision, configuration, data window, and activation posture;
    - live preview or deterministic review scenarios and expected outcomes;
    - test evidence aggregated by change and risk class;
    - known limitations, blockers, and unresolved questions;
    - external-mutation count and boundary/read-back evidence;
    - cleanup and integration receipt;
    - provisional downstream impact; and
    - the exact authority or bundle released by closure.

26. Pause for operator review. A review package, visible feature, green test, merged
    bundle, or ended meeting is not milestone closure.

CLASSIFY FINDINGS AND REMEDIATE

27. Record findings append-only with stable FND IDs, time, evidence, classification,
    affected requirements/contracts/scenarios, blocking status, owner, disposition,
    remediation lane, and status.
28. A verified defect against an already-approved requirement may be converted into a
    bounded remediation lane, published to main, and executed in the same milestone
    session without another scope decision. Do not silently enlarge the original lane.
29. A missing function, changed outcome, policy or authority decision, new persistence
    or provider effect, changed test oracle/contract, or downstream rebaseline requiring
    product judgment receives one batched approval before remediation. Unknown provider
    facts become read-only discovery lanes. Future enhancements do not block closure
    unless the operator explicitly promotes them.
30. Pause downstream milestones, update requirements/contracts/scenarios/tests, publish
    approved remediation lanes, execute them through the lane coordinator, revalidate
    affected and integrated evidence, rebaseline downstream specs, and republish the HRM
    package. Keep the original session ID and target HRM.

CLOSE WITHOUT ACTIVATING

31. Ask for one explicit operator decision to close or defer the HRM only when every
    finding has classification, owner, blocking status, disposition, and evidence; every
    must-fix item is verified or explicitly deferred with rationale; canonical planning
    records represent what was learned; and downstream specs are rebaselined.
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
    requirements: []
    contracts: []
    decisions: []
    milestones: []
    findings: []
  current_hrm:
    id: null
    status: "unknown|open|closed|deferred"
    evidence: []
  target_hrm:
    id: "{{target_hrm}}"
    title: "{{title}}"
    milestone_contract: "{{path}}"
    outcome: "{{milestone_outcome}}"
    review_questions: []
    prerequisites: []
    closure_criteria: []
    closure_authority: human_operator
    release_effect: null
  status: "resolving|defining|awaiting_bundle_approval|executing|review_ready|in_review|remediation|awaiting_closure|closed|deferred|blocked"
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
  evidence_gap_analysis:
    verified_satisfied: []
    implementation_needed: []
    discovery_needed: []
    human_decision_needed: []
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
    approval_status: "not_needed|pending|approved|rejected"
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
    integrated_head_sha: null
    next_action: null
  review_package:
    status: "not_started|draft|published|superseded|accepted|deferred"
    path_or_url: null
    review_head_sha: null
    configuration_profile: null
    scenarios: []
    test_evidence: []
    known_limitations: []
    external_mutations: 0
    cleanup_receipt: null
    closure_effect: null
  findings:
    ledger: null
    open: []
    blocking: []
    remediation_bundle: []
  closure:
    decision: "pending|closed|deferred"
    decided_by: null
    decided_at: null
    rationale: null
    exact_review_head_sha: null
    residual_risks: []
    released_next_bundle: []
```

## Change note

- **1.0 — 2026-08-21:** Establishes HRM-directed system-building: operators target a
  milestone outcome rather than enumerate lanes; the playbook resolves evidence and
  milestone contracts, designs acceptance and test coverage, derives and publishes the
  smallest approved lane bundle, delegates execution, supports informal HOTL previews,
  keeps findings/remediation in one session, requires explicit human closure, and keeps
  closure separate from canary, deployment, provider-write, migration, and activation
  authority.
