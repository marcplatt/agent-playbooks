# AP-INTERACT RC.33 experiment record

`AP-INTERACT RC.33` is the archival name for Agent Playbooks pull request #10,
the first development pilot designated as orchestrated by GPT-6 Astra with
GPT-5.6 Sol workers. It tests whether a small local interaction kernel can keep
operator intent, engineering assignments, review findings, and correction work
connected through repeated Human Review Milestone review cycles.

This name is qualified deliberately. The repository already has a separate
historical `AP-EXEC RC.33`, the deployment-preflight compiler at
`0856fd2b9cfad74a8122c8ae8b5acc61cecabfef`. The two experiments share the
baseline `d0e2d72b8774184f30487f678f860c4e989f6f57`; `AP-INTERACT RC.33` is not a
descendant or successor of `AP-EXEC RC.32`, and it does not replace or renumber
the earlier `AP-EXEC RC.33`.

## Identity and archival posture

- Experiment: `AP-INTERACT-RC33`
- Pull request: [#10](https://github.com/marcplatt/agent-playbooks/pull/10)
- Review branch: `codex/hrm-interaction-kernel`
- Archival base branch: `codex/ap-interact-rc33-archive-base`
- Archival base: `d0e2d72b8774184f30487f678f860c4e989f6f57`
- Implementation commit: `5db6ca44b48271680ef70bd27a8c5b7ae3473082`
- Implementation tree: `8ac48dd2ceceb3f0eb11f5e9a2f81b90ed90b89f`
- Protocol: `ap-hrm-interaction/1`
- Playbook: `AP-INTERACT-001` version `0.2.0-pilot`

The RC number identifies this preserved experiment. It does not change the
protocol ID, command format, playbook version, or historical AP-EXEC lineage.
The pull request is an experiment review and archival surface, not a proposal to
merge the pilot into Agent Playbooks `main`.

## Observed model roles

The user designated this as the first Astra-driven development. GPT-6 Astra
performed the orchestration and development coordination. GPT-5.6 Sol agents
performed bounded implementation and independent review during development.

The Alpine Estimating trial uses a fresh GPT-5.6 Sol runner and a separate
GPT-5.6 Sol checker. GPT-6 Astra manually bridges their work through the local
CLI because automatic host task transport and authenticated model binding are
not implemented. The runner completed its targeted assignment and the
independent checker completed a candid assessment with open failures. The
manifest keeps role assignments distinct from completed run evidence; an
assignment alone is not evidence that the model ran or that its result passed.

## Audit findings at the implementation commit

The audit reproduced both findings below by exercising the actual
`HrmKernel::Store` at `5db6ca4`. They remain open because this trial evaluates
the frozen implementation.

| ID | Finding | Consequence | Status |
|---|---|---|---|
| `RC33-ASTRA-F01` | Additive review feedback is treated as replacement intent. After “blue,” a later “Also bold” instruction supersedes the blue instruction. | The current desired state can lose an earlier still-required correction. | Open |
| `RC33-ASTRA-F02` | After `changes_requested`, unchanged artifact bytes can be paired with revised submission metadata and admitted to a new review. | A worker can return to review without the requested artifact change, explicit evidence-backed finding resolution, or operator clarification that makes a content change unnecessary. | Open |

These are functional defects, not merely absent integrations. Any later repair
should name a new candidate commit and preserve these original findings with a
fix disposition and exact regression run.

The reproduction used fixture actors and instructions rather than fabricated
human feedback. It ran from `2026-09-08T18:45:03.523673Z` through
`2026-09-08T18:45:03.537893Z` against the unchanged tracked AE artifact
`src/estimating/dashboard/static/dashboard.css`, SHA-256
`8cbb06e67ace9acabec85520a0eeb658193287454247629fd5a781ee4fe8cabf`.
Both invariants failed. The valid private probe ledger ended at 13 events with
event hash
`807b89df27f1f5c65fdee9228cd3b8f223c64eaf102a3d1b1790435275250ba9`.
The sanitized private result is bound in the manifest by digest and byte count.

## Alpine Estimating trial

The trial uses a fresh detached worktree created at
`2026-09-08T18:36:55Z`:

- Repository: `Novarah/alpine-estimating`
- Candidate: `b24885f74d0eafc64de2adf40bcaa29f18e4425e`
- Candidate tree: `5635761497aa14e2c2e8d16f893faf54917bafa0`
- Fetched `origin/main`: `d3272967cc771cd609853053d3b4f223df7746f9`
- Distance to fetched main: four first-parent merges and 78 total ancestor commits
- Reason for the older pin: it is the last first-parent main point whose
  `AGENTS.md` and current HRM map target the Canary; `origin/main~2` already
  carries Production V1 work.

The trial runs the repository's existing disposable local Canary proof with fake
providers. It has no automatic task transport, live provider action, deployment,
activation, customer communication, payment effect, or human milestone
acceptance. The Astra orchestrator manually translates between task results and
the CLI. This tests the interaction and review machinery; it does not establish
production readiness.

The Sol runner completed one outbound-denied sandbox invocation from
`2026-09-08T18:44:09Z` through `2026-09-08T18:44:15Z`. It ran ten targeted test
files with bytecode and pytest cache writes disabled: 134 collected, 134 passed,
and zero failed, errored, or skipped. The result verified separate Website and
Thomas fixture origins, four fake quote-email receipts, two fake post-completion
SMS receipts, SMS-only recovery without QBO replay, and fail-closed real-provider
mode.

The private runner result has SHA-256
`8c012bbd05a94b8f51b98fe3f331f7ac591199f4877321449d882f16ab77634d`;
its kernel check record has SHA-256
`5d0b2c59d04615eae7a0c2c63ed9a257ca323a2050d874b09e30223dc894aee1`.
The runner recorded zero provider or network actions and left tracked AE files
unchanged.

The independent Sol checker then ran the complementary suite once, excluding
the runner's ten files. In 64 seconds it collected 1,634 tests: 1,625 passed,
four failed, five skipped, and none errored, with 553 warnings. Combined, the
non-overlapping runs collected 1,768 tests: 1,759 passed, four failed, five
skipped, and none errored. This is not an overall application pass.

All four failures came from dashboard tests that reached an existing local
intake database through the historical fixture defaults and rejected a persisted
`contact` provenance class against the accepted `form`/`chat` enum. The
experiment harness failed to isolate the historical tests from the existing
local intake database. The failures are real observations from this run, but
they do not establish a deterministic clean-baseline application defect or a
network-sandbox failure.

The leaked database path was opened read/write and write-capable startup code
ran. No pre-run database or WAL digest exists, so the experiment cannot certify
that ambient local database bytes were preserved. No restoration was attempted.
No user-specific database rows, values, or counts are retained here.

The final private checker result has SHA-256
`1ed7e3756bad06c34d068b2b9ca45429814968ec4fbf4e8256a457ca38bd3083`;
its evidence-assessment check has SHA-256
`8073c56b3306fa8ed6ce431599740b82d29bd89578ab52f69da438664fa58f72`.
The passed evidence-assessment check means the report is complete and candid;
it does not make the complementary suite pass or resolve the two kernel defects.

Both work orders completed and the assessment report reached `review_ready` in
a valid eight-event interaction ledger with event hash
`cccf35ccd4ca87dda2368bcfca2d9c8b0fd42db10e919106daf56ddabf9e10cc`.
No `milestone.review` occurred and no human acceptance or HRM closure is claimed.
All eight CLI commands exited successfully and consumed 0.443056 measured CLI
seconds. Their JSON projections grew from 1,347 to 3,836 bytes. Those figures do
not measure model context, tool reads, dispatch, orchestration, or token savings.

Candidate Git verification, sandbox network denial, candidate-local Python
imports, non-overlapping test selection, separate real-model dispatch, and
worktree cleanup are controls of the Astra/Sol experiment harness. They are not
native guarantees of `ap-hrm-interaction/1`. Native kernel evidence in this
trial is limited to CLI state transitions and claim, revision, artifact, and
report-hash binding. These two report assignments do not demonstrate semantic
interpretation or approval classification.

## Archival disposition

Before cleanup at `2026-09-08T19:05:47.726662Z`, the six runner, checker, and kernel-check
artifacts that had been held under the disposable AE worktree were copied to a
private archive and verified by digest. The archive manifest has SHA-256
`49c9d8561d5d2a3ab0de4dad1dd2bd5b81d69abc71442459894d2b57e315a091`
and is 3,472 bytes. The exact checker command record has SHA-256
`8087a105ffa37867f134b3dd0223845b6778ae7069259fea952a9c0b79448279`
and is 2,205 bytes.

The fresh detached AE worktree, its Git registration, and its temporary parent
were then removed. Other worktree registrations and the operator AE checkout,
including unrelated dirty work, were preserved. The archived ledger is
hash-valid historical evidence but is not resumable because its original
project root no longer exists. Ledger integrity alone does not prove that its
formerly bound artifacts remain available. The cleanup does not certify the
ambient local intake database as unchanged.

## Comparison with historical AP-EXEC RC.32

Historical `AP-EXEC RC.32` at
`de4a53c92c1c55ae3432703862e8de19a2e0a964` has stronger mechanisms for bounded
context packs, exact Git workspace and candidate identity, compiled worker and
checker execution, self-contained check acquisition, and private postimage
scorecard binding. Those controls were built for the AP-EXEC execution protocol
and are not inherited by this pilot.

`AP-INTERACT RC.33` has the clearer review interaction model: durable operator
intent, exact decision revisions, general work orders, narrow role projections,
and repeated review and remediation within one milestone. Its advantage is the
shape of operator-to-work-to-review coordination. The open additive-feedback and
unchanged-artifact findings show that this machinery is not yet reliable enough
to displace RC.32's stronger execution and evidence controls.

The comparison is architectural and qualitative. No model-context or token
savings or head-to-head benchmark were measured, and no claim is made that
either experiment completed a live Production Canary.

## Boundaries

The local CLI trusts asserted actor IDs and message references. It does not
authenticate a human or model, launch Codex tasks, prove the semantic correctness
of an artifact, prove full diff reach, or grant external-effect authority. The
kernel can enforce structurally safe assignment and revision rules while a
trusted caller still supplies a semantically incomplete interpretation of the
operator's request; those are separate claims. The
experiment does not install policy in Alpine Estimating or any other adopting
repository. Private task transcripts and Canary artifacts stay outside Git;
tracked records contain only bounded references and digests suitable for review.
