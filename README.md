# Organization-to-System Agent Playbooks

**New operator or workspace?** Start with the interactive setup prompt in
[Operator-Workspace Onboarding and Method Orientation](playbooks/operator-workspace-onboarding.md).
If the operator already knows the method and is configuring another account, machine, or
project set, use [Operator-Workspace Conformance and Synchronization](playbooks/operator-workspace-conformance.md)
instead. In every playbook ID, `AP` means **Agent Playbooks**.

Version-controlled, human-readable, and machine-readable workflows for turning an
organization's business intent into governed system delivery. The repository is
organization-neutral: adopting organizations keep their own names, authority assignments,
policies, system inventory, and project state in their master-plan and project repositories.

## Purpose

These playbooks keep elicitation, planning, orchestration, review, change propagation,
and rollout patterns outside chat history so they can be invoked consistently and
reviewed like code. Human Review Milestones (HRMs) are the operator-facing control plane;
branches, worktrees, lanes, tests, and agents are subordinate implementation mechanisms.

## Repository contract

- `playbooks/` contains reusable workflows with YAML metadata and paste-ready prompts.
- `templates/` contains neutral records that an organization copies into its owning
  master-plan or project repository and adapts without changing the control semantics.
- `examples/` contains fictional, non-normative uses without secrets or customer data.
- `schemas/` contains fail-closed machine contracts for experimental execution records.
- `scripts/` contains repository-local validators and metric derivation; `tests/` protects
  their behavior with fictional fixtures.
- The adopting organization's governance and each project's `AGENTS.md` remain authoritative.
- The organization master plan owns business outcomes, system portfolio, authority,
  cross-system policy, and accepted change envelopes.
- Project repositories own system plans, requirements, scenarios, implementation manifests,
  versioned HRM maps, review state, and implementation evidence.
- This repository owns transferable process, prompts, schemas, and templates only.

Playbooks may coordinate approved work, but may not invent business meaning, assign
authority, weaken checkers, bypass human gates, or treat proposed, local, tested, merged,
deployed, activated, canary, or production-verified states as interchangeable.

## Operator and workspace setup

| Playbook | Use |
|---|---|
| [Operator-Workspace Onboarding and Method Orientation](playbooks/operator-workspace-onboarding.md) | Adaptively teach a human operator and their chosen workspace how to use the method, audit the available organization-to-system path, and discuss personalization without making writes. |
| [Operator-Workspace Conformance and Synchronization](playbooks/operator-workspace-conformance.md) | Audit and align a new account, machine, workspace, or project set when the operator already knows the method or wants a direct conformance path. |

## Lifecycle playbooks

| Stage | Playbook | Use |
|---|---|---|
| Intent | [Business Plan Elicitation](playbooks/business-plan-elicitation.md) | Convert evidence and operator interviews into outcomes, actors, capabilities, policies, authority, constraints, unknowns, and success measures. |
| Portfolio | [Organization System Portfolio Planning](playbooks/organization-system-portfolio.md) | Define system boundaries, authoritative subjects, owners, dependencies, contracts, and rollout order. |
| Project plan | [Project System-Plan Generation](playbooks/project-system-plan-generation.md) | Generate the project-owned system plan, requirements, scenarios, implementation manifest, and preliminary HRM journey. |
| HRM governance | [HRM Map Discovery and Rebaseline](playbooks/hrm-map-discovery-rebaseline.md) | Publish the complete-as-presently-knowable HRM map and govern discoveries, splits, additions, removals, and supersession. |
| Decisions | [Operator Decision Frontier](playbooks/operator-decision-frontier.md) | Surface semantic and authority decisions before non-disposable implementation and route S0-S3 interrupts. |
| Validation | [Operator Access and Validation Routing](playbooks/operator-access-validation.md) | Make completed discovery and decision packets available before integration CI while routing risk-scaled checks and non-recursive receipts. |
| Build | [System Build and Human Review Milestone Standard](playbooks/system-build-standard.md) | Advance one independently closable HRM through semantic readiness, a disposable vertical proof, derived implementation, and operator review. |
| Execute | [HRM Bundle Coordination Standard](playbooks/lane-coordination-standard.md) | Execute a published HRM bundle quietly with exact-head evidence and worker-to-orchestrator escalation. |
| Integrate | [Dedicated Checker and Merge Controller](playbooks/checker-merge-controller.md) | Delegate declared checks, exact-head merge, remote-main verification, and eligible cleanup to a source-read-only Codex subagent under one repository-global writer lease. |
| Workspace | [Workspace Topology and Review Handoff](playbooks/workspace-topology-review-handoff.md) | Maintain one stable operator desk while conditionally creating and promptly reconciling worker branches/worktrees. |
| Rollout | [Activation, Canary, and Production Rollout](playbooks/activation-production-rollout.md) | Govern deployment, activation, canary, production observation, and autonomy as separate evidence-bound decisions. |

