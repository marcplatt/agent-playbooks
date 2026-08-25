---
playbook_id: AP-ONBOARD-001
title: Operator-Workspace Onboarding and Method Orientation
version: "1.1"
status: active
owner: Adopting organization
mode: adaptive-read-only-orientation
human_readable: true
machine_readable: true
required_inputs: [operator, workspace]
optional_inputs: [organization_master_plan, project_repository, existing_operator_preferences]
controls: [read-only-first, adaptive-faq, authority-status-literacy, elicitation-handoff, operator-authorized-writes]
---

# Operator-Workspace Onboarding and Method Orientation

Use this playbook to bring a human operator and their chosen agent workspace into a shared
understanding of the Agent Playbooks method. The onboarding subject is the
**operator-workspace pair**, not the human or agent in isolation.

This is an adaptive FAQ and setup conversation, not a required document-production task.
It audits the available organization-to-system lifecycle, but it does not perform business
elicitation. When authoritative organization meaning is absent, route that work to the
Business Plan Elicitation playbook rather than inventing it here.

## Entry modes

The workspace determines the mode from current evidence and explains the result. Do not ask
a new operator to classify a governance state they may not yet understand.

| Mode | Entry condition | Operator experience |
|---|---|---|
| `join_and_synchronize` | Governing organization or project material exists | Read the applicable sources, explain their authority and status, audit lifecycle progress, answer questions, and propose any workspace alignment needed. |
| `foundation_gap_handoff` | Required organization authority, adoption, or project connection is absent or cannot be verified | Continue method orientation and personalization discussion, identify the missing prerequisite, and route organization elicitation or adoption as a separate task. Do not design the organization inside onboarding. |

## What is fixed and what may change

Teach three control levels instead of presenting every setting as either fixed or freely
modifiable.

| Control level | Meaning | Examples |
|---|---|---|
| `workflow_invariant` | Required for conformance with this HRM method | Operator-owned meaning and protected action, complete-as-presently-knowable HRM maps, controlled HRM discovery, early S0-S2 escalation, semantic readiness, bounded change units, stable review access, source-read-only checker/merge control, separate rollout states, and evidence-safe cleanup. |
| `governed_organization_choice` | Modifiable only through the organization's accepted authority and versioned decision process | Terminology, organizational roles, system boundaries, authoritative subjects, risk thresholds, review roles, providers, activation policy, and permitted deviations from a process version. |
| `operator_workspace_preference` | Personalizable for the operator-workspace pair without changing organization meaning | Explanation depth, notification urgency, decision batching, review presentation, tool familiarity, model or tool preference, operator checkout, and interaction style. |

An organization may use identifiers such as `RES-0001` or `RES-0002`, or completely
different identifiers. Explain the role and current authority of the records actually found.
Never treat an example identifier, copied record, research document, or proposed standard as
universally normative. `AP` in this repository's identifiers means **Agent Playbooks**.

## Prompt

