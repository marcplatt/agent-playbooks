---
playbook_id: AP-LANE-001
title: Lane Planning and Execution Standard
version: "2.0"
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
  - risk-based-review
  - bounded-correction-loops
  - serialized-merges
  - post-merge-verification
  - human-review-gates
  - phase-timing-ledger
---

# Lane Planning and Execution Standard

Use this playbook to plan and execute a bounded queue of existing lanes at the
highest practical level of abstraction. The coordinator owns state, authority,
dependencies, evidence, and merge order; builders implement; independent reviewers
verify exact heads. Parallel coding is used only when dependencies and file ownership
prove independence. Otherwise, preparation, CI, review, and acceptance setup overlap
while the critical path remains serial.

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
   files, checker, risk, reviewer count, human gate, PR/head, merge order, timing,
   and next action in one compact execution ledger.
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
8. Mark it READY, READY WITH APPROVED AMENDMENT, or BLOCKED. A merely planned,
   contradictory, or unknown-contract lane does not enter implementation.
9. Batch all foreseeable gaps into one approval packet: observed reality, proposed
   contract amendment, effects, files/owners, alternatives, safe default, and
   recommendation. Ask once, then update the authoritative contract before building.

RUN THE FASTEST SAFE FLOW

10. Assign one builder per released lane. Multiple builders may run only for lanes
    proved PARALLEL and READY. During serial work, use a free slot for the next lane's
    read-only readiness audit, checker preparation, or acceptance scenarios.
11. Builders stay inside approved files and behavior, preserve safety seams and human
    control, add tests, and run focused checks. An undeclared file, policy, dependency,
    contract, or external write returns to the coordinator as a scope divergence.
12. Freeze the candidate, verify its ownership boundary, run the exact lane checker,
    push, and bind the PR body and evidence to the candidate head SHA.
13. Run CI and exact-head independent review concurrently: one reviewer normally, at
    most two for CRITICAL lanes. Blocking findings require a violated invariant plus a
    reproduction, failing test, or concrete contract mismatch.
14. Deduplicate and reproduce findings, then send one correction batch. Any new commit
    invalidates prior head evidence and must be rechecked. After two material correction
    rounds, stop patch cycling and reassess readiness, decomposition, and contract.

PREPARE HUMAN ACCEPTANCE

15. Interrupt the human only for one batched contract/scope decision; a prepared UI,
    UX, or functional review; an unresolved authority decision; or action-time approval
    for a canary, external/production mutation, deployment, or irreversible migration.
16. Present the exact head and only the needed judgment with expected outcomes, known
    limits, safety state, and a suitable artifact: running local UI plus script,
    deterministic functional scenarios, or mutation-disabled provider dry run/read-back.
    Prior discussion, a lane doc, or a general instruction to finish is not action-time
    approval for an external or irreversible operation.

SERIALIZE AND VERIFY MERGES

17. One coordinator is the only merger. A PR is READY TO MERGE only when its exact
    head has the required checker, CI, independent review, human approval, scope,
    ownership, and dependencies. Git supplies merge primitives; the coordinator is
    the queue unless a hosted merge queue is explicitly enabled.
18. Before every merge, fetch and re-read origin/main and verify the PR head and gates.
    Merge one PR, read back the remote merge/main SHA, wait for required post-merge CI,
    and record a compact handoff before releasing the next. Reconcile any ambiguous
    mutation result before retrying.

MEASURE AND REPORT

19. Timestamp readiness, build, check, CI/review, correction rounds, human wait, merge,
    and post-merge verification. Separate active, automated-wait, and human-wait time.
20. Report completed, blocked, and unmerged lanes separately with branch, PR, final
    head, gates, correction rounds, human decision, merge/main SHA, external mutations,
    elapsed-time breakdown, and next action. State the critical path, useful parallel
    work, avoidable delay, and one process improvement for the next run.
21. Never describe a draft, local test, notification, proposal, visible UI, or queued
    merge as merged, deployed, activated, or production-verified evidence.
```

## Machine-readable ledger contract

```yaml
lane:
  id: "{{lane_id}}"
  state: "queued|readiness_audit|blocked_contract|awaiting_amendment_approval|ready_to_build|building|candidate_frozen|checking|reviewing|correcting|awaiting_human_acceptance|ready_to_merge|merging|verifying_main|complete|blocked"
  classification: "quick|serial|parallel|critical"
  contract: "{{path}}"
  dependencies: []
  base_sha: null
  worktree: null
  branch: null
  allowed_files: []
  checker: null
  reviewer_count: 1
  human_milestone: null
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

- **2.0 — 2026-08-18:** Adds a pre-build readiness audit, one batched amendment packet, explicit serial/parallel classification, bounded coordinator/reviewer roles, consolidated corrections with a two-round reassessment threshold, prepared acceptance, phase timing, and critical-path reporting.
- **1.0 — 2026-08-18:** Initial queue-wide coordination, exact-head review, prepared human acceptance, and coordinator-enforced merge queue.
