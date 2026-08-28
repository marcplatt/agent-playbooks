---
playbook_id: AP-EXEC-001
title: Compact HRM Execution Kernel
version: "0.1.0-rc.19"
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

Every rc.12-or-later context snapshot maps each loaded dependency ID to the exact source bytes
actually materialized through bounded queries or slices. A declared dependency authorizes targeted access;
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

RC.18 builder assignments are the explicit exception to the legacy query/slice transport above:
their capsule manifest requires the complete relevant primary source inside one separately
accounted context pack so the model can reason about interfaces, invariants, and consequences.
The compact receipt remains only a locator. Provider observers and RC.11-RC.16 workers retain the
query/slice accounting described in this section.

Zero-byte dependency reports are accepted as optional preflight evidence but normalized away in
rc.12 or later. They do not appear in `loaded_dependency_ids` or `loaded_artifact_bytes_by_id`, do not
increase `files_loaded`, and never seed repeated-artifact accounting. The worker performs bounded
source inspection and materialization first, then emits one cumulative context snapshot, executes
the exact guard command, and submits the exact result command. One or more same-role zero-artifact
preflights may precede that final snapshot; no business event or earlier positive snapshot may
intervene in the claim-bound result lifecycle.

The `inventory_runtime_bindings` provider observer has a 10,000-byte loaded-artifact ceiling
and a 2,000-byte minimum tool-output reserve within its unchanged 12,000-byte role budget.
Tool output may consume unused artifact headroom, but artifacts never consume the reserve and
the combined active total never exceeds 12,000 bytes. The 20,000-byte builder allocation remains
10,000 loaded-artifact bytes plus a 10,000-byte nominal tool-output reserve. Other actions retain
an even split. When real seams are declared, the inventory guard requires positive materialized
bytes from at least one implementation-source dependency authorized by the assignment.

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

The rc.19 experiment preserves the rc.18 state-owning process below the LLM orchestrator. The supervisor
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
the ledger before continuation. Every rc.13 through rc.19 append, handoff receipt, activation, context receipt,
guarded action, and transition goes through `scripts/hrm_supervisor.rb`; direct event appends are
legacy diagnostic behavior for older pins.
`transition` derives the execution-mode successor mechanically, writes it once, validates it,
and only then binds the predecessor's terminal supersession event.

Before handoff, context receipt, or guard, the supervisor recomputes the assignment from the
current capsule, ledger, API-skill coverage, and cursor. The stored dispatch must equal that
deterministic result exactly, and the current projection must bind its capsule, session, cursor,
path, and digest. A merely self-rehashed dispatch edit cannot authorize work. Each handoff event
records the action, role, source dispatch cursor and digest, and a deterministic worker-claim ID;
the receipt proves a claim was issued for a fresh worker but does not claim the supervisor spawned
the model. Named profiles pin their complete role-budget map; use `custom` for an intentional
override.

RC.12 `resume` and `handoff` return a compact `worker_launch` receipt containing the assignment,
role, cursor, one explicit project `working_directory`, a project-relative dispatch path, minimal
dependency and budget fields, and exact project-relative handoff, context, guard, and result
command arrays. `dispatch_sha256` binds the current post-refresh dispatch file; it is not the
handoff claim's pre-handoff source-dispatch hash. The supervisor rejects a complete launch receipt
over 4,096 bytes before appending its event. On an uninterrupted launch the root consumes that
receipt only: it executes the handoff command directly from `working_directory`, then immediately
spawns a fresh worker instructed to
consume the compiled dispatch at the supplied path. It does not open state, scorecard, projection,
or dispatch artifacts itself, does not empty-wait before spawning, and does not wrap protocol
commands in a shell that can obscure exit status or duplicate an already-recorded receipt.

Worker-owned lifecycle events are not generic appends in rc.12. A worker first presents its
claim through the handoff receipt, records bounded context, and passes the matching action guard.
The `result` command then accepts only the action's expected value event with the same claim ID,
action, and role; it atomically appends that value and a bound `worker_result_received`. Direct
or replayed handoff, context, guard, change-unit, runtime inventory, executable/operational value,
check, or worker-result appends fail without changing the ledger.