```text
Onboard this human operator and agent workspace into the Agent Playbooks method.

Operator: {{operator}}
Workspace: {{workspace}}
Organization master plan: {{organization_master_plan_or_unknown}}
Project repository: {{project_repository_or_none}}
Existing preferences: {{existing_operator_preferences_or_none}}

0. Begin with this read-back: "This onboarding session is read-only. I will not edit
   repositories, settings, instructions, memories, integrations, or planning records unless
   you later authorize a separate synchronization step after reviewing the proposed writes."
1. Ask what the operator wants to accomplish and briefly calibrate their familiarity with the
   workspace product, Git, organization governance, system planning, HRMs, agent delegation,
   deployment, and production operations. Adapt dynamically: skip subjects they know, explain
   unfamiliar subjects in their language, and allow questions at any time. Do not make the
   operator pass a quiz or repeat documentation they already understand.
2. Read the smallest authoritative source set available: the workspace's active instruction
   chain, the highest-level workspace README, this process source and version, applicable
   organization master-plan index, research/evidence records, adopted standards, adoption
   decisions or ADRs, project system plan, requirements, HRM map, current-review surface, and
   exact repository status. State every source's owner, revision, and accepted, proposed,
   stale, contradictory, missing, or unknown status.
3. Determine and announce `join_and_synchronize` or `foundation_gap_handoff` from evidence.
   In foundation-gap mode, explain the missing prerequisite and route business elicitation or
   process adoption separately. Do not elicit business meaning, create a surrogate master
   plan, or imply that a copied standard is adopted.
4. Explain the organization-to-system authority chain using the records actually present:
   evidence and research -> operator-owned business meaning -> adoption decision ->
   organization standard and system portfolio -> project system plan -> HRM map -> published
   change unit -> implementation and integration -> operator HRM acceptance -> deployment,
   activation, canary, production observation, and autonomy eligibility. Explain any local
   record IDs, including RES or ADR IDs, by function and status rather than assuming their
   names have universal meaning.
5. Teach the fixed HRM workflow through the operator's questions and current project examples:
   publish every HRM presently knowable; propose and version later HRM discoveries; expose
   S0 protected-action and S1 semantic decisions before non-disposable work; batch safe S2
   choices; permit only reversible S3 choices inside accepted semantics; require semantic
   readiness and a disposable proof before a large build; keep one change unit per branch and
   normally per PR; stop at review_ready; and never collapse implementation, integration,
   acceptance, deployment, activation, canary, production proof, or autonomy into one state.
6. Explain that tasks, conversations, branches, worktrees, lanes, tests, previews, and agents
   are supporting mechanisms, not the operator-facing plan. Show how the stable current-review
   surface lets the operator find the active HRM, decisions, exact candidate, review artifact,
   blockers, and next authorized action without hunting through worktrees. Explain that one
   dedicated source-read-only checker/merge controller may run explicitly scoped CI, merge
   only eligible exact heads while holding the one repository-global writer lease, verify
   remote main, and clean eligible worktrees while returning every semantic or authority
   exception through the HRM orchestrator. Multiple repository queues may have controllers,
   but they do not create multiple integration writers for the same remote and target ref.
7. Audit lifecycle progress from available evidence. For each stage--business elicitation,
   organization operating model, system portfolio, process adoption, project system plan,
   requirements and scenarios, HRM map, decision frontier, implementation, integration, HRM
   acceptance, deployment, activation, canary, production observation, and autonomy--report
   only a concise state of verified-current, historical-needs-revalidation, proposed,
   unknown-blocked, or not-applicable. Do not turn this conversational audit into a committed
   report unless the operator asks for one.
8. Discuss personalization across communication style, explanation depth, notification and
   interrupt urgency, S2 batching, review format, Git and workspace fluency, model and tool
   preferences, repositories, operator checkout, integrations, credentials, and notification
   channels. Never expose or store credentials or private evidence. Classify each proposed
   setting as workflow_invariant, governed_organization_choice, or
   operator_workspace_preference.
9. Answer questions conversationally and correct misconceptions with the controlling source.
   If sources disagree, show the contradiction and safe posture instead of choosing one.
10. End with a short spoken-style recap: the operator's current mental model, active sources,
    lifecycle position, fixed invariants, personalizable choices, gaps, and safest next action.
    Default to no durable deliverable and no writes.
11. If the operator wants changes, list the exact proposed account, machine, repository, and
    organization writes separately with purpose, authority, risk, and rollback. Wait for the
    operator to choose them, then begin a separately authorized synchronization change unit.
```

## Completion

Onboarding is complete when the operator can locate the controlling sources, understands
the authority and lifecycle distinctions needed for safe decisions, knows what is fixed
versus personalizable, and has received a truthful lifecycle audit and next-step choice.
Completion authorizes no writes or external effects.

## Change note

- **1.1 — 2026-08-25:** Adds the dedicated source-read-only checker/merge controller and
  explicitly scoped CI to the fixed HRM workflow orientation.
- **1.0 — 2026-08-25:** Initial organization-neutral operator-workspace onboarding,
  adaptive FAQ, lifecycle audit, foundation-gap handoff, and read-only personalization flow.
