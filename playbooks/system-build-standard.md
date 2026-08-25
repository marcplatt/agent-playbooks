---
playbook_id: AP-SYSBUILD-001
title: System Build and Human Review Milestone Standard
version: "2.5"
status: active
owner: Adopting organization
mode: hrm-directed-system-build
human_readable: true
machine_readable: true
required_inputs: [system_reference, target_hrm, milestone_outcome]
optional_inputs:
  - project_hrm_map
  - milestone_claim
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
  - operator_checkout
  - primary_checkout
  - completion_mode
  - operating_profile
  - checker_merge_controller_policy
  - manual_lane_constraint
controls:
  - project-rules-first
  - complete-as-presently-knowable-hrm-map
  - governed-hrm-discovery-and-rebaseline
  - evidence-before-lanes
  - operator-decision-frontier
  - operator-access-before-integration
  - validation-profile-routing
  - semantic-readiness-before-code
  - s0-s3-early-escalation
  - worker-to-orchestrator-routing
  - semantic-read-back
  - disposable-end-to-end-proof
  - target-hrm-first
  - project-defined-milestones
  - milestone-contract-before-implementation
  - milestone-claim-before-test-and-decomposition
  - vertical-completion-horizontal-breadth
  - owned-seam-equivalence
  - proof-spine-safety-shell-scale-perimeter
  - independently-closable-hrm
  - brownfield-capability-parity
  - brownfield-reuse-first
  - implementation-dominance
  - first-class-standalone-system-nodes
  - explicit-input-boundary-disposition
  - decision-transition-receipt
  - same-hrm-immediate-release
  - manual-lane-constraint-cannot-suppress-planning
  - authority-and-provenance
  - scenario-and-test-matrix-before-decomposition
  - claim-derived-test-budget
  - sequenced-obligation-no-silent-deferral
  - derived-lane-bundle
  - dedicated-checker-merge-controller
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
  - stable-operator-checkout
  - conditional-worktree-and-branch
  - one-hrm-many-change-units
  - one-change-unit-one-branch-normal-one-pr
  - disposable-discovery-no-pr-by-default
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
new project publishes all HRMs that are presently knowable before implementation.
Unknown milestone facts remain explicit blockers or requests; they are never filled by
inference. A later discovery is governed through map amendment and supersession.

The Git hierarchy is explicit: one HRM session may own multiple serial or parallel
published change units. Each published change unit gets one branch, normally one PR, and
one integration receipt. A lane normally maps to one change unit. Split it when independent
ownership, risk, validation, rollback, or integration boundaries emerge; do not force the
whole HRM into one long-lived PR or create Git state merely because a task was opened.

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
- **Milestone claim:** `{{milestone_claim_or_create}}`
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
- **Operator checkout:** `{{operator_checkout_or_primary_checkout_or_discover}}`
- **Completion mode:** `{{completion_mode_or_false}}`
- **Operating profile:** `{{operating_profile_or_one-human}}`
- **Checker/merge-controller policy:** `{{checker_merge_controller_policy_or_default}}`
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

All project HRMs presently knowable must appear in one versioned map at inception, before
implementation lanes begin. Publication means the control structure is complete given
current evidence; it does not claim clairvoyance or mean every prerequisite is known or
implemented. Record incomplete evidence as `unknown-blocked` with an owner, safe posture,
and resolution path. When evidence reveals a distinct operator-visible outcome, human
acceptance, closure/release effect, or authority/evidence state, raise an `HRM_DISCOVERY`
proposal. A later map change is a versioned rebaseline with supersession and downstream
impact, not rewritten history.

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
Milestone claim: {{milestone_claim_or_create}}.
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
Operator checkout: {{operator_checkout_or_primary_checkout_or_discover}}.
Completion mode: {{completion_mode_or_false}}.
Operating profile: {{operating_profile_or_one-human}}.
Checker/merge-controller policy: {{checker_merge_controller_policy_or_default}}.
Manual lane constraint: {{manual_lane_constraint_or_none}}.