## Experimental compact execution

[Compact HRM Execution Kernel](playbooks/hrm-execution-kernel.md) is a self-contained,
bounded-context replacement for the large Build, Execute, Integrate, and Rollout playbooks
during the `0.1.0-rc.14` experiment. It derives the active HRM from the accepted project map
instead of requiring the operator to restate it. A validated capsule grants routine workflow
through the next genuine human gate, including one bounded read-only provider diagnostic tree.
Sign-in and MFA are operator actions rather than decisions. Exact merge and material external
effects use bounded authority grants; fresh builder, checker, and provider-observer contexts
keep the root orchestrator small. An online action guard stops work before role, liveness,
context, or execution-mode violations. The small kernel preserves non-negotiable safety
constraints. Do not preload the replaced
playbooks into an experimental task. They are heading-bounded, metered references available
only through an approved question in the capsule.

This is intentionally an experiment rather than a new default. Pin the exact Agent Playbooks
commit in each capsule, keep the event log append-only, and derive the scorecard with the
repository script. Compare the resulting flow, context, CI, scope, safety, and operator-review
measures with the preregistered budgets; do not infer success from agent self-report.

The operator invocation is deliberately short: “Run the current HRM under the
repository-pinned AP-EXEC kernel.” The repository dispatcher derives the target, contract,
capsule, and event path; do not paste the kernel or require the operator to restate those inputs.

```sh
ruby scripts/hrm_experiment.rb validate-capsule path/to/hrm-execution-capsule.yaml
ruby scripts/hrm_experiment.rb validate-events path/to/hrm-run-events.jsonl
ruby scripts/hrm_experiment.rb validate-grant \
  path/to/hrm-authority-grant.yaml path/to/hrm-execution-capsule.yaml
ruby scripts/hrm_experiment.rb derive-state \
  path/to/hrm-execution-capsule.yaml path/to/hrm-run-events.jsonl
ruby scripts/hrm_experiment.rb evaluate \
  path/to/hrm-execution-capsule.yaml path/to/hrm-run-events.jsonl
ruby scripts/project_api_skill_registry.rb validate \
  path/to/project-api-skill-registry.yaml
ruby scripts/project_api_skill_registry.rb coverage \
  path/to/hrm-execution-capsule.yaml
ruby scripts/project_api_skill_registry.rb publish \
  path/to/hrm-execution-capsule.yaml path/to/hrm-run-events.jsonl < api-skill.json
ruby scripts/hrm_supervisor.rb resume \
  path/to/hrm-execution-capsule.yaml path/to/hrm-run-events.jsonl
ruby scripts/hrm_supervisor.rb handoff \
  path/to/hrm-execution-capsule.yaml path/to/hrm-run-events.jsonl
ruby scripts/hrm_supervisor.rb activate \
  path/to/hrm-execution-capsule.yaml path/to/hrm-run-events.jsonl \
  WORKER_CLAIM_ID DISPATCH_CURSOR DISPATCH_SHA256
ruby scripts/hrm_supervisor.rb context \
  path/to/hrm-execution-capsule.yaml path/to/hrm-run-events.jsonl ROLE \
  BASE64URL_CANONICAL_JSON_CONTEXT
ruby scripts/hrm_supervisor.rb result \
  path/to/hrm-execution-capsule.yaml path/to/hrm-run-events.jsonl \
  BASE64URL_CANONICAL_JSON_DOMAIN_DETAILS
ruby scripts/hrm_supervisor.rb append \
  path/to/hrm-execution-capsule.yaml path/to/hrm-run-events.jsonl < event.json
ruby scripts/hrm_supervisor.rb guard \
  path/to/hrm-execution-capsule.yaml path/to/hrm-run-events.jsonl ACTION ROLE
ruby scripts/hrm_supervisor.rb supersede \
  path/to/predecessor-capsule.yaml path/to/hrm-run-events.jsonl path/to/successor-capsule.yaml
ruby scripts/hrm_supervisor.rb transition \
  path/to/predecessor-capsule.yaml path/to/hrm-run-events.jsonl \
  path/to/successor-capsule.yaml SUCCESSOR_SESSION_ID EXECUTION_MODE
```

