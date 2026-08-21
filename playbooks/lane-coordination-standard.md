---
playbook_id: AP-LANE-001
title: Lane Planning and Execution Standard
version: "2.2"
status: active
owner: Alpine Structures
mode: lane-planning-and-execution
human_readable: true
machine_readable: true
required_inputs: [lane_list, objective]
optional_inputs:
  - required_order
  - authority_exceptions
  - human_review_requirements
  - target_time_or_priority
controls:
  - project-rules-first
  - bounded-scope
  - queue-dependency-graph
  - implementation-readiness-gate
  - dedicated-worktree
  - bounded-agent-context
  - exact-head-evidence
  - validation-classification
  - change-surface-test-matrix
  - hotl-design-batching
  - risk-based-review
  - release-boundary-regression
  - bounded-correction-loops
  - serialized-merges
  - post-merge-verification
  - human-review-gates
  - phase-timing-ledger
---

# Lane Planning and Execution Standard

Use this playbook to plan and execute a bounded queue of existing lanes at the
highest practical level of abstraction. The coordinator owns state, authority,
dependencies, evidence, validation class, and merge order; builders implement;
risk-scaled review verifies frozen candidates. Active human-on-the-loop UI design is
an iteration phase, not a sequence of acceptance candidates. Parallel coding is used
only when dependencies and file ownership prove independence. Otherwise, preparation,
CI, review, and acceptance setup overlap while the critical path remains serial.

## Inputs

- **Lanes:** `{{lane_list}}`
- **Objective:** `{{objective}}`
- **Required order:** `{{required_order_or_none}}`
- **Authority exceptions:** `{{authority_exceptions_or_none}}`
- **Human review:** `{{human_review_requirements_or_default}}`
- **Target time or priority:** `{{target_time_or_priority_or_none}}`

## Prompt