The target HRM is the work session's controlling objective and must resolve from the
published complete project HRM map. Do not ask the operator for a lane list. Derive the
execution bundle only after resolving the milestone contract,
current evidence, the vertically complete and horizontally bounded milestone claim,
required capabilities, acceptance scenarios, dependency reach, and test architecture.
Keep lanes visible as auditable implementation units, but keep
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
3a. The lane coordinator delegates frozen-candidate checks, hosted-gate observation,
    serialized merge, remote-main verification, and eligible cleanup to one source-read-only
    checker/merge-controller subagent per repository queue. Only one controller may hold the
    active writer lease for a canonical remote and target ref across all queues and HRMs; a
    hosted merge queue acting as writer makes controllers observe-only. The controller cannot
    edit the candidate, classify findings, change validation scope, or contact the operator
    directly.
4. The human operator owns unresolved product or authority decisions, prepared milestone
   function/UI/UX review and acceptance, closure or deferral, and action-time authority for provider/customer/money,
   canary, deployment, credentials, irreversible migration, or production effects.
   Agents never count as human approvers.
4a. The HRM orchestrator is the single operator route. Workers raise semantic, authority,
    contract, scope, identity, lifecycle, UX-intent, and HRM discoveries to it. The
    orchestrator deduplicates them, assigns S0-S3 urgency, prepares a recommendation, and
    notifies the operator at the earliest safe point. Workers do not independently send
    competing questions to the operator.

RESOLVE THE TARGET HRM

5. Fetch and reconcile current main and inspect project rules, worktrees, branches, PRs,
   CI, running revisions, system plan, requirements, invariants, policies, contracts,
   decisions, scenarios, tests, the project-wide HRM map, milestone records, implementation
   manifest, brownfield capability/parity inventory, system-node registry, contract-update
   requests, input records, findings, lanes, and handoffs. Classify
   material claims as verified-current, historical-needs-revalidation, proposed, or
   unknown-blocked.
6. Treat milestone IDs as project-defined opaque identifiers. Verify that one canonical,
   versioned map publishes all HRMs presently knowable from planning through activation,
   with each
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
   absent. Propose one consolidated planning amendment only when the absence makes the
   executable contract, authority, dependency graph, checker/test oracle, or HRM release
   semantics materially indeterminate. Preserve unknowns as `unknown-blocked`. Obtain required
   operator approval and publish that material repair before deriving affected implementation
   lanes. A traceability-only update that restates already-published semantics travels with the
   next already-required bounded change unit and does not create a separate planning or receipt-
   only unit. For an existing project, apply this prospectively and do not manufacture
   historical HRM evidence.
8. Determine the last explicitly closed or deferred milestone from durable records. A
   review meeting, merged lane, local preview, green suite, or completed implementation
   is not evidence that an HRM closed.
8a. If evidence reveals a possible HRM addition, split, dependency change, or supersession,
    freeze only the affected boundary and run the HRM Map Discovery and Rebaseline
    playbook. Do not create a branch, worktree, or lane for an unaccepted discovery.
    Continue only work proven compatible with every plausible disposition. Publish a new
    map version before deriving work for an accepted new milestone, and preserve prior
    versions and closed evidence.

CREATE THE MILESTONE SESSION CONTRACT

9. Create one stable milestone-session ID and contract containing:

   - system and repository references;
   - project HRM map path, version, and target entry;
   - current and target HRM;
   - operator-visible outcome and review questions;
   - milestone-claim path and version;
   - proof spine, safety shell, supported horizontal breadth, cardinality, distinct
     input/output seams, explicit exclusions, and scale perimeter;
   - required scenario matrix and machine plus human-observable success evidence;
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
   - operator checkout, current-review index, and workspace cleanup policy.

