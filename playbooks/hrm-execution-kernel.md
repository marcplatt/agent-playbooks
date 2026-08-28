---
playbook_id: AP-EXEC-001
title: Compact HRM Execution Kernel
version: "0.1.0-rc.10"
status: experimental
owner: Adopting organization
mode: self-contained-bounded-hrm-execution
human_readable: true
machine_readable: true
required_inputs: [repository_policy, accepted_project_hrm_map]
derived_inputs: [target_hrm_contract, execution_capsule, event_log, session_state, dispatch_envelope, operator_projection]
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
  - bounded-read-only-diagnostic-lease
  - operator-action-not-decision
  - exact-authority-grant-overlay
  - mutation-transmission-only-effect-gates
  - compact-state-artifact-writes
  - exact-version-pin
  - bounded-role-context
  - fresh-worker-context-isolation
  - durable-state-not-chat-state
  - non-llm-supervisor-single-writer
  - cursor-bound-projection-commit
  - compiled-hash-bound-dispatch
  - automatic-mode-successor-generation
  - fast-dispatch-budget
  - operator-attention-firewall
  - cross-hrm-api-skill-reuse
  - cross-kernel-api-skill-reuse
  - master-plan-api-skill-portability
  - frozen-function-slice
  - pre-build-runtime-binding-inventory
  - zero-effect-runnable-candidate-proof
  - one-writer-per-overlapping-change-unit
  - declared-deliverable-liveness
  - no-progress-termination
  - online-pre-action-budget-guard
  - lineage-bound-runtime-supersession
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
normative execution state for this experiment. The non-LLM supervisor compiles those sources
into a hash-bound dispatch envelope. On an unchanged pin and contract the orchestrator reads
that envelope, not the complete kernel or project map, and delegates in its first turn.

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
exact-head merge release, exact external-effect authority, and HRM closure. External-effect
authority means a mutation, transmission, money movement, credential or permission change,
deployment, activation, Canary execution, destructive action, or autonomy change. Read-only
repository inspection, provider health/config/log inspection, authenticated portal navigation,
and credential-presence diagnostics inside the capsule's one bounded diagnostic scope are
routine lease actions, not approval gates. Each request names a decision ID and exact effect;
never ask merely “approve” or “proceed.” A generic reply accepts only the last prepared
decision's complete envelope, then execution continues.

Sign-in, MFA, credential unlock, genuinely owner-private value entry, and required physical presence are
`operator_action_required` handoffs. They are not decisions, authority grants, or evidence of
acceptance. Resume the same diagnostic tree after the action without asking for another
approval; stop only when a declared diagnostic stop condition is reached. A private value must
be a credential, destination, customer case, or private identity that software cannot safely
derive. A reversible local path, filename, environment-variable name, adapter selection, or
other technical choice is routine implementation and cannot be serialized as operator attention.

## Stable capsule and authority overlay

The capsule freezes target, contract, function slice, starting bases, lease, safety, checks,
and budgets. Change units, candidates, PRs, merge approval/read-back, and expected advancement
of main do not rotate it. A successor requires an accepted playbook, target, contract,
function-slice, or execution-mode change and a lineage-bound durable state projection.

Later authority is a validated `hrm-authority-grant` overlay bound to the session, HRM,
candidate, issuer, effects, conditions, and time limit. An exact merge grant permits that one
merge and its automatic read-back; external-effect grants remain separately expiring and
fail-closed. A read-only observation never consumes such a grant. A grant never broadens the
frozen function slice or silently changes the mode.

## Project API skills and cross-repository transfer

Stable callable knowledge discovered by one HRM belongs to the project API skill registry,
not to that HRM's transient provider diagnostic. An API skill names its provider, stable call
IDs, operations, effect classes, contract references, contract version and fingerprint,
source-bound conclusive evidence, and exact invalidators. APM configuration/product/price
reads, GHL reads and workflows, QBO estimate operations, VoIP.ms notifications, Website
intake, and future integrations use the same skill abstraction.
The fingerprint is the canonical SHA-256 of provider system, skill kind, contract version,
and the exact call table, so a consumer can reproduce it without private source evidence.

