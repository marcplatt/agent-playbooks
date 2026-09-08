---
playbook_id: AP-INTERACT-001
title: HRM interaction kernel
version: "0.2.0-pilot"
status: experimental
owner: Adopting organization
mode: local-review-and-remediation
---

# HRM interaction kernel

This pilot implements the local command and state layer for commissioning work,
reviewing a milestone, and correcting it without losing the operator's decisions.
It is a separate protocol, `ap-hrm-interaction/1`, from the historical AP-EXEC RC
experiments. It does not upgrade, resume, or rewrite their ledgers.

The deliverable is a working Ruby command service. Automatic Codex task creation,
direct capture of operator messages in worker tasks, model execution, deployment,
and installation into Alpine repositories are subsequent integration work. Model
assignments in state express the requested role configuration; they do not prove
that a model ran.

## Responsibilities

| Actor | Responsibility |
|---|---|
| Operator | Supply intent, resolve genuine business questions, request changes, accept or defer a current milestone review. |
| GPT-6 Astra orchestrator | Reconcile requirements, turn intent into work orders, investigate technical gaps, manage affected evidence, and prepare reviews. |
| GPT-5.6 Sol worker | Implement a bounded work order and submit the artifacts and required check evidence for its exact revision and claim. |
| Fresh GPT-5.6 Sol reviewer | Independently assess consequential work against its requirements and evidence. |
| Kernel | Preserve the ledger, validate commands, serialize ownership, reject stale results, and derive role projections. |

The local CLI is a trusted caller boundary. Actor IDs and operator message references
are supplied by that caller. File permissions and validation do not authenticate a
person, sandbox a worker, prove a source message came from Codex, or establish the
truth of a passing check report. A future task adapter must bind these references
to actual host events and model identities. Until then, a trusted operator or
coordinator invokes commands and a trusted checker supplies reports.

## Operator interaction

An explicit instruction supplies the meaning it states. The orchestrator records it
and commissions implementation without requesting the same permission again.
For example, "the intended API mirror is missing; commission it" releases technical
investigation and local implementation within the adopted project boundary. It
does not require the operator to choose filenames or exported symbols.

An actual unresolved ownership, business rule, or external-effect decision must
name the remaining gap and its source. The kernel validates the record and known
structural rules; semantic correctness remains a judgment to test against real
operator scenarios. There is no metric that declares an interruption legitimate
merely because an agent labelled it `business_meaning`.

Original intent, question, answer, source, and revision remain in the private ledger.
A new actionable instruction invalidates a pending review immediately. It remains
pending until work orders account for all of its named requirements, so recording
feedback alone cannot let an older result pass review. Replacing part of an
assignment supersedes only the intent portions explicitly replaced. Unaffected
portions remain active; removing an assignment does not silently consume its
unreplaced instruction. Clarifications must name the requirements they affect.
Ordinary conversation does not require a kernel event.

A revised question cannot be answered using a stale response. Ordinary and revised
decisions bind the exact effect. Accepting an external-effect decision in this pilot
records a disposition; no operational grant or execution capability is created.
Decision bindings also include requirement revisions. When an operator changes
those requirements, an obsolete question or answer cannot gate or authorize the
new work. Any remaining business question must be assessed in the new context.

An orchestrator may withdraw an unanswered question after identifying it as an
unnecessary gate, preserving its reason in the ledger. It cannot withdraw or revise
an operator's answer. An operator can explicitly reopen an answered decision with
`decision.reopen`; this retains the old disposition and creates a new revision.
Exact duplicate questions are rejected even when an orchestrator invents a new ID.

## Milestones and work orders

Milestones move from execution into prepared review, remediation, and later review.
Only explicit operator acceptance of the current snapshot closes a milestone.
Changes requested during review require changed work before that snapshot can be
presented again. Deferral does not claim acceptance.

Work orders have their own revision, owner claim, paths, checks, and evidence. They
are queued, claimed, completed, amended, released for another attempt, or cancelled.
Every new claim and revision invalidates late results from the previous attempt.
Overlapping paths cannot have concurrent writers. A completed order supplies only
the requirements and evidence it actually names; uncovered requirements prevent
milestone review readiness.

Requirements have individual revisions. A change to one requirement makes old
assignments for it stale while preserving unaffected work. One instruction can be
decomposed into several work orders, each covering a subset of its requirements.
The kernel checks these bindings; the orchestrator and reviewer still judge whether
the implementation satisfies the intended behavior.