10. Maintain an operator-facing session banner: current HRM, target HRM, why it matters,
    capabilities complete, capabilities remaining, blockers, decisions requested,
    contract requests, function/UI/UX review state, activation posture, integrated
    revision, operator-access state, integration-validation state, last decision-transition
    effect, newly released work, still-frozen boundaries, decision-to-builder-or-blocker
    latency, and next action. Lane
    counts and IDs are secondary execution details. Apply the Operator Access and
    Validation Routing playbook: a completed discovery, S0-S2 decision packet, or prepared
    review surface becomes operator-accessible after minimum packet validation and never
    waits for application CI, merge, receipt publication, or cleanup. This early surface
    supports semantic decisions or provisional feedback only; formal function/UI/UX
    acceptance and HRM closure remain bound to the integrated exact head.
11. Use the lifecycle `resolving -> defining -> bundle_derivation -> executing ->
    review_ready -> in_review -> remediation -> awaiting_closure -> closed|deferred|
    blocked`. `review_ready` is a hard human stop: no autonomous remediation or attempt
    to reinterpret the outcome begins until the operator reviews the prepared function.
    Keep the same session and target through remediation. Closure alone does not begin a
    different HRM. When the operator decision explicitly authorizes that HRM's published
    bundle, open its session and assign eligible work under the transition receipt. This
    restriction does not delay a newly eligible change unit inside the already-authorized
    active HRM.
12. For an existing project adopting this standard, use completion mode prospectively.
    Record one adoption SHA, preserve established IDs and history, build a contradiction
    register, and map every named lane or change unit to complete, deferred, cancelled,
    blocked_external, or active. Apply the new session contract to open and future work.
    Do not rewrite historical merges or manufacture missing evidence. Before changing an
    established implementation, inventory every current operator surface, domain service,
    workflow, state machine, persistence path, integration, recovery path, test seam, and audit
    surface as required operator workflow, advanced capability, developer/audit capability,
    intentionally superseded, or unknown. Bind the target HRM to a required parity set,
    implementation-reuse map, and approved removals/relocations.

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
14. Compare the target contract with verified current behavior, merged architecture, tests,
    and evidence. Requirements are acceptance floors, not instructions to replace a stronger
    compatible implementation. Record each gap as already satisfied and reusable, reusable
    with adapter/wiring, reusable with missing tests/evidence, extension needed, genuine
    implementation gap, replacement proposed pending approval, discovery needed, human decision
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
    deferral, or `blocked_external`. Before assigning any implementation work, bind every
    requirement to an existing component/contract/test or to evidence proving a genuine gap.
    Prefer adapters, composition, extension, and missing tests over a parallel or replacement
    implementation. Replacement requires a demonstrated violated invariant, unavoidable
    incompatibility, unsafe behavior, or explicit operator-approved capability retirement,
    plus parity, migration, rollback, and affected-consumer evidence.
14a. Resolve unknown API or implementation behavior first through the smallest deliberately
     disposable discovery spike that can answer the question with fixtures, read-only calls,
     or writes structurally disabled. The spike remains attached to the current HRM and has
     no PR by default. Discard exploratory code unless a contract, fixture, test, or
     documentation artifact is valuable enough to publish as its own evidence change unit.
     Route any changed business meaning, authority, persistence, public contract, external
     effect, or distinct operator outcome back through the decision frontier or
     `HRM_DISCOVERY` before non-disposable implementation.
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

DECISION FRONTIER AND SEMANTIC READINESS

15a. Before substantive implementation, enumerate unresolved business meaning, authority,
     capability retirement, user journey, identity, lifecycle, correctness-gap acceptance,
     contract semantics, external effect, and operator acceptance tradeoffs. Record first
     observed and foreseeable times, invalidation reach, evidence provenance/expiry, latest
     safe decision time, safe posture, and permitted independent work.
15b. Classify each operator input: S0 for protected, irreversible, security/privacy,
     customer/money, or action-time production authority; S1 where agents would otherwise
     choose meaning, authority, UX intent, or capability retirement; S2 for a material but
     schedulable decision; and S3 for a reversible technical choice inside accepted
     semantics. Notify S0 immediately, S1 before assumption or non-disposable work, batch
     S2 within a bounded window, and decide/record S3 without interrupting the operator.