Every capsule declares only the API skill IDs and contract fingerprints required by its frozen
function slice. The supervisor validates the registry and projects reusable and missing skill
IDs. A matching stable skill remains reusable across HRMs and kernel versions. Guard
`discover_project_api_skills` only for genuinely missing fingerprints; when all requirements
are covered, the guard fails closed against rediscovery. Changed contracts or adapter bindings
supersede the prior skill instead of silently overwriting it.

API skills are portable across repositories, but transfer is authority-bound. The source
project may reuse its own `project_verified` skill. Another repository may reuse it only after
the Software Master Plan accepts the source-bound intake and the record becomes
`master_plan_accepted`. Transfer carries the callable contract and provenance, never
credentials, account or destination identifiers, customer data, private evidence, live
provider state, or external-effect authority. Volatile health, authentication, current data,
and action identity remain action-time checks.

Publish a newly verified stable skill with `scripts/project_api_skill_registry.rb` only from a
conclusive passed `project-api-skill:<skill_id>` check. The registry is tracked project contract
state; the session ledger remains supervisor-owned and append-only.

## Compact state and raw artifacts

Use the event appender so a state update returns only event ID, sequence, and type; never echo
the growing JSONL ledger into active context. Keep raw CI output outside chat, PR prose, review
packets, and events. Record only the check summary, raw-artifact path, byte count, and digest.
Do not paste this kernel into the task prompt. The supervisor dispatch envelope carries a
kernel cache key and target-contract cache key; reload changed source only within the compiled
role's bounded access policy when a corresponding hash changes or compact state is ambiguous.
Never turn a hash change into an unbounded implementation-source read. Emit cumulative per-turn
`context_snapshot` events at startup, worker handoff, and before
guarded actions. A root-orchestrator compaction before `first_executable_delta` or
`first_operational_evidence`, raw-log replay, or state-artifact echo is measured against the
capsule budget rather than treated as free. A governance record, state projection, capsule,
or receipt never counts as executable or operational value.

Every rc.10 context snapshot maps each loaded dependency ID to the exact source bytes actually
materialized through bounded queries or slices. A declared dependency authorizes targeted access;
it neither requires nor authorizes a full-source read. Dependency-derived query output is charged
once in `loaded_artifact_bytes_by_id` and excluded from `tool_output_bytes`, which covers only
non-dependency output. The supervisor rejects negative counts, counts above the bound source size,
overlapping category totals, and IDs outside the compiled assignment. Any loaded ID absent from
the capsule declaration must also appear in
`outside_declared_dependency_ids`, and its count must match
`files_outside_declared_dependencies`. The pinned kernel, capsule, dispatcher, accepted target
contract, API-skill registry, run state, implementation sources, and declared checks are not
scope escapes when explicitly bound there. An unidentifiable positive count is invalid
instrumentation rather than a terminal assumption.

The root context is coordination-only. It resolves meaning, owns the decision frontier, emits
bounded worker projections, and receives compact results. A fresh builder owns implementation
and correction, a fresh checker owns declared checks, and a fresh provider observer owns the
bounded provider diagnostic tree and operational-evidence collection. Do not make role labels
inside one growing root conversation stand in for these context boundaries.

An agent may open a named legacy section only when the capsule contains an approved
reference request with one unresolved question, exact source and heading, maximum bytes,
and required disposition. A full-playbook read is prohibited by default and counts as a
context-budget exception.

## Non-LLM supervisor and attention firewall

The rc.10 experiment uses one state-owning process below the LLM orchestrator. The supervisor
does not interpret business meaning, derive scope, spawn workers, select checks, grant
authority, or perform repository/provider effects. It owns only the mechanical run protocol:

1. take one exclusive lock for the event ledger;
2. reread and validate the capsule and complete ledger under that lock;
3. assign the next event sequence and append/fsync the event;
4. derive session state and scorecard from that exact in-memory ledger; and
5. compile the next worker assignment from the resolved HRM slice, skill coverage, runtime
   binding inventory, authority, and checks; and
6. atomically replace state, scorecard, dispatch, and projection, publishing the compact
   supervisor projection last as the cursor-bound commit marker.

The append-only ledger remains authoritative. The session state, scorecard, and supervisor
projection are disposable derived artifacts and grant no new authority. If a process stops
after the ledger append but before the projection commit, `resume` repairs the derived set from
the ledger before continuation. Every rc.10 append, handoff receipt, context receipt, guarded action, and transition goes through
`scripts/hrm_supervisor.rb`; direct event appends are legacy diagnostic behavior for older pins.
`transition` derives the execution-mode successor mechanically, writes it once, validates it,
and only then binds the predecessor's terminal supersession event.