During rc.14, use the non-LLM supervisor for release checks, run writes, handoff, activation and context receipts, and continuation reads. It serializes
event appends and commits cursor-bound state, scorecard, compiled worker dispatch, and a quiet
operator projection. Unchanged kernel and HRM contract hashes are consumed from the dispatch
envelope instead of rereading full startup sources. `resume` atomically writes `session_started`
when the bound ledger is empty, then emits the first worker assignment. `transition`
mechanically derives and binds runtime-build/production-observation successors. The legacy
`hrm_experiment.rb` append, guard,
and supersede commands fail closed for rc.6 through rc.14 so
they cannot advance the authoritative ledger without committing the matching projection.
Every run artifact path is project-root-bound. A run-invalid ledger or failed process envelope
projects an explicit stop and cannot accept more writes. A decision inherited from a predecessor
must carry a request receipt verified against the exact immutable predecessor event log.
Compiled assignments authorize bounded dependency queries, publish source-size bounds, split the
role budget into a loaded-artifact ceiling and minimum tool-output reserve, and prohibit full-source
dumps. The inventory observer receives a 10,000-byte artifact ceiling and 2,000-byte minimum
tool-output reserve inside its unchanged 12,000-byte role budget; the builder remains 10,000/10,000.
Context snapshots map dependency IDs to exact materialized bytes and exclude those bytes
from non-dependency tool output, preventing duplicate accounting.
Runtime-build dispatch begins with a zero-effect binding inventory. A runtime delta is not
executable until every frozen real seam is bound and construction is proven without effects.
Handoff, context, and guard commands recompute the exact current assignment and reject even a
self-rehashed dispatch edit. Structured handoff claims bind the assigned action and role to the
source dispatch cursor and digest. Named experiment profiles pin the complete role-budget map;
`custom` remains the explicit override path.
RC.11 through RC.14 worker-owned lifecycle events cannot enter through the generic append path. `result`
accepts them only after the exact pending worker claim, context receipt, and matching immediate
guard, then records the value and claim-bound worker completion atomically. A replay or edited
claim, action, role, order, or result type leaves the ledger unchanged.
RC.12 resume and handoff receipts include a compact `worker_launch` projection: action, role,
cursor, one explicit project `working_directory`, project-relative dispatch path, assignment
dependency IDs and budgets, plus exact project-relative handoff/context/guard/result commands.
The launch `dispatch_sha256` binds the current post-refresh dispatch file and is distinct from a
handoff claim's pre-handoff source-dispatch hash. The complete launch receipt is capped at 4,096
bytes and is rejected before a ledger append if it cannot fit. During uninterrupted startup, the
root executes the receipt's handoff command directly from `working_directory` and spawns the worker
immediately with the dispatch path and claim; it does not open the
state, scorecard, projection, or dispatch itself and never empty-waits before spawning. Workers
execute protocol command arrays directly, without shell wrappers that can hide exit status or
an already-appended receipt.

RC.13 extends that compact receipt with a claim/cursor/current-dispatch-digest-bound
`activation_command`, a fresh `fork_turns: none` launch instruction, the exact worker order, and
minimal action-specific result keys and templates. The child worker's first tool must execute the
activation command. It then verifies the activated dispatch digest without dumping the file,
materializes bounded source, submits one cumulative context report, guards, and submits its result.
Context and result payloads are canonical JSON encoded as one unpadded base64url argv value; they
never depend on stdin, a TTY, a pipe, a shell wrapper, or EOF. The supervisor derives the result
event type, action, role, and claim from the live protocol and accepts only the declared domain
details. Every action in the canonical worker-required action map has a compact valid payload
template; unsupported reachable actions fail closed before launch. After guard, the compiled
dispatch binds the exact handoff-through-guard lifecycle. Result acceptance checks that stable
supervisor-compiled binding, so lifecycle edits fail without a ledger write while a legitimate
worker may change its assigned implementation source or resolve its assigned API-skill registry
after the guard and still report the bound result. Exact deterministic source dispatch
recomputation remains mandatory through activation, context, and guard. The root performs no
derived-artifact read or wait before the spawn and waits exactly once afterward. The runtime-build profile measures
session-to-activation and handoff-to-activation against preregistered 20-second and 10-second gates.