15c. Every S0-S2 packet contains one decision sentence, affected HRMs, evidence, why now,
     latest-safe time, recommendation, no more than three meaningful alternatives,
     consequences, safe posture, permitted continuation, authority, and reply syntax. A
     timeout is never semantic acceptance. Read the response back as exact meaning, scope,
     exclusions, affected records, and expiry before resuming.
15d. Pass the semantic-readiness gate only when material terms, authority, identities,
     lifecycle and state transitions, contracts, scenarios, capability parity, evidence
     freshness, and operator review questions are explicit enough that implementation
     cannot silently decide business meaning. Open gaps remain frozen or explicitly
     independent; passing tests cannot compensate for a failed semantic-readiness gate.

FREEZE THE MILESTONE CLAIM BEFORE TEST DESIGN

15e. Freeze one versioned milestone claim before test design, lane derivation, or substantive
     implementation. Vertical completion defines the minimum new proof and real-system path
     from accepted input through required operator actions and ordered effects to the claimed
     human-visible result. Horizontal breadth defines exactly which input contracts, origins, variants,
     cardinalities, mutations, and recurrence patterns are supported. A vertically complete
     milestone may be intentionally narrow; a broad implementation is not a substitute for
     completing its proof spine. In brownfield work, this narrows the new delta and evidence;
     it does not authorize reducing, hiding, duplicating, or rewriting compatible capabilities.
15f. Divide the claim into a proof spine, safety shell, and scale perimeter. The proof spine
     is the smallest ordered real-system path that makes the operator-visible claim true.
     The safety shell contains identity, privacy, authorization, idempotency, partial-failure,
     resume, reconciliation, stop, and rollback or compensation invariants required to run
     that spine safely. The scale perimeter names generalized behavior, variants, automation,
     history, and lifecycle work that is deliberately outside this milestone.
15g. Build the required scenario matrix from owned contract seams, not interface labels. Each
     distinct input or output contract gets a scenario unless an explicit equivalence class
     proves that paths converge at an owned, versioned seam and share downstream semantics.
     Equivalence may remove duplicate downstream proof only; upstream owners still prove the
     path to the convergence seam. A label, screen, or channel is neither automatically a
     separate system seam nor automatically equivalent.
15h. State cardinality for inputs, operator actions, created records, messages, recipients,
     acknowledgements, and retries. State explicit exclusions and fail-closed behavior for
     unsupported inputs. If the claimed result is receipt or experience by a person, provider
     `sent`, queued, or API success evidence is insufficient by itself: require a privacy-safe
     human observation at the actual destination alongside machine receipts.
15i. Make newly introduced or changed reachable implementation match the accepted breadth.
     Necessary safety or shared infrastructure may extend beyond the proof spine, but
     generalized behavior that remains
     reachable cannot escape its required correctness tests merely because it is outside the
     milestone claim. Narrow, disable, or remove newly introduced behavior for this change
     unit, or amend the claim and carry the corresponding evidence. Preserve pre-existing
     accepted behavior and its regression evidence unless it is unsafe, incompatible, or
     explicitly retired through an operator-approved capability decision. Never use `out of
     scope` to defer an unsafe reachable path or to erase stronger existing capability.
15j. Read the claim back to the operator before non-disposable work when it selects business
     scope, supported origins, cardinality, human-visible effects, or explicit exclusions.
     A later discovery may correct a defect within the claim, propose a claim amendment,
     create a sequenced obligation, or trigger HRM discovery/rebaseline. Workers cannot
     silently expand the claim; only the affected boundary freezes while compatible work
     continues.

DESIGN TEST COVERAGE BEFORE DECOMPOSITION

