# AP-INTERACT RC.34 qualification repeat findings

> **STOPPED — did not qualify.** Final native disposition: September 8, 2026
> (Vancouver). Required browser execution was blocked by the fixed runner;
> product startup/integration remained unfinished and final delivery checks had
> five failures. No human review or production Canary occurred. Zero quote emails
> were sent or observed in the operator inbox. This is evidence for another
> kernel iteration, not approval to adopt it for live project orchestration.

Kernel: `0.3.0-rc34`, protocol 2, source pin
`0e24dd22bf8e604c9d7580f12985b995659c2229`. The repeat changed no kernel code and
is not RC.35. Findings remain on the RC.34 experiment branch, based on the RC.33
experiment; no AP main or canonical product checkout was changed by this repeat.

## Purpose and retained outcome

This qualification is a stricter repeat of the earlier RC.34 rehearsal. The
earlier run reconstructed a local AE workflow with seeded RFQs and recording
providers. It reached a local review state, but it did not exercise the
operator's intended Canary. This repeat starts a fresh protocol-2 ledger and
asks fresh workers to derive the missing implementation from historical source.
It does not reuse the earlier candidate, run state, model memory, or private
evidence.

The real terminal outcome remains unchanged: one controlled Website request and
one controlled Thomas request must reach AE through their real entry paths;
their four separately reviewed members must reach the real QBO API as four
estimate emails observed in the designated operator inbox; and the two RFQs must
produce the accepted salesperson SMS and GHL acknowledgements. Local tests,
source changes, an intermediate implementation review, and model reports do not
complete that outcome.

## Historical baseline isolation

The trial source was exported from four explicit historical commits:

| Repository | Commit |
| --- | --- |
| Alpine Estimating | `300f2b3294aa9e74b0b569958f4b696bf6480402` |
| QBO Gateway | `aeabcc2cbbe287a450ad12df28806648b42c6e21` |
| Alpine Website | `b3065cf317b437313dd6756c2600f1eb88737cf4` |
| Alpine Product Master | `a205ba540f17b55268990b15d386015876149bc8` |

Each export has a recorded tree and archive digest. Trial-specific `AGENTS.md`
dispatch instructions are separately hashed. Canonical future objects, prior
trial state, model memory, live operator data, and private production bindings
were unavailable to the implementation workers. Installed Python and Node
dependencies were supplied under version locks and executable hashes. The RC.34
runner does not recursively content-address every third-party dependency, so
those locks are useful environment evidence rather than a complete supply-chain
attestation.

The exports share one aggregate Git root because RC.34 has a single-project-root
contract. This is a test-harness accommodation. It does not demonstrate native
multi-repository checkout, ownership, or coordination.

## Orchestration and implementation observed

RC.34 hosts Sol workers but does not host an Astra orchestrator. A separate fresh
native Astra task therefore produced exact kernel and Host requests. The root
controller transported those requests and returned receipts manually. Repeated
turn metadata binds the continuations to the same Astra task UUID, but requested
model identity is not authenticated proof of the backend that served a task.
The manual bridge and polling are orchestration overhead, not autonomous kernel
behavior.

Within those limits, the orchestrator retained the terminal outcome and found
implementation gaps which the earlier rehearsal avoided. It commissioned five
nonoverlapping orders: Website entry surfaces and transport, AE startup/runtime
composition, Website-to-GHL ingress, provider graph construction, and the SMS
authorization boundary. These were derived from historical source. The separate
ingress, provider and SMS orders were created when cross-owner dependencies
became concrete; no completed canonical UI or implementation was supplied.

The SMS discovery is particularly relevant to semantic scope: the existing
production authorizer needs an already prepared durable SMS outbox part, but the
follow-up adapter prepared and submitted without pausing. A separately owned
service change was commissioned to expose preparation and an authorized resume.
This is evidence of cross-component engineering discovery. It is not evidence
that the resulting integration works, or that a human change-order loop works.

The kernel exercised work-order creation, exact claims, same-task continuation,
release/reclaim, structured collection, native checks, and one evidence-bound
ingress submission. A normal worker process exit or an `implemented` report did
not complete an order by itself. The controller made no product or kernel source
edits; it did supply environment repairs and exact request/receipt transport.

## Early stops and setup repairs

Runtime assignments repeatedly ended normally with useful partial edits while
explicitly leaving assigned constructors, persistence, tests or stock startup
unfinished. One `implemented` report covered a narrower repository adapter but
admitted that its requested test and full startup were absent. A separate
continuation failed before any source work because the model service was at
capacity. The evidence distinguishes normal partial returns, service failure,
and genuine sibling dependencies; it does not establish the model's internal
reason for stopping.

The missing default startup schema and constructors were already authorized
engineering. Real private values are required for later use, but no unanswered
operator decision was identified as necessary to write those missing adapters.
The later worker still requested an approved schema; Astra explicitly reassigned
schema design as ordinary engineering and continued independent work while the
separate SMS API was pending. This is a completion/decomposition problem, not
proof that the operator must design the application glue.

