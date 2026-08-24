---
playbook_id: AP-POLICY-001
title: Master-Plan Policy Amendment and Propagation
version: "1.0"
status: active
owner: Adopting organization
mode: master-plan-policy-amendment
human_readable: true
machine_readable: true
required_inputs:
  - organization_or_master_plan
  - policy_scope
  - amendment_objective
optional_inputs:
  - originating_hrms
  - contract_request_ids
  - operator_decision_authority
  - propagation_scope
  - implementation_authority
  - human_review_requirements
controls:
  - evidence-claim-separation
  - hrm-first-propagation
  - operator-decision-frontier
  - semantic-read-back
  - typed-change-envelope
  - evidence-expiry
  - operator-led-elicitation
  - stable-id-traceability
  - contract-impact-analysis
  - request-is-not-adoption
  - downstream-hrm-rebaseline
  - canonical-authoring-location
  - cross-workspace-propagation
  - versioned-history
  - repository-rules-first
  - exact-head-verification
  - no-production-mutation-without-action-time-approval
---

# Master-Plan Policy Amendment and Propagation

Use this prompt from inside an HRM-first organization master-plan repository. The master
plan is the registry of business intent and authority; linked application repositories
retain their own implementation manifests, tests, and evidence. The prompt elicits
operator decisions, discovers contract implications, amends canonical records, and
propagates the approved change through every known provider, consumer, manifest,
document, and generated view without rewriting history or inventing authority.

Research evidence is informative unless the organization has adopted it through its own
decision mechanism. It does not itself authorize policy, implementation, or production
changes. An adopting organization may map local standards to this playbook's evidence-
separation and HRM-first controls. A contract-update request may be opened autonomously
as a documentation and routing act, but it is not adopted meaning, implementation, or
activation authority.

## Inputs

- **Organization or master plan:** `{{organization_or_master_plan}}`
- **Policy IDs or topics:** `{{policy_scope}}`
- **Amendment objective:** `{{amendment_objective}}`
- **Originating HRMs:** `{{originating_hrms_or_none}}`
- **Contract request IDs:** `{{contract_request_ids_or_none}}`
- **Operator decision authority:** `{{operator_decision_authority_or_discover}}`
- **Propagation scope:** `{{propagation_scope_or_all_registered_consumers}}`
- **Implementation authority:** `{{implementation_authority_or_docs_and_contracts_only}}`
- **Human-review requirements:** `{{human_review_requirements_or_default}}`

## Prompt

