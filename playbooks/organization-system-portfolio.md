---
playbook_id: AP-PORTFOLIO-001
title: Organization System Portfolio Planning
version: "1.0"
status: active
owner: Adopting organization
mode: operating-model-to-system-portfolio
human_readable: true
machine_readable: true
required_inputs: [accepted_operating_model, authorized_operator]
optional_inputs: [existing_system_inventory, contracts, constraints, rollout_horizon]
controls: [authority-by-subject, explicit-system-boundaries, standalone-nodes, no-implementation-authority]
---

# Organization System Portfolio Planning

Use this playbook to decide what systems the organization owns, operates, buys, or depends
on and which subject each system governs. The portfolio is an organization record, not a
project implementation plan.

## Prompt

```text
Create or amend the organization system portfolio from the accepted operating model.

Operating model: {{accepted_operating_model}}
Authorized operator: {{authorized_operator}}
Existing inventory: {{existing_system_inventory_or_none}}

1. Bind every proposed system responsibility to accepted outcomes, capabilities, policies,
   actors, and information flows. Preserve traceability to exact source versions.
2. Inventory repositories, applications, spreadsheets, local bridges, daemons, providers,
   manual services, and shadow workflows. Do not hide non-Git or human-operated nodes inside
   a consuming project.
3. Define stable system IDs, purpose, lifecycle owner, operator, deployment owner, data or
   decision subjects, authoritative subjects, prohibited authority, consumers, dependencies,
   canonical location, and operational boundary.
4. Draw contract boundaries. For every inter-system promise name producer, consumer,
   contract owner, version, transport, freshness, compatibility, safe failure, identity,
   reconciliation, and request route. Missing promises remain open contract requests.
5. Detect overlapping authority, orphan subjects, circular dependencies, duplicate systems,
   unsupported manual bridges, privacy/security boundaries, and single points of failure.
6. Present material boundary and authority choices through operator decision packets. Read
   accepted meaning back before assigning project scopes.
7. Propose rollout waves based on business dependency and learning risk, not repository
   convenience. Name prerequisites, project planning records, HRM dependencies, transition
   states, and safe coexistence with current operations.
8. Publish the versioned portfolio and one system record per node. State which project may
   begin system-plan generation; do not create implementation lanes from this workflow.
```

## Required output

Use `templates/system-portfolio.yaml`. The organization master plan keeps the canonical
portfolio; projects may mirror only the accepted slice they consume.

## Change note

- **1.0 — 2026-08-24:** Initial organization-neutral portfolio and authority workflow.
