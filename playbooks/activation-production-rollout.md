---
playbook_id: AP-ROLLOUT-001
title: Activation, Canary, and Production Rollout
version: "1.2"
status: active
owner: Adopting organization
mode: post-implementation-rollout
human_readable: true
machine_readable: true
required_inputs: [accepted_hrm, rollout_target, action_time_authority]
optional_inputs: [milestone_claim, validation_scope, deployment_plan, canary_plan, recovery_plan, observation_window]
controls: [state-separation, exact-artifact, accepted-milestone-claim, scoped-canary-validation, scenario-matrix-canary, destination-observation, action-time-approval, read-back-reconciliation, rollback]
---

# Activation, Canary, and Production Rollout

Use this playbook only after the required implementation HRM is explicitly accepted. Green
tests, a preview, merge, deployment, or prior approval does not supply current rollout authority.

## State model

Record separately: implemented, integrated, artifact-proven, deployment-ready, deployed,
activation-ready, activated, canary-authorized, canary-observed, production-observed, and
autonomy-eligible. Evidence for one state never silently promotes another.

## Prompt

```text
Prepare and, only within explicit authority, execute the requested rollout stage.

Accepted HRM: {{accepted_hrm}}
Rollout target: {{rollout_target}}
Action-time authority: {{action_time_authority}}
Milestone claim: {{milestone_claim_or_accepted_hrm_record}}
Validation scope: {{validation_scope_or_accepted_milestone_budget}}

1. Verify the accepted HRM, exact candidate SHA/artifact/manifest, target environment,
   configuration, dependencies, contract versions, owner, credential/permission state,
   data/privacy boundary, and evidence freshness. A producer build does not prove the actual
   promoted artifact or usable consumer contents. Resolve the accepted milestone-claim
   version and confirm its proof spine, safety shell, supported breadth, scenario matrix,
   cardinality, exclusions, and evidence requirements match the rollout request. Verify the
   accepted `targeted`, `affected`, or `full` validation scope, coverage, exclusions,
   freshness, authority, and policy compatibility. A canary label does not itself require
   full CI; unknown reach or a binding full-suite gate remains blocking. Fail closed unless
   the rollout candidate repository SHA and artifact digest exactly match the unexpired
   validation-readiness binding, including policy SHA, bounded changed surfaces, dependency
   reach, required hosted-gate dispositions, full-suite-trigger dispositions, and controller
   receipt. Every `not_applicable` hosted gate or `not_triggered` full-suite trigger requires
   a reason, binding policy/checker reference and SHA, deciding authority, and controller-
   receipt evidence; an empty disposition is blocking. A stage label or later build cannot
   inherit evidence from a different candidate.
2. Identify the single requested stage. Reject composite `go live` authority that conflates
   deployment, activation, canary, production observation, and autonomy.
3. Prepare stage-specific entry criteria, bounded effects, expected receipts, health signals,
   reconciliation, retry/idempotency, stop conditions, rollback/compensation, support owner,
   observation window, and success/failure decision authority.
3a. For a canary, create the real-execution matrix from distinct owned input and output seams.
    Execute every contract path required by the accepted claim unless an explicit convergence
    record proves representative equivalence after a named seam. Preserve the claim's exact
    cardinality and ordered effects; do not add lifecycle breadth, mutations, variants, or
    automation during canary execution.
3b. Define machine and human proof separately. Provider acceptance, `sent`, queued, or API
    read-back proves only provider state. When the claim is that a person received or could
    use an effect, require privacy-safe observation at the actual destination. Record only
    the minimum non-sensitive receipt metadata in governed evidence.
4. Surface new semantic, risk, topology, correctness-gap, or irreversible choices through an
   S0/S1 operator packet. Read action-time authority back with exact scope and expiry.
5. Before any external effect, revalidate the exact target and guard. If identity or response
   is ambiguous, reconcile by original request/operation ID and provider read-back; never retry
   as a new operation.
6. Execute only the authorized bound. Capture immutable receipts and current evidence. Stop on
   any violated invariant or stale prerequisite; preserve the safest prior posture. On partial
   failure, retain successful effects as final, reconcile ambiguous operations by original
   identity, and resume only the first incomplete ordered effect unless the accepted recovery
   plan explicitly requires compensation.
7. Reconcile intended versus observed state. Roll back or compensate according to the approved
   plan; do not invent recovery authority.
8. Publish the activation/production record with exact stage result, evidence window, effects,
   incidents, reconciliation, residual risk, next eligibility, and what remains unauthorized.
```

## Change note

- **1.2 — 2026-08-25:** Accepts explicitly authorized targeted, affected, or full canary
  validation without treating the canary label itself as a full-suite trigger.
- **1.1 — 2026-08-25:** Binds canaries to the accepted milestone claim and its distinct
  contract seams, cardinality, ordered effects, destination observation, and partial-failure
  resume rules without expanding horizontal scope during rollout.
- **1.0 — 2026-08-24:** Initial organization-neutral post-HRM rollout workflow.
