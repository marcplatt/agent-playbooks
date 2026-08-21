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
| [Lane Planning and Execution Standard](playbooks/lane-coordination-standard.md) | Plan and execute a bounded queue of existing lanes with an implementation-readiness gate, behavior-and-reach test planning, live HOTL design batching, risk-scaled exact-head validation, prepared human review, and serialized merges. |

## Using a playbook

1. Open the selected playbook and supply its required inputs.
2. Paste the text under **Prompt** into a Codex task.
3. Keep the coordinator at the outcome and authority level; builders and reviewers receive bounded assignments.
4. Review only prepared UI, UX, function, scope, activation, or irreversible-action gates.

Example:

```text
Use the Lane Planning and Execution Standard.
Lanes: AE-18.13, AE-18.14, AE-18.11, AE-18.12
Objective: complete the approved lanes without adding successors.
```

The intended personal Codex skill entrypoint is `$alpine-workflows`; until that skill is installed, the Markdown playbooks are the canonical invocation source.

## Change standard

Every material playbook change updates its version and change note. Retired playbooks remain in Git history and are not silently repurposed. Never commit credentials, private provider evidence, customer data, generated estimate files, or conversation transcripts.