RC.13 makes activation an explicit supervisor-owned lifecycle boundary. After the root executes
the receipt's handoff command, it spawns the assigned fresh worker immediately with
`fork_turns: none`, no intervening derived-artifact read, and no wait. The worker's first tool is
the receipt's `activation_command`, bound to the pending claim, current ledger cursor, and current
dispatch-file digest. A mismatch, forgery, or replay leaves the ledger unchanged. The activation
receipt provides the refreshed dispatch path, cursor, and file digest so the worker can verify the
compiled dispatch without dumping it. The root performs exactly one wait after the spawn.

The worker then performs bounded source inspection, encodes its single cumulative context report
as canonical JSON in one unpadded base64url argv value, executes the exact guard array, and submits
one action-specific domain payload through the result command in the same encoding. It does not use
stdin, a TTY, a pipe, a shell wrapper, or EOF as protocol. The supervisor derives the event type,
action, role, claim, and completion envelope from the live lifecycle. The launch receipt publishes
only the minimal action-specific result keys and valid template needed for every reachable action
in the canonical worker-required action map and remains subject to the complete 4,096-byte
preappend cap. After the guard, the compiled dispatch binds the exact handoff-through-guard event
slice. Result acceptance verifies that stable supervisor-compiled lifecycle binding without
recomputing inputs that the assigned work may legitimately change after the guard. Lifecycle edits
therefore fail without a ledger write, while a legitimate worker can change an implementation
source or resolve an API-skill registry after its guard and still submit the bound result. Exact
deterministic source dispatch recomputation remains mandatory through activation, context, and
guard. A valid provider inventory result refresh exposes the next builder launch immediately.

RC.14 changes only the launch-receipt representation. Start and handoff receipts retain the
session, cursor, next action, append identity, and complete `worker_launch`, but omit projection
diagnostics that the root does not consume before spawning. `worker_launch` keeps every exact
command array, dispatch path and digest, dependency ID, role budget, worker claim, activation
binding, and action-specific valid result template. Shared one-shot encoding, argument, and size
metadata appears once; fresh-fork, root-wait, and execution-order policy uses one compact structured
block. The receipt remains self-sufficient: neither root nor worker rereads a derived artifact
before launch. The claim-bearing handoff receipt's `activation_command` is the compact launch-ready
signal; the preceding resume receipt has no activation command. The 4,096-byte runtime preappend
cap is unchanged. The AE-scale seven-seam fixture
that produced a 4,155-byte rc.13 claim-bearing handoff is 2,941 bytes at rc.14 resume and 3,660
bytes at rc.14 handoff, leaving 436 bytes below the hard cap.

RC.15 keeps the rc.14 compact launch representation and makes activation evidence unambiguous.
`claim_validation` binds the claim's pre-activation dispatch digest to the digest actually observed
at that cursor and derives `matched` from exact equality rather than asserting it. Every RC.15
ledger load requires both digests to be present and equal. Context and guard additionally compare
them with the supervisor-recomputed pre-activation dispatch; result validates the unchanged pair
through the stored supervisor-bound post-guard lifecycle so assigned source and API-registry
mutations remain valid. `post_activation_dispatch` identifies the distinct dispatch derived after
`worker_started` is appended. Named runtime-build and production-observation profiles preregister
inclusive hard limits of 30 seconds from session start and 20 seconds from handoff to worker
activation. The 20-second/10-second figures remain optimization targets, never hard stops inside
30/20. A failed hard gate projects bounded stable `reason_codes`, and the terminal operator summary
starts with the process blocker rather than the HRM outcome. No raw or private detail enters either.
The dedicated AE-scale fixture pins RC.15 at 2,969-byte resume and 3,695-byte handoff receipts with
401 bytes of headroom; the exact 30/20 boundary continues, while 31 seconds or 21 seconds terminalizes.