RC.14 preserves that protocol and compacts only start and handoff receipts. The complete
`worker_launch` still carries exact executable commands, working directory, dispatch path/digest,
dependency IDs and budgets, action/role, claim and activation binding, and the valid
action-specific template. Shared one-shot metadata appears once, launch policy is one compact
structured block, and pre-spawn projection diagnostics are omitted from the outer receipt. No root
or worker derived-artifact reread is introduced. A handoff receipt's `activation_command` is the
compact launch-ready signal; the preceding resume receipt intentionally has no activation command.
The 4,096-byte preappend limit is unchanged: the
realistic seven-seam AE fixture reproduces rc.13's 4,155-byte rejection and measures rc.14 at 2,941
bytes for resume and 3,660 bytes for claim-bearing handoff, leaving 436 bytes below the hard cap.

Optional zero-byte preflight receipts are normalized to empty dependency maps:
they do not count as loaded files, artifact identity, or repetition. RC.12 result validation may
cross any number of same-role zero-artifact preflights, but rejects an intervening business event
or a prior positive context before the final cumulative receipt.
Routine technical choices remain silent; only unavoidable environment/private-value actions,
genuine decisions, prepared review, and terminal state reach the operator projection.
Stable API skills are registered once and reused across HRMs and kernel versions. Each skill
contains callable contracts—including APM reads—and privacy-safe provenance. A different
repository may consume a skill only after Software Master Plan intake acceptance; volatile
provider state and every live-effect authority remain local and action-time bound.

## Change-propagation playbooks

| Playbook | Use |
|---|---|
| [Master-Plan Policy Amendment and Propagation](playbooks/master-plan-policy-amendment.md) | Elicit and version policy or contract meaning, emit a typed change envelope, and rebaseline affected systems and HRMs. |
| [Bidirectional Master-Plan Repository Polling and HRM Intake](playbooks/master-plan-repository-polling.md) | Route accepted master-plan changes and project receipts without inventing semantics or implying implementation authority. |

## Templates

Organization and portfolio:

- [Organization operating model](templates/organization-operating-model.yaml)
- [System portfolio](templates/system-portfolio.yaml)
- [Master-plan change envelope](templates/master-plan-change-envelope.yaml)

Project planning and review:

- [System plan](templates/system-plan.yaml)
- [Milestone claim and scenario matrix](templates/milestone-claim.yaml)
- [Complete-as-presently-knowable project HRM map](templates/project-hrm-map.yaml)
- [HRM-discovery proposal](templates/hrm-discovery-proposal.yaml)
- [Operator decision packet](templates/operator-decision-packet.yaml)
- [Input-boundary record](templates/input-boundary-record.yaml)
- [Contract-update request](templates/contract-update-request.yaml)
- [Checker/merge-controller handoff](templates/checker-merge-controller-handoff.yaml)
- [HRM review package](templates/hrm-review-package.md)
- [Stable current-review index](templates/current-review.md)
- [HRM session ledger](templates/hrm-session-ledger.yaml)
- [Workspace registry](templates/workspace-registry.yaml)
- [Activation and production record](templates/activation-production-record.yaml)
- [Codex global working agreements](templates/codex-global-agents.md)
- [Compact HRM execution capsule](templates/hrm-execution-capsule.yaml)
- [Exact HRM authority grant](templates/hrm-authority-grant.yaml)
- [Derived compact HRM session state](templates/hrm-session-state.yaml)
- [Compact HRM experiment profiles](templates/hrm-experiment-profiles.yaml)
- [Derived HRM run scorecard shape](templates/hrm-run-scorecard.yaml)
- [Fictional HRM-directed session](examples/hrm-directed-session.example.yaml)
- [Fictional compact execution capsule](examples/hrm-execution-capsule.example.yaml)
- [Fictional production-observation continuation capsule](examples/hrm-production-observation-capsule.example.yaml)
- [Fictional exact-head authority grant](examples/hrm-authority-grant.example.yaml)
- [Fictional derived compact session state](examples/hrm-session-state.example.yaml)
- [Fictional compact run events](examples/hrm-run-events.example.jsonl)
- [Fictional derived run scorecard](examples/hrm-run-scorecard.example.yaml)

## Operating model

1. Elicit the business plan without converting uncertainty into requirements.
2. Publish the organization operating model and system portfolio in the master plan.
3. Generate each project system plan with provenance back to accepted organization records.
4. Publish all HRMs that are presently knowable. Unknowns remain explicit; later discoveries
   use a versioned amendment rather than being forced into an existing milestone.
5. Resolve the decision frontier and semantic-readiness gate before substantive code. Every
   accepted decision emits a transition receipt in the response that acknowledges it, naming
   its effect, newly eligible work, frozen boundaries, owner, next action, and target. Eligible
   work in the same active HRM—or in a different HRM explicitly authorized by that decision—is
   assigned immediately or receives an explicit blocker receipt.