All event, state, scorecard, and projection paths resolve from the capsule `project_root`; a
same-named path elsewhere is rejected. The projection carries the scorecard verdict and stops
on `run_invalid` or a failed process envelope before any later routine action can be guarded.
A successor may consume an earlier decision only through a capsule receipt that binds the
decision ID, kind, effect class, request event digest, and immutable predecessor ledger digest.

The attention projection includes only unavoidable environment/owner-private actions, genuine decision requests,
blocking or S0/S1 findings, and an active `review_ready` stop. Routine workflow is represented
by a silent operator projection, not rendered as an operator-facing validation transcript or a
request to approve a micro-transition. Cursor, hash, worker, scope, check, and retry detail stays
in the dispatch/ledger. The projection is capped at 4,096 bytes and carries the ledger cursor,
state hash, scorecard event count, dispatch digest, next action, and its own digest. An LLM may
render only the operator projection unless attention, review, or terminal state requires a
message; it may not silently reinterpret it or use conversation memory as newer state.

## Non-negotiable safety kernel

1. **Meaning before irreversible work.** Surface unresolved business meaning, authority,
   identity, lifecycle, UX intent, capability retirement, or acceptance oracles before
   non-disposable implementation. A timeout is never consent.
2. **One HRM, one human decision.** The target must be independently closable by one stated
   operator decision. A composite outcome stops for split or rebaseline.
3. **State separation.** Planned, implemented, integrated, deployed, activated,
   canary-observed, production-observed, and autonomy-eligible are distinct. Evidence for one
   never promotes another.
4. **Exact authority.** Provider mutation, customer transmission, money movement, credential
   or permission mutation, deployment, activation, Canary execution, destructive action, or
   autonomy change requires current explicit authority for the exact action. Bounded read-only
   inspection is routine; privacy, preservation, and access controls still apply.
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
- one scorecard derived from the capsule and event log; and
- one compact supervisor projection committed at the same event cursor; and
- one compiled dispatch envelope committed at the same event cursor.

Later gated effects require a grant validated against `hrm-authority-grant.schema.json` and
the active capsule.

The event log is a local or CI artifact while active. Add the derived scorecard to an
already-required HRM closure record. Never open a branch or PR solely to receipt metrics.

## Prompt