16. Derive the scenario-and-test matrix from the frozen claim before creating lanes. For
    each required scenario, claim-breaking failure mode, safety-shell invariant, and changed
    behavior,
    record affected consumers, invariants, risk modifiers, exact repository-native command
    or deterministic scenario, phase, expected signal, fixture/environment, artifact,
    timeout, and mutation safety. Every planned check must trace to a claim, plausible
    regression, safety invariant, dependency risk, or binding repository/release gate; raw
    test count is not coverage. Map every acceptance criterion to positive, negative,
    boundary, partial-failure, recovery, reconciliation, and accessibility/security coverage
    where applicable. Test one failure mode at the lowest deterministic layer that can prove
    it, and repeat it end to end only when the seam or integrated effect itself is the claim.
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
      runs, followed by idempotency, reconcile-before-retry, exact read-back, the accepted
      targeted/affected/full validation budget, and separately authorized canary/rollback
      gates before live effects. Provider reach that is shared or cannot be bounded triggers
      the full suite.
    - Documentation/configuration/contracts: parse/schema, links or configured lint,
      executable examples, canonical/mirror search, defaults, missing/malformed/conflicting
      values, safe-off behavior, secret/PII non-disclosure, and affected-mode startup.

18. Apply the union of all applicable checks and use the highest-risk changed surface as
    the provisional validation class. Required check categories may be marked not
    applicable only with a bounded reason. A mandatory checker remains binding unless an
    explicit approved lane-doc amendment changes it.
19. Select `targeted`, `affected`, or `full` validation from the frozen milestone claim,
    changed-surface reach, safety shell, dependency map, evidence freshness, and binding
    repository/release policy. A canary, deployment, or release label does not alone require
    a repository-wide suite. Limited-scope CI must name every covered scenario and invariant,
    excluded check with reason, fresh unaffected evidence relied on, scope authority, and the
    policy permitting it. Unknown reach fails closed. A repository-wide suite is required
    when shared domain, contract, persistence,
    authentication, provider, public API, schema, state transition, dependency, or core
    structure changes; the affected surface cannot be bounded; targeted checks expose
    unexpected coupling; a mandatory checker requires it; or binding repository/release
    policy requires it. A multi-lane lighter-weight bundle receives one
    combined regression run at the integrated milestone head. During iteration prefer
    focused checks; run the release-required full suite once on the frozen integrated head
    and rerun it only when that head changes or the evidence is invalidated. Run the full
    suite again before production canary or release only when the accepted validation budget
    or binding release gate requires fresh evidence. Isolated CSS, wording, spacing, layout, and
    bounded control simplification do not independently trigger a full suite.

PROVE THE END-TO-END INTENT CHEAPLY

19a. Before authorizing a large bundle, build the smallest deliberately disposable
     end-to-end proof that exercises the riskiest semantic seam using safe fixtures,
     read-only adapters, or structurally disabled writes. Its purpose is to expose wrong
     meanings, missing states, unusable operator journeys, identity ambiguity, and contract
     gaps before architecture hardens around them.
19b. Review this proof against the accepted outcome and semantic read-back. Treat its code
     as disposable unless retention criteria, tests, ownership, and production quality are
     explicitly approved. A skeleton is learning evidence, not implementation, HRM closure,
     deployment, activation, or canary authority.
19c. If the proof reveals new meaning, return to the decision frontier or HRM-discovery
     process and rebaseline before deriving the full lane bundle.

DERIVE AND PUBLISH THE LANE BUNDLE

20. Derive the smallest coherent new delta from verified current implementation that can
    satisfy the target HRM. Reuse dominates replacement when existing behavior satisfies or
    exceeds the requirement without violating contract, authority, or the safety shell. Each
    lane must declare requirement and scenario coverage, milestone contribution, in/out of scope,
    authority and activation posture, dependencies and exact base, owned files, state or
    data changes, migration/recovery posture, exact checker/test plan, human-readable
    acceptance, hard stops, handoff, and assigned target HRM.
21. Use dependency and file-ownership evidence to mark lanes serial or safely parallel.
    `SERIAL` requires an exact dependency edge, conflicting owned path/resource, incompatible
    state transition, or authority boundary. Uncertain independence triggers a bounded
    readiness audit, not indefinite serialization. Freeze only the affected boundary and
    continue work proven independent.
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
    Coordination Standard, which creates the bounded Dedicated Checker and Merge Controller
    handoff for frozen candidates. Do not translate the session back into an operator-
    maintained lane queue or make the HRM orchestrator babysit routine checks and merges.

RUN PREVIEWS AND THE FORMAL REVIEW

