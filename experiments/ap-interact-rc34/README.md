# AP-INTERACT RC.34 implementation and review trial

RC.34 develops the archived [Astra RC.33 experiment](../ap-interact-rc33/README.md)
on `codex/ap-interact-rc34`, from `93c536fa53e669a5c9cf9719efbca21ae661ac74`.
It is a separate experiment, not an AP main adoption or a continuation of the
historical AP-EXEC RC.33. The implementation uses `AP-INTERACT-001 0.3.0-rc34`
and a fresh `ap-hrm-interaction/2` ledger. Historical ledgers remain unchanged.

## Operator correction: this run was a simulation, not a Canary

The operator clarified the acceptance criterion after this report: use simple
controlled/customer test data through the real production workflow and observe
the final result. For AE, the Website form and Thomas chat on the website must
reach the real QuickBooks Online API and produce quote emails actually received
in the operator's designated inbox. A Canary checks that the route exists; it is
not an exhaustive catalogue of failure cases.

This run did not do that. It seeded RFQs directly in AE and substituted recording
providers. The earlier `review_ready` result applied to the orchestrator's narrowed
simulation contract, not the intended Canary HRM. That interpretation was an
orchestrator error. The pending review is now invalidated by an append-only
operator requirement correction; historical receipts and assessments are retained.
No actual inbox receipt was established, and this correction does not execute
live services. The retained app is a rehearsal environment only.

## How the AE result was produced

This was a guided reconstruction, not an independent implementation derived from
the HRM alone. The original UI work order explicitly allowed porting the four UI
files from canonical commit `fda0bdb`. Later prompts referenced canonical tests and
controls. The delivery work order explicitly pointed to the minimal `review.py`
fix in `c360a8d`. The runtime order explicitly prohibited real providers and asked
for seeded synthetic RFQs with recording adapters and frozen prepared commands.

There were three retained AE implementation tasks: recovery (eight attempts),
delivery (three), and runtime (nine), plus two fresh independent review tasks.
Additional supporting delegates worked on kernel state, host/coordination,
isolation, and comparison. They were not ten independent AE product builders.
The UI worker ported and adapted known controls; the delivery worker reconstructed
the known retry fix; the runtime worker built the isolated test composition and
its tests. The orchestrator supplied detailed corrections across repeated attempts.

No Gateway implementation, real Website/Thomas intake, production tax-code
configuration, or production data update was commissioned in this trial. The
operator reports that Gateway tax-code and data changes were needed in the
canonical run. This experiment neither rediscovered nor proved those dependencies;
it exercised AE's recording seams instead. Similar appearance and passing local
tests therefore cannot establish equivalent end-to-end production capability.

## What changed

The kernel preserves additive operator requirements, records explicit scoped
supersession, retains the original milestone contract, and makes unresolved
findings durable. A correction cannot regain review merely by changing submission
metadata. Implementation milestones require actual changed artifacts, native
candidate-bound checks, and a current independent assessment of every declared
acceptance scenario before human review can open.

Small corrections can reopen the owning worker without dropping its constraints.
Multifile technical gaps remain orchestrator assignments within the accepted
project boundary. An unanswered business decision is recorded separately from an
engineering discovery. Neither native checks nor a model assessment can accept a
Human Review Milestone for the operator.

The host launches real GPT-5.6 Sol CLI tasks and resumes their exact task UUIDs.
It persists dispatch identity before launch, freezes check plans, bounds initial
packets, separates process completion from worker success, and collects structured
results. Native checks use disposable storage, denied network access, read-only
candidate sources, and signed execution receipts. Reviewer tasks are separate
and cannot write the candidate. Requested CLI model identity is recorded; it is
not authenticated proof of which backend served the request.

## Trial design

The AE experiment uses `codex/ae-canary-rc34` at historical base
`300f2b3294aa9e74b0b569958f4b696bf6480402`, four commits before the accepted
Canary head `c360a8d128ba1aa9991cad5fd522d9ee3b3751d2`. This base requires real
product edits. The canonical head and its merge `89552a3` have tree
`3277cda1b51e4b7631a603f5eff1efaf7e4858be`; that is a comparison target, not
evidence that the new checkout has human acceptance.

