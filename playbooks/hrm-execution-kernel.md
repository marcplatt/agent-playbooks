---
playbook_id: AP-EXEC-001
title: Compact HRM Execution Kernel
version: "0.1.0-rc.2"
status: experimental
owner: Adopting organization
mode: self-contained-bounded-hrm-execution
human_readable: true
machine_readable: true
required_inputs: [repository_policy, accepted_project_hrm_map]
derived_inputs: [target_hrm_contract, execution_capsule, event_log, session_state]
optional_inputs: [scorecard, authority_grants, approved_reference_requests]
replaces_as_startup_context_during_experiment:
  - AP-SYSBUILD-001
  - AP-LANE-001
  - AP-INTEGRATE-001
  - AP-ROLLOUT-001
controls:
  - self-contained-safety-kernel
  - accepted-current-hrm-auto-resolution
  - routine-workflow-execution-lease
  - exact-authority-grant-overlay
  - mechanical-operator-prompt-budget
  - compact-state-artifact-writes
  - exact-version-pin
  - bounded-role-context
  - durable-state-not-chat-state
  - frozen-function-slice
  - one-writer-per-overlapping-change-unit
  - declared-deliverable-liveness
  - no-progress-termination
  - governance-loop-termination
  - scope-addition-disposition
  - changed-reach-validation
  - no-duplicate-equivalent-ci
  - clean-context-review
  - machine-derived-run-scorecard
---

# Compact HRM Execution Kernel

Use this experimental kernel as the complete active AP execution playbook for one HRM.
Do not preload the legacy system-build, lane-coordination, checker-controller, or rollout
playbooks. They remain historical and explanatory references, not required startup context.
The kernel, validated capsule, repository policy, and target HRM contract contain the
normative execution state for this experiment.

## Current-HRM target resolution

Derive the target from the accepted project map's `current_target_hrm`, corroborated by the
compact repository projection. Omitted, aliased, or descriptive prompt language never
overrides it; only an exact operator-supplied non-current HRM ID can use
`explicit_exact_override`. Record the selector path/version/status and resolution in the
capsule. Missing, proposed, contradictory, multi-valued, or mismatched selectors stop
`blocked_input`. Never ask the operator to restate an unambiguous accepted selector.

## Execution lease and human gates

“Run the current HRM” delegates the lease through the next genuine human gate. Without another
prompt, perform its bounded discovery, branch/worktree setup, in-scope implementation, commit,
PR publication/update, checks, budgeted correction, CI wait, authorized-merge read-back, and
next in-scope change unit. Capsule creation, technical proof, publication, and CI repair are
not operator decisions.

Human gates are limited to business meaning, operator-facing function review, policy-required
exact-head merge release, exact live-effect authority, and HRM closure. Each request names a
decision ID and exact effect; never ask merely “approve” or “proceed.” A generic reply accepts
only the last prepared decision's complete envelope, then execution continues.

## Stable capsule and authority overlay

The capsule freezes target, contract, function slice, starting bases, lease, safety, checks,
and budgets. Change units, candidates, PRs, merge approval/read-back, and expected advancement
of main do not rotate it. A successor requires an accepted playbook, target, contract,
function-slice, or execution-mode change and a lineage-bound durable state projection.

Later authority is a validated `hrm-authority-grant` overlay bound to the session, HRM,
candidate, issuer, effects, conditions, and time limit. An exact merge grant permits that one
merge and its automatic read-back; live-effect grants remain separately expiring and
fail-closed. A grant never broadens the frozen function slice or silently changes the mode.

## Compact state and raw artifacts

Use the event appender so a state update returns only event ID, sequence, and type; never echo
the growing JSONL ledger into active context. Keep raw CI output outside chat, PR prose, review
packets, and events. Record only the check summary, raw-artifact path, byte count, and digest.
Do not paste this kernel into the task prompt when the pinned repository dispatcher can load
it. A context compaction before first executable value, raw-log replay, or state-artifact echo
is measured against the capsule budget rather than treated as free.

An agent may open a named legacy section only when the capsule contains an approved
reference request with one unresolved question, exact source and heading, maximum bytes,
and required disposition. A full-playbook read is prohibited by default and counts as a
context-budget exception.

## Non-negotiable safety kernel

1. **Meaning before irreversible work.** Surface unresolved business meaning, authority,
   identity, lifecycle, UX intent, capability retirement, or acceptance oracles before
   non-disposable implementation. A timeout is never consent.
2. **One HRM, one human decision.** The target must be independently closable by one stated
   operator decision. A composite outcome stops for split or rebaseline.
3. **State separation.** Planned, implemented, integrated, deployed, activated,
   canary-observed, production-observed, and autonomy-eligible are distinct. Evidence for one
   never promotes another.