24. During active HOTL UI/UX design, keep one preview live and batch operator feedback.
    These are informal checkpoints. Do not freeze, spawn independent reviewers, push a
    candidate, or rerun a repository-wide suite after each presentational adjustment.
    Freeze only when the operator declares the design batch ready. Informal feedback does
    not replace the formal HRM function/UI/UX acceptance.
25. When all published bundle lanes are integrated and applicable integrated-head checks
    pass, publish the HRM review package and move to REVIEW READY. The package contains:

    - project HRM map version, current and target HRM, outcome, and decisions requested;
    - accepted milestone-claim version, proof spine, scenario matrix, cardinality,
      explicit exclusions, and sequenced obligations;
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
    - checker/merge-controller validation, integration, remote-main, and cleanup receipt;
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
27a. Classify a finding as a current milestone blocker only when it is reachable in a
     required scenario or accepted implementation surface and it violates the frozen claim,
     a required invariant, or the safety shell; makes a required result false; or can
     duplicate, misroute, expose, corrupt, or lose a required effect. A finding that adds
     new breadth or later lifecycle capability does not enter the active implementation
     without an operator-approved claim amendment. It becomes a sequenced obligation unless
     it exposes unsafe reachable behavior, in which case narrow the implementation or fix
     and test it now.
27b. Every sequenced obligation records its originating finding or discovery, required
     outcome, why it does not block the current claim, owner, target HRM or release, latest
     safe point, promotion trigger, and safe interim posture. This is scheduled necessary
     work, not an unowned backlog or evidence that the behavior already exists.
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
    findings, and the next bundle made eligible. Issue the decision-transition receipt in the
    same response that acknowledges the operator decision. Closure alone releases eligibility
    and does not begin another milestone session. When the same decision explicitly authorizes
    the next HRM's published bundle, open its session and assign eligible work; already-authorized
    newly eligible work inside the active HRM is likewise assigned immediately. Otherwise issue
    a blocker receipt within the configured builder-or-blocker target, default 600 seconds.
33. Keep implementation completion, HRM readiness, HRM closure, canary authority,
    deployment, provider/customer/money effects, irreversible migration, and production
    activation as distinct states. Require explicit action-time authority and exact
    read-back/reconciliation for every external effect.
34. Delegate project-scoped workspace control to the lane coordinator and Workspace
    Topology and Review Handoff playbook. A task is not a Git change unit; create a branch
    only for a published change unit and a worktree only for concurrency, active review,
    or unique-work preservation. Keep one stable operator checkout and current-review
    index; workers never implement there. Remove safely merged worktrees after verified
    integration rather than waiting for closure, and preserve every dirty, ambiguous, or
    unique worktree. Report the target HRM first and workspace detail second.
