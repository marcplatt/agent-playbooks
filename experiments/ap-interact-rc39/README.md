# AP-INTERACT RC.39: bounded native scratch links and stopped RC.38 continuation

RC.39 develops RC.38 software version `0.7.0-rc38` on
`codex/ap-interact-rc39`, separate from AP main. Its software version is
`0.8.0-rc39`; the operator ledger remains `ap-hrm-interaction/2`.

## Problem and boundary

RC.38 correctly confines pytest caches, disposable HOME content and fixtures to
an owner-private execution root. Pytest normally creates `pytest-current` and
per-test `*_current` symlinks inside that root. RC.38 rejected those links after
the native process ended, before writing output or an authenticated receipt.

RC.39 accepts only bounded links whose final target is an owned regular file or
directory inside the same execution root. After the whole check process group is
reaped, the runner validates every scratch entry without following directory
links, removes the accepted links, privatizes the remaining scratch, and binds
the sorted link descriptors and transformation to the HMAC-authenticated native
receipt. Receipt reuse requires every removed link to remain absent.

Escaped, broken, oversized, root-level, foreign-owned, candidate-targeting and
special-file entries fail closed. The isolated candidate and canonical project
permissions do not change. The descriptor does not authorize a check or establish
its outcome; exit status and bounded output remain the only inputs to the native
receipt conclusion.

## Stopped RC.38 to RC.39 transition

Wait for the RC.38 Driver lock to be available and every recorded Host job to be
terminal. From a clean committed RC.39 checkout, run:

```sh
ruby scripts/hrm_kernel.rb driver-continue \
  --state-dir /private/stopped-rc38-state \
  --destination-state-dir /private/new-rc39-state \
  --input /private/rc39-continuation.json
```

The input contract is unchanged except that it must name the exact clean RC.38
kernel pin and a new replacement environment identity:

```json
{
  "new_run_id": "project-rc39",
  "source_kernel_root": "/absolute/clean/rc38-kernel",
  "source_kernel_revision": "40-character-source-commit",
  "controller_stopped": true,
  "supervisor_provenance": {
    "schema_version": "ap-hrm-supervisor-continuation/1",
    "supervisor_id": "trusted-supervisor-adapter",
    "commission_id": "bounded-rc39-transition",
    "asserted_at": "2026-09-10T12:00:00Z",
    "source": "reference to the observed stopped controller and environment facts"
  },
  "environment_replacement": {
    "environment_id": "project-runtime-rc39",
    "read_roots": ["/absolute/declared/dependency-root"],
    "environment_allowlist": [
      "PATH", "GIT_CONFIG_NOSYSTEM", "GIT_CONFIG_GLOBAL",
      "GIT_CONFIG_SYSTEM", "GIT_ATTR_NOSYSTEM", "GIT_OPTIONAL_LOCKS",
      "GIT_NO_LAZY_FETCH", "GIT_TERMINAL_PROMPT", "HOME",
      "PYTHONPATH", "PYTHONDONTWRITEBYTECODE", "PYTHONPYCACHEPREFIX"
    ],
    "preflight_checks": [
      {
        "id": "runtime-startup",
        "environment_id": "project-runtime-rc39",
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
          "HOME": "{run_root}"
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

Each preflight spec and subsequent check uses the new `environment_id`. Writable
pytest caches, bytecode and HOME content remain under `{run_root}`. A normal
project `pyproject.toml` is selected through argv with `configuration_paths: []`.
The isolated repository policy, pinned Git environment and private dependency
roots remain as documented by RC.38.

The transition writes schema `ap-hrm-run-continuation/4` below
`driver/continuation/rc39/`. It copies the operator ledger and completed
contributions unchanged, preserves original claims, artifacts, human gates,
technical-input cursor and the consumed round/max-turn budget, archives every
old Host job, clears active jobs and all model-resume fields, and runs fresh
replacement preflight. No worker, Astra task or provider effect is resumed.
Completed contributions still require fresh `revalidate` receipts under the
RC.39 environment before review readiness.

RC.38 attempts that reached scratch cleanup have no native receipt, stdout or
stderr record. RC.39 never assigns them a test conclusion. When the private
source contains the exact failed Driver cleanup receipt, the continuation may
copy regular bytes from such a 64-hex execution root, record source modes and
same-run link targets, and omit those links from the destination. The v4 manifest
records failed Driver request IDs and incomplete run IDs as separate sets, with
`process_exit_known: false` and `evidence_eligible: false`; it does not invent a
one-to-one pairing. Unattributed or excess incomplete scratch is rejected.

Continuation is atomic at the destination and does not chmod or otherwise mutate
the source. Fresh preflight failure removes the incomplete destination. A
successful clone is implementation evidence only. It grants no operator approval,
path expansion, environment access, provider action, merge, deployment, customer
delivery or production Canary acceptance.

## Current native receipt contract

New RC.39 native and preflight receipts include:

```json
{
  "inert_scratch_links": [
    {
      "path": "pytest-of-unknown/pytest-current",
      "target": "/private/state/execution/id/pytest-of-unknown/pytest-0",
      "resolved_path": "pytest-of-unknown/pytest-0",
      "target_type": "directory",
      "mode": 511,
      "uid": 501
    }
  ],
  "scratch_link_transformation": "removed_after_process_group_termination_before_receipt"
}
```

The descriptor is authenticated with the rest of the receipt. Paths are unique
and sorted. Historical RC.38 receipts remain valid only through the existing
historical continuation verification path; current RC.39 receipts must carry the
new transformation fields.

## Adoption boundary

RC.39 remains an experimental project-profile candidate. Adoption requires a
reviewed AP revision and a separate project decision. A successful transition,
preflight, revalidation or local suite is not human acceptance, a release, a
provider authorization, customer delivery or production proof.
