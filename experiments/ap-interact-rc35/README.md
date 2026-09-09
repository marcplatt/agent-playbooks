# AP-INTERACT RC.35: automatic orchestration and diagnostic continuation

RC.35 develops RC.34 at `c754d36b5071b010e61fdd0170b1f42c9f6cdcf8` on
`codex/ap-interact-rc35`. Its software version is `0.4.0-rc35`; its ledger protocol
remains `ap-hrm-interaction/2`. This is an experiment outside AP main. RC.33 remains
the first Astra-driven development in this project; RC.35 continues that lineage.

## Problem addressed

The [RC.34 qualification repeat](../ap-interact-rc34/qualification-repeat.md)
left four work orders claiming to run after every native worker had finished.
The external controller manually transferred requests and receipts. Partial worker
results could not receive ordinary candidate-bound diagnostic checks, and the
Website browser process failed before assertions. None of this established the
operator's real Website/Thomas → QBO → inbox Canary outcome.

RC.35 implements the missing execution loop. Native GPT-6 Astra returns bounded
operation requests; a trusted driver applies permitted commands, launches GPT-5.6
Sol workers, collects their results, runs actual checks and resumes Astra's exact
task. A fresh Sol reviewer independently assesses the candidate before human
review. Requested models and returned task UUIDs are recorded; model metadata is
launch evidence, not authenticated backend identity.

## Implementation

- `driver.rb` adds durable request envelopes/receipts, bounded feedback, worker
  collection, native check feedback, exact Astra resumption, current-decision stops,
  stale-response rejection, writer/check sequencing and finite turn limits.
- `continuation.rb` separates process completion, partial engineering progress,
  declared dependencies and explicit decisions. Unclassified blocked prose stays an
  engineering issue. Repeated lack of progress suggests smaller work assignments.
- `coordinator.rb` runs frozen checks for completed blocked workers as
  `diagnostic_evidence`. Those records cannot submit work or replace successful
  current completion evidence.
- `execution.rb` records signed environment preflight before claims, distinguishing
  startup from product-check failure when a startup marker is declared. It repairs
  the macOS Chromium launch with narrow RootDomain/rendezvous permissions.
- `host.rb` supports a read-only native Astra role, exact-session resume, sensitive
  context denial and trusted creation of empty owned-path parent directories.
  Workers retain exact-file write grants.
- The CLI adds `driver-start`, `driver-step`, `driver-status` and `driver-run`.
  The updated playbook and optional project template describe the actual interface;
  global instructions and other repositories' AGENTS files were not installed or
  changed by this experiment.

## Verification and observed failures

The focused kernel suite passes **131 tests, 675 assertions**, including state,
store/CLI, Host, execution, preflight, coordinator, continuation and Driver. Driver
fixtures use deterministic model output but real subprocesses, native checks and
ledger transitions. They exercise a blocked partial implementation, failed native
diagnostics, same-worker correction, independent review and an unaccepted human
review. They also reject operator impersonation, conflicting request IDs, stale
Astra output after operator input and tampered preflight on restart. Concurrent
operator input is serialized with each short driver mutation; input arriving
between requests discards the remainder of that stale batch. A regression also
prevents an old blocked diagnostic from being upgraded after a resumed worker
completes the order. A durable pending-dispatch registration recovers a worker
launched before its Driver receipt was saved, so cursor-based replanning cannot
silently lose that worker from collection.

The original Playwright Chromium launch now passes a real page assertion while
outer forbidden read, write and network probes remain blocked. This keeps the
original browser defaults; the change does not add another browser sandbox-disable
flag. A separate stricter inner-browser experiment failed and is retained as failed
evidence, not confused with the actual RC.34 target.

Running the **exact frozen RC.34 Website UI command** builds 22 pages and executes
both tests: **one passes, one fails**. The failed assertion expected the last status
to contain `No quote has been sent yet`; the page instead reported that Thomas chat
was awaiting its configured production binding. The runner startup failure is
repaired; Website acceptance is still incomplete. This iteration did not edit the
preserved AE/Website candidate to suppress that assertion.

The first real native Astra/Sol Driver development trial exposed API friction:
Astra attempted an operator-only intent command, referenced the nonexistent intent
and initially chose too small a worker context ceiling. The driver rejected these
requests. A compact API guide was added to the orchestration packet: use the
existing `milestone_initial`, supply concrete request shapes and treat context
limits as ceilings. The guide contains protocol instructions, not application
solution hints.

### Native transport trial

The first real-model trial reached `review_ready` in **five Astra turns**. Its tiny
application requirement was for `greeting.rb` to print exactly `Hello, Alpine!`
and a newline. A fixed test executed that program and asserted the output. This
deliberately small task tests native transport and evidence flow, not cross-system
discovery or semantic difficulty. The driver commissioned one Sol worker, ran the
frozen native check, then commissioned a separate Sol reviewer. It recorded the
assessment and opened an unaccepted human review without manual receipt copying or
operator input during execution.