4. **Exact authority.** Provider, customer, money, credential, permission, deployment,
   activation, canary, production, destructive, or autonomy effects require current explicit
   authority for the exact action. Otherwise remain fail-closed.
5. **Stable effects.** Every authorized external mutation needs exact destination, stable
   operation identity, idempotency, read-back or reconciliation, ambiguous-result handling,
   bounded retry, stop conditions, and rollback or compensation.
6. **Privacy and preservation.** Do not expose secrets, credentials, private evidence, or
   customer data. Preserve unrelated changes, unique work, review runtimes, and ambiguous
   state. Never reset, clean, overwrite, or force-remove them.
7. **Frozen claim and function slice.** Accepted scenarios, required seams, non-goals,
   allowed paths, deliverable, safety shell, and proof obligations are frozen before build.
   Workers do not re-derive organization-wide scope.
8. **Brownfield reuse and parity.** Reuse stronger compatible implementation, tests, and
   operator capabilities. Replacement or retirement requires explicit incompatibility,
   parity, migration, rollback, and authority evidence.
9. **Exact candidate evidence.** Checks, review, merge, and receipts bind to exact candidate,
   base, policy, contract, and environment identities. A head change invalidates affected
   evidence. Integration proof is remote-main read-back, not a follow-up receipt PR.
10. **Human review and later authority.** `review_ready` is an operator function/UI/UX stop,
    not HRM closure or rollout authority. Only the stated human closure decision closes or
    defers the HRM.

## Required artifacts

- an execution capsule validated against `hrm-execution-capsule.schema.json`;
- the repository's closest applicable `AGENTS.md` or equivalent policy dispatcher;
- the exact target HRM contract and its accepted scenarios;
- one append-only JSONL event log; and
- one compact session-state projection derived from the capsule and event log; and
- one scorecard derived from the capsule and event log.

Later gated effects require a grant validated against `hrm-authority-grant.schema.json` and
the active capsule.

The event log is a local or CI artifact while active. Add the derived scorecard to an
already-required HRM closure record. Never open a branch or PR solely to receipt metrics.

## Prompt

```text
Run the target HRM under AP-EXEC-001/0.1.0-rc.2.

Repository policy and accepted HRM map: load from the current repository.
Capsule, event log, and session state: resume valid artifacts or derive them.

0. Resolve the target from the accepted current-HRM selector before capsule creation. Treat
   vague or omitted prompt language as `derived_current`; only an exact non-current HRM ID is
   an override. Stop on missing, proposed, or contradictory current-target authority.

1. Validate the capsule before planning or mutation. Bind the session to the exact kernel
   SHA, HRM contract, repository bases, authority, execution mode, function slice, context
   budgets, validation plan, and terminal budgets. A necessary kernel or contract change
   terminates this run as `superseded`; start a new versioned capsule after acceptance.

   Apply the workflow lease immediately. Do not request permission for a routine action it
   already authorizes, and do not rotate the capsule for an ordinary workflow transition.

2. Use the stable capsule, derived session-state projection, append-only events, and validated grants as active
   state. Conversation is not authoritative state. A generic reply can accept only the last
   prepared exact decision. Emit an event for every lifecycle transition, material decision,
   candidate freeze, conclusive check, operator-review boundary, finding disposition, and
   terminal reason; append it without replaying the ledger into context.

3. Load only the role projection:
   - orchestrator: outcome, decision frontier, phase, active units, blockers, budgets, next
     transition;
   - builder: function slice, scenarios, allowed paths, non-goals, dependencies, exact checks,
     stop conditions;
   - checker/reviewer: policy and contract pins, candidate/base, changed paths, diff, declared
     checks, results, limitations;
   - operator: capabilities ready and remaining, blockers, prepared decisions, exact review
     surface, findings requiring disposition, closure effect.
   Do not give builders organization-level derivation or reviewers the builder conversation.
   Record every context manifest and budget exception.

4. Advance only through:
   `planned -> semantic_readiness -> ready -> building|observing -> candidate_frozen ->
   checking -> review_ready -> closed|deferred|blocked`.
   Apply the safety kernel at every transition. Later operational states remain separately
   authorized even during `production_observation`.

5. Before non-disposable work, freeze the function slice. Type each discovery as
   `current_claim_blocker`, `defer`, `separate_proposal`, or `accepted_current_scope`.
   Only the orchestrator may accept current scope, and material semantic expansion retains
   its human or contract gate.

6. Permit one writer per overlapping change unit. Other agents are read-only. Parallel
   writers require evidenced non-overlap in paths, state, resources, authority, validation,
   and integration order.

7. Count material progress only when there is a newly accepted decision, resolved blocker,
   required executable delta, required verified operational evidence, evidenced state
   transition, or eligibility-changing finding disposition. More prose, repeated status,
   equivalent checks, unchanged-source rereads, and receipt-of-receipt work do not count.
   Technical proof and routine workflow are checker/orchestrator responsibilities unless the
   HRM contract explicitly makes the proof an operator-visible acceptance scenario.

8. Enforce capsule budgets. A runtime-build run terminates `governance_loop` when
   consecutive non-runtime units exceed budget without an executable delta. Terminate
   `no_progress` when the material-progress clock expires and `budget_exhausted` when
   correction, CI, or context limits are exceeded. Return the smallest blocker and permitted
   continuation; do not manufacture documentation.

9. Select checks from changed reach plus binding repository rules. Use the exact checks,
   full-suite triggers, and CI-plan hash in the capsule. Do not add suites for reassurance or
   repeat a conclusive check for the same candidate, plan hash, and environment. Store raw
   logs externally and project only a digest-bound summary.

10. Freeze one candidate per correction round. A clean reviewer receives only the review
    projection. Return valid findings as one bounded correction bundle. Exceeding the
    correction budget stops for disposition.

11. Mark `review_ready` only when the declared deliverable and evidence exist. Runtime-build
    runs cannot close with documentation alone. Production-observation runs do not invent
    code when operational evidence is the deliverable. Stop for operator review; do not
    cross later authority boundaries.

12. Derive the terminal scorecard from events. Agents emit facts but do not hand-edit derived
    metrics. Missing instrumentation is `run_invalid`, never a favorable assumption. A run
    passes only when outcome/safety gates pass and the preregistered process envelope holds.
    Blocked or deferred can be validly controlled without being a completed HRM.
```