```text
Coordinate only these lanes: {{lane_list}}.

Objective: {{objective}}.
Required order: {{required_order_or_none}}.
Authority exceptions: {{authority_exceptions_or_none}}.
Human review: {{human_review_requirements_or_default}}.
Target time or priority: {{target_time_or_priority_or_none}}.

Obey every applicable AGENTS.md and approved lane contract. Do not discover, create,
or begin additional lanes. One lane remains one branch, one dedicated worktree, and
one PR unless the owning project explicitly requires otherwise.

AUTHORITY AND ROLES

1. The coordinator owns the queue ledger, authority, dependencies, worktrees, agent
   assignments, evidence, human gates, correction decisions, merge order, and report.
   It does not duplicate a broad code review; if it performs one, it counts toward
   the reviewer limit.
2. Give agents only applicable rules, lane spec, worktree, branch, exact base/head,
   allowed files, checker, and bounded assignment. Do not fork full chat history.
   Builders edit; contract auditors and reviewers are read-only.
3. Keep full logs in the PR or an artifact. Require compact handoffs with state,
   exact SHA, evidence, findings, unresolved decisions, and next authorized action.

PLAN THE QUEUE ONCE

4. Reconcile origin/main, worktrees, branches, PRs, CI, lane states, dependencies,
   and file ownership for the complete named queue. Build its dependency graph.
5. Record each lane's contract, state, dependencies, base, worktree, branch, owned
   files, checker, validation class, risk, reviewer requirement, human gate, PR/head,
   merge order, timing, and next action in one compact execution ledger.
6. Classify lanes as QUICK, SERIAL, PARALLEL, or CRITICAL. Parallel implementation
   requires proven dependency and ownership independence. Name safe parallel pairs;
   if none exist, say so and identify read-only preparation or gates that can overlap.

PROVE READINESS BEFORE CODING

7. A read-only contract auditor must reconcile the next eligible lane against current
   main before a builder starts. Prove that its sources/adapters, reads, write gates,
   transition and recovery hooks, session/completion rules, outbox/artifact ownership,
   allowed files, policies, provider state, checker, and human acceptance artifact are
   explicit and implementable. Confirm secrets, PII, mutation, rollback, and read-back
   boundaries.
8. Complete the exact test plan below, then mark the lane READY, READY WITH APPROVED
   AMENDMENT, or BLOCKED. A merely planned, contradictory, unknown-contract, or test-
   unspecified lane does not enter implementation.
9. Batch all foreseeable gaps into one approval packet: observed reality, proposed
   contract amendment, effects, files/owners, alternatives, safe default, and
   recommendation. Ask once, then update the authoritative contract before building.
   Design lane checkers to be risk-scaled. An existing mandatory lane checker remains
   binding; never silently skip it. If it is disproportionate, prepare one explicit
   lane-doc amendment for approval instead of repeatedly bypassing or running it.

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

10. Assign one builder per released lane. Multiple builders may run only for lanes
    proved PARALLEL and READY. During serial work, use a free slot for the next lane's
    read-only readiness audit, checker preparation, or acceptance scenarios.
11. Builders stay inside approved files and behavior, preserve safety seams and human
    control, add tests, and run focused checks. An undeclared file, policy, dependency,
    contract, or external write returns to the coordinator as a scope divergence.
12. During active human UI/UX design, keep one preview live and batch operator feedback.
    Do not freeze a candidate, start exact-head review, push a candidate commit, or run
    a repository-wide suite after each presentational adjustment. Apply the batch through
    hot reload, retain the operator's design feedback as iteration history, and freeze
    only when the operator declares the design batch ready.
13. At candidate freeze—or the operator-declared design freeze for a UI lane—classify
    the final diff and apply its validation class:

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

14. Freeze one acceptance commit, verify its ownership boundary, run the applicable
    checks plus every still-mandatory lane checker, push, and bind the PR body, human
    acceptance, automated evidence, and required review to the candidate head SHA.
15. Run applicable CI and risk-scaled exact-head review concurrently. Blocking findings
    require a violated invariant plus a reproduction, failing test, or concrete contract
    mismatch. A presentation-only lane needs lightweight automated visual/accessibility
    evidence and operator approval, not an independent code reviewer.
16. A repository-wide suite is required only when at least one of these is true:

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
17. Deduplicate and reproduce findings, then send one correction batch. A new commit
    makes the prior SHA no longer the exact head and invalidates evidence or approval
    that claims that candidate or covers its changed surface; it does not erase reusable
    contract facts or operator feedback from design iteration. Reclassify the new diff
    and rerun only its applicable checks and reviews. After two material correction
    rounds, stop patch cycling and reassess readiness, decomposition, and contract.

PREPARE HUMAN ACCEPTANCE

18. Interrupt the human only for one batched contract/scope decision; a prepared UI,
    UX, or functional review; an unresolved authority decision; or action-time approval
    for a canary, external/production mutation, deployment, or irreversible migration.
19. During UI design, present the live working tree as an explicitly non-frozen preview
    and collect feedback in batches. At freeze, present the exact head and only the
    needed judgment with expected outcomes, known limits, safety state, and a suitable
    artifact: running local UI plus script, deterministic functional scenarios, or
    mutation-disabled provider dry run/read-back. Prior discussion, iteration feedback,
    a lane doc, or a general instruction to finish is not action-time approval for an
    external or irreversible operation.

SERIALIZE AND VERIFY MERGES

20. One coordinator is the only merger. A PR is READY TO MERGE only when its exact
    head has all applicable checks, every mandatory checker, required CI, risk-scaled
    review, human approval, scope, ownership, and dependencies. Git supplies merge
    primitives; the coordinator is the queue unless a hosted merge queue is explicitly
    enabled.
21. Before every merge, fetch and re-read origin/main and verify the PR head and gates.
    Merge one PR, read back the remote merge/main SHA, wait for required post-merge CI,
    and record a compact handoff before releasing the next. Reconcile any ambiguous
    mutation result before retrying.

MEASURE AND REPORT

22. Timestamp readiness, build, UI iteration, design freeze, check, CI/review, correction
    rounds, human wait, merge, and post-merge verification. Separate active, automated-
    wait, and human-wait time.
23. Report completed, blocked, and unmerged lanes separately with branch, PR, final
    head, validation class, gates, correction rounds, human decision, merge/main SHA,
    external mutations, elapsed-time breakdown, and next action. State the critical
    path, useful parallel work, avoidable delay, and one process improvement for the
    next run.
24. For a queue of lighter-weight lanes, use scoped lane checks and one combined full-
    suite run after integration. Run the full suite again before any production canary
    or release.
25. Never describe a draft, local test, notification, proposal, visible UI, or queued
    merge as merged, deployed, activated, or production-verified evidence.
```

