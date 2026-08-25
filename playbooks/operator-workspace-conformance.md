---
playbook_id: AP-CONFORM-001
title: Operator-Workspace Conformance and Synchronization
version: "1.1"
status: active
owner: Adopting organization
mode: read-only-audit-then-authorized-synchronization
human_readable: true
machine_readable: true
required_inputs: [operator, workspace, process_source]
optional_inputs: [organization_master_plan, project_repositories, prior_workspace, operator_preferences]
controls: [portable-process-source, exact-version-adoption, layered-instructions, fresh-session-probes, operator-authorized-writes]
---

# Operator-Workspace Conformance and Synchronization

Use this playbook when an experienced operator is bringing a new account, machine,
workspace product, organization, or project set into conformance with the Agent Playbooks
method. It is separate from operator onboarding: teach only the unfamiliar surfaces the
operator asks about, and concentrate on evidence, drift, and repair.

Account setup alone cannot establish conformance. Required method and project guidance must
be portable, versioned, and reviewable outside one account's chat history or memory. The
operator's personal preferences remain a distinct local layer.

## Portable conformance layers

| Layer | Owns | Portable source |
|---|---|---|
| Transferable process | HRM workflow, prompts, schemas, and fixed invariants | Exact version or commit of this Agent Playbooks repository |
| Organization adoption | Business authority, system portfolio, accepted process version, deviations, and cross-system policy | Organization-owned master plan and explicit adoption decision or ADR |
| Project binding | Project plan, requirements, HRM map, local instructions, current review, checkers, and evidence | Version-controlled project repository |
| Operator preference | Communication style, explanation depth, notification posture, and personal defaults | Workspace-supported user instruction or profile layer |
| Machine capability | Models, permissions, sandbox, tools, hooks, skills, integrations, paths, and credentials | Machine configuration plus separately authorized and authenticated services |
| Recall | Helpful prior context | Workspace memory; never the sole source of a required rule or authority |

For Codex, typical surfaces are global `~/.codex/AGENTS.md` for personal guidance,
repository `AGENTS.md` files for durable project rules, trusted project `.codex/config.toml`
for project configuration, and `.agents/skills` for reusable repository workflows. Codex
local memories and many machine settings are local rather than repository authority. For a
different workspace product, discover and record the equivalent surfaces instead of assuming
Codex paths.

Keep the always-loaded instruction layer concise. It should name the controlling sources,
non-negotiable stops, routing order, and verification command; detailed workflows belong in
versioned playbooks or skills. A link without an instruction to read and verify the source is
not evidence that an agent loaded it.

## Fixed conformance assertions

A workspace is not conformant until fresh-session evidence shows that it:

1. Preserves operator authority over business meaning, protected effects, material UX and
   function acceptance, HRM closure, risk acceptance, and activation.
2. Uses a complete-as-presently-knowable, versioned HRM map and controlled HRM discovery,
   addition, split, removal, resequencing, and supersession.
3. Routes S0 immediately, S1 before assumption or non-disposable work, S2 in bounded batches,
   and only reversible S3 decisions autonomously inside accepted semantics.
4. Requires semantic readiness before substantive implementation and a deliberately
   disposable proof of the riskiest seam before deriving a large bundle.
5. Treats a task or conversation as distinct from a Git change unit; gives each published
   change unit one branch, normally one PR, and one integration receipt; and uses worktrees
   only for concurrency, active review runtime, or preservation.
6. Provides one stable operator review surface and makes safe discovery, decision, and review
   packets available before unrelated application CI, merge receipts, or cleanup.
7. Classifies validation subjects by behavior and dependency reach as review_packet,
   executable_contract, or runtime_change and records targeted, affected, or full CI without
   weakening mandatory project controls or automatically promoting canaries to full CI.
8. Delegates exact-head checks, serialized merge, remote-main verification, and eligible
   cleanup to a source-read-only checker/merge controller. Dedicated repository queues may
   have separate controllers, but repository mutation requires the one current, read-back-
   verified writer lease for the canonical remote and target ref. A hosted merge queue acting
   as writer puts controllers in observe-only mode. Controllers cannot edit candidates,
   decide semantics, waive gates, or contact the operator.
9. Keeps implementation, integration, HRM acceptance, deployment, activation, canary,
   production observation, and autonomy eligibility as independent evidence and authority
   states.
10. Consumes organization changes only through status-qualified, exact-source, semantically
   readable inputs and never treats a proposed or stale record as adopted.
11. Uses hosting read-back as the terminal integration receipt, avoids recursive receipt-only
    changes, and cleans only worktrees proven clean, integrated, unlocked, non-review-dependent,
    free of unique artifacts, and unused by running processes.

## Prompt