```text
Work from this master-plan repository: {{organization_or_master_plan}}.

Policy scope: {{policy_scope}}.
Amendment objective: {{amendment_objective}}.
Originating HRMs: {{originating_hrms_or_none}}.
Contract request IDs: {{contract_request_ids_or_none}}.
Operator decision authority: {{operator_decision_authority_or_discover}}.
Propagation scope: {{propagation_scope_or_all_registered_consumers}}.
Implementation authority: {{implementation_authority_or_docs_and_contracts_only}}.
Human review: {{human_review_requirements_or_default}}.

WORKSPACE AND AUTHORITY

1. Treat this HRM-first master-plan repository as the registry of intent and
   authority. Treat linked repositories as federated owners of implementation
   manifests, local contracts/tests, and evidence. A downstream repository is an
   affected repository when it authors, provides, consumes, implements, tests,
   copies, renders, or evidences a changed record.
2. Read every applicable AGENTS.md and repository rule before acting. Reconcile
   current branches, worktrees, remotes, PRs, and uncommitted work. Preserve user work.
3. Default authority is documentation and contract amendment only. Do not implement
   application behavior, merge, deploy, migrate, send customer communication, change
   credentials, move money or inventory, or mutate an external/production system
   unless this run has explicit authority for that exact action and required approval.
4. Research, observed behavior, operator input, proposed policy, accepted
   policy, implementation, deployment, and runtime evidence are different claim types.
   Never promote one to another silently.
   A `CTRQ` is a proposed question and impact record, not the missing promise or approval.

DISCOVER THE CURRENT POLICY AND IMPACT GRAPH

5. Locate the active standard, policy/rule records, ADRs, authority claims, state
   models, requirements, flows, material edges, integration cards, machine contracts,
   systems, implementation manifests, evidence, operator views, and generated indexes
   related to the named policy scope. Identify each canonical authoring location.
6. Build a versioned impact graph using stable IDs and this traceability path:

   Outcome -> capability -> policy/rule/requirement -> state/authority -> flow/edge
   -> integration/contract -> provider and consumer manifests -> tests/evidence
   -> affected project HRMs -> operator and generated views.

7. Search the registry, backlinks, manifests, and repository contents for every known
   producer, consumer, copied declaration, and shared seam. Do not claim the search is
   complete when a registered repository is unavailable; record it as a blocker with
   owner and required follow-up.
8. Give the operator a concise current-policy brief: exact IDs/versions and status,
   effective dates, authority, current wording, supporting evidence and freshness,
   known implementations/consumers, contradictions, exceptions, and unresolved
   questions. Separate direct operator input, current-state observation, proposal,
   assumption, and unknown.

ELICIT THE AMENDMENT

9. Interview the authorized operator at the business-decision level. Batch related
   questions into small decision packets instead of asking for routine technical
    choices. For each packet, show the current claim, why a decision is needed, the
    recommended answer, viable alternatives, and consequences for customers, people,
    money, inventory, privacy, operations, and automation.
9a. Establish the decision frontier before editing: S0 for protected, irreversible, or
    action-time effects; S1 where agents would otherwise choose meaning or authority;
    S2 for material schedulable decisions; and S3 for reversible technical choices inside
    accepted meaning. Notify S0 immediately, S1 before non-disposable propagation, batch
    S2, and record S3 autonomously. Record first foreseeable/notified times, invalidation
    reach, latest-safe time, safe posture, permitted continuation, and evidence expiry.
10. Elicit at least: desired outcome and non-goals; actors and authority; applicability
    and effective time; inputs and provenance; decision/default/no-match behavior;
    lifecycle and transitions; ordinary, edge, exception, cancellation and reversal
    cases; human approval/escalation; customer-facing effects; audit and evidence;
    review/expiry; and migration or grandfathering of existing records.
11. Preserve disagreement and uncertainty as QST, ASM, RSK, or EXC records. Unknown is
    valid and must not become false, zero, empty, a guessed default, or executable truth.
    Any unresolved issue affecting customer communication, money, credentials, privacy,
    safety, inventory, legal records, or live mutation blocks normative promotion.

ELICIT CONTRACT AND SEAM CHANGES

12. For every proposed policy difference, walk every affected material edge and ask
    only the operator decisions that cannot be established from approved contracts.
    Assess all four promise classes:
    - semantic: meaning, identities, units, time, authority, and invariants;
    - syntactic: fields, types, allowed values, schemas, and versions;
    - behavioral: preconditions, states, ordering, duplicates, idempotency, errors,
      retries, cancellation, compensation, reconciliation, and human intervention;
    - operational: availability, privacy, credentials, retention, observability,
      support, rollout, recovery, deprecation, and evidence.
13. For each changed authority claim, make subject, bounded context, lifecycle,
    operation, authorized writer/decider, authoritative read-back, copies/staleness,
    conflict resolution, transfer event/evidence, effective date, and expiry explicit.
14. Determine whether each contract change is compatible, conditionally compatible,
    or breaking. Define supported versions, producer/consumer upgrade order, safe
    behavior during mixed versions, migration, rollback/compensation, test obligations,
    and deprecation window. Do not assume provider-first or consumer-first rollout.
15. A coordinator may create or enrich a stable `CTRQ` without a separate operator gate
    when repository rules authorize documentation-only intake. It may record evidence,
    affected HRMs, owning system, required decision, safe posture, and compatibility
    questions. It may not choose new business meaning, authority, compatibility policy,
    external effects, or acceptance criteria. Those answers remain proposed until the
    authorized operator approves the consolidated amendment.
16. Before editing adopted records, present one consolidated amendment packet containing
    the policy diff, contract/authority implications, affected stable IDs and repositories,
    compatibility and migration plan, unresolved blockers, recommended decision, and
    exact approval requested. Do not drip-feed foreseeable scope amendments.
16a. Read the operator's answer back as exact accepted meaning, authority, scope,
     exclusions, effective time, affected records, and expiry. Resolve ambiguity before
     canonical amendment; a timeout or partial answer is not acceptance.

AMEND CANONICAL RECORDS

17. After operator approval, use the master plan's adopted decision mechanism. Create
    or update the required ADR/change record; version the policy and affected contracts;
    record effective/review dates, approval scope, rationale, alternatives, consequences,
    confirmation plan, and supersession links. Never rewrite an accepted historical
    decision to make the new decision appear original, and never reuse stable IDs.
18. Edit each fact at its canonical authoring location once. Update linked policy,
    rule/decision table, requirement, state, authority, flow, integration card, machine
    contract, risk/question/exception, and operator-view sources as applicable. Regenerate
    deterministic indexes, backlinks, diagrams, and summaries; do not hand-edit generated
    artifacts.
18a. Emit one typed master-plan change envelope with source record IDs, before/after
     versions, accepted SHA, semantic/syntactic/behavioral/operational differences,
     provenance and evidence expiry, affected systems/contracts/requirements/projects/HRMs,
     compatibility, mixed-version posture, migration, rollback, sunset, rebaseline needs,
     safe posture, permitted work, downstream routes, and separate documentation,
     implementation, merge, deployment, activation, canary, and production authority.
     Unresolved meaning remains explicit and has no inferred default.

PROPAGATE THROUGH AFFECTED REPOSITORIES

19. Create a propagation ledger with one row per affected repository and affected HRM:
    relationship to the change, stable IDs and versions, canonical or copied records, files/manifests/
    tests/views affected, owner, repository rules, compatibility action, dependency,
    branch/PR, exact head, checks, approval, merge state, and blocker.
20. Reconcile every registered affected repository before editing it. Apply its own
    branch, worktree, lane, checker, review, and PR rules. Update contract references,
    implementation manifests, local documentation, examples, fixtures, compatibility
    tests, evidence hooks, and generated views that are in the authorized scope.
21. If the approved policy requires application behavior outside this run's authority,
    do not silently implement it. Create the repository's required bounded lane/change
    plan with acceptance criteria and traceability, or record an explicit blocked
    implementation obligation. Documentation must not claim the behavior exists.
22. Rebaseline every affected project HRM map and milestone contract prospectively from
    the typed change envelope. Mark
    blocked HRMs, changed prerequisites, review scenarios, evidence requirements, and
    superseded map versions explicitly. Do not rewrite already closed HRM evidence.
23. Order changes according to the compatibility plan. Independent repositories may be
    prepared in parallel; merges that establish or consume a shared contract are
    serialized. Bind checks and independent review to exact heads. After each merge,
    verify the remote default branch, required CI, references, and generated drift index.

VERIFY AND HAND OFF

24. Validate stable IDs, schemas, references, supersession, material-edge coverage,
    manifest versions, compatibility tests, generated artifacts, secrets/PII checks,
    and policy-to-contract-to-repository traceability. A valid document is not proof
    that policy is correct, implemented, deployed, or production-verified.
25. Prepare one operator acceptance brief showing the approved business meaning,
    exact changed versions, customer/financial/operational effects, exceptions and
    human controls, affected repositories, compatibility/migration state, residual
    blockers, and evidence still required. Obtain any mandated review against exact
    versions and commits.
26. Finish with four lists: amended canonical records; propagated and verified
    repositories; blocked/unavailable repositories; and implementation, deployment,
    canary, or production actions still requiring separate authority. Report no external
    mutations unless each is explicitly authorized and independently read back.
```

