---
playbook_id: AP-VALIDATE-001
title: Operator Access and Validation Routing
version: "1.1"
status: active
owner: Adopting organization
mode: early-operator-access-risk-scaled-validation
human_readable: true
machine_readable: true
required_inputs: [validation_subject, changed_surfaces]
optional_inputs: [change_unit, operator_packet, milestone_claim, repository_validation_policy, integration_policy]
controls: [operator-access-before-integration, validation-profile-routing, claim-derived-validation-budget, no-duplicate-suite, non-recursive-receipts]
---

# Operator Access and Validation Routing

Use this playbook to make completed discovery and decision material available to the
operator promptly while preserving risk-scaled integration evidence. Operator access,
integration eligibility, and activation authority are separate gates.

## Validation profiles

| Profile | Applies to | Required evidence | Application suite |
|---|---|---|---|
| `review_packet` | Read-only audits, decision packets, HRM discoveries, planning records, and inert documentation | Stable packet ID/version/content hash, provenance, schema/parse checks where applicable, privacy scan, and internal consistency; add changed-file allowlist, documentation lint/link checks, and `git diff --check` only when repository-backed | Not applicable; reclassify if the final diff changes a generated or runtime-consumed input |
| `executable_contract` | Agent policy, schemas, executable examples, contract mirrors, configuration, generators, and other machine-consumed governance | All applicable `review_packet` checks plus targeted consumer/schema/example checks | Affected-consumer tests plus every mandatory checker or broader trigger |
| `runtime_change` | Application code, runtime data, persistence, providers, deployment, and production-affecting configuration | The HRM Bundle Coordination Standard's changed-surface and risk-scaled test plan | Focused, affected-package, or full suite according to demonstrated reach and release gates |

Classify from changed behavior and dependency reach, not the file extension or directory
alone. A non-Git packet is identified by stable packet ID, version, content hash, and
provenance; Git paths, diffs, and SHAs are optional and apply only when repository-backed.
If a supposedly inert record is consumed at runtime, raise its profile. Do not raise an
inert review packet merely because the repository also contains application code.

For runtime changes, a validation budget is complete when it covers every required milestone
scenario, claim-breaking failure mode, safety invariant, demonstrated dependency risk, and
binding release gate--not when it reaches a target number of tests. Equivalent downstream
paths may share evidence only through an explicit owned-seam equivalence record. Generalized
reachable behavior outside the milestone claim must be narrowed or receive its necessary tests.

## Prompt

```text
Route operator access and validation for this subject.

Validation subject: {{validation_subject}}
Change unit: {{change_unit_or_none}}
Changed surfaces: {{changed_surfaces}}
Operator packet: {{operator_packet_or_none}}
Milestone claim: {{milestone_claim_or_none}}

1. Classify the validation subject or repository diff as review_packet,
   executable_contract, or runtime_change and record the evidence for that classification
   and every affected consumer. Bind a non-Git subject to packet ID, version, content hash,
   and provenance; require Git-specific checks and identity only when repository-backed.
2. For S0-S2 decisions, completed read-only discovery, possible HRM discoveries, and
   prepared function/UI/UX review, publish the stable operator packet as soon as its
   minimum structural, privacy, and consistency checks complete. A structural or consistency
   failure sets `operator_access_blocked` and delivers a bounded failure notice plus safe,
   readable evidence. A privacy, secret, or PII failure quarantines the payload and delivers
   only a redacted failure notice; never expose the failed material. Do not wait for application tests,
   independent code review, PR mergeability, integration, receipt publication, cleanup,
   or unrelated CI before allowing operator interaction.
3. Record access as not_ready, operator_access_ready, operator_access_blocked, in_review,
   withdrawn, or superseded separately from integration_eligible. Early access authorizes
   semantic decisions, discovery disposition, or provisional feedback only. It is not formal
   HRM function/UI/UX acceptance, HRM closure, integration proof, or activation authority.
   Formal HRM acceptance remains bound to the integrated exact head required by AP-LANE-001.
4. Apply the profile's checks in addition to repository policy, mandatory checkers,
   AP-LANE-001 full-suite triggers, and release gates; profiles never weaken those controls.
   A review_packet never triggers application tests: reclassify it when generated/runtime-
   consumed inputs changed. An executable_contract starts with targeted consumers and adds
   every mandatory broader trigger. A runtime_change follows demonstrated dependency reach.
   Unknown consumer reach or classifier failure fails integration closed and is never an
   explicit validation pass, while any already-safe operator packet remains visible.
4a. For a runtime change, trace every check to the frozen milestone claim, a plausible
    changed-surface regression, dependency risk, or binding gate. Test a failure mode at
    the lowest deterministic layer that can prove it and repeat it end to end only when
    the integrated seam or real effect is itself claimed. Use focused iteration checks and
    one release-required full-suite run on the frozen integrated head. If a generic policy
    applies application tests to an inert review packet, preserve the policy gate but report
    the contradiction as a conformance amendment; never hide the safe packet from the operator.
5. Configure CI so one candidate head does not receive duplicate equivalent suites from
   both branch-push and pull-request events. Prefer a lightweight change classifier and
   one required aggregate result that records safely classified non-applicable jobs as pass.
6. Treat remote Git and hosting read-back as authoritative integration identity. Do not
   create a new change unit or PR solely to record the merge of the immediately preceding
   documentation/governance change. Hosting merge read-back containing PR identity, accepted
   head, merge/main SHA, and timestamp is the terminal receipt. An optional reference added
   by a later planned unit is informational and non-self-receipting. A cross-system carrier
   additionally records `impact_key`, `caused_by`, `content_hash`, `hop_count`, and
   `max_hops`, and never emits a receipt in response to its own receipt. Only an explicit
   regulatory rule may require an immediate receipt-only unit.
7. Receipt reconciliation, full application CI, and workspace cleanup may continue in
   parallel. None may delay a packet already ready for operator interaction. They remain
   required before any claim or action whose gate explicitly depends on them.
8. Record operator_packet_published_at, operator_access_ready_at, validation_started_at,
   candidate identity (packet ID/version/content hash or Git SHA), integrated_head_sha when
   repository-backed, integration_eligible_at, and any avoidable wait caused by
   misclassification, duplicate CI, or receipt recursion. Also record time to first meaningful
   operator interaction and time to formal HRM review so fast packet access is not confused
   with milestone completion.
```

## Change note

- **1.1 — 2026-08-25:** Derives runtime validation budgets from frozen milestone claims,
  distinct seams, failure modes, and safety invariants; preserves early access when local
  policy over-tests inert documentation; and separates first interaction from formal HRM time.
- **1.0 — 2026-08-24:** Separates operator access from integration and activation gates,
  defines review-packet, executable-contract, and runtime-change validation profiles,
  prevents duplicate equivalent CI suites, and prohibits recursive receipt-only PRs by
  default.
