---
playbook_id: AP-LANE-001
title: HRM Bundle Coordination Standard
version: "4.0"
status: active
owner: Adopting organization
mode: hrm-bundle-execution
human_readable: true
machine_readable: true
required_inputs: [system_reference, target_hrm, milestone_outcome]
optional_inputs:
  - project_hrm_map
  - implementation_manifest
  - brownfield_capability_inventory
  - system_node_registry
  - milestone_session_contract
  - published_lane_bundle
  - approved_lane_bundle
  - manual_lane_bundle
  - current_hrm
  - review_questions
  - required_order
  - authority_envelope
  - activation_posture
  - target_time_or_priority
  - operator_checkout
  - primary_checkout
  - worktree_cleanup_policy
  - completion_mode
  - operating_profile
  - integration_mode
  - legacy_baseline_sha
  - protected_governance_paths
  - standing_merge_authority
  - supervisor_rotation_limits
controls:
  - project-rules-first
  - complete-as-presently-knowable-hrm-map-prerequisite
  - governed-hrm-discovery-return
  - independently-closable-hrm-prerequisite
  - brownfield-capability-parity
  - first-class-standalone-system-nodes
  - explicit-input-boundary-return
  - target-hrm-first
  - published-milestone-bundle
  - no-operator-lane-enumeration
  - manual-lane-constraint-cannot-suppress-inputs
  - bounded-scope
  - prospective-adoption-baseline
  - contradiction-register
  - queue-dependency-graph
  - implementation-and-semantic-readiness-gates
  - s0-s3-worker-escalation
  - worker-to-orchestrator-routing
  - semantic-read-back
  - task-is-not-change-unit
  - conditional-worktree
  - stable-operator-checkout
  - bounded-agent-context
  - exact-head-evidence
  - validation-classification
  - change-surface-test-matrix
  - hotl-design-batching
  - risk-based-review
  - release-boundary-regression
  - bounded-correction-loops
  - deterministic-integration
  - single-writer-integration
  - early-classified-human-interruption
  - autonomous-contract-update-request-routing
  - quiet-lanes-noisy-hrm-stop
  - operator-function-acceptance
  - milestone-review-and-remediation
  - explicit-human-closure
  - post-merge-verification
  - post-merge-worktree-cleanup
  - unique-work-preservation
  - operator-checkout-review-handoff
  - durable-supervisor-ledger
  - phase-timing-ledger
---

# HRM Bundle Coordination Standard

Use this playbook to execute a published implementation bundle toward one Human Review
Milestone (HRM). The target HRM is the work session's operator-visible outcome. Lanes
are bounded, auditable implementation units derived by the System Build and Human Review
Milestone Standard; they are not the normal operator-facing session target.

The coordinator owns session state, authority, dependencies, evidence, validation,
integration, milestone readiness, and cleanup. Builders implement; risk-scaled checks
and reviews verify frozen candidates. Active human-on-the-loop UI design is an informal
iteration phase inside the milestone session, not a sequence of acceptance candidates
or milestones. The session remains open through review and approved remediation until
the operator explicitly closes or defers the target HRM.

## Inputs

- **System or project:** `{{system_reference}}`
- **Project HRM map:** `{{project_hrm_map_or_session_contract}}`
- **Implementation manifest:** `{{implementation_manifest_or_session_contract}}`
- **Brownfield capability inventory:** `{{brownfield_capability_inventory_or_session_contract}}`
- **System-node registry:** `{{system_node_registry_or_session_contract}}`
- **Target HRM:** `{{target_hrm}}`
- **Milestone outcome:** `{{milestone_outcome}}`
- **Milestone session contract:** `{{milestone_session_contract_or_discover}}`
- **Published lane bundle:** `{{published_lane_bundle_or_derive_from_session_contract}}`
- **Legacy approved-lane bundle:** `{{approved_lane_bundle_or_none}}`
- **Manual lane bundle:** `{{manual_lane_bundle_or_none}}`
- **Current HRM:** `{{current_hrm_or_discover}}`
- **Review questions:** `{{review_questions_or_session_contract}}`
- **Required order:** `{{required_order_or_dependency_graph}}`
- **Authority envelope:** `{{authority_envelope_or_project_policy}}`
- **Activation posture:** `{{activation_posture_or_safe_current_state}}`
- **Target time or priority:** `{{target_time_or_priority_or_none}}`
- **Operator checkout:** `{{operator_checkout_or_primary_checkout_or_discover}}`
- **Worktree cleanup:** `{{worktree_cleanup_policy_or_automatic_after_verified_merge}}`
- **Completion mode:** `{{completion_mode_or_false}}`
- **Operating profile:** `{{operating_profile_or_one-human}}`
- **Integration mode:** `{{integration_mode_or_project-policy}}`
- **Legacy baseline SHA:** `{{legacy_baseline_sha_or_discover}}`
- **Protected governance paths:** `{{protected_governance_paths_or_project-policy}}`
- **Standing merge authority:** `{{standing_merge_authority_or_project-policy}}`
- **Supervisor rotation limits:** `{{supervisor_rotation_limits_or_default}}`

The normal caller is the system-build playbook, which supplies the published bundle. A
manual bundle is a legacy or emergency constraint, not an invitation to make the
operator reconstruct the plan.

## Quick-start example

```text
Use the HRM Bundle Coordination Standard.
System: SYS-EXAMPLE-001.
Target HRM: HRM-2.
Milestone outcome: an operator can complete the bounded workflow and understand every
failure without production side effects.
Milestone session contract: milestones/HRM-2.md.
Published lane bundle: derive from that contract.
Activation posture: read-only.
```

## Prompt