```text
Audit and, only after authorization, synchronize this operator-workspace pair with the
Agent Playbooks method.

Operator: {{operator}}
Workspace and machine: {{workspace}}
Process source and required version: {{process_source}}
Organization master plan: {{organization_master_plan_or_unknown}}
Project repositories: {{project_repositories_or_none}}
Prior workspace or profile: {{prior_workspace_or_none}}
Operator preferences: {{operator_preferences_or_none}}

0. Start read-only. State that no account setting, file, repository, branch, instruction,
   memory, integration, credential, or external system will be changed until the operator
   reviews a proposed synchronization plan and authorizes specific writes.
1. Ask for the desired scope and what the operator already knows. Use an experienced-operator
   fast path by default: do not reteach Git, HRMs, Codex, or governance unless requested or a
   detected misconception would make the audit unsafe.
2. Resolve the exact transferable process source and version. Confirm that `AP` means Agent
   Playbooks. Do not import another organization's accepted identifiers, authority, system
   boundaries, or decisions. Identifiers such as RES-0001, RES-0002, and ADR records have only
   the meaning and status assigned by their owning organization.
3. Inventory the current workspace's instruction precedence, account or user preferences,
   project instructions, configuration, permission and sandbox posture, models, skills,
   plugins, hooks, tools, connectors, authentication requirements, repositories, operator
   checkout, current-review surfaces, and memory behavior. Do not read secrets. Mark every
   surface portable-repository, portable-package, local-machine, local-account,
   reauthorization-required, or unknown.
4. Inspect the organization master plan, when present, for an explicit adoption decision that
   binds the organization to the exact process version and records any deviations. Inspect
   each project for an exact organization connection, system plan, requirements and scenarios,
   implementation manifest, current HRM map, current-review surface, change-unit policy,
   validation routing, and activation boundary. Missing organization elicitation is a separate
   business-elicitation task; do not perform it here.
5. Audit every fixed conformance assertion in this playbook using exact current evidence.
   Classify each pass, gap, stale, contradiction, unknown-blocked, or not-applicable. A copied
   file, remembered instruction, branch, local modification, or screen observation does not
   prove adoption or current conformance.
6. For Codex, verify the effective instruction chain from global guidance through the project
   root and current directory; check that required content is not displaced by overrides or
   instruction-size limits; and start a fresh session after instruction changes because the
   chain is assembled at session start. Keep required team rules in version-controlled
   instructions or skills, not only in memories. For other workspace products, perform the
   equivalent effective-instruction verification.
7. Run read-only fresh-session conformance probes against the workspace. Require it to explain
   the controlling process and organization sources, distinguish proposed from adopted
   records, stop on a missing HRM contract, route an S1 ambiguity before implementation,
   propose HRM_DISCOVERY for a newly distinct human outcome, allow early access to a safe
   review_packet without application CI, enforce an explicitly justified limited-scope
   canary CI handoff without inventing a full-suite requirement, delegate check/merge/read-
   back/cleanup to a source-read-only controller, require affected checks for runtime_change,
   refuse to infer activation from merge or deployment, and preserve a dirty or unique worktree.
   Record observed behavior, not expected behavior.
8. Present a concise conversational gap summary grouped by transferable process,
   organization adoption, project binding, operator preference, machine capability, and
   reauthorization. Do not create or commit a conformance report unless requested.
9. Propose the smallest synchronization plan. Separate personal/local settings, reusable
   process installation, organization governance, and each project repository into their own
   authority and change boundaries. State exact files or settings, reason, risk, rollback,
   credentials or sign-ins needed, and the conformance probe that will verify each change.
10. Ask the operator which writes to authorize. A general desire for conformance is not
    authorization to alter accepted organization meaning, weaken security, copy credentials,
    install tools, connect accounts, merge repositories, deploy, activate, or affect
    production. Read the authorized scope back before acting.
11. Apply only the selected writes. Use version-controlled change units for shared process,
    master-plan, and project changes; use the workspace's supported user configuration for
    personal preferences; and require interactive reauthorization for connectors and secrets.
    Never use memory as the only carrier of a fixed rule.
12. Restart or open a fresh workspace session and rerun the affected probes. Report exact
    passes, remaining gaps, source versions, local-only dependencies, and next operator choice.
    Do not claim organization, project, deployment, or production conformance beyond the
    evidence actually verified.
```

## Completion

The read-only audit completes when every in-scope layer and fixed assertion has a truthful
state and proposed recovery path. Synchronization completes only for the exact writes the
operator authorized and the fresh-session probes verified. Either may end as a conversational
session without a durable report.

## Change note

- **1.1 — 2026-08-25:** Adds conformance probes for the source-read-only checker/merge
  controller and explicitly authorized targeted, affected, or full CI, including bounded
  canary validation.
- **1.0 — 2026-08-25:** Initial organization-neutral account, machine, workspace, and project
  conformance audit with portable layers, fixed HRM assertions, operator-authorized writes,
  and fresh-session behavioral probes.