6. Publish completed discovery and decision packets after minimum packet validation; do not
   make operator interaction wait for application CI, merge, receipts, or cleanup.
7. Freeze the milestone claim: its vertically complete proof spine, horizontally bounded
   scenario matrix, cardinality, real-system effects, evidence, exclusions, and scale perimeter.
8. Prove the riskiest end-to-end path with a deliberately disposable vertical skeleton.
9. Derive tests from claim-breaking failure modes, then derive the smallest missing
   implementation delta and execute its change units under one HRM orchestrator. In brownfield
   systems, requirements are acceptance floors: reuse stronger compatible architecture,
   components, workflows, and tests before adding or replacing implementation.
10. Delegate declared checks, serialized merge, remote-main verification, and eligible cleanup
    to a source-read-only checker/merge-controller subagent. Repository queues may have
    dedicated controllers, but only one controller may hold the repository-global writer
    lease for a canonical remote and target ref at a time.
11. Stop at `review_ready` for explicit operator function/UI/UX acceptance and finding disposition.
12. Treat deployment, activation, canary, production observation, and autonomy as separate
   action-time gates with current evidence.

Vertical completeness and horizontal breadth are separate controls. Vertical completeness
proves the required real systems, operator actions, ordered effects, recovery, and human-
observable result from accepted input to destination. Horizontal breadth states exactly which
origins, variants, cardinalities, and mutations are supported. Paths that converge at an owned,
versioned contract seam may share downstream proof only when upstream equivalence is evidenced;
labels alone neither create nor eliminate a distinct scenario.

The operator decides business outcome and meaning, material scope or capability retirement,
authority, risk acceptance, HRM closure, and production-affecting action. The orchestrator
elicits those decisions early, consolidates worker discoveries, recommends a response, records
a semantic read-back, and delegates evidence gathering and implementation. Workers route
uncertainty to the orchestrator; they do not independently bombard the operator.

## Workspace model

A Codex task or conversation is not a Git change unit. A task first attaches to a published
HRM session. One HRM session may own multiple serial or parallel published change units. Each
published change unit gets one branch, normally one PR, and one integration receipt. A lane
normally maps to one change unit; split it when independently reviewable ownership, risk,
validation, rollback, or integration boundaries emerge instead of silently enlarging it.
The smallest coherent bundle means the smallest new delta, not the smallest implementation
considered in isolation. Every brownfield lane binds its requirements to the strongest compatible
existing implementation and tests; replacement requires an explicit incompatibility, safety,
retirement, parity, migration, rollback, and consumer-evidence basis. Serial classification names
the exact dependency, shared path or resource, state, or authority boundary that requires it.
Create a worktree only when concurrent execution, an active review runtime, or preservation
of unique unmerged work requires it. Disposable API or behavior discovery may end without a
PR; retain it only as a bounded evidence, contract, fixture, test, or documentation change
unit. Each project designates one stable operator checkout and one stable current-review index;
worker agents never implement in that checkout. Reconcile and remove eligible worktrees after
verified integration rather than waiting for HRM closure.

The HRM orchestrator owns meaning, scope, finding disposition, operator interaction, and
closure. A dedicated checker/merge-controller subagent owns the deterministic check and Git
integration segment for one repository queue. It remains source-read-only, never waives a
gate or edits a failing candidate, and reports exceptions back through the orchestrator.

## Using a playbook

1. Select the earliest applicable lifecycle stage; do not begin with implementation when
   organization meaning or project semantics are unresolved.
2. Open the playbook and supply its required inputs.
3. Paste the text under **Prompt** into an agent task.
4. Store outputs in the owning master-plan or project repository using stable IDs and versions.
5. Review only prepared decision packets, HRM review packages, and reserved action-time gates.

Example:

```text
Use the System Build and Human Review Milestone Standard.
System: SYS-EXAMPLE-001 in the current project.
Project HRM map: docs/planning/project-hrm-map.yaml.
Target HRM: HRM-WORKFLOW-001.
Milestone outcome: the operator can complete and correct the local workflow and
understand failures without external writes.
Activation posture: read-only.
```

## Change standard

Every material playbook change updates its version and change note. An adopting
organization may map its own standards to these controls, but organization-specific
identifiers are not normative here. Retired playbooks remain in Git history and are not
silently repurposed. Never commit credentials, private provider evidence, customer data,
generated business artifacts, or conversation transcripts.
