---
playbook_id: AP-ROLLOUT-001
title: Activation, Canary, and Production Rollout
version: "1.0"
status: active
owner: Adopting organization
mode: post-implementation-rollout
human_readable: true
machine_readable: true
required_inputs: [accepted_hrm, rollout_target, action_time_authority]
optional_inputs: [deployment_plan, canary_plan, recovery_plan, observation_window]
controls: [state-separation, exact-artifact, action-time-approval, read-back-reconciliation, rollback]
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

1. Verify the accepted HRM, exact candidate SHA/artifact/manifest, target environment,
   configuration, dependencies, contract versions, owner, credential/permission state,
   data/privacy boundary, and evidence freshness. A producer build does not prove the actual
   promoted artifact or usable consumer contents.
2. Identify the single requested stage. Reject composite `go live` authority that conflates
   deployment, activation, canary, production observation, and autonomy.
3. Prepare stage-specific entry criteria, bounded effects, expected receipts, health signals,
   reconciliation, retry/idempotency, stop conditions, rollback/compensation, support owner,
   observation window, and success/failure decision authority.
4. Surface new semantic, risk, topology, correctness-gap, or irreversible choices through an
   S0/S1 operator packet. Read action-time authority back with exact scope and expiry.
5. Before any external effect, revalidate the exact target and guard. If identity or response
   is ambiguous, reconcile by original request/operation ID and provider read-back; never retry
   as a new operation.
6. Execute only the authorized bound. Capture immutable receipts and current evidence. Stop on
   any violated invariant or stale prerequisite; preserve the safest prior posture.
7. Reconcile intended versus observed state. Roll back or compensate according to the approved
   plan; do not invent recovery authority.
8. Publish the activation/production record with exact stage result, evidence window, effects,
   incidents, reconciliation, residual risk, next eligibility, and what remains unauthorized.
```

## Change note

- **1.0 — 2026-08-24:** Initial organization-neutral post-HRM rollout workflow.