Three nonoverlapping orders commission parser-independent quote recovery,
delivery retry/reconciliation safety, and a runnable synthetic operator workspace.
The contract retains separate Website and Thomas RFQs, ADT and DT options, four
recording-provider deliveries, two salesperson SMS records, and two GHL
acknowledgements. All effects are synthetic. The canonical live Canary was
accepted with a scope variance; this local trial does not reverse that decision
or claim to have completed the originally intended live envelope.

Only this new AE checkout uses the experimental AGENTS dispatcher. Global
instructions, canonical AE policy, existing worktrees, operator data, and both
repositories' main branches are outside the implementation changes. The review
environment is retained for actual feedback rather than deleted after a report.

## Failures found by actual execution

The first three real worker processes completed with `blocked` results and no
worker product edits. An outer Seatbelt policy could not nest with Codex's own
sandbox (`sandbox_apply: Operation not permitted`). Fake-host tests had missed
this integration failure. The repair uses explicit native Codex permission
profiles, without `--sandbox` or permission-bypass flags. A real Sol command then
proved allowed source reads and owned-file writes, denied sentinel reads/writes,
and denied an outbound connection to an actually listening loopback probe.
The same three task UUIDs were resumed successfully.

The first native AE test invocation stopped during collection: blocking all
reads of `.env.example` also blocked the `stat` used by pytest discovery. The
runner now permits metadata while denying sensitive file contents. A real
Seatbelt regression verifies both properties. The failed receipt is preserved.

The next application runs found missing access to macOS public timezone data and
an invalid synthetic quote-confirmation lifetime. Timezone files are now explicit
read-only system dependencies, with a real Python `ZoneInfo` check. Application
failures return to the original worker task; neither a successful model process
nor a test that merely describes UI source is treated as working product behavior.

Review of repeated correction semantics also found that full-candidate invalidation
could strand an unchanged completed sibling order: its old receipt became stale,
but submission returned the old evidence. Evidence refresh now has its own
structural transition. It retains the worker, requirement revision, scope, and
artifact bytes, replaces only verified evidence, and requires a fresh independent
assessment. It does not invent a new operator instruction to rerun checks.

Actual workers also reported another order's AGENTS file as their own output.
Collection rejected those reports, and the same tasks corrected them. Declared
paths now express ownership rather than a requirement to modify every file in
the list. Host write grants reject symlinks, including parent components, so an
owned path cannot grant write access to a sibling's artifact through a link.

Actual browser inspection found a semantic integration failure after most tests
were green: the synthetic RFQ declared two candidates without explicit quote-set
intent, and the legacy detail template hid validated per-member bindings behind
the scalar proposal's `sendable` state. Multi-option eligibility deliberately
does not authorize a scalar send. The correction preserves that distinction:
frozen prepared-set delivery has its own reviewed bindings and must reject
material edits that would make the prepared commands stale. Editable workspace
recovery and frozen-set delivery are separate proofs; this trial does not claim
that arbitrary workspace edits regenerate a delivery plan automatically.

The retained preview also required an actual launch repair: Seatbelt denied the
child's writes to preopened log descriptors outside its writable root. Process
logs now live inside its disposable data boundary and are treated as untrusted
output; controller identity, policies, and launch records remain outside it.
The controller verifies PID, process group, start time, and command before stopping
its own process. Tests rejected a substituted PID and verified denied outbound
connections against a listening local endpoint.

## Interpretation limits

Initial packet bytes and cumulative reported tokens are different measurements.
Worker tool reads and retained task context are not bounded by packet size alone.
The trial must not be presented as a measured context-saving or RC.32 performance
win. Full-candidate invalidation is intentionally conservative: a sibling edit
requires fresh checks even if a dependency-aware scheduler might avoid them.

The initial milestone path policy is fixed in this pilot. Assignments can expand
within that policy; a change beyond it requires an explicit boundary change in
the host workflow. The local CLI trusts actor IDs and source references. The
reviewer can miss semantics. Dependency trees are not recursively content-addressed;
dependency changes require a fresh environment identity and checks.

## Current execution evidence

The kernel implementation pin is
`0e24dd22bf8e604c9d7580f12985b995659c2229`. Its focused state, store, host,
execution, and coordinator tests pass: **99 tests, 504 assertions**. The CLI
acceptance demonstration also passes its fictional change-request/review cycle;
those actors are not a substitute for actual human feedback.

