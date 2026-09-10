# AP-INTERACT RC.40: history-aware completed contributions

RC.40 develops RC.39 software version `0.8.0-rc39` on
`codex/ap-interact-rc40`, separate from AP main. Its software version is
`0.9.0-rc40`; the operator ledger remains `ap-hrm-interaction/2`.

## Problem and evidence boundary

RC.39 preserved a completed contribution during an environment transition, then
expected the current work-order projection to remain completed at that exact
revision. A later authorized `work_order.amend` correctly queued a new revision and
cleared its current artifacts, checks and evidence. The Driver then rejected the
older preserved contribution before Astra could commission the revised work.

RC.40 stores only immutable contribution provenance: work-order revision, claim,
worker, artifact digest, evidence digest, check IDs and required fresh-validation
action. It authenticates that record against the original hash-linked
`work_order.submit` or `work_order.refresh_evidence` command. On every projection it
derives whether the evidence still names the completed current revision or is
superseded by an exact amendment-history revision. The derived status is not frozen
in continuation configuration.

An amendment does not make old evidence current. A superseded contribution is
historical only. The active revision must be completed and freshly validated in the
active environment before it can support review. Later owner changes, check-plan
changes and repeated amendments do not rewrite the authenticated old submission.
Missing claim, revision, path or check lineage fails closed.

## Stopped RC.39 to RC.40 transition

Wait for the RC.39 Driver lock to be available and every recorded Host job to be
terminal. From a clean committed RC.40 checkout, run:

```sh
ruby scripts/hrm_kernel.rb driver-continue \
  --state-dir /private/stopped-rc39-state \
  --destination-state-dir /private/new-rc40-state \
  --input /private/rc40-continuation.json
```

The JSON input uses the existing continuation contract:

```json
{
  "new_run_id": "project-rc40",
  "source_kernel_root": "/absolute/clean/rc39-kernel",
  "source_kernel_revision": "40-character-source-commit",
  "controller_stopped": true,
  "supervisor_provenance": {
    "schema_version": "ap-hrm-supervisor-continuation/1",
    "supervisor_id": "trusted-supervisor-adapter",
    "commission_id": "bounded-rc40-transition",
    "asserted_at": "2026-09-10T12:00:00Z",
    "source": "reference to the observed stopped controller and environment facts"
  },
  "environment_replacement": {
    "environment_id": "project-runtime-rc40",
    "read_roots": ["/absolute/declared/dependency-root"],
    "environment_allowlist": [
      "PATH", "GIT_CONFIG_NOSYSTEM", "GIT_CONFIG_GLOBAL",
      "GIT_CONFIG_SYSTEM", "GIT_ATTR_NOSYSTEM", "GIT_OPTIONAL_LOCKS",
      "GIT_NO_LAZY_FETCH", "GIT_TERMINAL_PROMPT", "HOME",
      "PYTHONPYCACHEPREFIX"
    ],
    "preflight_checks": [
      {
        "id": "runtime-startup",
        "environment_id": "project-runtime-rc40",
        "argv": ["/absolute/tool", "startup-check"],
        "env": {
          "PATH": "/absolute/pinned/bundled:/usr/bin:/bin",
          "GIT_CONFIG_NOSYSTEM": "1",
          "GIT_CONFIG_GLOBAL": "/dev/null",
          "GIT_CONFIG_SYSTEM": "/dev/null",
          "GIT_ATTR_NOSYSTEM": "1",
          "GIT_OPTIONAL_LOCKS": "0",
          "GIT_NO_LAZY_FETCH": "1",
          "GIT_TERMINAL_PROMPT": "0",
          "HOME": "{run_root}",
          "PYTHONPYCACHEPREFIX": "{run_root}/pycache"
        },
        "cwd": "/absolute/project-root",
        "timeout_seconds": 60,
        "max_output_bytes": 65536,
        "configuration_paths": []
      }
    ],
    "check_repository": {
      "schema_version": "ap-hrm-isolated-head-candidate/1",
      "kind": "isolated_head_candidate",
      "git_executable": "/absolute/pinned/bundled/git"
    }
  },
  "production": true
}
```

`preflight_checks` must be nonempty and every check must use the replacement
`environment_id`. Supply the exact reviewed RC.40 environment specification; the
paths and command above only show the contract shape.

The transition writes schema `ap-hrm-run-continuation/5` below
`driver/continuation/rc40/`. It copies the operator ledger and historical evidence
unchanged, preserves work-order amendments, artifacts, failed Driver requests,
human gates, technical-input journal and acknowledged cursor, round/max-turn budget,
and incomplete scratch attribution. It clears active Host registries and all model
resume fields, then requires fresh replacement preflight. It resumes no worker,
Astra task or provider effect.

The source lock and trusted supervisor stop assertion establish an observed safe
boundary; they cannot prove an unrecorded old controller will never restart. Keep
the source controller stopped. The new environment identity and exact roots,
allowlist, preflight checks and isolated repository policy remain mandatory. This
transition does not widen project paths, requirements, execution grants, operator
authority, review authority or provider permissions.

## Adoption boundary

RC.40 remains an experimental project-profile candidate. A successful clone,
preflight, native check or local suite is implementation evidence only. It is not
human acceptance, a merge, deployment, provider authorization, customer delivery or
production Canary proof.