```

## Machine-readable session contract

```yaml
system_build_session:
  schema_version: agent_playbooks.system_build_session.v2.5
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
    complete_as_presently_knowable: true
    evidence_cutoff_at: null
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
  milestone_claim:
    path: "{{path}}"
    id: "{{milestone_claim_id}}"
    version: "{{version}}"
    status: "proposed|accepted|superseded"
    proof_spine:
      input_event: null
      required_real_systems: []
      required_operator_actions: []
      ordered_effects: []
    safety_shell:
      invariants: []
      partial_failure_cases: []
      retry_resume_reconciliation: []
    horizontal_breadth:
      supported_input_contracts: []
      supported_variants: []
      cardinality: []
      explicit_exclusions: []
      reachable_implementation_matches_claim: false
    seam_equivalence: []
    required_scenario_matrix: []
    human_observations_required: []
    validation_budget:
      scope: "targeted|affected|full"
      scope_authority_reference: null
      scope_authority_expires_at: null
      limited_scope_basis:
        bounded_changed_surfaces: []
        dependency_reach: []
        excluded_checks_with_reason: []
        fresh_unaffected_evidence_relied_on: []
        repository_policy_compatible: false
        unknown_reach_absent: false
        required_hosted_gate_dispositions: []
        full_suite_trigger_dispositions: []
      full_suite_triggers: []
    scale_perimeter: []
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
  decision_frontier:
    open_s0: []
    open_s1: []
    open_s2: []
    recorded_s3: []
    semantic_read_backs: []
    gate: "blocked|ready"
    latest_transition_receipt:
      id: null
      effect: "record_only|releases_change_units|closes_stage|closes_hrm"
      decision_accepted_at: null
      transition_reported_at: null
      newly_eligible_change_units: []
      newly_authorized_hrms: []
      still_frozen_boundaries: []
      assigned_work:
        - change_unit_id: null
          owner_or_task: null
          builder_started_at: null
          blocker_receipt_id: null
      decision_to_builder_or_blocker_target_seconds: 600
      actual_decision_to_builder_or_blocker_seconds: null
      target_met: null
  disposable_end_to_end_proof:
    path_or_url: null
    disposition: "not_started|discard|retain_with_approval|rebaseline_required"
  hrm_discoveries: []
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
    implementation_reuse_map:
      - requirement_or_capability: null
        existing_components: []
        existing_tests_and_evidence: []
        disposition: "already_satisfied_reuse|reuse_with_adapter_or_wiring|reuse_with_missing_tests_or_evidence|extend_existing_implementation|genuine_implementation_gap|replacement_proposed_pending_approval"
        missing_delta: null
        replacement_authority: null
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
    reuse_with_adapter_or_wiring: []
    reuse_with_missing_tests_or_evidence: []
    extension_needed: []
    implementation_needed: []
    replacement_proposed_pending_approval: []
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
      claim_failure_modes: []
      validation_class: "ui_presentation|ui_interaction|application_behavior|critical_integration|release_bundle"
      exact_checks: []
      full_suite_triggers: []
  sequenced_obligations:
    - id: "{{obligation_id}}"
      source_finding_or_discovery: null
      required_outcome: null
      why_not_a_current_claim_blocker: null
      target_hrm_or_release: null
      owner: null
      latest_safe_point: null
      promotion_trigger: null
      safe_posture_until_promoted: null
  checker_merge_controller:
    playbook: AP-INTEGRATE-001
    policy: "dedicated_codex_subagent|equivalent_authenticated_repository_worker"
    handoff_template: templates/checker-merge-controller-handoff.yaml
    dedicated_controller_per_repository_queue: true
    repository_global_writer_lease_per_remote_and_target_ref: true
    hosted_merge_queue_writer_requires_controller_observe_only: true
    source_read_only: true
    controller_may_contact_operator: false
  lane_bundle:
    source: "derived|approved_existing|manual_constraint"
    planning_authority: "standing_hrm_contract|operator_approved_change|blocked"
    approval_evidence: null
    lanes:
      - id: "{{lane_id}}"
        change_unit_id: "{{change_unit_id}}"
        milestone_contribution: []
        requirement_ids: []
        dependencies: []
        classification: "quick|serial|parallel|critical"
        serialization_basis:
          dependency_edges: []
          conflicting_paths_or_resources: []
          incompatible_state_or_authority_boundaries: []
        implementation_reuse_map: []
        validation_profile: "review_packet|executable_contract|runtime_change"
        validation_class: "ui_presentation|ui_interaction|application_behavior|critical_integration|release_bundle"
        contract: "{{path}}"
        publication_sha: null
        branch: null
        pull_request: null
        integration_receipt: null
        state: "proposed|approved|executing|integrated|blocked|complete"
  discovery_spikes:
    - id: "{{discovery_id}}"
      assigned_hrm: "{{target_hrm}}"
      question: null
      safe_method: "fixture|read_only|writes_disabled|other"
      disposition: "active|discarded|retained_evidence_change_unit|rebaseline_required"
      retained_change_unit_id: null
      pull_request: null
  operator_banner:
    capabilities_complete: []
    capabilities_remaining: []
    blockers: []
    decisions_requested: []
    contract_requests: []
    input_requirements: []
    operator_access_state: "not_ready|operator_access_ready|operator_access_blocked|in_review|withdrawn|superseded"
    access_purpose: "semantic_decision|discovery_disposition|provisional_feedback|formal_integrated_review"
    function_review_state: "not_ready|review_ready|in_review|accepted|accepted_with_findings|rejected"
    candidate_head_sha: null
    integrated_head_sha: null
    last_decision_transition_effect: null
    newly_released_change_units: []
    still_frozen_boundaries: []
    decision_to_builder_or_blocker_target_seconds: 600
    actual_decision_to_builder_or_blocker_seconds: null
    next_action: null
    time_to_next_meaningful_operator_interaction_seconds: null
    time_to_formal_hrm_review_seconds: null
  review_package:
    status: "not_started|draft|published|superseded|accepted|deferred"
    operator_access_state: "not_ready|operator_access_ready|operator_access_blocked|in_review|withdrawn|superseded"
    access_purpose: "semantic_decision|discovery_disposition|provisional_feedback|formal_integrated_review"
    validation_profile: "review_packet|executable_contract|runtime_change"
    integration_validation_state: "not_started|running|passed|failed|not_applicable"
    operator_packet_published_at: null
    operator_access_ready_at: null
    validation_started_at: null
    integration_eligible_at: null
    avoidable_wait_seconds: 0
    avoidable_wait_reason: null
    validation_subject_identity:
      kind: "repository_commit|non_git_packet"
      id: null
      version: null
      content_hash: null
      provenance: []
      repository_sha: null
    path_or_url: null
    candidate_head_sha: null
    integrated_head_sha: null
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
    transition_events: noisy
    transition_events_include: [decision_accepted, capability_released, builder_assigned, release_target_missed, blocker_discovered, critical_path_changed]
    last_operator_interrupt_reason: null
  closure:
    decision: "pending|closed|deferred"
    decided_by: null
    decided_at: null
    rationale: null
    exact_review_head_sha: null
    residual_risks: []
    released_next_bundle: []
    transition_receipt_id: null
    operator_function_acceptance:
      decision: "pending|accepted|accepted_with_findings|rejected"
      decided_by: null
      decided_at: null
      evidence: []
