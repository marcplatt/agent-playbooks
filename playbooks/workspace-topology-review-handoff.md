---
playbook_id: AP-WORKSPACE-001
title: Workspace Topology and Review Handoff
version: "1.0"
status: active
owner: Adopting organization
mode: operator-readable-workspace-control
human_readable: true
machine_readable: true
required_inputs: [project_repository, operator_checkout]
optional_inputs: [current_hrm, published_change_units, cleanup_policy]
controls: [task-is-not-change-unit, one-operator-desk, conditional-worktrees, evidence-safe-cleanup]
---

# Workspace Topology and Review Handoff

Use this playbook to keep fast-moving Git work subordinate to one stable operator surface.

## Policy

- A task or conversation is not a Git change unit.
- A branch represents one published, independently reviewable change unit.
- A worktree is optional and exists only for concurrency, active review runtime, or preservation.
- One designated project checkout is the operator desk; workers never implement there.
- One current-review index locates the HRM package, exact SHA, preview, decisions, and blockers.

## Project-policy adoption text

```text
A task or conversation is not a Git change unit. Attach it to the current HRM session and
a published change unit before creating Git state. Create one branch for that change unit.
Create a worktree only for concurrent execution, an active review runtime, or preservation
of unique unmerged work. Worker agents must not implement in the designated operator
checkout. Maintain one stable current-review index and reconcile eligible worktrees after
verified integration. A possible HRM discovery creates a proposal, not Git workspace state.
```

## Prompt

```text
Reconcile project workspace topology and prepare the operator review handoff.

Project: {{project_repository}}
Operator checkout: {{operator_checkout}}
Current HRM: {{current_hrm_or_none}}

1. Read project policy and inventory this repository only: remote main, local branches,
   registered worktrees, PRs, processes, dirty state, untracked/ignored unique artifacts, and
   the published HRM/change-unit registry. Never scan or mutate sibling repositories.
2. Attach each task to an HRM session and published change unit before creating Git state.
   Reuse the unit's branch. Create a worktree only when its necessity is recorded.
3. Register every worktree with exact path, branch, HRM, change unit, owner, purpose, created
   time, last activity, state, review dependency, unique-work check, and cleanup condition.
4. Keep the operator checkout free of worker implementation. Before `review_ready`, place or
   expose the integrated candidate through the project-defined operator-desk mechanism and
   publish `docs/planning/current-review.md` or an equivalent stable index.
5. The index names current/target HRM, map version, outcome, decisions, review artifact,
   branch and exact SHA, preview command or URL, blockers, discovered-HRM proposals,
   activation posture, and next authorized action. The operator never hunts for a worktree.
6. Classify each worktree as active-current-HRM, retained-for-review, unique-unmerged-recovery,
   cleanup-eligible, or unexplained-blocker. Return unexplained entries before review handoff.
7. After verified integration, remove a clean eligible worktree using repository-safe Git
   operations and read back the result. Dirty, ambiguous, locked, review-dependent, or unique
   work is retained with evidence and recovery action. Never force-delete or discard.
8. Delete branches only under explicit repository policy after remote incorporation and unique-
   work proof. Cleanup need not wait for HRM closure. Finish with a workspace receipt.
```

## Change note

- **1.0 — 2026-08-24:** Initial operator-desk, workspace-registry, and conditional-worktree workflow.