RC.16 changes only the named runtime-build and production-observation post-handoff activation hard
limit from an inclusive 20 seconds to an inclusive 25 seconds. The total startup limit remains an
inclusive 30 seconds, and 20/10 remains the optimization target. All RC.15 activation evidence,
compact receipt, one-shot command, lifecycle, and reason-code semantics are unchanged. The observed
27-second startup/21-second post-handoff path continues under RC.16, as does the exact 30/25 boundary;
31 seconds total or 26 seconds post-handoff terminalizes with the corresponding stable code. The
AE-scale receipt remains under the 4,096-byte cap with more than 300 bytes of headroom.

RC.18 separates protocol transport from model context. The coordination plane retains a 4,096-byte
hard cap but targets no more than 3,072 bytes under realistic identifiers and paths, preserving at
least 1,024 bytes of margin. Its receipt carries only action/role, cursor and claim, dispatch and
worker-context-pack references, budgets, and exact lifecycle commands. Selectors, API contracts,
output targets, result schemas, and source content remain in the claim-bound dispatch or the
separate worker data plane; the root never loads the pack.

For a builder handoff the supervisor constructs one ignored, mode-0600 JSON context pack from the
capsule's explicit manifest before appending the handoff. It contains the complete primary source,
direct imported interface bodies with their decorators, focused tests, registered API skill/call
contracts, a canonical supervisor-generated task capsule, the exact target contract, kernel rules,
output target, result schema, and
per-section path/selector/digest/byte accounting. The pack binds capsule, source dispatch, claim,
source snapshot, API-registry digest, and construction-manifest digest. Activation, context, and
guard independently rederive and rehash it; drift fails closed. Context accounting charges the
serialized pack bytes, not its compact locator, against the builder's 256-KiB artifact allowance.
The provider observer has a 96-KiB artifact allowance. Their separate tool-output reserves are
64 KiB and 32 KiB. These budgets are evidence-seeded but provisional until two representative
builder runs measure pack use, compaction, and implementation quality.

Initial scope is capsule-defined. A reasoned builder expansion request may mechanically add only a
named preapproved adjacency class within allowed paths, repository-safe privacy, and its remaining
byte allowance. Acceptance writes a digest-chained delta pack containing only the added sections
plus an append-only accounting event. Context and guard revalidate the complete chain and charge
the retained base plus every delivered delta against the artifact allowance; a replacement pack
never hides bytes that the model has already loaded.
Any request that changes task boundary, authority, privacy/provider surface, business meaning, or
material budget returns an orchestrator escalation without changing ledger or pack state. Direct
filesystem reads are policy violations and never authorize advancement; RC.18 provides provenance,
authorization, and accounting, not filesystem isolation. Builder result acceptance reads back the
exact outside-repository regular artifact, binds its byte count and digest to the ledger, and
rejects later artifact drift.

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
Run the target HRM under AP-EXEC-001/0.1.0-rc.19.

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
   before compiling the first assignment. Use the compact receipt as root active state; the root
   does not open the projection or dispatch during uninterrupted launch. After activation, the
   child verifies the supplied dispatch-file digest mechanically and consumes the compiled
   assignment without rereading the complete kernel, project map, capsule, or ledger when their
   cache keys are unchanged. The dispatch names only the dependencies authorized for its current
   assignment and carries the
   role context budget, loaded-artifact allowance, tool-output reserve, and exact supervisor
   handoff, activation, context, expansion, result-contract, guard, result, and fail-closed commands. Execute the resume
   receipt's handoff command directly. For rc.18 and rc.19, spawn the assigned role immediately with
   `fork_turns: none` when the claim-bearing handoff receipt contains `commands.activate`; for
   rc.14 through rc.16 use the claim-bound `activation_command`, and for older formats use `launch_ready` when
   present. Do not open state, scorecard, projection, or dispatch and do not wait before the spawn. The root waits
   exactly once after spawning. Machine-parsed dispatch bytes are not conversation echo. The
   provider reports exact materialized dependency bytes by ID. An rc.18 or rc.19 builder instead acknowledges
   the exact worker-context-pack digest; the supervisor accounts the pack's serialized bytes.
   A process-failing accepted event and its terminal stop are written under the same lock.
   The stable capsule, append-only events, and validated grants remain durable authority. Conversation is not
   authoritative state. A generic reply can accept only the last prepared exact decision. Emit
   an event for every lifecycle transition, material decision, candidate freeze, conclusive
   check, operator-review boundary, finding disposition, and terminal reason; append it through
   the supervisor without replaying the ledger or derived artifacts into context.