```

## Change note

- **2.5 — 2026-08-25:** Makes requirements acceptance floors for brownfield work, requires
  reuse/adapter/extension analysis before genuine implementation gaps or replacement, scopes
  the smallest bundle to the new delta, requires affirmative serialization evidence, and adds
  decision-transition receipts with immediate same-HRM release or bounded blocker reporting.
- **2.4 — 2026-08-25:** Delegates deterministic checking and integration to a source-read-only
  checker/merge-controller subagent and makes targeted, affected, or full validation an
  explicit milestone-claim decision, including bounded canary CI without automatic full-
  suite promotion while failing closed on unknown reach or binding-policy conflicts.
- **2.3 — 2026-08-25:** Freezes a vertically complete and horizontally bounded milestone
  claim before test design; adds proof-spine, safety-shell, scale-perimeter, owned-seam
  equivalence, cardinality and destination evidence; derives validation from claim-breaking
  failure modes; and routes non-blocking discoveries into owned sequenced obligations.
- **2.2 — 2026-08-24:** Separates operator access from integration validation and requires
  completed discoveries, S0-S2 decisions, and prepared review surfaces to reach the operator
  after minimum packet checks rather than waiting for application CI or merge bookkeeping.
- **2.1 — 2026-08-24:** Defines one HRM as the orchestration/review boundary and published
  change units as the Git boundary. Allows multiple change units per HRM; assigns each one
  branch, normally one PR, and one integration receipt; makes lanes normally one-to-one
  with change units; and adds disposable API discovery with no PR unless evidence is retained.
- **2.0 — 2026-08-24:** Generalizes ownership; defines complete-as-presently-knowable
  HRM maps and governed discoveries; adds S0-S3 decision-frontier escalation, worker-to-
  orchestrator routing, semantic read-back/readiness, a disposable end-to-end proof, and
  a stable operator checkout with conditional branches/worktrees. Preserves explicit
  operator closure and separate deployment, activation, canary, and production proof.
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