```text
Coordinate the published implementation bundle for this milestone session.

System: {{system_reference}}.
Project HRM map: {{project_hrm_map_or_session_contract}}.
Implementation manifest: {{implementation_manifest_or_session_contract}}.
Brownfield capability inventory: {{brownfield_capability_inventory_or_session_contract}}.
System-node registry: {{system_node_registry_or_session_contract}}.
Current HRM: {{current_hrm_or_discover}}.
Target HRM: {{target_hrm}}.
Milestone outcome: {{milestone_outcome}}.
Milestone session contract: {{milestone_session_contract_or_discover}}.
Published lane bundle: {{published_lane_bundle_or_derive_from_session_contract}}.
Legacy approved-lane bundle: {{approved_lane_bundle_or_none}}.
Manual lane bundle: {{manual_lane_bundle_or_none}}.
Review questions: {{review_questions_or_session_contract}}.
Required order: {{required_order_or_dependency_graph}}.
Authority envelope: {{authority_envelope_or_project_policy}}.
Activation posture: {{activation_posture_or_safe_current_state}}.
Target time or priority: {{target_time_or_priority_or_none}}.
Operator checkout: {{operator_checkout_or_primary_checkout_or_discover}}.
Worktree cleanup: {{worktree_cleanup_policy_or_automatic_after_verified_merge}}.
Completion mode: {{completion_mode_or_false}}.
Operating profile: {{operating_profile_or_one-human}}.
Integration mode: {{integration_mode_or_project-policy}}.
Legacy baseline SHA: {{legacy_baseline_sha_or_discover}}.
Protected governance paths: {{protected_governance_paths_or_project-policy}}.
Standing merge authority: {{standing_merge_authority_or_project-policy}}.
Supervisor rotation limits: {{supervisor_rotation_limits_or_default}}.

The target HRM, not a list of lanes, is the work session's controlling objective. It
must resolve from the complete-as-presently-knowable, versioned project HRM map. Obey
every applicable AGENTS.md, approved system plan, milestone contract, and lane contract.
Do not ask the operator to enumerate lanes. If the map or target is undefined or not
independently closable, the canonical planning package is absent, the bundle is absent,
or the bundle cannot plausibly satisfy the milestone outcome, return control to the
system-build playbook for rebaseline. Do not discover, create, silently enlarge, or begin
additional lanes in this execution playbook. A manual bundle cannot suppress that return.

A task or conversation is not a Git change unit. Attach it to this HRM session and a
published change unit before creating Git state. Use one branch per published change unit.
Create a worktree only when concurrency, an active review runtime, or preservation of unique
unmerged work requires it. Treat approved repository policy at the current main SHA as the
durable automation authority. Record a contradiction instead of silently selecting between
conflicting instructions.

AUTHORITY AND ROLES

1. The coordinator or merge supervisor owns the milestone-session ledger, authority
   classification, lane dependencies, worktrees, assignments, evidence, human gates,
   correction decisions, integration order, cleanup, continuity, and report. A
   deterministic merge controller, when configured, is the routine integration writer.
2. The system-build playbook owns HRM definition, gap analysis, lane creation or
   rebaselining, contract-update requests, findings disposition, and the canonical
   milestone package. The lane coordinator executes only the published bundle and
   returns scope-changing discoveries to that owner.
3. Give builders only applicable rules, lane spec, worktree, branch, exact base/head,
   allowed files, checker, assigned HRM, and bounded assignment. Builders edit; contract
   auditors and reviewers are read-only. Agents never count as human approvers.
3a. Builders route every semantic, authority, contract, identity, lifecycle, scope, UX-
    intent, capability-retirement, or possible new-HRM discovery to the coordinator. The
    coordinator deduplicates and classifies it S0-S3 before any operator notification.
    Workers do not independently ask the operator or select a silent business default.
4. Apply the operating profile explicitly. In ONE HUMAN mode, agents never count as the
   human approver and routine policy-compliant integration may be automatic. In TWO
   HUMANS mode, protected or high-risk changes require the non-authoring human when
   project policy says so. In MANY COLLABORATORS mode, use ownership review, protected
   rules, and a hosted merge queue when available. Human review is required only by the
   HRM contract, risk or protected-path policy, a classified exception, or reserved
   business/production authority. Routine lane-level UI approval is not a substitute
   for the prepared HRM function/UI/UX review.
5. Keep full logs in the PR or an artifact. Require compact handoffs with target HRM,
   state, exact SHA, policy SHA, evidence, findings, unresolved decisions, exception
   class, cleanup disposition, and next authorized action.

ESTABLISH THE MILESTONE SESSION

6. Fetch and reconcile current main, then read applicable repository policy, system
   plan, complete project HRM map and version, target milestone contract, requirements,
   implementation manifest, contracts, contract-update requests, input records, brownfield
   capability/parity inventory or explicit not-applicable record, system-node registry,
   decisions, findings, published lane
   specs, and predecessor handoffs. Prove the target HRM exists in the map and has one
   independently closable outcome, review questions, closure criteria, closure effect,
   authority envelope, activation posture, downstream release effect, and lane bundle.
   If the canonical package is absent or silently incomplete, stop and return a rebaseline
   request; do not manufacture missing milestones or bridge readiness.
7. Record the lifecycle `planned -> executing -> review_ready -> in_review ->
   remediation -> awaiting_closure -> closed|deferred|blocked`. `review_ready` is a
   conspicuous hard human checkpoint, not completion or approval. Do not solve around
   failed operator behavior, begin remediation, or release work assigned to a later HRM
   while this milestone remains open and undispositioned.
8. When completion mode is enabled, record one adoption SHA on main and treat earlier
   history as the legacy baseline. Reconcile contradictory rules once in a register,
   including lane versus change-unit granularity, documentation publication, business
   approval versus merge authority, draft versus implementation-ready state, integration
   mode, and merge method. Build a completion manifest mapping every named lane or change
   unit to complete, deferred, cancelled, blocked_external, or active. Do not rewrite old
   merges, rename established lane IDs, or backfill historical evidence. Apply the new
   contract prospectively to open and future changes. For an affected established UI,
   require a capability/parity inventory that classifies required operator, advanced
   operator, developer/audit, intentionally superseded, and unknown capabilities. Do not
   accept simplification that makes required work unreachable without an approved HRM-
   level removal or relocation.
9. Maintain an operator-facing milestone banner throughout the session: system, current
   HRM, target HRM, milestone outcome, capabilities complete, capabilities remaining,
   blockers, contract-update requests, decisions requested, function review state,
   activation posture, integrated head, and next action. Lane progress is quiet supporting
   detail beneath this view unless it creates a classified HRM blocker.

PLAN THE PUBLISHED BUNDLE ONCE

10. Reconcile origin/main, worktrees, branches, PRs, CI, lane states, dependencies, and
    file ownership for the published bundle. A legacy approved bundle or manual bundle
    may narrow execution but may not silently replace the canonical milestone contract,
    suppress a required input
    record/disposition, or keep a later production-observation/autonomy lane active before
    its prerequisites exist.
11. Record each lane's requirement and milestone coverage, contract, state, dependencies,
    base, worktree, branch, owned files, checker, validation class, risk, reviewer policy,
    PR/head, merge policy, policy SHA, order, cleanup disposition, timing, exception
    class, and next action in the milestone-session ledger.
12. Classify lanes as QUICK, SERIAL, PARALLEL, or CRITICAL. Parallel implementation
    requires proven dependency and ownership independence. Name safe parallel pairs;
    otherwise overlap only read-only preparation, CI, review, or acceptance setup.

PROVE READINESS BEFORE CODING

13. A read-only contract audit must reconcile each next eligible lane against current
    main and the target HRM. Prove its sources/adapters, reads, write gates, transition
    and recovery hooks, session/completion rules, outbox/artifact ownership, allowed
    files, policies, provider state, checker, test plan, and milestone acceptance
    contribution are explicit and implementable. Confirm secrets, PII, mutation,
    rollback, and read-back boundaries. When a lane touches a standalone, local, manually
    operated, provider-managed, or non-Git bridge, verify its first-class system-node
    identity, contract and deployment owners, canonical workflow, versioned interface,
    readiness evidence, topology, configuration, start/restart, health, recovery,
    rollback, and reconciliation. Never create a consumer worktree as a proxy for it.
    Confirm the session's semantic-readiness gate passed and the disposable end-to-end
    proof was reviewed or explicitly ruled unnecessary; the lane cannot compensate for
    an unresolved semantic decision or an unreviewed riskiest seam.
14. Complete the exact test plan below, then mark the lane READY, READY WITH APPROVED
    AMENDMENT, or BLOCKED. A merely planned, contradictory, unknown-contract, or test-
    unspecified lane does not enter implementation.
15. Batch foreseeable gaps into one amendment packet: observed reality, effect on the
    target HRM, proposed correction, files/owners, alternatives, safe default, and
    recommendation. A missing or inadequate inter-system promise becomes a stable `CTRQ`
    routed to the system-build or contract owner; the request records the unknown and
    blocks dependent work but never supplies the missing answer. Return material HRM-
    meaning changes to the system-build playbook. An existing mandatory checker remains
    binding; if disproportionate, amend the lane contract explicitly instead of silently
    bypassing or repeatedly running it. For any input requirement, freeze the smallest
    boundary and return a stable record with observation, affected HRM/requirement/scenario,
    safe posture, evidence, owner, consequence, and permitted independent work. Its primary
    disposition is human decision, `CTRQ`, read-only discovery, planning amendment,
    accepted limitation, named-HRM deferral, or `blocked_external`.
15a. S0 covers protected, irreversible, privacy/security, customer/money, and action-time
     production authority: freeze and notify immediately. S1 covers business meaning,
     authority, identity, UX intent, correctness-gap acceptance, or capability retirement:
     notify before assumption or non-disposable work. S2 is material but schedulable and is
     delivered in a bounded batch. S3 is a reversible technical choice inside accepted
     semantics and is decided and recorded without operator interruption.
15b. Each S0-S2 packet records first observed/foreseeable/notified times, invalidation reach,
     evidence and expiry, latest-safe-decision time, recommendation, no more than three
     alternatives, consequences, safe posture, permitted continuation, authority, and reply
     syntax. A timeout is not acceptance. Read the response back as exact meaning, scope,
     exclusions, affected records, and expiry before resuming.
15c. If the discovery may create a distinct operator outcome, acceptance, closure/release
     effect, or authority/evidence state, return an `HRM_DISCOVERY` proposal to system build.
     Freeze the affected boundary and do not create a branch, worktree, or lane for the
     proposed HRM until a superseding map version is accepted and published.

SELECT THE EXACT TEST PLAN

Testing follows changed behavior and dependency reach, not filenames alone. A CSS file
can alter accessibility or interaction; a JavaScript edit can be presentational, local
application behavior, or critical shared logic; a data file can be an inert fixture or
authoritative production input. Before building:

- Map every changed surface, directly affected consumer, public contract, persisted or
  external side effect, and risk modifier. Apply the union of all required checks. The
  highest-risk known surface determines the provisional lane validation class; lower-risk
  checks are not discarded. Confirm or raise the class from the final diff at freeze.
- For each check, record the exact repository-native command or deterministic scenario,
  when it runs (iteration, frozen candidate, integrated release), its expected signal,
  artifact, timeout, fixtures/environment, and mutation safety. `run tests` or `test
  affected code` is not a test plan.
- Map every acceptance criterion and changed invariant to positive, negative/error, and
  boundary coverage where applicable. Record a justified NOT APPLICABLE entry for a
  category that does not apply. An untested required behavior is a visible gap, not an
  implicit pass.
- Every code or data lane gets an allowed-file diff check; configured formatting/lint;
  compilation, build, or type-check for each changed language/toolchain; focused tests
  for changed behavior; every mandatory checker; and a clean runtime/console smoke when
  the change executes in an application. Do not invent a command when the repository
  lacks one: add the smallest deterministic test if it is in scope, or block on a test-
  contract amendment.

Required checks by changed surface:

Within a selected surface, run each check that can detect a plausible regression from
the diff and mark the others NOT APPLICABLE with a bounded reason. `The preview looked
fine` and `the change is small` are not reasons to omit a relevant check.

- CSS, styling, and static visual presentation: parse/build and configured style lint;
  targeted screenshots at affected and canonical responsive widths; overflow, clipping,
  wrapping, visibility, stacking, and theme smoke; keyboard tab order, visible focus,
  and automated accessibility smoke. Add contrast checks when color changes, reduced-
  motion checks when motion changes, and print/high-zoom checks only when those modes are
  supported or affected. Add targeted supported-browser smoke when browser-specific CSS
  or layout primitives change. No unit or repository-wide suite is required solely for
  CSS.
- HTML, templates, and component markup: compile/render; semantic structure, accessible
  names, labels, roles, heading order, link/form targets, keyboard order, and hydration/
  console smoke. Add targeted browser scenarios for any interactive element. Snapshot
  tests supplement behavior checks but never replace them.
- JavaScript or TypeScript: first classify the behavior. Pure calculations or selectors
  require unit tests for normal, empty, boundary, and invalid input. DOM/control changes
  require lint/type-check/build plus pointer and keyboard browser scenarios, state and
  disclosure assertions, duplicate-handler protection, and clean console/network output.
  Async requests, routing, stores, or form submission additionally require success,
  validation failure, server/network failure, timeout/cancel, retry or double-submit,
  stale-response, and contract serialization tests where those states exist. Shared or
  public JS/TS follows the core/shared rules below. Add supported-browser smoke when the
  edit depends on browser APIs, storage, navigation history, or event-model differences.
- Backend domain or service logic: unit-test each changed invariant and decision branch
  with representative, boundary, invalid, and denied inputs; test state transitions and
  error mapping; integrate with each changed repository/gateway through fakes or disposable
  local services; then run the affected package suite. Shared domain behavior, public
  contracts, or effects that cannot be bounded trigger the repository-wide suite.
- Pure data parsing, normalization, calculation, or export: schema validation and fixture
  tests for representative, empty/null, malformed, duplicate, boundary, and large-enough
  inputs; domain invariants; deterministic ordering; deduplication; precision, rounding,
  locale, and time-zone behavior when relevant; and round-trip tests for reversible
  formats. Use property/invariant tests when the input space is combinatorial.
- Reference, generated, or bulk data: all applicable pure-data checks plus provenance,
  uniqueness/referential integrity, expected count/range checks, stable digest or diff,
  generator reproducibility, and at least one real consumer smoke. Never validate only
  that the file parses.
- Persistence, cache, schema, or migration: all applicable data checks plus integration
  tests on a disposable store for transaction atomicity, idempotent replay, duplicate
  prevention, concurrent access, partial failure, restart/recovery, and exact read-back.
  Prove forward migration and compatibility with the prior supported state; prove rollback
  or the approved recovery path on a copy/fixture, with before/after counts and invariants.
  Never use production/customer data. Schema or shared persistence changes trigger the
  full suite.
- Package-private refactor or file/module move with no public-contract change: compile/
  type-check, import/startup smoke, focused invariant tests, the affected package suite,
  and direct-consumer integration smoke. Prove behavior equivalence; do not rely on a
  diff that merely looks mechanical.
- Shared core, public API, routing/state-machine structure, dependency injection, build
  configuration, or dependency/lockfile changes: public compatibility/contract tests,
  core invariant tests, all direct-consumer integration suites, clean startup and build,
  and the repository-wide suite. Dependency changes also require lockfile consistency
  and a reproducible clean install/build in CI; apply security/license checks required by
  project policy.
- API, authentication, authorization, provider, or external-write paths: test success,
  invalid input, unauthenticated/unauthorized, not-found/conflict, timeout, rate-limit,
  duplicate/replay, partial failure, and response serialization as applicable. Use fakes
  or mutation-disabled dry runs for provider calls, then require idempotency, reconcile-
  before-retry, exact provider read-back, full-suite, and separately approved canary/
  rollback gates before live effects.
- Documentation, schemas, examples, or contract mirrors: parse and schema validation,
  configured documentation lint/link checks, executable example or command smoke, and a
  repository search proving canonical and mirrored references agree. Documentation-only
  work does not trigger application tests unless it changes generated/runtime inputs.
- Configuration, flags, and environment handling: parse/schema checks; defaults; missing,
  malformed, unknown, and conflicting values; safe-off behavior; secret/PII non-disclosure;
  and startup smoke for each supported mode affected by the change.

Add cross-cutting checks whenever the changed behavior includes the modifier:

- accessibility: keyboard-only path, focus order/restoration, accessible name/state,
  automated scan, and manual screen-reader semantics for a changed critical journey;
- money, quantity, date, or time: units/currency, precision/rounding, min/max/zero/negative,
  calendar boundaries, time zones, and deterministic serialization;
- identity, permissions, secrets, or PII: isolation, deny-by-default, role boundaries,
  redaction/logging, forged/stale identity, and cross-record access denial;
- untrusted input or a security boundary: encoding/escaping and the applicable injection,
  cross-site request, open-redirect, path traversal, or server-side request tests for the
  changed layer; never claim security from validation of the happy path alone;
- concurrency, retry, queue, or cache: races, duplicate delivery, ordering, stale data,
  lock/transaction boundaries, crash/restart, idempotency, and reconciliation;
- scale or hot-path performance: representative-volume timing/memory and a recorded
  threshold when the lane changes complexity, query count, payload size, or render load.

If a focused test exposes an unexpected consumer or cross-component failure, stop and
expand the dependency map and validation class; do not dismiss it as unrelated without
reproducing it on the exact base. A candidate failure may be called pre-existing only
with base/head commands and outputs recorded. Do not rerun a flaky failure until green
and omit the failed attempts.

At candidate freeze, reconcile planned versus executed checks. A missing, skipped,
expected-failure, timed-out, unavailable, or artifact-less required check is an unsatisfied
gate unless the contract explicitly accepts it. Report exact pass/fail/skip counts and
review new warnings. A bug fix requires a regression test that demonstrates the prior
failure when safe and feasible. Do not weaken assertions, delete coverage, or approve
changed snapshots/goldens merely to make the lane green; bind an intentional expectation
change to the contract and human acceptance.

RUN THE FASTEST SAFE FLOW

16. Assign one builder per released lane. Multiple builders may run only for lanes
    proved PARALLEL and READY. During serial work, use a free slot for the next lane's
    read-only readiness audit, checker preparation, or acceptance scenarios.
17. Builders stay inside approved files and behavior, preserve safety seams and human
    control, add tests, and run focused checks. An undeclared file, policy, dependency,
    contract, HRM obligation, or external write returns to the coordinator as a scope
    divergence and stable input requirement; it is not absorbed into the active lane or
    hidden because a manual queue forbids new records.
18. During active human UI/UX design, keep one preview live and batch operator feedback.
    Do not freeze a candidate, start exact-head review, push a candidate commit, or run
    a repository-wide suite after each presentational adjustment. Apply the batch through
    hot reload, retain the operator's design feedback as iteration history, and freeze
    only when the operator declares the design batch ready. These previews are informal
    checkpoints inside the milestone session and do not open or close the HRM.
19. At candidate freeze—or the operator-declared design freeze for a UI lane—classify
    the final diff and apply its validation class. For a brownfield UI, first reconcile
    the candidate against the required parity inventory and prove every retained operator
    journey remains reachable; missing established capability blocks candidate freeze:

    - UI PRESENTATION — CSS, spacing, static wording, labels, visual grouping, or button
      placement. During iteration use live preview and human review. At freeze run
      build/lint, responsive visual smoke, and keyboard/focus checks. The operator is
      the primary UI/UX reviewer; no independent code-review agent is required.
    - UI INTERACTION — bounded changes to existing controls, existing-action arrangement,
      or disclosure behavior, including reducing seven controls to three without changing
      the underlying action semantics. During iteration use a live functional walkthrough.
      At freeze run targeted browser scenarios for affected actions, confirm remaining
      controls invoke the intended actions, and prove removed controls are neither visible
      nor keyboard-reachable. Use one targeted reviewer or one deterministic browser
      scenario; do not run the full suite by default.
    - APPLICATION BEHAVIOR — form handling, routes, state transitions, persistence, or
      API contracts. Run focused tests during implementation; at freeze run the lane
      checker and the affected package suite, with one independent reviewer normally.
    - CRITICAL INTEGRATION — QBO sends, GHL writes, identity, concurrency, authentication,
      or financial/customer effects. Run focused tests and mutation-disabled dry runs
      during implementation; at freeze require the full suite, exact-head review,
      provider readiness/read-back, and separately approved canary gates. Use at most
      two independent reviewers.
    - RELEASE BUNDLE — several merged lanes approaching activation. It has no design-
      iteration validation; run the full suite once against the integrated exact head.

20. Freeze one acceptance commit, verify its ownership boundary, run the applicable
    checks plus every still-mandatory lane checker, push, and bind the PR body, human
    acceptance, automated evidence, and required review to the candidate head SHA.
21. Run applicable CI and risk-scaled exact-head review concurrently. Blocking findings
    require a violated invariant plus a reproduction, failing test, or concrete contract
    mismatch. A presentation-only lane needs lightweight automated visual/accessibility
    evidence; operator acceptance occurs against the integrated HRM function/UI/UX
    journey, not as a separate lane-management gate.
22. A repository-wide suite is required only when at least one of these is true:

    - shared domain, contract, persistence, authentication, or provider code changed;
    - a public API, schema, state transition, or dependency changed;
    - the affected surface cannot be bounded confidently;
    - targeted checks reveal unexpected cross-component coupling;
    - the approved lane checker explicitly requires it;
    - the exact head is being prepared for a canary, deployment, or release; or
    - several lighter-weight lanes are integrated for one combined regression run.

    CSS, static wording, layout, responsive spacing, and bounded control simplification
    do not independently trigger a full suite. Escalate immediately if targeted checks
    show that a supposedly isolated UI change is coupled to deeper behavior.
23. Deduplicate and reproduce findings, then send one correction batch. A new commit
    makes the prior SHA no longer the exact head and invalidates evidence or approval
    that claims that candidate or covers its changed surface; it does not erase reusable
    contract facts or operator feedback from design iteration. Reclassify the new diff
    and rerun only its applicable checks and reviews. A blocking exact-head review that
    reproduces a real defect and fails closed is a healthy implementation control, not by
    itself a planning failure; preserve the stop and separately return any contributing
    planning/decomposition weakness. After two material correction
    rounds, stop patch cycling and reassess readiness, decomposition, and contract.

INTEGRATE AND VERIFY

24. A PR is ELIGIBLE only when its current base, merge policy, lane contract, target-HRM
    coverage, dependencies, scope, mandatory exact-head checks, review policy, protected
    paths, current head SHA, and clean merge state all pass. `Ready for review` means
    implementation completeness, not business approval or milestone closure.
25. Use exactly one integration writer: a hosted merge queue, deterministic expected-head
    controller, or coordinator in manual mode. The merge call must bind the expected
    head SHA and record checked base/head, policy version, CI run, review/audit evidence,
    merge identity, operator, and decision mode. A reasoning task supervises exceptions;
    it does not race the integration writer.
26. Marking an implementation-complete PR ready, applying routine labels, updating a
    clean base, retrying one transient CI failure, enabling auto-merge, merging an
    eligible PR, recording evidence, and removing its eligible worktree are preauthorized
    only when repository policy and standing merge authority allow them. Keep merge
    authority separate from business, milestone, canary, deployment, and production
    authority.
27. If a branch is behind but clean, update and recheck it according to project policy.
    Classify unresolved conditions as needs-human-ci, needs-human-conflict,
    needs-human-governance, needs-human-evidence, or controller-stuck. Never weaken a
    check, auto-resolve a content conflict, invent evidence, or merge under stale state.
28. Before every serialized merge decision, fetch and re-read origin/main and verify the
    head and gates. Merge one dependency-ordered candidate, read back the remote merge
    and main SHA, wait for required post-merge CI, and record a compact handoff before
    releasing the next. Reconcile any ambiguous mutation result before retrying.

PREPARE AND REVIEW THE TARGET HRM

29. Once the published bundle is integrated, validate the integrated exact head. For a
    bundle of lighter-weight lanes, run scoped lane checks and one combined regression
    suite at this boundary when the milestone contract or full-suite triggers require
    it. Run the full suite again before any production canary or release.
30. Publish one milestone review package containing the project HRM map version, system
    and target HRM; milestone outcome and decisions requested; capabilities completed in
    operator language; exact
    integrated revision and configuration; live preview or deterministic scenarios;
    tests aggregated by validation class; brownfield parity evidence and exceptions;
    affected standalone/local system-node readiness and deployment boundaries; limitations
    and blockers; external-mutation and activation posture; open input requirements and
    their dispositions; open/resolved/blocking contract-update requests;
    cleanup/integration receipt; provisional downstream impact; explicit operator
    function/UI/UX acceptance fields; and the exact effect of closure. Move the session
    to REVIEW READY, make the stop noisy, and pause for the operator. A visible UI,
    completed lane list, or ended meeting is not function acceptance or HRM closure.
31. Interrupt the human at the earliest classified need: immediately for S0; before
    assumption or non-disposable work for S1; in a bounded batch for S2; and at the noisy
    `review_ready` stop for prepared milestone/UI/UX/function acceptance. Also interrupt
    for persistent CI/content conflict or action-time canary, external/production mutation,
    deployment, credential/permission, or irreversible-migration approval. Routine S3
    choices, merge, and cleanup inside standing authority are not human gates. A `CTRQ`
    resolvable by approved contracts or read-only discovery need not interrupt; one needing
    new business meaning follows S1/S2 timing rather than waiting for milestone review.
32. Record review findings append-only with stable identifiers and return them to the
    system-build playbook for classification. Verified defects against already-approved
    requirements may become published remediation lanes and execute without another
    scope decision only after operator review or explicit finding disposition. Missing
    functions, policy or authority changes, new persistence or external effects, or
    changed milestone outcomes require one batched operator approval.
33. Keep the same milestone session and target HRM through approved remediation. Pause
    downstream work, execute only the published remediation bundle, revalidate affected
    evidence, rebaseline downstream specifications, and republish the review package.
    Do not silently enlarge the original lane or start a new milestone session.
34. Close or defer the HRM only on the operator's explicit decision after every finding
    has a classification, owner, blocking status, disposition, and required evidence,
    and after function/UI/UX acceptance is recorded as accepted, accepted with findings,
    or rejected.
    Closure makes the next published bundle eligible but does not start it. HRM closure
    never by itself authorizes a canary, provider write, deployment, migration, or
    production activation.

CLOSE AND RECONCILE WORKSPACES

35. Maintain one stable operator checkout and one current-review index for this project;
    workers never implement in the operator checkout. Before `review_ready`, the index must
    name target HRM, map version, outcome, decisions, exact review SHA, preview, blockers,
    HRM discoveries, activation posture, and next action. After each lane's remote-main and
    required post-merge checks are verified, inventory
    this project only with `git worktree list --porcelain`. Resolve every path to an exact
    absolute path under the current repository's registered worktrees. Never scan, prune,
    switch, or delete a sibling repository or a broad parent directory. Move the lane to
    CLEANUP PENDING; mark it COMPLETE only after the worktree is removed or retained with
    an exact, evidence-backed reason.
36. A lane worktree is automatically eligible for removal only when all are true:

    - the lane is terminal and its exact merge/main SHA was read back from the remote;
    - the branch head is an ancestor of `origin/main`; or a squash/cherry-pick merge has
      authoritative merged-PR read-back plus exact proof that every lane commit and owned-
      path change is incorporated or explicitly superseded on `origin/main`;
    - staged, unstaged, and untracked status is empty, and no nested repository/submodule
      contains uncommitted work;
    - ignored paths contain no non-reproducible review artifacts, training data, evidence,
      databases, exports, or operator files; disposable caches/dependencies are removable
      only when repository policy identifies them as reproducible;
    - no user-owned process, active milestone preview, or live review session depends on
      the worktree; and
    - the worktree is neither locked nor the designated operator checkout.

37. Dirty or ambiguous means RETAIN. Inspect staged, unstaged, untracked, ignored,
    submodule, and nested-repository state. Compare with `origin/main` when useful, but
    never assume a merged branch makes later working-tree changes disposable. Do not
    reset, clean, stash, overwrite, switch away, or use forced worktree removal. Record
    the exact unique diff/artifact or unresolved condition and the next recovery action.
38. Before removing an eligible worktree, stop only task-owned preview/test processes
    whose command and working directory identify that exact path. Do not kill a user-owned
    or ambiguous process. Use `git worktree remove <exact-absolute-path>` without `--force`;
    never use recursive filesystem deletion. Read back that the path is absent and run
    `git worktree prune` only for this repository's stale administrative records.
39. Worktree removal does not authorize local or remote branch deletion. Delete an
    incorporated branch only when repository policy explicitly permits it and remote merge/
    read-back plus unique-work checks pass. Otherwise preserve the branch reference.
40. Reconcile eligible worker worktrees immediately after verified integration rather than
    waiting for milestone closure. Classify every remaining worktree as active-current-HRM,
    retained-for-review, unique-unmerged-recovery, cleanup-eligible, or unexplained-blocker.
    Put the operator checkout into the project-defined review posture without discarding or
    overwriting user work. Never reset, force-switch, stash, or discard to normalize it.
41. Finish with a project-scoped cleanup receipt: worktrees removed with merge proof;
    worktrees retained with exact dirty/unmerged/locked/process/artifact reason; primary
    checkout path, branch, local SHA, remote SHA, clean status, and pull result; pruned
    administrative entries; preserved branches; and confirmation that no other project
    was touched. Do not claim complete cleanup while an unexplained worktree remains.

SUPERVISE AND HAND OFF

42. Durable state lives in live Git/hosting state, repository policy at main, checked-in
    milestone/change records, and one milestone-session ledger, in that order. Task
    context is a cache, not the audit record. Remain quiet while routine integration is
    healthy; alert only for a classified exception, the prepared HRM, reserved authority,
    or controller failure.
43. Rotate a long-running supervisor at configured limits, defaulting to 20 merge
    decisions, 14 days, 3 exception investigations, policy-version change, context
    compaction, or inability to reconstruct state from live evidence. Reconcile live
    state, record exact heads and next actions, and ensure exactly one integration writer
    survives the handoff.

MEASURE AND REPORT

44. Timestamp session readiness, lane readiness/build, UI iteration, design freeze,
    checks, CI/review, corrections, integration, milestone-review readiness, human wait,
    remediation, closure, post-merge verification, and cleanup. Separate active,
    automated-wait, and human-wait time.
45. Report the target HRM first: outcome, status, capabilities complete/remaining,
    review decisions, findings, integrated head, activation posture, closure effect, and
    next action. Report completed, blocked, deferred, cancelled, blocked-external, and
    unmerged lanes as supporting detail with branch, PR, exact head, validation evidence,
    merge/main SHA, cleanup disposition, external mutations, and timing.
46. State the critical path, useful parallel work, avoidable delay, routine interruptions
    avoided, and one improvement for the next milestone session. Never describe a draft,
    local test, notification, proposal, visible UI, queued merge, or closed planning gate
    as merged, deployed, activated, or production-verified evidence.
```

