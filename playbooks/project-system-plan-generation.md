---
playbook_id: AP-PLAN-001
title: Project System-Plan Generation
version: "1.1"
status: active
owner: Adopting organization
mode: portfolio-assignment-to-project-plan
human_readable: true
machine_readable: true
required_inputs: [accepted_system_record, project_repository, authorized_operator]
optional_inputs: [existing_codebase, brownfield_evidence, contract_catalog, constraints]
controls:
  - source-provenance
  - decision-frontier-before-decomposition
  - semantic-readiness
  - scenario-before-lane
  - vertical-completion-horizontal-breadth
  - owned-seam-equivalence
  - complete-as-presently-knowable-hrm-map
---

# Project System-Plan Generation

Use this playbook to turn an accepted organization system assignment into the project-owned
planning package required before implementation.

## Required package

- `docs/system/system-plan.md` or equivalent structured record;
- requirements ledger with stable IDs and provenance;
- scenario matrix including safe failure, recovery, and reconciliation;
- milestone claims defining proof spine, safety shell, supported breadth, cardinality,
  seam equivalence, explicit exclusions, and sequenced obligations;
- implementation manifest mapping requirements to owned surfaces and evidence;
- contract and system-node registry;
- brownfield capability inventory when applicable; and
- preliminary complete-as-presently-knowable HRM map.

## Prompt

```text
Generate the project system-planning package.

Accepted system record: {{accepted_system_record}}
Project repository: {{project_repository}}
Authorized operator: {{authorized_operator}}
Existing codebase: {{existing_codebase_or_none}}

1. Read project rules and reconcile current source, tests, runtime evidence, contracts,
   decisions, and existing plans. Classify claims as accepted-current, observed-current,
   historical-needs-revalidation, proposed, contradictory, or unknown.
2. Define system outcome, boundary, actors, authoritative subjects, prohibited authority,
   dependencies, privacy/security posture, lifecycle states, and explicit exclusions. Bind
   each to organization record IDs and versions.
3. For brownfield systems, inventory required operator, advanced operator, developer/audit,
   intentionally superseded, and unknown capabilities. No word such as simplify, modernize,
   or remove authorizes retiring an established capability.
4. Build the operator decision frontier before requirements decomposition. Freeze affected
   boundaries and obtain semantic read-back for unresolved meaning, authority, identity,
   lifecycle, correctness-gap, external-effect, and capability-retirement decisions.
5. Write behavioral requirements and invariants with provenance. Define scenarios for normal,
   boundary, malformed, denied, unavailable, duplicate, stale, partial, retry, recovery,
   reconciliation, and rollback behavior as applicable. Distinguish vertical completion--the
   real-system proof from accepted input to human-observable result--from horizontal breadth--
   the supported origins, variants, cardinalities, and mutations.
5a. Map every intake and output at the system's owned boundary. When several upstream paths
    converge on the same versioned contract, record the convergence seam and evidence that
    their downstream behavior is equivalent. Keep distinct contracts as distinct required
    scenarios; do not multiply downstream tests merely because upstream labels differ.
6. Register every repository and standalone/local/provider/manual node with contract and
   deployment owners, canonical workflow, versioned interfaces, readiness evidence, health,
   recovery, rollback, and reconciliation.
7. Create the implementation manifest. Map each requirement and scenario to current support,
   gap, owner surface, validation evidence, dependencies, and target HRM. Do not create lanes.
8. Derive all HRMs presently knowable, from planning review through operator workflow and any
   separate activation, canary, production observation, or autonomy decisions. Unknown facts
   remain explicit and may later produce a governed HRM discovery.
8a. For each HRM, draft one milestone claim containing its proof spine, safety shell, required
    scenario matrix, cardinality, real-system and human evidence, explicit exclusions, and
    scale perimeter. Record necessary later work as sequenced obligations with an owner,
    target HRM or release, latest safe point, promotion trigger, and safe interim posture.
9. Run the semantic-readiness gate. The project is planning-ready only when material terms,
   authority, lifecycle, identity, contracts, scenarios, evidence freshness, and operator
   review questions are explicit enough that implementation will not choose business meaning.
10. Publish the package for operator review. Acceptance authorizes HRM session planning only;
    it does not authorize code, merge, deployment, activation, canary, or production effects.
```

## Change note

- **1.1 — 2026-08-25:** Separates vertical completion from horizontal breadth, makes owned
  convergence seams explicit, and adds bounded milestone claims with sequenced obligations.
- **1.0 — 2026-08-24:** Initial organization-neutral project planning workflow.