The native AE candidate has **168 passing tests**: recovery 39, delivery 30,
and isolated rehearsal 99 (historical check ID `isolated-canary`). The selected interpreter is Python 3.9.6 with explicit
candidate imports and read-only historical dependencies. This is not a Python
3.12 CI result. Deprecation warnings remain in inherited framework paths.
All three native receipts report exit status zero, denied forbidden reads and
writes, and a network-denying policy. Their SHA-256 identifiers are:

| Check | Receipt SHA-256 |
| --- | --- |
| recovery-ui | `499e1c874333f62e34a4522ed663b8f53fae3092c8fbb71e102d2ff2d53768e2` |
| delivery-reconcile | `73bb01823d32e76344a01c52a8007a07a1ea31999530f0f5c0ac522c71f6b8e5` |
| isolated-canary | `2bd4485f986462937d657a2e289b26016a6cb10b78cd6ce6b9f33c757d061706` |

The combined milestone candidate is
`55d4cbc4d098a7fa0667ba8f55559f89ce0c8b4963ca11f3035416f6cdfbb8cc`.
It binds eleven changed/new AE files to historical base `300f2b3`; the AE
checkout remains uncommitted so that the review evidence retains that identity.
An exact owned-file snapshot and manifest are retained privately with the ledger.

The implementation required **20 worker attempts across three retained tasks**:
17 returned implemented results and the initial three returned blocked. Initial
packets were 14,957–17,413 bytes; the 17 resume packets were 14,582–18,872 bytes.
Summing the 20 worker completion events gives 17,459,204 input tokens,
16,167,168 cached input tokens, and 79,181 output tokens. These are repeated
inference usage counters, not a simultaneous context size or a savings result.
The amount of iteration is a practical weakness of this run, despite the bounded
dispatch packets. Reviewer usage is accounted for separately.

The first independent reviewer passed the scenarios but flagged a false display
claim. The orchestrator confirmed it in the browser and commissioned runtime
revision 2 under the existing authority. The revised summary now exposes exact
frozen prices and availability. Native checks passed again; the two unchanged
sibling orders each gained one evidence-history entry. The earlier assessment
became obsolete. A fresh independent reviewer passed all four scenarios for the
final candidate, and the kernel opened **AE-RC34-HRM-1** at ledger cursor 18.
At that earlier handoff its status was **pending**, with no human decision, no
unresolved findings, and no pending business-authority decisions. The operator
correction above subsequently invalidated that review. There were no redundant approval
requests during these engineering corrections.

The retained review URL is **http://127.0.0.1:63592/**. The final source digest is
`b6fa0e4131dc204f2b1cedba7e45f313d334b6b8163f07cf4e0407732c4a2d2f`;
the verified process at handoff is PID 61901. The app uses a frozen synthetic
clock and recording adapters. Real browser actions confirmed Website province BC,
released its two members, and reached `quoted_verified`; both member controls
became delivered records. Recording read-back showed one create/send/read-back
sequence per member and one SMS submission/verification. The Thomas pair remains
untouched in the retained preview. The automated isolated run exercised both
origins and CRM failure/reconciliation. These are distinct evidence sets.

## Comparison with the canonical AE Canary

The trial changed six existing files and added five relative to `300f2b3`.
Against `c360a8d`, 132 of 134 existing product files are byte-identical, including
`review.py`, the workspace CSS, and JavaScript. Of those, 129 already matched at
the historical base. Two HTML templates differ, and the trial adds the isolated
runtime module. The template differences include explicit frozen-set controls,
operator-price intent fields, and revised review presentation. Historical project
docs retain the old base contents; no canonical HRM closure or completed capsule
was copied into this experiment.

This run demonstrates actual implementation and enforced evidence transitions,
which RC.33's report-only AE trial did not. It does not establish an efficiency
win, a live Canary closure, or complete natural-language task ingestion. The
trusted orchestrator still translates chat feedback into kernel commands; there
is no automatic inbox bridge from arbitrary worker chat messages. Workspace edits
also do not automatically regenerate the frozen prepared delivery set. Those
limits matter before adopting this as an unattended multitasking workflow.

The implementation run left global and canonical repository dispatchers unchanged.
The later operator correction adds the Canary definition to global guidance and
the experimental dispatcher; it does not adopt the kernel globally. Only the retained
AE experiment installs the pinned RC.34 dispatcher. AP main is untouched; the
RC.34 branch is reviewed against the archived RC.33 experiment branch.