3. Load only the compiled assignment and role projection and execute worker-owned work in fresh contexts.
   The child's first tool is the exact claim/cursor/dispatch-digest-bound `activation_command`.
   Under rc.19 its second tool executes `commands.result` without its final payload placeholder when
   `commands.result_contract` is `result_without_payload`; this claim-bound contract read returns only the
   exact domain template and bounded failure vocabulary, never source or task context. It verifies
   the refreshed dispatch digest without dumping the dispatch. An rc.18 or rc.19 builder reads
   only the supplied ignored base context pack and any accepted digest-chained delta packs. If a necessary adjacent interface is absent, it may use
   the supplied expansion command for one capsule-preapproved adjacency class; an escalation
   disposition returns to the root and authorizes no wider read. The builder then emits one
   cumulative context snapshot with the latest supplied pack digest and one-shot argv command;
   the supervisor accounts all retained packs in the chain,
   executes the guard array, and submits only action-specific domain details with the provided
   one-shot result array. If a post-guard command cannot complete, use the exact fail-closed array;
   malformed result input itself never writes the ledger. Do not use stdin, a TTY, a pipe, a shell
   wrapper, or EOF for context or result protocol. Then apply these role boundaries:
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
`scope_divergence`, `governance_loop`, `no_progress`, `budget_exhausted`, `protocol_failure`, and
`superseded` are the only kernel terminal reasons. Detail belongs in evidence, not an
unbounded vocabulary. RC.15, RC.16, RC.18, and RC.19 map terminal process facts to at most eight stable `reason_codes` for
the supervisor projection and terminal receipt; the operator summary renders the leading code and
never copies raw or private evidence.

## Change note

- **0.1.0-rc.19 — 2026-08-28:** Preserves RC.11-RC.18 version-gated ledger, claim,
  activation, compact receipt, and worker-context-pack behavior. Adds a read-only, claim-bound
  result-contract mode so a fresh worker retrieves the exact action-specific domain template
  without inlining or duplicating command arrays in root coordination. The same result command's
  exact `protocol_failure` envelope supplies the separate post-guard fail-closed mode with
  a fixed error-code/stage vocabulary; it atomically records `protocol_failure`, while malformed
  result payloads remain no-write. RC.19 receipts continue to target 3,072 bytes with at least
  1,024 bytes of hard-cap margin.

- **0.1.0-rc.18 — 2026-08-28:** Preserves RC.11-RC.16 version-gated capsule, dispatch,
  claim, receipt, and ledger behavior while separating compact coordination transport from
  builder reasoning context. Claim-bearing launch receipts target at most 3,072 bytes under the
  unchanged 4,096-byte cap and carry a hash/locator rather than source or result contracts.
  The supervisor builds and revalidates a capsule-manifested ignored context pack, accounts exact
  serialized bytes against provisional 256-KiB builder and 96-KiB provider artifact allowances,
  supports only preapproved adjacent expansion, and binds result read-back to the exact safe-off
  outside artifact. The demonstration fixture observes an approximately 2.45-KiB handoff receipt
  with more than 1.6 KiB of hard-cap headroom, an approximately 230-KiB base pack, and an
  approximately 15.5-KiB delta carrying a 12.5-KiB adjacent section. The cumulative retained load
  remains more than 11 KiB below the provisional builder allowance. Final tuning remains
  provisional pending two representative live
  builder runs.
- **0.1.0-rc.16 — 2026-08-28:** Preserves RC.15 activation evidence, compact receipts, one-shot
  commands, lifecycle integrity, stable reason codes, and the inclusive 30-second total activation
  hard limit. Changes only the named runtime-build and production-observation post-handoff hard
  limit from inclusive 20 seconds to inclusive 25 seconds; 20/10 remains the optimization target.
  Fixed regressions retain RC.15's terminal 27/21 behavior, allow RC.16 at 27/21 and exactly 30/25,
  and terminalize at 31 seconds total or 26 seconds post-handoff. RC.11-RC.15 objects, hashes,
  receipts, pending claims, and version-gated semantics remain unchanged.
