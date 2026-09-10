# AP-INTERACT RC.37: explicit execution environment transition

RC.37 develops RC.36 commit `226782efedc6e393c670a551b2b598dd21658e6d`
on `codex/ap-interact-rc37`, separate from AP main. Software version is
`0.6.0-rc37`; protocol remains `ap-hrm-interaction/2`. The first Astra-driven
development remains RC.33/PR #10.

## Failure observed in the actual AE continuation

RC.36 successfully continued the preserved historical AE run, restored the exact
native Astra task and delivered genuine supervisor observations separately from
operator intent. All 148 preserved RC.35 files retained their recorded hashes.
Initial RC.36 native checks passed imports, source compilation and four inbox
observer tests. Application tests failed during collection because `HOME` was
absent and the sandbox could not resolve the user's home directory. The dispatcher
governance check failed when the system Git shim attempted to use `xcode-select`.

The environment was still frozen to the earlier Python 3.9 roots and two Python
environment variables. A separate Python 3.12 environment had been prepared and
its imports checked, but it was not part of the Driver's preflighted execution
contract. Technical observations correctly could not grant it execution access.
RC.36 had no explicit environment-change operation.

The supervisor stopped the Driver between steps at round 8 of 40 and allowed
useful workers to finish. This is another measured supervisor intervention. The
kernel must support an explicit environment revision rather than repeatedly
commissioning impossible checks or changing product behavior solely to accommodate
the harness.

## Transition requirements

An execution-environment change must name a new environment identity and the exact
executable, dependency-read and environment-variable changes. The trusted
supervisor supplies provenance and the reason for each change. Native model
requests and `driver-input` cannot grant these permissions.

Preserve the stopped source, historical checks, technical journal, operator
decisions, work history and consumed budget. Verify new preflight under the new
policy before dispatch. Old-environment results remain historical evidence and
cannot silently satisfy fresh checks or review. The orchestrator must commission
the appropriate fresh work attempt and validation under the new contract.

Use a disposable `HOME` where needed, not access to the operator's home. The
existing `{run_root}` substitution supports environment values. Preflight should
exercise representative startup/import and check-tool requirements; an executable
version print alone does not demonstrate repository-check readiness. Keep
networking, private-state denial and existing effect controls intact.

This is a bounded transition for unfinished engineering. Already completed or
assessed work cannot be silently carried forward as current evidence after an
environment change. Unsupported states must fail explicitly rather than rewriting
operator decisions or granting a new turn budget.

The trial's Git whitespace command was chosen by the native worker; scoped
repository guidance did not establish it as a named HRM requirement. The
orchestrator may select faithful source-only governance validation. Such a check
is not reported as `git diff --check`, and any separately performed generic Git
hygiene remains outside native acceptance evidence. No canonical Git metadata
grant or privileged Git adapter is part of this iteration.

## Running the supported transition

From a clean committed RC.37 checkout, call:

```sh
ruby scripts/hrm_kernel.rb driver-continue --state-dir /private/rc36-state --destination-state-dir /private/new-rc37-state --input /private/continuation.json
```

Use the RC.36 continuation input shape with actual stop provenance, the clean
RC.36 source pin, a new run ID, and this additional field:

```json
{
  "environment_replacement": {
    "environment_id": "project-runtime-v2",
    "read_roots": ["/absolute/canonical/dependency-root"],
    "environment_allowlist": ["HOME", "PYTHONPATH", "PYTHONDONTWRITEBYTECODE"],
    "preflight_checks": [
      {
        "id": "project-imports-v2",
        "environment_id": "project-runtime-v2",
        "argv": ["/absolute/python", "-c", "import your_project; print('runtime-ready')"],
        "env": {"HOME": "{run_root}", "PYTHONPATH": "/absolute/project/src", "PYTHONDONTWRITEBYTECODE": "1"},
        "cwd": "/absolute/project",
        "timeout_seconds": 30,
        "max_output_bytes": 16384,
        "configuration_paths": [],
        "startup_success_marker": "runtime-ready"
      }
    ]
  }
}
```

Replace example paths and imports with the actual bounded project requirements.
The new manifest and archived source configuration live under
`driver/continuation/rc37/`; prior continuation evidence stays unchanged.
Inspect the manifest and fresh preflight receipts before starting the new Driver.
A failed fresh preflight rejects the transition and removes its incomplete
destination; the source remains unchanged. Capture the returned error for diagnosis.

Copied jobs are historical diagnostics. The orchestrator can use
`historical_resume_job_id` only for the latest eligible attempt on the same current
work-order revision and claim. Otherwise it must release and rebind the claim.
Either route needs a fresh job and active-environment check plan. The original
controller remains stopped.

Validation includes continuation copy/authority/cursor preservation, actual fresh
preflight and failure atomicity, historical-job rejection through Driver and
Coordinator, constrained worker resumption, private dependency model denial,
and a real Python disposable-home isolation test. The combined kernel tests and
command-line review/remediation fixture pass. These are kernel checks, not AE
production delivery evidence.

## Canary interpretation

The public Website form and chat UI were found during read-only discovery. An
earlier disabled-form observation applied only to a local draft route; it was not
evidence that the public production form was disabled. No submission or chat
message was sent during that discovery.

Real Website and Thomas intake, the declared QBO quote roster and inbox receipts,
SMS/GHL obligations, and actual operator reviews remain pending. Neither RC.36
mechanics nor this environment repair demonstrates final Canary success. Keep
each version's failures and interventions visible when evaluating whether the
operator can work primarily at the HRM review level.
