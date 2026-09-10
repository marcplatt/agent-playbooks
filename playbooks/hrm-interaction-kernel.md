---
playbook_id: AP-INTERACT-001
title: AP-INTERACT RC.41 - authenticated public templates and stopped RC.40 continuation
version: "0.10.0-rc41"
status: experimental
owner: Adopting organization
mode: local-implementation-review-and-remediation
experiment_id: AP-INTERACT-RC41
---

# HRM interaction kernel

**AP-INTERACT RC.41** develops the [RC.40 experiment](../experiments/ap-interact-rc40/README.md).
It uses software version `0.10.0-rc41` and protocol `ap-hrm-interaction/2`.
It permits isolated repository checks to read an authenticated tracked root
`.env.example` public template while preserving data-read denial for runtime secrets
and untracked or linked lookalikes. The [RC.41 experiment record](../experiments/ap-interact-rc41/README.md)
defines the stopped transition and receipt contract. Production Canary acceptance
remains unproved.

Protocol 2 starts in a fresh private state directory. It does not upgrade, resume,
or rewrite a protocol 1 ledger. Historical AP-EXEC experiments and the earlier
AP-EXEC RC.33 deployment-preflight compiler remain separate lines.

The Ruby service now covers state, local Codex host dispatch, frozen candidate and
check plans, native check execution receipts, independent scenario assessment, and
operator review. These are local implementation controls. They do not deploy a
candidate, apply a provider effect, merge a branch, or establish live canonical
product acceptance.

## Canary meaning and faithful acceptance

A Canary proves that the real end-to-end production route works for a small set
of easy cases. Synthetic input or an operator acting as the customer is valid;
substituting recording or mocked providers is a rehearsal, not a Canary. Preserve
the declared entry routes, real systems, destination and success observation.
Provider API acceptance alone does not prove inbox receipt when receipt is the
requested outcome. Keep broad regression and failure-mode coverage separate.

The orchestrator must not replace an HRM outcome with an easier local contract,
then count enforcement of that contract as success on the original HRM. Label
partial simulation evidence and missing real-system proof explicitly. A pending
review based on a misunderstood outcome must be invalidated when the operator
corrects the meaning. Record the correction without rewriting historical evidence
or treating clarification alone as an instruction to execute live effects.

## Responsibilities

| Actor | Responsibility |
|---|---|
| Operator | Supply intent, resolve genuine business questions, request changes, accept or defer a current milestone review. |
| GPT-6 Astra orchestrator | Reconcile requirements, turn intent into work orders, investigate technical gaps, manage affected evidence, and prepare reviews. |
| GPT-5.6 Sol worker | Implement a bounded work order and submit the artifacts and required check evidence for its exact revision and claim. |
| Fresh GPT-5.6 Sol reviewer | Independently assess consequential work against its requirements and evidence. |
| Kernel | Preserve the ledger, validate commands, serialize ownership, reject stale results, and derive role projections. |

The local CLI remains a trusted caller boundary for actor IDs and operator message
references. The host adapter records a requested model, Codex task/thread evidence,
and a bound structured result. Requested-model metadata is not authenticated proof
of the model that executed. A trusted adapter must verify that a source reference
really came from the operator. Native receipts prove that the declared local process
ran against the bound candidate under the recorded policy; they do not establish
business truth or semantic correctness.

