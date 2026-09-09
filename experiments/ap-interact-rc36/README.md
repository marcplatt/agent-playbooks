# AP-INTERACT RC.36: supervisor evidence and versioned continuation

RC.36 develops frozen RC.35 commit
`14f82502bb9bfbcb27e2dcb7ab6bdb38ac382f97` on `codex/ap-interact-rc36`.
Software version is `0.5.0-rc36`; the operator ledger remains
`ap-hrm-interaction/2`. RC.33/PR #10 remains the first Astra-driven development
in this project. This successor is an experiment, not an AP main release or
evidence that the operator can already rely on autonomous milestone delivery.

## Why this iteration exists

The visible AE trial started at historical commit
`300f2b3294aa9e74b0b569958f4b696bf6480402`, four commits before the accepted
canonical comparison `c360a8d128ba1aa9991cad5fd522d9ee3b3751d2`. The test aims
to observe native Astra commissioning bounded Sol code and documentation work
while retaining the business outcome and real operator reviews.

RC.35 exposed two practical transport defects. A discovery worker consumed too
much context and was interrupted by the supervisor, but Astra received generic
host failure instead of the actual reason and partial usage evidence. Separately,
repeated rejected check plans confused project configuration with disposable
execution configuration. These are engineering failures, not unanswered business
questions for the operator.

The supervisor deliberately stopped the Driver between steps and allowed existing
workers to finish. The AE supervisor reported all nine native jobs terminal: one
interrupted discovery failure and eight successes. Retained candidate files are
`AGENTS.md`, `src/estimating/production_canary_runtime.py`, and
`tests/test_production_canary_runtime_wiring.py`. Their validation is pending.
The milestone remains executing at ledger cursor 7, Driver round 4. Initial
package-import preflight passed; later requested checks were rejected before
execution. No real intake, quote send, receipt or human review occurred.

The supervisor reported aggregate native usage of 11,323,273 input tokens,
10,824,192 cached input tokens and 67,555 output tokens. The interrupted job's
last partial counters are included and labelled separately in private evidence.
These are reported process measurements, not a successful-efficiency benchmark.
The full private state and candidate snapshots remain with the AE task; customer
details and private runtime paths are not published here.

## Implemented behavior

- A trusted local adapter can append bounded, hash-linked technical observations
  with immutable IDs and real source references. Exact replay is idempotent;
  conflicting reuse and overflow reject explicitly.
- Technical evidence has its own cursor. It cannot become operator intent or
  approve a business, review, permission or provider transition. A new observation
  invalidates an in-flight Astra result so it must reconcile current evidence.
- Explicit `driver-continue` copies a stopped RC.35 run into a new private root,
  preserves historical evidence, attributes both kernel revisions and retains
  consumed turns and human gates. It does not replay old Astra requests.
- Copied preflight evidence is reverified against the destination's execution
  policy and executable identity. It remains historical evidence; continuation
  does not label it a fresh startup check.
- Check-plan guidance and validation explain that `configuration_paths` is for
  existing disposable run configuration. Project files such as `pyproject.toml`
  are selected through command arguments with `configuration_paths: []`.

## Trusted adapter commands

Publish technical evidence using a private JSON file:

```json
{
  "input_id": "supervisor-observation-001",
  "kind": "technical_observation",
  "source": {
    "adapter_id": "ap-supervisor",
    "reference": "actual source message or private evidence reference"
  },
  "summary": "A bounded technical observation supported by the referenced evidence",
  "facts": [{"name": "dependency-status", "value": "observed status"}]
}
```

```sh
ruby scripts/hrm_kernel.rb driver-input --state-dir /private/continued-state --input /private/technical-input.json
```

An interruption uses `kind: execution_interruption`, a known
`observed_job: {job_id, status}`, and
`interruption: {failed: true, reason_code, detail}`. Optional `usage` includes
measured `input_tokens`, `cached_input_tokens`, `output_tokens`, `reasoning_tokens`
or `total_tokens`; omit unavailable counters. Source references are trusted-caller
assertions, not independently authenticated human identities.

The continuation input is:

```json
{
  "new_run_id": "ae-rc36-continuation",
  "source_kernel_root": "/absolute/clean/rc35/agent-playbooks",
  "source_kernel_revision": "14f82502bb9bfbcb27e2dcb7ab6bdb38ac382f97",
  "controller_stopped": true,
  "supervisor_provenance": {
    "schema_version": "ap-hrm-supervisor-continuation/1",
    "supervisor_id": "ap-supervisor",
    "source": "actual controller stop evidence reference",
    "commission_id": "ae-rc36-continuation",
    "asserted_at": "2026-09-09T23:00:00Z"
  }
}
```

Replace example references and time with actual evidence. From the committed,
clean RC.36 checkout, with the old controller stopped and native jobs terminal:

```sh
ruby scripts/hrm_kernel.rb driver-continue --state-dir /private/original-state --destination-state-dir /private/new-state --input /private/continuation.json
```

Inspect the returned manifest and publish the actual technical observations before
explicitly running the new Driver. The original controller must stay stopped.
The source lock and stop assertion cannot prevent an unrelated legacy controller
from restarting. The API supports this RC.35-to-RC.36 transition only; it is not a
general ledger migration or budget-reset mechanism.

## Validation scope

Focused checks cover technical-input replay/conflicts, stale response rejection,
failed-dispatch redelivery, human and budget gates, historical-copy preservation,
unsafe continuation refusal, copied-run Driver stepping, and configuration-path
diagnostics. State/store checks and the command-line review/remediation fixture
also pass. The fixture uses invented participants and is not a native AE run.

## Acceptance still required

The AE continuation must retain both Website and Thomas RFQs and the historical
quote roster (ADT20x40 and DT20x40 per RFQ), four operator-controlled sends and
received QBO estimate emails, two complete-RFQ salesperson SMS notifications and
two GHL acknowledgements with their declared read/write/read behavior. Existing
action-time controls remain in force. Inbox receipt is final acceptance evidence;
it does not silently change the business timing of SMS or GHL actions.

Local code, green unit checks, a successful model receipt and `review_ready` each
prove less than this production outcome. The preserved RC.35 trial remains a
partial engineering experiment even if a later RC.36 continuation succeeds.