## Context-reference protocol

The capsule starts with an empty `reference_requests` list. Add a request only when the
active artifacts cannot answer a specific question:

```yaml
reference_requests:
  - id: REF-001
    question: "Which exact rollback evidence is required for this authorized stage?"
    source_path: playbooks/activation-production-rollout.md
    source_heading: "Prompt"
    max_bytes: 6000
    approved_by: orchestrator
    disposition: pending
```

Read the smallest heading-bounded section, record bytes loaded, answer the question, and set
the disposition. Do not retain unrelated reference prose in subsequent role projections.

## Initial context budgets

| Role or artifact | Maximum active non-code context |
|---|---:|
| Global instructions | 2,000 bytes |
| Repository dispatcher | 8,000 bytes |
| Execution capsule | 8,000 bytes |
| Derived session state | 4,000 bytes |
| Orchestrator projection | 32,000 bytes |
| Builder projection | 20,000 bytes |
| Checker projection | 12,000 bytes |
| Reviewer projection excluding diff | 20,000 bytes |
| Operator projection | 8,000 bytes |

Projects may tighten or explicitly override these envelopes only under the `custom` profile.

## Experiment profiles and evaluation

Use `runtime_build_fast_feedback` for a build HRM and
`production_observation_fail_closed` for a production-proof HRM. The named profiles in
`templates/hrm-experiment-profiles.yaml` preregister execution mode, deliverable, validation
posture, and process budgets. A changed value must use `custom`; it may not retain a named
profile and contaminate comparison with a silent override. Production observation uses exact
operational proof, not a reflexive full application suite when no runtime reach changed.

The evaluator reports three independent conclusions:

- `run_valid`: event order, identity, and required instrumentation are sufficient;
- `outcome_and_safety`: accepted scenarios and non-negotiable safety gates pass; and
- `process_envelope`: liveness, context, CI, correction, and scope budgets pass.

The process envelope also fails on a mechanical operator prompt before `review_ready`, a
pre-value context compaction, or raw-log/state-ledger echo beyond budget. Report genuine and
mechanical decision requests separately; a safe run can still fail the autonomy experiment.

`overall: pass` requires all three. Do not average them into a score that can trade safety
for speed. A blocked or deferred run may be validly controlled but is not a completed outcome.
A just-closed run remains `pending` until a separately timestamped aftercare observation
reaches its preregistered window. Compare measures within the same named profile and inspect
the raw events when a metric regresses.

## Terminal reasons

`done_verified`, `review_ready`, `blocked_input`, `blocked_external`,
`scope_divergence`, `governance_loop`, `no_progress`, `budget_exhausted`, and
`superseded` are the only kernel terminal reasons. Detail belongs in evidence, not an
unbounded vocabulary.

## Change note

- **0.1.0-rc.2 — 2026-08-26:** Derives the active HRM automatically; adds a routine execution
  lease, five genuine human gates, exact authority-grant overlays, stable capsule lineage,
  compact event writes, external raw logs, and measured prompt/context overhead.
- **0.1.0-rc.1 — 2026-08-25:** Creates a self-contained safety and execution kernel with
  bounded context, on-demand legacy references, explicit liveness controls, clean review,
  append-only events, and machine-derived post-HRM evaluation.