## Machine-readable ledger contract

```yaml
milestone_session:
  id: "{{session_id}}"
  system_reference: "{{system_reference}}"
  hrm_map:
    path: "{{path}}"
    version: "{{version}}"
    complete_as_presently_knowable: true
    evidence_cutoff_at: null
  source_documents:
    system_plan: null
    implementation_manifest: null
    requirements_ledger: null
    brownfield_capability_inventory: null
    system_node_registry: null
  current_hrm: null
  target_hrm: "{{target_hrm}}"
  milestone_contract: "{{path}}"
  milestone_outcome: "{{operator_visible_outcome}}"
  closability:
    independently_closable: false
    composite_states: []
  status: "planned|executing|review_ready|in_review|remediation|awaiting_closure|closed|deferred|blocked"
  review_questions: []
  closure_criteria: []
  closure_effect: null
  downstream_release_effect: null
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
  hrm_discoveries:
    observed: []
    returned_to_system_build: []
    accepted_map_version: null
  operator_banner:
    capabilities_complete: []
    capabilities_remaining: []
    blockers: []
    decisions_requested: []
    contract_update_requests: []
    input_requirements: []
    function_review_state: "not_ready|review_ready|in_review|accepted|accepted_with_findings|rejected"
    integrated_head_sha: null
    next_action: null
  published_lane_bundle: []
  legacy_approved_lane_bundle: []
  manual_lane_constraint: []
  completion_mode: false
  adoption_sha: null
  legacy_baseline_sha: null
  policy_sha: null
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
    candidate_reachability_evidence: []
  system_nodes:
    - id: "{{system_node_id}}"
      kind: "repository|local_bridge|daemon|desktop_process|provider|manual_service|other"
      contract_owner: null
      deployment_owner: null
      canonical_location: null
      workflow: "git|non_git|provider_managed|manual|unknown"
      interface_versions: []
      readiness_evidence: []
      deployment_boundary: null
  operating_profile: "one-human|two-human|many-collaborators"
  integration:
    mode: "manual|expected-head-controller|hosted-merge-queue"
    writer: null
    standing_merge_authority: null
    protected_governance_paths: []
  review_package:
    status: "not_started|draft|published|superseded|accepted|deferred"
    path_or_url: null
    review_head_sha: null
    configuration_profile: null
    scenarios: []
    known_limitations: []
    test_evidence: []
    brownfield_parity_evidence: []
    system_node_readiness: []
    input_requirements: []
    external_mutations: 0
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
    released_next_bundle: []
    operator_function_acceptance:
      decision: "pending|accepted|accepted_with_findings|rejected"
      decided_by: null
      decided_at: null
      evidence: []
  supervisor:
    generation: 1
    task_id: null
    ledger_url: null
    decisions_supervised: 0
    exception_investigations: 0
    rotate_after_decisions: 20
    rotate_after_days: 14
    rotate_after_exceptions: 3

lanes:
  - id: "{{lane_id}}"
    change_id: "{{change_id_or_lane_id}}"
    assigned_hrm: "{{target_hrm}}"
    milestone_contribution: []
    state: "queued|readiness_audit|blocked_contract|awaiting_amendment_approval|ready_to_build|building|design_iteration|candidate_frozen|checking|reviewing|correcting|eligible|merging|verifying_main|cleanup_pending|complete|deferred|cancelled|blocked_external|blocked"
    classification: "quick|serial|parallel|critical"
    validation_class: "ui_presentation|ui_interaction|application_behavior|critical_integration|release_bundle"
    design_phase: "not_applicable|iterating|frozen"
    contract: "{{path}}"
    dependencies: []
    base_sha: null
    workspace_necessity: "none|concurrent_execution|active_review_runtime|unique_work_preservation"
    worktree: null
    branch: null
    allowed_files: []
    checker: null
    test_plan:
      changed_surfaces: []
      affected_consumers: []
      changed_invariants: []
      risk_modifiers: []
      acceptance_coverage:
        - criterion: "{{criterion}}"
          positive_check_ids: []
          negative_check_ids: []
          boundary_check_ids: []
      checks:
        - id: "{{check_id}}"
          phase: "iteration|frozen_candidate|integrated_release"
          command_or_scenario: "{{exact_command_or_scenario}}"
          expected_signal: "{{expected_result}}"
          artifact: "{{artifact_or_log}}"
          mutation_safety: "none|fake|disposable_local|dry_run|approved_live"
      not_applicable: []
      full_suite:
        required: false
        triggers: []
      execution_reconciliation:
        candidate_head_sha: null
        passed: []
        failed: []
        skipped: []
        timed_out: []
        new_warnings: []
    reviewer_requirement: null
    deterministic_review_scenario: null
    pr: null
    candidate_head_sha: null
    checked_base_sha: null
    checked_head_sha: null
    implementation_complete: false
    handoff_complete: false
    merge_policy: "automatic|human"
    policy_sha: null
    exception_class: null
    correction_round: 0
    merge_sha: null
    main_sha: null
    external_mutations: 0
    worktree_cleanup:
      candidate_path: null
      merge_proof: "ancestor|merged_pr_content_equivalence|unproved"
      status_clean: false
      nested_repositories_clean: false
      ignored_audit_complete: false
      preservation_sensitive_ignored_paths: []
      process_audit_complete: false
      active_milestone_preview: false
      locked: false
      eligible: false
      disposition: "pending|removed|retained_dirty|retained_unmerged|retained_locked|retained_process|retained_artifact|retained_preview|retained_primary|blocked"
      retained_reason: null
      path_absent_readback: false
      branch_preserved: true
    next_authorized_action: readiness_audit

milestone_cleanup:
  policy: automatic_after_verified_merge
  project_root: null
  operator_checkout: null
  current_review_index: null
  expected_main_sha: null
  local_main_sha: null
  remote_main_sha: null
  operator_checkout_ready: false
  fast_forward_pull: "pending|passed|blocked"
  removed_worktrees: []
  retained_worktrees:
    - path: null
      reason: null
      recovery_action: null
  unexplained_worktrees: []
  pruned_administrative_entries: []
  preserved_branches: []
  no_other_project_touched: false
```

