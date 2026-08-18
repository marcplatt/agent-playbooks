---
playbook_id: AP-LANE-001
title: Lane Coordination Standard
version: "1.0"
status: active
owner: Alpine Structures
mode: lane-coordination
human_readable: true
machine_readable: true
required_inputs:
  - lane_list
  - objective
optional_inputs:
  - required_order
  - authority_exceptions
  - human_review_requirements
controls:
  - project-rules-first
  - bounded-scope
  - dedicated-worktree
  - exact-head-evidence
  - risk-based-review
  - serialized-merges
  - post-merge-verification
  - human-review-gates
---

# Lane Coordination Standard

Use this playbook to coordinate a bounded list of implementation lanes at the highest practical level of abstraction. It supports serial execution and parallel preparation; parallel implementation is allowed only when dependencies and file ownership prove independence.

## Required inputs

- **Lanes:** `{{lane_list}}`
- **Objective:** `{{objective}}`
- **Required order, if any:** `{{required_order_or_none}}`
- **Authority exceptions:** `{{authority_exceptions_or_none}}`
- **Human-review requirements:** `{{human_review_requirements_or_default}}`

## Prompt

```text
Coordinate only these lanes: {{lane_list}}.

Objective: {{objective}}.
Required order: {{required_order_or_none}}.
Authority exceptions: {{authority_exceptions_or_none}}.

Operate autonomously within the approved lane contracts. Do not discover, create,
or begin additional lanes. Read and obey every applicable AGENTS.md before acting.
One lane remains one branch, one dedicated worktree, and one PR unless the owning
project contract explicitly says otherwise.

INTERRUPT THE HUMAN ONLY FOR

- a prepared UI, UX, or functional acceptance review;
- a contract or scope amendment;
- a canary, external or production mutation, deployment, or irreversible migration;
- an unresolved authority decision that materially changes the outcome.

QUEUE PREFLIGHT

1. Reconcile origin/main, existing worktrees, branches, PRs, CI, declared
   dependencies, and file ownership once for the complete named queue.
2. Create a compact execution ledger containing, for every lane: dependency and
   base SHA, worktree, branch, allowed files, checker, risk class, reviewer count,
   human milestone, current state, and merge order.
3. Classify each lane as quick, serial, parallel, or critical.
4. Parallel implementation is permitted only when dependency and file-ownership
   independence are proven. Dependent lanes remain serial.

PIPELINED EXECUTION

5. Keep one builder on the current lane. Give it only the applicable project
   rules, lane specification, worktree, branch, exact base SHA, allowed files,
   checker, and bounded assignment. Do not fork full conversation history.
6. While the current lane builds, one read-only scout may preflight the next
   permitted lane. It may prepare context, checks, and review scenarios but may
   not implement before dependencies merge.
7. Store verbose logs in an artifact or PR body. Require concise structured
   handoffs from every subagent.

CHECK AND REVIEW

8. Freeze the candidate head and run the lane's exact checker without weakening
   or replacing it.
9. Push once, then start GitHub CI and independent exact-head review concurrently.
10. Use one targeted reviewer for quick or standard lanes and no more than two
    for critical lanes. Use a larger council only for a disputed severe finding.
11. A blocking finding must identify a violated invariant and include a
    reproduction, failing test, or concrete contract mismatch.
12. Consolidate reproduced findings into one correction batch. Every new commit
    invalidates prior head evidence; recheck the exact new head.

HUMAN REVIEW

13. Preserve human review of UI, UX, and function, but summon the human only after
    automated checks and agent findings are complete.
14. Prepare the artifact that matches the lane:
    - UI/UX: running local screen, safe fixtures, and scripted scenarios;
    - non-UI function: deterministic scenario walkthrough and outcome matrix;
    - provider/canary: dry-run and read-back evidence with mutations disabled.
15. Present the exact head, expected outcomes, safety state, and only the choices
    requiring human judgment.

COORDINATOR-ENFORCED MERGE QUEUE

16. One coordinator owns the ordered PR ledger and is the only merger for this run.
17. Before each merge, re-read origin/main and verify the lane, dependency/base
    SHA, exact PR head SHA, checker, independent review, CI, and required approval.
18. Merge one PR at a time. Read back main, verify the merge SHA, wait for
    post-merge CI, and record a compact handoff before releasing the next merge.
19. If any merge or API result is ambiguous, reconcile remote state before retrying.

COMPLETION

20. Report completed and unmerged lanes separately. For each lane, record its
    branch, PR, final head, checker, review result, human gate, merge SHA,
    post-merge state, external mutations, and next authorized action.
21. Do not describe a draft PR, local test, notification, proposal, or visible UI
    as merged, deployed, activated, or production-verified evidence.
```

## Change note

- **1.0 — 2026-08-18:** Initial standard. Adds queue-wide preflight, pipelined next-lane preparation, risk-based exact-head review, prepared human acceptance, and a coordinator-enforced serialized merge queue.