| Role | Native task UUID | Result |
|---|---|---|
| Astra orchestrator, five turns with four resumptions | `01a087fa-b2ef-7a93-8e4c-82c1ca066127` | review ready |
| Sol implementation | `01a087fc-47f7-7120-9c2c-7a08f69606b6` | implemented |
| Fresh Sol review | `01a087fd-541b-7b83-919a-809bc9817e79` | reviewed, no findings |

The initial Astra prompt was 7,062 bytes; subsequent packets were 7,463–12,017
bytes. Worker and reviewer packets were 6,897 and 7,625 bytes. These are supplied
packet sizes, not total model context or token usage. The initial interface errors
above were recovered automatically and remain in private request receipts. The
final ledger cursor was 6; `greeting-human-review-1` remained pending with no
operator disposition. No human review was fabricated to close the test.

The fresh second trial also reached pending review. The compact guide eliminated
Driver request rejections, but the run used **six Astra turns**, so it did not
improve turn count. One implemented worker left scenario verification pending
because it could not run trusted tests; Astra unnecessarily resumed it to reconcile
the already-passed check. A first reviewer then incorrectly listed inspected files
as changed files and was rejected. Astra commissioned another fresh reviewer and
completed the assessment without operator intervention.

These observations produced two further changes: pending verification now advises
running native checks instead of another implementation turn, and reviewer output
is constrained to `reviewed|blocked` with an empty `changed_paths` array. A separate
native Sol reviewer validated that new schema successfully; it did not add an
assessment or human disposition. The revised pending-verification advice has focused
regression coverage but has not had another full native trial.

| Metric | First native trial | Trial with compact guide |
|---|---:|---:|
| Astra turns | 5 | 6 |
| Driver request rejections | 4 | 0 |
| Reported input tokens, all native roles | 596,773 | 384,859 |
| Cached input tokens, included in input above | 514,048 | 308,096 |
| Uncached input tokens | 82,725 | 76,763 |
| Reported output tokens | 4,831 | 4,544 |

The totals cover repeated native model processing, not unique context-window size;
cached input is not added to input again. The trials are observations, not a
controlled performance benchmark. This remains expensive coordination for a
one-file application. Request construction improved; production autonomy and
efficient operator multitasking are not established by these small successes.

Second-trial identities: Astra `01a08801-45e4-7880-8256-a4b76afa42d0`, resumed Sol
worker `01a08801-9d07-73a2-965f-cefc3c36b379`, successful fresh reviewer
`01a08803-d740-7070-a2c3-f29403918e28`. The separate schema validation used Sol
`01a08808-049d-7ca1-a9af-64d5e6edba07` and schema SHA-256
`828bff46e27f298e797fbf36fc6cca4db42aa8930f65e59a26d9865d8a82ad0a`.
Its 46,781 input / 30,592 cached / 527 output tokens are excluded from the table.
Private jobs retain exact dispatch schema, prompt and result bytes. These were
development runs while kernel fixes were in progress; they are not exact-final-head
full integration runs. The later restart/registration and pending-verification
repairs are covered by focused tests.

Private evidence is retained under
`~/.codex/hrm-private/ap-interact-rc35-development/`. Browser receipts:

| Check | Receipt SHA-256 | Outcome |
|---|---|---|
| Original browser startup and page assertion | `51f7028de9f1132d08fc33ec58e5d796fa9c7ccc4facfa64e56683ca31590cb0` | passed |
| Exact frozen RC.34 Website UI command | `44b138da6e2778d6f0e920a1f3100dcc66fff8753ebf9b7726d40feee957586e` | failed product assertion |

## Running the driver

Initialize a fresh private implementation milestone through the existing operator
CLI. Copy [the configuration template](../../templates/hrm-driver-config.json) to
private storage and replace its canonical project/runtime paths, environment ID,
dependency reads and startup checks. A runtime version smoke check proves only
that runtime can launch; browser or integration environments need a relevant small
startup check. Keep product assertions in the work orders' separate frozen plans.

```sh
ruby scripts/hrm_kernel.rb driver-start --state-dir /private/state --input /private/driver.json
ruby scripts/hrm_kernel.rb driver-run --state-dir /private/state
ruby scripts/hrm_kernel.rb driver-status --state-dir /private/state
```

The driver yields at human review, a current unresolved decision or an explicit
engineering/service/budget stop. Supply actual operator feedback through the
trusted CLI and resume the driver for the next review cycle. It cannot manufacture
operator input, acceptance or external-effect authority. A partially applied
response interrupted by a crash may be conservatively discarded and replanned
from the ledger; already applied commands remain durable. Turn limits require a
deliberate follow-up rather than resetting automatically.

## Qualification boundary

This iteration repairs and tests kernel execution mechanics. It does not establish
successful AE Canary delivery, autonomous discovery of cross-system requirements,
or the operator experience of reviewing and commissioning real changes. No real
Website/Thomas submission, QBO quote send or inbox receipt was performed here.
The small native application trial tests the new transport; it does not replace
the agreed repeat AE Canary. Production adapters, real operator review and the
declared final destination still need that qualification. Preflight binds declared
configuration and executable/policy identity; dependency trees are not recursively
hashed. Global/project adoption remains a separate step.
