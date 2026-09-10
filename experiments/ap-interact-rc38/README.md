# AP-INTERACT RC.38: isolated repository validation and preserved contributions

RC.38 develops RC.37 software version `0.6.1-rc37` on
`codex/ap-interact-rc38`, separate from AP main. Its software version is
`0.7.0-rc38`; the operator ledger remains `ap-hrm-interaction/2`.

## Problem and boundary

RC.37 can replace a stopped run's execution environment, but it treats all old
jobs and receipts as historical and originally refused a transition containing a
completed work order. The AE pilot reached that state legitimately: native workers
submitted contributions before the full declared suite exposed Git-dependent
validation that the frozen environment could not run.

RC.38 carries those submissions forward without rewriting their work orders or
pretending old receipts ran in the new environment. It also supplies real Git
semantics for checks that inspect the repository while withholding canonical Git
history and later known solutions from native workers.

This is a local validation and continuation mechanism. It does not accept a
milestone, amend operator intent, grant a path or environment permission, merge or
deploy code, call a provider, or establish production Canary success.

## Stopped RC.37 to RC.38 transition

The old controller must be stopped between steps and all recorded Host jobs must
be terminal and collectable. From a clean committed RC.38 checkout, run:

```sh
ruby scripts/hrm_kernel.rb driver-continue \
  --state-dir /private/stopped-rc37-state \
  --destination-state-dir /private/new-rc38-state \
  --input /private/rc38-continuation.json
```

The input has this exact top-level shape; `production` defaults to `true`:

```json
{
  "new_run_id": "project-rc38",
  "source_kernel_root": "/absolute/clean/rc37-kernel",
  "source_kernel_revision": "40-character-source-commit",
  "controller_stopped": true,
  "supervisor_provenance": {
    "schema_version": "ap-hrm-supervisor-continuation/1",
    "supervisor_id": "trusted-supervisor-adapter",
    "commission_id": "bounded-transition-commission",
    "asserted_at": "2026-09-10T12:00:00Z",
    "source": "reference to the observed stopped controller and replacement facts"
  },
  "environment_replacement": {
    "environment_id": "project-runtime-rc38",
    "read_roots": ["/absolute/declared/dependency-root"],
    "environment_allowlist": [
      "PATH",
      "GIT_CONFIG_NOSYSTEM",
      "GIT_CONFIG_GLOBAL",
      "GIT_CONFIG_SYSTEM",
      "GIT_ATTR_NOSYSTEM",
      "GIT_OPTIONAL_LOCKS",
      "GIT_NO_LAZY_FETCH",
      "GIT_TERMINAL_PROMPT",
      "HOME",
      "PYTHONPATH",
      "PYTHONDONTWRITEBYTECODE",
      "PYTHONPYCACHEPREFIX"
    ],
    "preflight_checks": [],
    "check_repository": {
      "schema_version": "ap-hrm-isolated-head-candidate/1",
      "kind": "isolated_head_candidate",
      "git_executable": "/absolute/pinned/bundled/git"
    }
  },
  "production": true
}
```

Every preflight and work-order check must use the replacement `environment_id`.
When isolated repository checks are enabled, each check environment must bind the
Git controls exactly:

```json
{
  "PATH": "/absolute/pinned/bundled/git-directory:/usr/bin:/bin",
  "GIT_CONFIG_NOSYSTEM": "1",
  "GIT_CONFIG_GLOBAL": "/dev/null",
  "GIT_CONFIG_SYSTEM": "/dev/null",
  "GIT_ATTR_NOSYSTEM": "1",
  "GIT_OPTIONAL_LOCKS": "0",
  "GIT_NO_LAZY_FETCH": "1",
  "GIT_TERMINAL_PROMPT": "0",
  "HOME": "{run_root}",
  "PYTHONPYCACHEPREFIX": "{run_root}/pycache"
}
```

Use `-o cache_dir={run_root}/pytest-cache` or an equivalent declared scratch path
for tools that write caches. A normal project `pyproject.toml` remains source input;
set `configuration_paths` to `[]` and select it through the tool's project-readable
arguments. `configuration_paths` is only for configuration copied into the
disposable run root.

