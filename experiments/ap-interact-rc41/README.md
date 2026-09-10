# AP-INTERACT RC.41: authenticated public environment template

RC.41 develops RC.40 software version `0.9.0-rc40` on
`codex/ap-interact-rc41`, separate from AP main. Its software version is
`0.10.0-rc41`; the operator ledger remains `ap-hrm-interaction/2`.

## Public-template boundary

RC.40 denied file-data reads for every `.env.*` basename. That correctly protected
runtime credentials, but also prevented repository governance tests from reading a
tracked public `.env.example` template in the isolated exact-HEAD candidate.

RC.41 allows only the root `.env.example` path, only inside the read-only isolated
repository view, and only when pinned Git proves that `HEAD` tracks it as a regular
blob. The authenticated repository receipt binds the tracked blob OID, source
SHA-256 and byte count, and the exact isolated-candidate SHA-256, byte count and
mode. Candidate and metadata manifests remain bound as before.

The replacement environment uses repository schema
`ap-hrm-isolated-head-candidate/2`. Schema v1 remains readable only for historical
RC.40 verification and does not receive the public-template allowance.

Tracked `.env`, every other real `.env.*` file, untracked or nested
`.env.example`, symlinks, hard links, external targets and special files remain
denied or rejected. The allowance does not apply to preflight against the canonical
project or to native model source permissions. It grants no credentials or runtime
environment values.

## Stopped RC.40 to RC.41 transition

After the RC.40 controller is stopped and every Host job is terminal, invoke from a
clean committed RC.41 checkout:

```sh
ruby scripts/hrm_kernel.rb driver-continue \
  --state-dir /private/stopped-rc40-state \
  --destination-state-dir /private/new-rc41-state \
  --input /private/rc41-continuation.json
```

The input names the exact clean RC.40 source pin, explicit
`controller_stopped: true`, trusted supervisor provenance, a new run ID, and a full
replacement environment with a new environment ID, exact roots, allowlist,
nonempty preflight checks and the existing isolated repository policy. The
transition writes schema `ap-hrm-run-continuation/6` under
`driver/continuation/rc41/`.

The source ledger, state, work-order amendments, completed and queued work,
artifacts, failed Driver requests, historical execution attribution, human gates,
technical-input journal and acknowledged cursor, round count and max-turn budget
are copied unchanged. All old Host jobs are archived, active job and model-resume
registries are cleared, and fresh replacement preflight is mandatory. No worker,
Astra task or provider effect resumes through the clone. Historical checks remain
ineligible for current validation.

The source remains subject to the 100,000-entry, 16 MiB-per-file and 2 GiB-total
continuation bounds and all ownership, mode, no-follow, receipt, hash and
unchanged-source checks. These explicit aggregate bounds preserve a sustained
full-suite run whose authenticated execution history exceeded RC.40's smaller
limits; no history or artifact is pruned. The kernel's lossless compact source-tree
manifest has a separate 64 MiB bound because it authenticates up to 100,000 bounded
entries and can therefore exceed the ordinary per-file bound. That exception applies
only to exact versioned `source-manifest.json` paths whose contents are checked
against the continuation digest; ordinary state files remain limited to 16 MiB.
Serialization is bounded before copying or preflight. The source lock observes a
stopped boundary but cannot prove an unrecorded old controller will never restart.

## Adoption boundary

RC.41 remains an experimental project-profile candidate. A successful clone,
preflight, check or local suite is implementation evidence only. It is not human
acceptance, a merge, provider authorization, deployment, customer delivery or
production Canary proof.