The host passes an explicit native Codex permission profile with strict config
validation: project and declared dependency reads, exact owned-file writes, private
scratch writes, denied operator Documents and kernel control state, and disabled
command networking. Independent reviewers cannot write candidate files. The model
transport keeps its existing authentication; it is not wrapped in another Seatbelt
sandbox. The trusted host prepares missing owned-file parent directories without
granting workers write access to those directories. Sensitive source paths are
excluded from context packets and denied in native command profiles. These profiles
follow the [official permissions configuration](https://learn.chatgpt.com/docs/permissions).
Error findings in structured reviewer output must
name their `scenario_ids`; every such finding is retained as an unresolved kernel
finding. Native receipts bind executable bytes as well as source and check plans.
Third-party dependency trees are not recursively content-addressed, so dependency
changes require a new environment identity and fresh checks.

## Operator interaction

### Technical supervision and versioned continuation

`driver-input --state-dir DIR --input TECHNICAL_INPUT.json` accepts bounded
technical observations from a trusted local supervisor adapter. Each record has
an immutable input ID and source reference. Repeating identical input is safe;
conflicting reuse fails. Records live in a separate private hash-linked journal,
never in the operator intent ledger. They cannot approve work, revise business
requirements, expand execution permissions or satisfy a human decision.

The driver delivers unread observations to Astra and rejects an in-flight response
if trusted input changed after dispatch. Technical evidence can unblock an
engineering or host failure, but cannot override review, decision, preflight or
turn-budget gates. Publication during a synchronized driver step returns an
explicit retry error; the caller must retry the same input ID.

For the supported RC.40 to RC.41 environment transition, stop the old controller between steps,
allow its native jobs to finish and preserve the original state. Invoke
`driver-continue --state-dir SOURCE --destination-state-dir DESTINATION --input CONTINUATION.json`
from a clean committed RC.41 checkout. The source kernel must match its declared
clean RC.40 pin. Supply an explicit `environment_replacement` with a new
`environment_id`, exact `read_roots`, `environment_allowlist`, `preflight_checks`,
and `check_repository`. The repository object names the exact pinned Git executable
and schema `ap-hrm-isolated-head-candidate/2`. The new environment requires fresh
successful preflight; neither Astra nor the technical-input journal can grant it.

The continuation keeps the source ledger byte-for-byte, including submitted
contributions, amendments, original claims and evidence, while retaining the
consumed turn budget, failed requests, unread technical input and every human gate.
Old jobs and check receipts become historical. Active job registries and
model-resume fields are cleared, so cloning does not resume a worker, Astra task or
provider effect. A still-completed contribution must be revalidated in the active
environment. If a later amendment superseded it, the old contribution remains
authenticated historical provenance only; the current revision must be completed
and freshly validated. Historical evidence never transfers eligibility to the
amended revision.

RC.41 bounds a continued source tree to 100,000 entries, 16 MiB per regular file and
2 GiB total. The aggregate allowance preserves the authenticated native candidate
and check history of a sustained run; it does not skip per-file, ownership, mode,
symlink, receipt, hash or unchanged-source verification. The kernel-generated,
losslessly compact source-tree manifest has a separate 64 MiB bound so it can
authenticate the bounded entry set. That bound applies only to exact versioned
`source-manifest.json` paths verified through the continuation digest. Serialization
is checked before copying or preflight; ordinary source files remain limited to
16 MiB.

Receipt-less RC.38 attempts that failed during post-process scratch cleanup never
become native evidence. The RC.39 continuation accepts them only when private,
owner-bound 64-hex execution roots correspond in count to exact failed Driver
cleanup receipts. It copies regular bytes, records source modes and same-run link
targets, and omits the links from the destination. The manifest records failed
request IDs and incomplete run IDs as separate sets with unknown process exit and
`evidence_eligible: false`; it does not invent a request-to-run pairing.

New native receipts validate and remove bounded owned links whose final target is
a regular file or directory in the same disposable execution root after the full
process group ends. Sorted link descriptors and the removal transformation are
authenticated with the receipt, and reuse fails if a link is recreated. Escaped,
broken, root-level, candidate-targeting or special-file entries remain rejected.

Each isolated repository check materializes the source repository's exact HEAD
tree and overlays the captured current candidate. Its worktree is read-only to the
check. Parent objects, source branch and tag refs, reflogs, remotes, hooks,
alternates and ambient Git configuration are unavailable. The receipt binds the source root, HEAD and tree,
candidate manifest, copied object set, pinned Git identity and a raw no-follow
metadata snapshot. Check output must describe this isolated view rather than claim
canonical history validation. Use `{run_root}` for writable caches and fixtures;
`{candidate_root}` refers to the read-only validation root. `configuration_paths`
still names only configuration copied into `{run_root}`.

Within that isolated view, RC.41 permits data reads only for the root
`.env.example` file when pinned Git proves it is a regular tracked file in `HEAD`.
The repository receipt records the HEAD blob OID, source SHA-256 and byte count,
plus the exact candidate SHA-256, byte count and mode. A real `.env`, another
`.env.*` name, an untracked nested `.env.example`, a symlink, or an external target
remains subject to the sensitive-file data-read denial. Preflight and native model
source access do not receive this exception.

The source lock establishes an observed safe boundary; it cannot prove an old
external controller will never restart. Keep that controller stopped. The earlier
RC.35 to RC.36 and RC.36 to RC.37 transitions remain available from their frozen
kernel checkouts. See the RC.41 experiment record for exact JSON contracts and
limitations.

The RC.41 replacement retains this exact repository policy beside the replacement
environment ID, roots, allowlist and preflight checks:

```json
{
  "check_repository": {
    "schema_version": "ap-hrm-isolated-head-candidate/2",
    "kind": "isolated_head_candidate",
    "git_executable": "/absolute/pinned/bundled/git"
  }
}
```

Fresh validation of a preserved completed contribution uses:

```json
{
  "revalidation_id": "unique-id",
  "work_order_id": "completed-work-order-id",
  "check_plan": {
    "environment_id": "active-environment-id",
    "checks": []
  }
}
```

The checks array must contain exactly the order's declared check IDs and normal
frozen execution specifications. Use
`revalidate --state-dir DIR --input REVALIDATION.json` for a direct trusted call;
the Astra request transport exposes the same technical operation but no operator
role, approval, environment grant or effect permission.

### Automatic driver

Initialize the project-owned implementation milestone through the trusted operator
CLI, then call `driver-start` with a private configuration and `driver-run` (or
poll `driver-step`). The configuration freezes environment ID, dependency reads,
environment variable names, startup checks, model reasoning settings, parallelism
and a maximum turn count. Preflight must pass before any claim or model launch;
restart re-verifies its signed receipts, executable and policy bindings.
Choose preflights that exercise representative project imports and check tools.
A version print alone does not establish that the required project checks can run.
If a runtime needs a home directory, declare `HOME` explicitly and use
`HOME: "{run_root}"` for disposable check storage; never substitute the operator's
real home or grant unrelated private directories.

The driver resumes the exact Astra task UUID and transports its structured
requests. It does not plan work or supply a known implementation. It records request
envelopes and receipts, collects completed workers after writers stop, executes
their frozen checks and returns bounded diagnostics to Astra. A worker's `blocked`
result may produce diagnostic evidence; only an `implemented` result with successful
current completion evidence may be submitted. Repeated incomplete work produces
advice to narrow or decompose the assignment, not an inferred operator question.

Only orchestrator commands can enter through Astra's request transport. Human
messages, decisions and review dispositions still enter through the trusted operator
CLI; the driver does not authenticate chat messages. New ledger input during an
Astra turn discards its unapplied requests and supplies the current projection on
resumption. A restart after a partially applied response may conservatively replan;
already committed commands and receipts remain intact.

The driver yields at a current human review or unresolved decision, service failure,
repeated idle response or turn limit. These stops are distinct outcomes. A turn limit
does not reset merely because the ledger changed. Keep the driver running again
after actual operator input to resume a review/remediation cycle. This transport
does not provide a production-effect adapter or an operator review UI.

Preflight is a startup check for the declared environment. It does not recursively
hash dependency trees or replace product tests. The native browser runner permits
only the macOS Chromium rendezvous and RootDomain user-client access required by
the original launch settings; its outer read, write and network restrictions remain.

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
feedback alone cannot let an older result pass review. New intent is additive by
default. `supersedes` must identify the prior intent and exact requirement constraints
for a replacement or removal. Every other active constraint remains attached to the
amended order. Clarifications must name the requirements they affect. Ordinary
conversation does not require a kernel event.

A small correction delivered directly to the same worker may use
`work_order.reopen`. It preserves the work order's paths, checks, and requirements,
records the original operator source through the trusted caller, appends intent, and
creates a new revision and claim. A larger technical gap returns to the Astra
orchestrator, which may expand work-order paths and checks inside the milestone's
already authorized path policy. File count is not a new business decision. A path
outside that policy, a genuinely unresolved business meaning, or a new external
effect follows its existing authority boundary.

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

Milestones move from execution into independent assessment, prepared review,
remediation, and later review. An implementation milestone freezes its initial
contract digest and declares acceptance scenarios with required check IDs. Later
operator requirement amendments retain their before/after revisions and source;
the original outcome and initial digest remain intact.

`milestone.assess` records a fresh reviewer's disposition for every acceptance
scenario, the current candidate digest, requirement revisions, evidence references,
and assessor identity. The builder cannot assess its own candidate. An accepted
assessment and closed work orders are evidence for review readiness; neither is
product acceptance. Only the operator can accept or defer the current review.

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
Native candidate capture binds Git state, authorized paths, the requirement and
work-order contract, and the frozen check plan before execution. A worker result is
never treated as a check receipt or submission command.

In implementation mode, declared checks run as native child processes from the
frozen execution plan. The private authenticated receipt binds the process result,
candidate, claim, work-order and requirement revisions, environment ID, argv,
configuration-presence checks, sandbox policy, and bounded output descriptors. The
service rereads the current candidate and receipt before submission. A worker-authored
report or `completed` status cannot substitute for native execution.

When a sibling edit invalidates checks for an unchanged completed order, rerun its
frozen checks and submit the same host job again. The coordinator uses
`work_order.refresh_evidence` to retain its scope, owner, requirement revision, and
artifact bytes while appending fresh evidence. Previous evidence remains in the
ledger. The refreshed candidate requires a new independent assessment; no new
operator instruction is invented merely to rerun a check. Changed artifact bytes
must use the ordinary engineering correction workflow instead.

Review findings are first-class state. `finding.raise` binds an independent reviewer's
finding to the current candidate and requirement revisions. `finding.resolve` accepts
only `fixed` or `no_change_needed`, current behavioral evidence, and a reviewer who did
not build the candidate. `fixed` also requires changed artifact content. An operator's
`changes_requested` review creates or binds unresolved findings. Open findings block
another `review_ready`; changing only an order revision or report digest does not
resolve them.

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
ruby scripts/hrm_kernel.rb host-dispatch --state-dir /private/run-directory --input worker-job.json
ruby scripts/hrm_kernel.rb host-status --state-dir /private/run-directory --input job-id.json
ruby scripts/hrm_kernel.rb host-collect --state-dir /private/run-directory --input job-id.json
ruby scripts/hrm_kernel.rb check --state-dir /private/run-directory --input check-id.json
ruby scripts/hrm_kernel.rb submit --state-dir /private/run-directory --input job-id.json
ruby scripts/hrm_kernel.rb assess --state-dir /private/run-directory --input review-job-id.json
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

For example, the initial operator command establishes an implementation boundary and
the behavior that independent review must exercise:

```json
{
  "command_id": "create-demo-1",
  "type": "milestone.create",
  "actor": {"id": "operator", "role": "operator"},
  "data": {
    "milestone_id": "HRM-DEMO",
    "outcome": "Review and correct a local information panel",
    "project_root": "/absolute/canonical/path/to/project",
    "mode": "implementation",
    "requirements": [{"id": "REQ-PANEL", "text": "The panel displays the intended information"}],
    "allowed_paths": ["src/**", "tests/**"],
    "acceptance_scenarios": [{
      "id": "ACC-PANEL-01",
      "text": "An operator opens the panel and sees the intended information",
      "requirement_ids": ["REQ-PANEL"],
      "check_ids": ["check-panel-behavior"]
    }]
  }
}
```

The state command families are `milestone.*`, `intent.record`, `work_order.*`,
`finding.*`, and `decision.*`. The host commands dispatch and collect bounded Codex
jobs. `check`, `submit`, and `assess` coordinate native execution and state transitions
from their frozen job records; they do not accept worker-authored substitute commands.
See the state, store, execution, host, and coordinator acceptance tests for complete
shapes.

```sh
ruby examples/hrm_interaction_demo.rb
```

The example retains a fresh private temporary directory and prints the paths to
its result, ledger, and local HTML artifact. Use `--output-dir /absolute/new/path`
to choose the destination; an existing destination is refused. It applies real CLI
commands and checks local fixture behavior through a visual correction and a
multifile API-mirror correction, including rejected stale responses, stale results,
and explicit independent finding resolution. It is a compact coordination fixture;
its operator, worker, and reviewer messages are fixtures rather than actual model
executions, native implementation evidence, or acceptance by a human.

The state directory contains a private hash-linked JSONL ledger. Commands are
validated and appended under an exclusive lock and fsynced. Reads replay that
ledger; projections are derived views and do not grant authority. A corrupted or
truncated ledger fails closed rather than being silently repaired or overwritten.
Preserve a failed ledger for diagnosis and use explicit recovery work.

## Adoption and validation

Adoption is explicit. Use the [RC.41 dispatcher](../templates/hrm-interaction-agents.md)
in an isolated project pilot, pinned to one reviewed AP revision. For Alpine
Estimating, this is an experimental project-profile recommendation only. Preserve
the installed global and repository policies unless their own adoption change is
reviewed. Creating this runtime does not install it globally or activate it in AE.

Run changed-reach checks, including:

```sh
ruby tests/test_hrm_kernel_state.rb
ruby tests/test_hrm_kernel_store.rb
ruby tests/test_hrm_kernel_execution.rb
ruby tests/test_hrm_kernel_host.rb
ruby examples/hrm_interaction_demo.rb
```

The historical `ruby tests/test_hrm_experiment.rb` remains available for compatibility.
Do not create documentation or receipt changes solely to report that checks ran.

## Change note

- **0.10.0-rc41 — 2026-09-10:** Allows the tracked root `.env.example` public
  template to be read only in the isolated repository candidate. The authenticated
  receipt binds its tracked HEAD blob and exact candidate bytes; real environment
  files, untracked examples, symlinks and external paths remain denied. Adds an
  explicit stopped RC.40-to-RC.41 continuation that preserves ledger, work history,
  failed-attempt attribution, technical input and remaining budget while requiring
  fresh preflight and resuming no model task or provider effect.

- **0.9.0-rc40 — 2026-09-10:** Authenticates preserved completed contributions
  against their original hash-linked submit or refresh command and derives their
  current disposition from verified work-order amendment lineage. Adds an explicit
  stopped RC.39-to-RC.40 continuation that preserves ledger, artifacts, failed
  requests, technical-input cursor and remaining budget. Superseded evidence stays
  historical; the current revision requires fresh completion and validation, and
  no model task or provider effect resumes.

- **0.8.0-rc39 — 2026-09-10:** Accepts bounded owned same-run scratch symlinks only after native process cleanup, removes them without following directory links, and authenticates their descriptors in new receipts. Adds an explicit stopped RC.38-to-RC.39 continuation that preserves ledger, contributions, human gates and remaining budget while archiving receipt-less cleanup failures without claiming a test exit or current evidence. No model task resumes and fresh environment validation remains mandatory.

- **0.7.0-rc38 — 2026-09-10:** Preserves completed submissions across the
  stopped RC.37 environment transition while making old receipts ineligible for
  current review. Adds bounded native `revalidate`, an exact-HEAD isolated Git
  candidate with authenticated repository-view receipts, and stale-response
  rejection across the revalidation transaction. Authenticated historical
  execution scratch is copied without mutating source modes and normalized only
  in the private destination. Historical model tasks are not resumed and the
  original ledger authority and turn budget remain intact.

- **0.6.1-rc37 — 2026-09-09:** Corrects stopped-run copying of ordinary test
  scratch inside private execution directories, preserving original permissions
  and bytes while keeping control records strictly private.

- **0.6.0-rc37 — 2026-09-09:** Supports an explicit execution-environment
  transition with a new environment identity, fresh preflight and retained
  evidence. Historical checks do not become new-environment evidence. Preserves
  the original run, operator authority and consumed turn budget.

- **0.5.0-rc36 — 2026-09-09:** Adds separate technical supervisor input,
  stale-response rejection on technical changes, explicit stopped-run continuation,
  and actionable scratch-configuration diagnostics. Keeps the original RC.35
  experiment and AE evidence unchanged; no Canary acceptance is implied.

- **0.4.0-rc35 — 2026-09-09:** Adds native Astra driver transport, exact-task
  continuation, authenticated preflight, diagnostic-only blocked-worker checks,
  bounded continuation advice, and browser startup repairs. Retains protocol 2 and
  historical RC.34 evidence. Develops on the RC.34 experiment branch, not AP main.

- **0.3.0-rc34 — 2026-09-08:** Starts protocol `ap-hrm-interaction/2` with additive
  intent, explicit supersession, immutable initial contract identity, direct same-worker
  intake, native candidate-bound checks, first-class findings, and independent scenario
  assessment. Protocol 1 ledgers remain archival and are not migrated in place.

- **AP-INTERACT RC.33 record — 2026-09-08:** Names PR #10 as the first Astra-driven
  experiment, records its separate ancestry and known defects, and retains AE trial
  findings outside AP `main`. Does not change the kernel or its protocol version.

- **0.2.0-pilot — 2026-09-08:** Introduces a separate local interaction protocol with
  durable operator intent, exact decision binding, general work orders, writer claims,
  and repeated human review/remediation. Keeps legacy RC history intact and makes
  the future host-transport and external-effect boundaries explicit.