- **0.1.0-rc.15 — 2026-08-28:** Preserves rc.14 compact launch and the full activation/one-shot/
  lifecycle protocol while setting named runtime-build and production-observation activation hard
  limits to inclusive 30-second startup and 20-second post-handoff bounds. The prior 20/10 values
  remain optimization targets. Activation receipts now distinguish exact pre-activation
  `claim_validation` from the newly derived `post_activation_dispatch`. Terminal projections and
  receipts carry bounded stable reason codes, and terminal operator summaries lead with the actual
  process blocker. The RC.15 AE-scale fixture is pinned at 2,969-byte resume, 3,695-byte handoff,
  and 401-byte headroom, with exact inclusive 30/20 and failing 31/21 timing regressions.
  RC.11-RC.14 capsule, dispatch, claim, and receipt behavior remains version-gated.
- **0.1.0-rc.14 — 2026-08-28:** Compacts only start and claim-bearing handoff receipts while
  preserving rc.13 activation, one-shot commands, result contracts, lifecycle integrity, and
  20-second/10-second gates. Deduplicates one-shot metadata and launch policy, and removes
  pre-spawn projection diagnostics without removing executable commands, exact claim/dispatch
  bindings, dependency budgets, or action-specific templates. The permanent AE-scale regression
  reproduces the rc.13 4,155-byte fail-closed receipt and measures rc.14 at 2,941-byte resume and
  3,660-byte handoff under the unchanged 4,096-byte preappend cap. RC.11-RC.13 objects and pending
  claims remain version-gated and unchanged.
- **0.1.0-rc.13 — 2026-08-28:** Adds an atomic claim/cursor/current-dispatch-digest-bound
  worker activation as the child's required first tool and measures session-to-activation and
  handoff-to-activation against 20-second and 10-second runtime-build gates. Launch receipts carry
  the fresh-fork and one-wait root protocol plus compact action-specific input keys/templates.
  Context and result become argv-safe one-shot canonical-JSON base64url commands with no stdin,
  TTY, pipe, wrapper, or EOF dependency. The supervisor derives result lifecycle identity from the
  pending assignment, rejects malformed, tampered, oversized, replayed, or out-of-order inputs
  without mutation, publishes valid compact contracts for every reachable worker action, and
  exposes the next builder launch after an accepted provider inventory. A post-guard lifecycle
  digest preserves tamper detection without rehashing source files that a legitimate builder has
  just changed.
  All additions are version-gated so rc.11 and rc.12 dispatches and pending claims remain stable.
- **0.1.0-rc.12 — 2026-08-28:** Adds compact receipt-driven worker launch data so the root can
  hand off and spawn without opening derived artifacts. Normalizes zero-byte preflight reports
  away from artifact identity, file counts, and repetition; permits multiple same-role zero
  preflights before the final cumulative context; and keeps result binding closed on intervening
  events, prior positive contexts, claim mismatch, or replay. Compiled dispatches publish the
  direct bounded-materialization, context, guard, and result order and exact command arrays.
  Project-relative launch commands share one working directory, bind the current dispatch-file
  digest, and fail before ledger mutation if the complete receipt exceeds 4,096 bytes; these new
  protocol fields are version-gated so rc.11 pending claim hashes remain stable.
- **0.1.0-rc.11 — 2026-08-28:** Widens only the runtime-binding inventory observer's artifact
  ceiling to 10,000 bytes while retaining its 12,000-byte total budget and a 2,000-byte reserve.
  Recomputes dispatches before handoff, context, and guard; binds structured worker claims to the
  exact source assignment; pins named-profile role budgets; requires implementation-source bytes
  before an inventory guard; derives worker roles from the canonical isolation contract; and
  closes generic lifecycle appends behind an ordered, claim-bound, replay-safe result protocol.
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