```text
Run the target HRM under AP-EXEC-001/0.1.0-rc.10.

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
   If the capsule's execution mode cannot produce a known missing deliverable, derive and
   validate the declared successor capsule immediately when its inputs are complete; otherwise
   stop `blocked_input` before discovery, branch creation, or evidence preparation. If a new
   incompatible deliverable is discovered during execution, use
   `scripts/hrm_supervisor.rb transition` to derive, write, validate, and bind the mode successor
   before the predecessor may become terminal. A manually copied capsule or free-text
   `superseded` event is invalid during routine mode transition.

2. Put the exact first `scripts/hrm_supervisor.rb resume` command in the compact repository
   dispatcher that the cold HRM thread already loads. Its first action is that command: do not
   search memory, README files, old worktrees, the full kernel, map, capsule, or supervisor source.
   Validate a released worktree beforehand with the read-only `release-check`
   command. It must contain no artifacts for the new session. Start or resume only inside the
   actual HRM task through `scripts/hrm_supervisor.rb resume`. On an empty bound ledger, `resume`
   creates the ignored artifact directory if needed and atomically writes `session_started`
   before compiling the first assignment. Use its
   cursor-bound compact projection
   and compiled dispatch envelope as active model state. Validate hashes mechanically; do not
   reread the complete kernel, project map, capsule, or ledger when their cache keys are unchanged.
   The dispatch names only the dependencies authorized for its current assignment and carries the
   role context budget, a smaller loaded-artifact allowance, a tool-output reserve, source-size
   bounds, `bounded_queries_never_full_source`, and exact supervisor handoff, context, and guard
   commands. Machine-parsed dispatch bytes are not conversation echo. The worker reports exact
   materialized dependency bytes by ID and non-dependency tool-output bytes without double counting.
   A process-failing accepted event and its terminal stop are written under the same lock.
   The stable capsule, append-only events, and validated grants remain durable authority. Conversation is not
   authoritative state. A generic reply can accept only the last prepared exact decision. Emit
   an event for every lifecycle transition, material decision, candidate freeze, conclusive
   check, operator-review boundary, finding disposition, and terminal reason; append it through
   the supervisor without replaying the ledger or derived artifacts into context.

3. Load only the compiled assignment and role projection and execute worker-owned work in fresh contexts:
   - orchestrator: outcome, decision frontier, phase, active units, blockers, budgets, next
     transition;
   - builder: function slice, scenarios, allowed paths, non-goals, dependencies, exact checks,
     stop conditions;
   - checker/reviewer: policy and contract pins, candidate/base, changed paths, diff, declared
     checks, results, limitations;
   - operator: only the supervisor's operator projection—capability state, a genuine blocker or
     decision, prepared review, or terminal outcome.
   Do not give builders organization-level derivation or reviewers the builder conversation.
   The root may not implement, correct, run checks, perform provider diagnosis, prepare private
   inputs, or collect operational evidence. Record every handoff and cumulative per-turn context
   snapshot; return compact results rather than worker conversation.

4. Advance only through:
   `planned -> semantic_readiness -> ready -> building|observing -> candidate_frozen ->
   checking -> review_ready -> closed|deferred|blocked`.
   Apply the safety kernel at every transition. Later operational states remain separately
   authorized even during `production_observation`.

5. Before non-disposable work, freeze the function slice. In runtime-build mode, dispatch a
   fresh provider observer to emit `runtime_binding_inventory` for every required real seam
   before the builder. Missing adapters and clients become builder inputs, not a later
   production-observation discovery or an operator task. Type each discovery as
   `current_claim_blocker`, `defer`, `separate_proposal`, or `accepted_current_scope`.
   Only the orchestrator may accept current scope, and material semantic expansion retains
   its human or contract gate.

   Provider observers inspect implementation dependencies with targeted `rg`, symbol or AST
   queries, and bounded line slices. They must never dump a complete implementation source merely
   because its dependency ID appears in the assignment.

6. Permit one writer per overlapping change unit. Other agents are read-only. Parallel
   writers require evidenced non-overlap in paths, state, resources, authority, validation,
   and integration order.

7. Count material progress only when there is a newly accepted decision, resolved blocker,
   required executable delta, required verified operational evidence, evidenced state
   transition, or eligibility-changing finding disposition. More prose, repeated status,
   equivalent checks, unchanged-source rereads, and receipt-of-receipt work do not count.
   Technical proof and routine workflow are checker/orchestrator responsibilities unless the
   HRM contract explicitly makes the proof an operator-visible acceptance scenario.

8. Before every guarded action, run `guard-action` against the current capsule, event log,
   action, role, context snapshot, and current time. The guard records its result and prevents
   the action when the role topology, lease, context budget, pre-value compaction budget, or
   no-progress clock fails. A runtime-build run terminates `governance_loop` when
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

11. Mark `review_ready` only when the declared deliverable and evidence exist. Emit
    `first_executable_delta` only after its runtime-readiness proof names every frozen real seam,
    shows every seam bound, and proves zero-effect construction. A created file or module digest
    alone is not executable value. Emit `first_operational_evidence` only for verified operational proof. Runtime-build
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
| Compiled dispatch envelope | 12,288 bytes |
| Orchestrator projection | 32,000 bytes |
| Builder projection | 20,000 bytes |
| Checker projection | 12,000 bytes |
| Provider-observer projection | 12,000 bytes |
| Reviewer projection excluding diff | 20,000 bytes |
| Operator projection | 8,000 bytes |

Projects may tighten or explicitly override these envelopes only under the `custom` profile.
Each compiled worker assignment reserves half of its role envelope for non-dependency tool output
and limits dependency-derived materialization to the other half unless a later kernel version
defines a different preregistered split.

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

The event validator rejects a routine or read-only operation serialized as an operator
decision. The process envelope fails immediately when a measurable budget violation exists,
including a root compaction before the expected executable
or operational value, uninterrupted semantic readiness or first worker handoff beyond 30
seconds, or raw-log/state-ledger echo beyond budget. Report genuine decision
requests separately from non-decision operator actions; a safe run can still fail the autonomy
experiment.

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

- **0.1.0-rc.10 — 2026-08-28:** Makes cold startup command-first from the compact repository
  dispatcher and compiles per-role context, loaded-artifact, and tool-output budgets. Declared
  dependency IDs authorize bounded queries rather than full reads. Context receipts count exact
  materialized bytes by dependency ID, exclude those bytes from tool output, enforce source-size
  bounds, and derive active context from nonoverlapping categories. Adds a no-replay fresh-worker
  handoff receipt while preserving locked append, projection refresh, and terminalization.
- **0.1.0-rc.9 — 2026-08-27:** Makes released sessions provably unstarted, terminalizes accepted
  process failures in the same locked append, and stops stale active sessions on resume. Replaces
  free-form context events with supervisor-measured declared dependencies, assignment-minimal
  dependency sets, and exact context/guard commands in the compiled dispatch. Platform instructions
  and machine-parsed dispatch are excluded from repository-context and echo accounting respectively.
- **0.1.0-rc.8 — 2026-08-27:** Compiles a hash-bound worker dispatch envelope and separate quiet
  operator projection so unchanged kernel/HRM sources do not need full LLM rereads. Enforces
  30-second uninterrupted semantic/handoff budgets, derives execution-mode successors through
  one supervisor transition, inventories runtime bindings before build, and requires all frozen
  real seams plus zero-effect construction proof before `first_executable_delta`. Reversible
  technical choices cannot be encoded as private-value operator interruptions.
- **0.1.0-rc.7 — 2026-08-27:** Fails the state-owning supervisor closed on semantic integrity.
  Project-root-bound artifact paths prevent cross-worktree projection writes. Compact projections
  carry the scorecard verdict and stop on run-invalid or failed process state; later writes are
  refused. Cross-session decisions require an exact predecessor-request receipt verified against
  the immutable predecessor ledger, while rc.6 event ledgers remain readable as history. The
  bounded context-dependency correction adds capsule-bound dependency IDs and matching event
  evidence so a required external pinned kernel cannot be misclassified by an opaque count; a
  failed process envelope also makes the aggregate verdict fail.
- **0.1.0-rc.6 — 2026-08-27:** Adds cross-HRM and cross-kernel API skills. Capsules declare
  required skill fingerprints; the supervisor reuses matching stable contracts and dispatches
  discovery only for missing skills. Source projects may reuse verified skills immediately;
  cross-repository reuse requires Software Master Plan acceptance. APM calls use the same
  skill model as GHL, QBO, VoIP.ms, Website, and future integrations. Volatile and private
  provider state remains excluded and action-time only.
- **0.1.0-rc.5 — 2026-08-27:** Adds the smallest state-owning supervisor slice: one lock and
  append path, crash-repairing resume, cursor-bound state/scorecard/attention projection, and a
  compact continuation signal. It does not add worker management, new authority, business
  interpretation, or operational effects.
- **0.1.0-rc.4 — 2026-08-27:** Makes execution-mode supersession an atomic, machine-bound
  transition. A predecessor cannot stop `superseded` until a valid successor capsule names the
  same HRM and accepted target, increments lineage, inherits the exact state path, changes mode,
  and carries a newly missing deliverable that the predecessor could not produce.
- **0.1.0-rc.3 — 2026-08-26:** Makes bounded read-only provider diagnostics routine, types
  sign-in and MFA as operator actions rather than decisions, restricts effect grants to
  mutations/transmissions and other material external effects, requires fresh builder/checker/
  provider-observer contexts, introduces online pre-action liveness/context guards, replaces
  generic first value with executable-delta and operational-evidence events, and fails capsule
  validation when its mode cannot produce a known missing deliverable.
- **0.1.0-rc.2 — 2026-08-26:** Derives the active HRM automatically; adds a routine execution
  lease, five genuine human gates, exact authority-grant overlays, stable capsule lineage,
  compact event writes, external raw logs, and measured prompt/context overhead.
- **0.1.0-rc.1 — 2026-08-25:** Creates a self-contained safety and execution kernel with
  bounded context, on-demand legacy references, explicit liveness controls, clean review,
  append-only events, and machine-derived post-HRM evaluation.