## Machine-readable propagation record

```yaml
amendment:
  id: "{{change_or_adr_id}}"
  status: proposed
  organization: "{{organization}}"
  operator_authority: "{{role_or_person}}"
  policy_versions_before: []
  policy_versions_after: []
  effective_from: null
  approval_record: null
  semantic_read_back: null
  change_envelope:
    schema_version: agent_playbooks.master_plan_change_envelope.v1
    id: null
    accepted_sha: null
    differences:
      semantic: []
      syntactic: []
      behavioral: []
      operational: []
    evidence_expires_at: null
    safe_posture_until_adopted: null
  originating_hrms: []
  contract_request_ids: []
  affected_records: []
  affected_hrms:
    - project: "{{project}}"
      hrm_id: "{{hrm_id}}"
      prior_map_version: null
      rebaselined_map_version: null
      impact: "blocked|prerequisite_changed|review_changed|evidence_changed|none"
  unresolved_questions: []
  affected_repositories:
    - repository: "{{repository}}"
      relationship: "author|provider|consumer|implementation|copy|view|evidence"
      stable_ids: []
      required_changes: []
      compatibility: "compatible|conditional|breaking|unknown"
      dependency_order: null
      branch: null
      pr: null
      exact_head_sha: null
      checks: []
      review: null
      merge_sha: null
      status: "identified|blocked|prepared|reviewed|merged|verified"
  external_mutations: 0
  next_authorized_action: operator_review
```

## Change note

- **1.0 — 2026-08-24:** Generalizes the workflow for any adopting organization and adds
  an S0-S3 decision frontier, semantic read-back, evidence expiry, and a typed change
  envelope that separates semantic, syntactic, behavioral, and operational impact from
  implementation, deployment, activation, canary, and production authority.
- **0.2 — 2026-08-21:** Earlier organization-local release added HRM-first propagation,
  distinguished autonomous
  documentation-only `CTRQ` intake from adopted contract meaning, and requires affected
  HRM maps and milestone contracts to be rebaselined without rewriting history.
- **0.1 — 2026-08-19:** Initial organization-local draft. Applied evidence separation,
  operator-level elicitation, four-class contract impact analysis, scoped authority,
  stable-ID traceability, federated propagation, compatibility ordering, and exact-head
  verification to single- or multi-policy amendments.
