---
playbook_id: AP-DECIDE-001
title: Operator Decision Frontier
version: "1.2"
status: active
owner: Adopting organization
mode: early-human-input-routing
human_readable: true
machine_readable: true
required_inputs: [target_outcome, planning_evidence]
optional_inputs: [current_hrm, worker_discoveries, operator_response_window]
controls: [earliest-foreseeable-escalation, operator-access-before-integration, consolidated-routing, semantic-read-back, decision-transition-receipt, proportional-traceability-update, no-silent-default]
---

# Operator Decision Frontier

Use this playbook before lane authorization and whenever a worker discovers uncertainty
that could make later work semantically wrong. The orchestrator is the single operator route.

## Interrupt classes

| Class | Meaning | Action |
|---|---|---|
| S0 | Protected, irreversible, security/privacy, money/customer effect, or action-time production authority | Freeze the affected boundary and notify immediately. |
| S1 | Agents would otherwise choose business meaning, authority, identity, UX intent, correctness gap, or capability retirement | Freeze and notify before implementation; no silent default. |
| S2 | Material but schedulable choice whose delay will not create non-disposable work | Consolidate and deliver in a bounded decision batch. |
| S3 | Reversible technical choice inside accepted semantics and authority | Orchestrator or worker decides and records it; no operator interrupt. |

## Prompt

```text
Establish and maintain the operator decision frontier.

Target outcome: {{target_outcome}}
Planning evidence: {{planning_evidence}}
Current HRM: {{current_hrm_or_none}}

1. Identify every unresolved term, authority assignment, capability removal, user journey,
   external identifier, state transition, acceptance tradeoff, risk acceptance, production
   effect, and evidence gap that implementation could otherwise decide implicitly.
2. Classify each S0-S3 and record first observed time, first foreseeable decision time,
   invalidation reach, latest safe decision time, safe posture, and permitted work.
3. Workers send discoveries to the HRM orchestrator, not directly to the operator. The
   orchestrator deduplicates overlapping input records, contract requests, findings, and HRM
   discoveries, then selects the earliest necessary route.
4. Prepare each operator packet with stable ID, affected HRMs, one-sentence decision,
   provenance, why now, recommendation, at most three alternatives, consequences, safe posture,
   permitted continuation, evidence expiry, response syntax, and decision authority.
5. Deliver S0 immediately, S1 before assumption or non-disposable work, and S2 in a short
   bounded batch. Do not suppress an early question merely because an HRM review is not ready.
   Once the readable packet passes minimum structural, privacy, and consistency checks,
   mark it `operator_access_ready` and deliver it. Application CI, independent code review,
   PR mergeability, integration, receipt publication, and cleanup are not prerequisites to
   operator interaction. A structural or consistency failure becomes
   `operator_access_blocked` with a safe failure notice. A privacy, secret, or PII failure
   quarantines the payload and delivers only a redacted notice; never expose failed material.
   Early access supports semantic decisions and provisional feedback only, not formal HRM
   acceptance, closure, integration proof, or activation.
6. A timeout never becomes semantic acceptance. Continue only explicitly permitted reversible
   work; otherwise remain fail-closed and send compact status without repeating the full packet.
7. Read the response back as the exact accepted meaning, scope, exclusions, affected records,
   and expiry. Resolve ambiguity before unfreezing the boundary.
8. In the same response that acknowledges the operator decision, issue a decision-transition
   receipt stating whether the decision is `record_only`, `releases_change_units`,
   `closes_stage`, or `closes_hrm`; every newly eligible change unit; any different HRM newly
   authorized by the decision; every boundary still frozen and why; the assigned owner/task;
   the next action; and the decision-to-builder-or-blocker target, default 600 seconds.
   Assign already-authorized eligible work immediately or return a concise blocker receipt
   within that target. A different HRM still requires its own
   published authority; when the accepted decision explicitly supplies that authority, assign
   its eligible published work under the same receipt. Work newly eligible inside the active
   HRM does not wait for HRM closure.
9. Update canonical plans and traceability before implementation only when the decision changes
   executable contract meaning, authority, dependencies, checker/test oracle, or HRM release
   semantics. When the decision merely records already-published semantics, carry traceability
   in the released runtime unit or another already-required bounded unit. Do not create a
   separate planning or receipt-only change unit merely to restate the accepted decision.
```

## Change note

- **1.2 — 2026-08-25:** Requires an immediate decision-transition receipt, releases eligible
  same-HRM work without waiting for closure, and prevents traceability-only planning units from
  delaying implementation when executable semantics did not change.
- **1.1 — 2026-08-24:** Separates operator access from integration eligibility so completed
  discovery and S0-S2 decision packets reach the operator after minimum packet validation,
  without waiting for application CI, merge, receipts, or cleanup.
- **1.0 — 2026-08-24:** Initial S0-S3 early operator-input protocol.
