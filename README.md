# Alpine Agent Playbooks

Version-controlled, human-readable and machine-readable Codex workflows for Alpine Structures.

## Purpose

This repository keeps proven coordination and elicitation patterns outside chat history so they can be invoked consistently, reviewed like code, and improved without expanding every project's instructions.

## Repository contract

- `playbooks/` contains reusable workflows with YAML metadata and a paste-ready prompt.
- `templates/` contains reusable output forms such as execution ledgers and human-review packets.
- `examples/` contains representative completed uses without secrets or customer data.
- Project `AGENTS.md` files remain authoritative for project-specific rules.
- Approved implementation scope remains in the owning project's lane or contract documents.
- Business evidence and elicitation results remain in their owning system-of-record repository.

Playbooks must defer to the applicable `AGENTS.md`. They may coordinate approved work, but may not invent authority, weaken checkers, bypass human gates, or treat a draft, local result, or proposal as merged or activated truth.

## Available playbooks

| Playbook | Use |
|---|---|
| [System Build and Human Review Milestone Standard](playbooks/system-build-standard.md) | Advance a system to an operator-selected HRM by resolving evidence and milestone contracts, deriving and publishing the necessary lane bundle, coordinating review/remediation, and requiring explicit human closure without implying activation. |
| [HRM Bundle Coordination Standard](playbooks/lane-coordination-standard.md) | Execute an approved milestone bundle with behavior-and-reach test planning, live HOTL design batching, risk-scaled exact-head validation, deterministic integration, milestone review/remediation states, and safe automatic worktree cleanup. |

## Templates and examples

- [HRM review package](templates/hrm-review-package.md)
- [HRM session ledger](templates/hrm-session-ledger.yaml)
- [Example HRM-directed session](examples/hrm-directed-session.example.yaml)

## Draft playbooks

| Playbook | Use |
|---|---|
| [Master-Plan Policy Amendment and Propagation](playbooks/master-plan-policy-amendment.md) | Elicit and version one or more policy amendments, determine implied contract and authority changes, and propagate approved records through every registered affected repository. |
| [Bidirectional Master-Plan Repository Polling and Lane Intake](playbooks/master-plan-repository-polling.md) | Run one task per application repository to turn accepted master-plan changes into mirrors/lanes and merged repository changes into implementation receipts, evidence pointers, drift findings, or amendment proposals. |

## Using a playbook

1. Open the selected playbook and supply its required inputs.
2. Paste the text under **Prompt** into a Codex task.
3. Name the system, target HRM, milestone outcome, and authority envelope; do not reconstruct a lane queue unless constraining legacy work.
4. Review only prepared UI, UX, function, scope, activation, or irreversible-action gates.

Example:

```text
Use the System Build and Human Review Milestone Standard.
System: SYS-EXAMPLE-001 in the current project.
Target HRM: HRM-2.
Milestone outcome: the operator can complete and correct the local workflow and
understand failures without external writes.
Activation posture: read-only.
```

The system-build playbook derives the approved lane bundle and invokes the lane
coordinator. Direct lane-coordinator use is reserved for an already-approved milestone
session contract or a bounded legacy/recovery constraint.

The intended personal Codex skill entrypoint is `$alpine-workflows`; until that skill is installed, the Markdown playbooks are the canonical invocation source.

## Change standard

Every material playbook change updates its version and change note. Retired playbooks remain in Git history and are not silently repurposed. Never commit credentials, private provider evidence, customer data, generated estimate files, or conversation transcripts.