The transition copies the source into a brand-new destination, preserves the
operator ledger byte-for-byte, records both kernel and environment identities,
retains the supervisor-input cursor and consumed round/max-turn budget, and runs
fresh replacement preflight. Failure removes the incomplete destination and leaves
the source unchanged. The manifest and source snapshots live below
`driver/continuation/rc38/`.

Completed work orders retain their status, revision, claim history, worker,
artifacts, checks and evidence digest. Their old receipts remain historical, so
the derived projection lists them in
`technical_validation.pending_work_order_ids` and blocks review readiness. Running
work orders retain their ledger history, but all old jobs are historical and no
model task is resumed. Astra must release such a claim before a fresh active-
environment dispatch.

## Fresh completed-contribution validation

Astra may request `revalidate`, or a trusted local caller may invoke it directly:

```sh
ruby scripts/hrm_kernel.rb revalidate \
  --state-dir /private/new-rc38-state \
  --input /private/revalidation.json
```

The input contract is:

```json
{
  "revalidation_id": "unique-revalidation-id",
  "work_order_id": "completed-work-order-id",
  "check_plan": {
    "environment_id": "project-runtime-rc38",
    "checks": [
      {
        "id": "declared-check-id",
        "environment_id": "project-runtime-rc38",
        "argv": ["/absolute/tool", "declared", "arguments"],
        "env": {},
        "cwd": "/absolute/project-root",
        "timeout_seconds": 300,
        "max_output_bytes": 1048576,
        "configuration_paths": []
      }
    ]
  }
}
```

The check IDs must exactly equal the completed work order's frozen check IDs and
their executables must have been exercised by replacement preflight. Revalidation
recaptures the current candidate, refuses any artifact change, runs each check and
authenticates its native receipt. Only a fully passed set appends the existing
`work_order.refresh_evidence` event as the preserved worker. That event moves the
old evidence into `evidence_history`; it does not change the work-order contract or
claim new authority.

Revalidation binds both candidate capture and final mutation to the Astra response's
expected ledger cursor without holding the ledger lock while checks run. Operator
input during validation makes the response stale. The successful validation event,
if already committed, remains, while every later request in the old response is
discarded and Astra receives a fresh projection.

## Isolated repository view

For each check, the trusted runner creates a fresh repository beneath its private
execution root. It copies only the exact HEAD commit plus the tree/blob closure
reachable from that tree, materializes regular tracked files and overlays the
captured added, modified and deleted candidate paths. Parent objects are omitted.
The check runs with this directory as its project root, so `__file__`, root-relative
test discovery, `git ls-files`, `git show HEAD:path` and `git diff --check HEAD --`
operate on the same isolated candidate.

The whole candidate and its `.git` metadata are sandbox-write denied. Git runs with
system/global configuration disabled, hooks and fsmonitor disabled, replace objects
disabled, lazy fetch disabled and no terminal prompting. The runner rejects hooks,
alternates, replacement refs, grafts, shallow/linked-worktree controls, symlinks,
special files and hard-linked metadata. It snapshots metadata with no-follow file
reads before any post-check Git command, terminates the check process group, then
verifies HEAD, tree, changes, object policy and metadata before signing the receipt.

The isolated view supports only regular tracked files. It deliberately omits parent
history, source branches and tags, reflogs, remotes, submodules, symlinks and
gitlinks. Checks
requiring ancestry, merge-base, release branches or canonical remote state remain
release/CI responsibilities and cannot use an RC.38 native receipt as equivalent
proof. Checks cannot write source files; writable fixtures, bytecode and caches must
use `{run_root}`. Canonical project `.git` metadata and later history are never
granted to the native check.

## Adoption boundary

RC.38 remains an experimental project-profile candidate. Adoption requires one
reviewed AP revision and an explicit project decision. A successful continuation,
preflight, revalidation or full local suite is implementation evidence only. It is
not a human review disposition, merge, deployment, provider authorization, customer
delivery or production Canary result.
