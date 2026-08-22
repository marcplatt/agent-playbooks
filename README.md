# Alpine Agent Playbooks

Version-controlled, human-readable and machine-readable Codex workflows for Alpine Structures.

## Purpose

This repository keeps proven coordination and elicitation patterns outside chat history so they can be invoked consistently, reviewed like code, and improved without expanding every project's instructions.

## Repository contract

- `playbooks/` contains reusable workflows with YAML metadata and a paste-ready prompt.
- `templates/` contains reusable output forms such as complete project HRM maps,
  contract-update requests, execution ledgers, and human-review packets.
- `examples/` contains representative completed uses without secrets or customer data.
- Project `AGENTS.md` files remain authoritative for project-specific rules.
- Approved project intent and operator progress remain in the owning project's complete,
  versioned HRM map and milestone contracts. Lane records remain subordinate implementation history.
- Business evidence and elicitation results remain in their owning system-of-record repository.

Playbooks must defer to the applicable `AGENTS.md`. They may coordinate approved work, but may not invent authority, weaken checkers, bypass human gates, or treat a draft, local result, or proposal as merged or activated truth.

## Available playbooks

| Playbook | Use |
|---|---|
| [System Build and Human Review Milestone Standard](playbooks/system-build-standard.md) | Advance one HRM from the complete project map, autonomously route missing promises as contract-update requests, derive subordinate lanes, and stop for explicit operator function/UI/UX acceptance without implying activation. |
| [HRM Bundle Coordination Standard](playbooks/lane-coordination-standard.md) | Execute a published milestone bundle quietly with behavior-and-reach test planning, exact-head validation, deterministic integration, a conspicuous HRM review stop, and safe worktree cleanup. |

## Templates and examples

- [Complete project HRM map](templates/project-hrm-map.yaml)
- [Contract-update request](templates/contract-update-request.yaml)
- [HRM review package](templates/hrm-review-package.md)
- [HRM session ledger](templates/hrm-session-ledger.yaml)
- [Example HRM-directed session](examples/hrm-directed-session.example.yaml)

## Draft playbooks

| Playbook | Use |
|---|---|
| [Master-Plan Policy Amendment and Propagation](playbooks/master-plan-policy-amendment.md) | Elicit and version policy/contract answers, distinguish requests from adopted meaning, and rebaseline every affected repository and HRM. |
| [Bidirectional Master-Plan Repository Polling and HRM Intake](playbooks/master-plan-repository-polling.md) | Route accepted master-plan changes, HRM obligations, and contract-update requests bidirectionally while keeping implementation lanes subordinate and status honest. |

## Using a playbook

1. Open the selected playbook and supply its required inputs.
2. Paste the text under **Prompt** into a Codex task.
3. Supply or discover the complete versioned project HRM map, then name the system,
   target HRM, outcome, and authority envelope; do not reconstruct a lane queue unless
   constraining legacy work.
4. Review only prepared UI, UX, function, scope, activation, or irreversible-action gates.

Example:

```text
Use the System Build and Human Review Milestone Standard.
System: SYS-EXAMPLE-001 in the current project.
Project HRM map: milestones/index.yaml.
Target HRM: HRM-2.
Milestone outcome: the operator can complete and correct the local workflow and
understand failures without external writes.
Activation posture: read-only.
```

The system-build playbook derives and publishes the lane bundle under the project HRM
contract and invokes the lane coordinator. The operator lives at the HRM layer: routine
lane details stay quiet, while prepared function/UI/UX review, material decisions, and
persistent blockers are explicit. Direct lane-coordinator use is reserved for a
published milestone session contract or a bounded legacy/recovery constraint.

For new projects, publish all intended HRMs at inception. Unknowns may remain visibly
`unknown-blocked`; they may not be replaced with invented facts. A missing inter-system
promise becomes a stable `CTRQ` whose creation does not adopt the answer.

The intended personal Codex skill entrypoint is `$alpine-workflows`; until that skill is installed, the Markdown playbooks are the canonical invocation source.

## Change standard

Every material playbook change updates its version and change note. RES-0002 supplies the
HRM-first operating model while preserving RES-0001 evidence separation. Retired
playbooks remain in Git history and are not silently repurposed. Never commit credentials,
private provider evidence, customer data, generated estimate files, or conversation transcripts.