A work order specifies desired behavior rather than predetermined output bytes.
The worker chooses the implementation. Its submitted file hashes bind the result
after implementation, and the service rereads them before review and acceptance.
Hash checks cover declared artifacts, not all possible files in the workspace.
An independent checker remains responsible for diff reach and behavioral correctness.

Check reports are separate JSON files under the project root. Each report binds
`check_id`, `conclusion`, `work_order_id`, `revision`, and the exact deliverable
`artifacts` array of path/SHA-256 pairs. The report is not itself a deliverable in
that array, avoiding a self-hash. The submitted check descriptor also binds the
report's path and digest. A passing report from an older revision or different
artifact set cannot be reused as current evidence.

The initial project path policy is fixed for this pilot. The orchestrator may
amend assignments within it. A request outside it remains an explicit limitation;
the service must not silently grant access to another repository or external effect.

## Command interface

```sh
ruby scripts/hrm_kernel.rb --help
ruby scripts/hrm_kernel.rb apply --state-dir /private/run-directory --input command.json
ruby scripts/hrm_kernel.rb status --state-dir /private/run-directory --role orchestrator
ruby scripts/hrm_kernel.rb status --state-dir /private/run-directory --role worker --actor-id builder-1
ruby scripts/hrm_kernel.rb status --state-dir /private/run-directory --role reviewer
ruby scripts/hrm_kernel.rb verify --state-dir /private/run-directory
```

`apply` also accepts `--input -` for JSON on standard input. Each command has a
stable `command_id`, a `type`, an `actor` with `id` and `role`, and command-specific
`data`. Replaying the exact same command ID and payload returns its existing receipt.
Reusing the ID with different contents is rejected.
Errors return nonzero with JSON on standard error containing a readable `error`,
a `code`, and applicable `details`. A rejected command does not append an event.
Uncommissioned instructions and uncovered requirements return `work_remaining`:
they require engineering continuation. An `authority_gap` requires inspecting the
named decision or scope boundary; the code alone is not an instruction to ask the
operator another question.
`redundant_decision` means a current operator instruction already supplies the
exact requested effect, including when the requested scope is a subset of it.

For example, the initial operator command establishes the local milestone boundary:

```json
{
  "command_id": "create-demo-1",
  "type": "milestone.create",
  "actor": {"id": "operator", "role": "operator"},
  "data": {
    "milestone_id": "HRM-DEMO",
    "outcome": "Review and correct a local information panel",
    "project_root": "/absolute/canonical/path/to/project",
    "requirements": [{"id": "REQ-PANEL", "text": "The panel displays the intended information"}],
    "allowed_paths": ["src/**", "tests/**"]
  }
}
```

The supported command families are `milestone.*`, `intent.record`, `work_order.*`,
and `decision.*`. See the executable state acceptance tests for complete examples
of a review/correction cycle, a multifile API-mirror commission, and decision revisions.
The runnable example is fictional local work; it is not evidence of an Alpine
integration or an automatic host task transport.

```sh
ruby examples/hrm_interaction_demo.rb
```

The example retains a fresh private temporary directory and prints the paths to
its result, ledger, and local HTML artifact. Use `--output-dir /absolute/new/path`
to choose the destination; an existing destination is refused. It applies real CLI
commands and checks local fixture behavior through a visual correction and a
multifile API-mirror correction, including rejected stale responses and results.
Its operator and worker messages are fixtures, not actual model executions or
acceptance of this kernel by a human.

The state directory contains a private hash-linked JSONL ledger. Commands are
validated and appended under an exclusive lock and fsynced. Reads replay that
ledger; projections are derived views and do not grant authority. A corrupted or
truncated ledger fails closed rather than being silently repaired or overwritten.
Preserve a failed ledger for diagnosis and use explicit recovery work.

## Adoption and validation

Adoption is explicit. Use the [pilot dispatcher](../templates/hrm-interaction-agents.md)
in an isolated project pilot, pinned to one reviewed AP revision. Preserve the
installed global and repository policies until their adoption change is reviewed.
The AP development instructions do not automatically apply this runtime to projects.

Run changed-reach checks, including:

```sh
ruby tests/test_hrm_kernel_state.rb
ruby tests/test_hrm_kernel_store.rb
ruby examples/hrm_interaction_demo.rb
```

The historical `ruby tests/test_hrm_experiment.rb` remains available for compatibility.
Do not create documentation or receipt changes solely to report that checks ran.

## Change note

- **0.2.0-pilot — 2026-09-08:** Introduces a separate local interaction protocol with
  durable operator intent, exact decision binding, general work orders, writer claims,
  and repeated human review/remediation. Keeps legacy RC history intact and makes
  the future host-transport and external-effect boundaries explicit.