## Machine-readable ledger contract

```yaml
lane:
  id: "{{lane_id}}"
  state: "queued|readiness_audit|blocked_contract|awaiting_amendment_approval|ready_to_build|building|design_iteration|candidate_frozen|checking|reviewing|correcting|awaiting_human_acceptance|ready_to_merge|merging|verifying_main|complete|blocked"
  classification: "quick|serial|parallel|critical"
  validation_class: "ui_presentation|ui_interaction|application_behavior|critical_integration|release_bundle"
  design_phase: "not_applicable|iterating|frozen"
  contract: "{{path}}"
  dependencies: []
  base_sha: null
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
        surface: "{{changed_surface}}"
        phase: "iteration|frozen_candidate|integrated_release"
        command_or_scenario: "{{exact_command_or_scenario}}"
        expected_signal: "{{expected_result}}"
        artifact: "{{artifact_or_log}}"
        timeout_seconds: null
        fixtures_environment: "{{isolated_fixture_and_runtime}}"
        mutation_safety: "none|fake|disposable_local|dry_run|approved_live"
    not_applicable:
      - category: "{{test_category}}"
        reason: "{{bounded_reason}}"
    full_suite:
      required: false
      triggers: []
    base_reproduction: null
    execution_reconciliation:
      candidate_head_sha: null
      passed: []
      failed: []
      skipped: []
      timed_out: []
      new_warnings: []
  reviewer_requirement: null
  reviewer_count: null
  deterministic_review_scenario: null
  human_milestone: null
  operator_design_ready: false
  pr: null
  candidate_head_sha: null
  correction_round: 0
  merge_sha: null
  main_sha: null
  external_mutations: 0
  next_authorized_action: readiness_audit
  timing:
    readiness_started_at: null
    readiness_finished_at: null
    build_started_at: null
    candidate_frozen_at: null
    human_wait_seconds: 0
    automated_wait_seconds: 0
    completed_at: null
```

## Change note

- **2.2 — 2026-08-21:** Adds behavior-and-reach test selection with exact command/scenario planning, required checks for CSS/markup, JavaScript, backend logic, data transformations and datasets, persistence/migrations, private refactors, shared core/dependencies, APIs/providers, configuration, and documentation, plus cross-cutting risk modifiers, base-vs-head failure handling, and planned-versus-executed evidence reconciliation.
- **2.1 — 2026-08-21:** Separates live HOTL UI iteration from a frozen acceptance candidate; adds validation classes, explicit full-suite triggers, risk-scaled review, proportional SHA evidence invalidation, and integrated-head regression backstops while preserving mandatory lane checkers and critical integration gates.
- **2.0 — 2026-08-18:** Adds a pre-build readiness audit, one batched amendment packet, explicit serial/parallel classification, bounded coordinator/reviewer roles, consolidated corrections with a two-round reassessment threshold, prepared acceptance, phase timing, and critical-path reporting.
- **1.0 — 2026-08-18:** Initial queue-wide coordination, exact-head review, prepared human acceptance, and coordinator-enforced merge queue.