## Change note

- **4.0 — 2026-08-24:** Generalizes ownership; makes tasks distinct from published Git
  change units; makes worktrees conditional; establishes one stable operator checkout and
  current-review index; adds worker-to-orchestrator S0-S3 escalation, semantic read-back,
  and early HRM-discovery return; and reconciles workspaces after verified integration.
- **3.2 — 2026-08-22:** Requires an independently closable target and complete brownfield
  planning package, validates established UI parity and standalone/local system nodes,
  returns stable input-boundary dispositions despite manual queue constraints, and
  preserves healthy fail-closed exact-head defect review while routing upstream planning
  weaknesses separately.
- **3.1 — 2026-08-21:** Requires the complete inception-time HRM map and map version,
  routes missing inter-system promises through non-adopting `CTRQ` records, keeps routine
  lane execution quiet, makes `review_ready` a noisy hard stop, and moves explicit
  function/UI/UX acceptance and remediation disposition to the integrated HRM level.
- **3.0 — 2026-08-21:** Makes the target HRM the work-session objective and lanes derived execution units; adds milestone readiness/review/remediation/closure states, operator-facing milestone reporting, prospective completion baselines, contradiction handling, operating profiles, deterministic single-writer integration, exception-only interruption, durable supervision, and safe project-scoped worktree cleanup. HRM closure remains separate from canary, deployment, provider-write, migration, and production authority.
- **2.2 — 2026-08-21:** Adds behavior-and-reach test selection with exact command/scenario planning, required checks for CSS/markup, JavaScript, backend logic, data transformations and datasets, persistence/migrations, private refactors, shared core/dependencies, APIs/providers, configuration, and documentation, plus cross-cutting risk modifiers, base-vs-head failure handling, and planned-versus-executed evidence reconciliation.
- **2.1 — 2026-08-21:** Separates live HOTL UI iteration from a frozen acceptance candidate; adds validation classes, explicit full-suite triggers, risk-scaled review, proportional SHA evidence invalidation, and integrated-head regression backstops while preserving mandatory lane checkers and critical integration gates.
- **2.0 — 2026-08-18:** Adds a pre-build readiness audit, one batched amendment packet, explicit serial/parallel classification, bounded coordinator/reviewer roles, consolidated corrections with a two-round reassessment threshold, prepared acceptance, phase timing, and critical-path reporting.
- **1.0 — 2026-08-18:** Initial queue-wide coordination, exact-head review, prepared human acceptance, and coordinator-enforced merge queue.