Several failures belonged to the harness:

- Initial packet size/parent setup and explicit developer Git read access.
- Isolated locked dependencies and a regular-file Python executable, after the
  runner correctly rejected the initial interpreter symlink.
- Disposable `HOME`, isolated Git configuration, and localhost resolution under
  denied network access.
- Astro CLI host configuration did not reach its internal Vite server. Its
  supported programmatic build API with a numeric host resolved that problem;
  both Astro and Vite caches then needed explicit disposable locations.
- The first ingress submission found the kernel's generated report path inside
  the Git candidate. Excluding that exact report directory repaired submission
  without changing product source or rewriting the failed receipt.

Five versioned environment manifests retain these changes. Environment 5 passed
Website contract tests and a 22-page production build. It did not solve browser
execution. Locked Chromium crashed before page creation or assertions, with the
crash in macOS power-monitor initialization. The observed stack and the matching
[Chromium source](https://raw.githubusercontent.com/chromium/chromium/refs/tags/151.0.7922.34/base/power_monitor/power_monitor_device_source_mac.mm)
point to an interaction with the default-deny runner's lack of IOKit access.
The exact minimum permission repair was not verified; logs did not provide an
explicit denial identifying it. No broader permission grant, browser bypass or
kernel change was applied. This is an inconclusive browser check due to the
harness, not a failed product assertion or evidence of browser correctness.

These repairs consumed controller work and environment-only resumptions. They
must be counted separately from useful product implementation. Failed receipts
remain part of the record.

A later check request exposed a separate kernel restriction: the coordinator
permits frozen checks only after the worker reports `implemented`. AE had returned
`blocked` while preserving useful partial edits, so three requested checks were
rejected before execution. This withholds feedback that could help finish the
assignment. Relabelling unfinished work solely to get checks would corrupt the
meaning of the worker status; a future design should allow candidate-bound
diagnostics on partial work while keeping submission and review requirements
strict. The unchanged rule is in [the coordinator](../../lib/hrm_kernel/coordinator.rb).

## Native evidence and end posture

Passing receipts establish bounded checks of the candidate captured at that
execution. They do not establish a current combined implementation:

| Check | Observed result | Evidence |
| --- | --- | --- |
| Website contract/transport | 6 passed; repeated under environment 5 | native receipt |
| Website production build | 22 pages built under environment 5 | native receipt |
| Website browser | failed before page creation/assertions | native receipt and matched macOS crash report |
| AE Website-to-GHL ingress | 77 passed, two inherited dependency warnings | submitted at cursor 10 |
| Earlier AE runtime selection | 40 passed, 6 failed | five environment/Git failures and one startup-interface failure |
| Earlier provider factory selection | 62 passed | predates subsequent provider edits; not current completion |
| Final SMS/delivery selection | 57 passed, 5 failed | completion-state regressions; no submission |

The final delivery failures stop at `FOLLOWUP_COMPLETE` where the selected
existing cases require `CANARY_VERIFIED` or `QUOTED_VERIFIED`. They are actual
failed assertions, separate from the browser initialization failure. Passing new
pause tests did not establish successful authorization, resume or integration.

Selected receipt file SHA-256 values retained with private evidence:

- Website environment-2 contract pass:
  `ef76f5db6aacb997f0e1919ee408efc9829b7b605a7fe1ee9e4f43aeefd47844`.
- Ingress pass:
  `5b65c68ae4b127e4ad875d80a82ce1d3161f35ba0be9e710f2139174bb46199f`.
- Final SMS/delivery failure:
  `0691b32d813051f3827600139fdd32eaa6d7f175346e11fbf1cfb519d5556a54`.
- Final Website contract pass:
  `3de21ea817c5ce3884321ea3acf5eec442e0e7c7b2d0cae16b6cb312fad330df`.
- Final Website build pass:
  `e500a24a3c2a2dcb74cec2855135be36473aa82a13b0b5448831ace774487642`.
- Locked browser binary:
  `7687bff7cb2db075f250e6d5848bbc8838cac3802ac3952a899c574f8eccab45`.
- Matched macOS crash report:
  `d9a090bd8c44031c6df1eaa2db183ed2c61860c3717176623ca64d3b6f409ad5`.

Signed native receipts bind check plans, executable identities, candidate
content, work-order authority, denied command network access, read-only candidate
sources and disposable writes. Failed checks remain preserved even when the
transport operation itself exited successfully. These measures protect evidence
provenance; they do not prove that selected tests express the intended behavior.

At the final controller boundary, runtime still acknowledges a missing adapter
from current Website/Thomas/APM source to persisted review and follow-up bindings.
Its maintained assembly layers are useful partial code; stock startup still ends
safe-off. The SMS service worker reported implemented, while provider-factory
activation of that API and dashboard challenge/confirmation integration remained
separate unfinished work. No working combined dashboard was presented for review.

Kernel integrity verified at cursor **16**, with event hash
`aa26370c8c5818a7da15e30b2f830a128b460ce01d9ca6110ba5f44f66fe300c`.
The milestone remains `executing`: one of five work orders is completed and four
retain running claims, although **no native worker process remains active**.
There is no current review candidate, assessment, review or operator decision.
Delivery and review requirements remain structurally uncovered. The ingress
submission is historical evidence; it was not refreshed against the final sibling
changes and does not certify the combined checkout.

The final Astra task ends with a structured `blocked` report, no further requests,
no operator review request and explicit unresolved Website, runtime, provider and
SMS assignments. It records controller-imposed closure and the original live
outcome as unfulfilled. Its task was resumed in place throughout, not terminated
mid-edit or presented as a successful orchestrator review.

The preserved partial checkout has **34 changed/new files: 18 in AE and 16 in
Website**, including source, tests and required implementation documentation.
Gateway and APM sources were not changed. This run therefore does not demonstrate
discovery or correction of the Gateway tax-code/database issues the operator
encountered in the canonical live Canary; it never reached that production path.
The file manifest SHA-256 is
`da43e033da4265ebacb6c13819541fe2d122e14c131b408cb3c2c3e7c91ff01e`.

Final native process counters:

| Measure | Astra orchestrator | Sol workers |
| --- | ---: | ---: |
| Native tasks | 1 | 7 |
| Turns/jobs | 34 | 23 |
| Reported input tokens | 16,060,578 | 20,610,206 |
| Included cached input tokens | 15,571,968 | 18,839,296 |
| Reported output tokens | 51,362 | 138,318 |
| Cumulative process execution | 37.2 minutes | 85.6 minutes |

Worker jobs ended with 12 `implemented` reports, 10 `blocked` reports and one
service-capacity process failure. These counts include continuations and
Website environment-only resumptions; they are not 23 independent builders or
12 completed orders. The private transport contains 99 request-directory receipts
plus five top-level setup/environment receipts; 77 of the request-directory
receipts carry qualification request identifiers. The remainder include the
controller's actual job-event collections/status reads. The largest supplied Astra follow-up
prompt was 59,359 bytes. Setup repairs, five environment revisions, polling and
manual transport remain root work.

Token counters accumulate repeated inference and cache reuse; they are not peak
context occupancy or dollar costs. Processing times can overlap and omit root
and evaluator work, so they are not elapsed operator time. Reasoning effort was
not explicitly pinned. These measurements establish neither context savings nor
an efficiency advantage.

The runtime history contains three fresh native tasks and eight continuations:
11 dispatches, nine normal `blocked` reports, one `implemented` report for a
narrower partial adapter, and one model-capacity process failure. Missing code was
already assigned. Genuine ingress/SMS dependencies explain some waits, but do not
explain all independent unfinished startup work.

The root controller closed the attempt at the fixed-runner blocker after allowing
already active work to finish and requesting eligible final checks. That stop is
an evaluation intervention, not an Astra-originated completion or operator HRM
decision. The candidate, original outcome, work-order state and private failed
receipts remain preserved. No blocked worker result was relabelled to obtain
checks or submission.

## Operator-loop proof still missing

The trial has not exercised an independent candidate assessment, an operator
view of a working candidate, real operator feedback, a direct same-worker reopen,
an orchestrator-routed larger correction, finding raise/resolve, evidence refresh
after a sibling change, or a human milestone decision. The planned small and
large feedback paths will count only if real operator review produces them. They
will not be manufactured to satisfy the test plan.

The trial has also not exercised the terminal production path. A later local
`review_ready` state would only place the implementation before the operator. It
would not prove Website or Thomas intake, QBO delivery, SMS, GHL acknowledgement,
recipient observation, deployment, or HRM acceptance.

## Implications for a later kernel iteration

These are observations for later design work; they are not mid-run changes:

- Native orchestrator hosting and explicit multi-repository ownership would
  remove much of the manual transport and aggregate-root accommodation.
- Environment identity and runner preflight should expose executable, `HOME`,
  Git configuration, hostname, dependency, and report-path requirements before
  product workers spend continuation turns on setup repair.
- Process completion, worker disposition, native evidence, implementation
  review, operator acceptance, and production effects should remain separately
  named and measured. The current run shows why collapsing any two creates a
  false-completion risk.
- Repeated partial worker returns need an automatic engineering continuation
  policy, an explicit list of unmet deliverables and bounded decomposition when
  progress stalls. Missing code stays with an engineering owner; missing private
  values and actual release decisions go to the operator only when needed. A
  normal process exit with useful edits is not completion.
- Partial candidates need native diagnostic checks without declaring the worker
  implemented. Keep strict all-passing evidence and semantic review for
  submission, while making failed diagnostics available during construction.
- Scenario coverage depends partly on independent semantic review. Structurally,
  an orchestrator can cancel origin-specific work while another order carries a
  shared requirement. A later design should make indispensable owner paths or
  scenario contributions explicit rather than relying only on shared
  requirement coverage.
- Future comparisons should record reasoning effort and controller
  interventions, and should separate setup overhead from implementation and
  operator time. This run does not establish an efficiency advantage.
