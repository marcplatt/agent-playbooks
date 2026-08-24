---
playbook_id: AP-ELICIT-001
title: Business Plan Elicitation
version: "1.0"
status: active
owner: Adopting organization
mode: business-plan-to-operating-model
human_readable: true
machine_readable: true
required_inputs: [business_plan_sources, authorized_operator]
optional_inputs: [existing_operating_model, research_evidence, constraints, target_horizon]
controls:
  - evidence-provenance
  - operator-owned-meaning
  - unknowns-remain-unknown
  - recommendation-before-question
  - no-system-design-by-default
---

# Business Plan Elicitation

Use this playbook before system planning when business intent is incomplete, distributed,
contradictory, or expressed only as a solution. It produces a versioned organization
operating model; it does not authorize a system, project, purchase, or production change.

## Required output

Create an `organization-operating-model.yaml` record containing source provenance,
outcomes, actors, value flows, capabilities, policies, authority, constraints, risks,
success measures, contradictions, and unknowns. Separate observation, interpretation,
proposal, and accepted decision.

## Prompt

```text
Elicit the business plan into a governed organization operating model.

Sources: {{business_plan_sources}}
Authorized operator: {{authorized_operator}}
Existing model: {{existing_operating_model_or_none}}
Target horizon: {{target_horizon_or_none}}

1. Read applicable governance and inventory every source with date, owner, revision,
   authority status, and evidence-expiry rule. Never turn a search result, current behavior,
   agent suggestion, or unapproved document into accepted business meaning.
2. Extract desired outcomes and measures before discussing systems. For each outcome record
   beneficiary, present condition, desired condition, exclusions, time horizon, leading and
   lagging measures, and the human authorized to accept its meaning.
3. Model actors, responsibilities, handoffs, value and information flows, decision rights,
   policies, constraints, material risks, and existing capabilities. Distinguish authority
   from expertise and operation from approval.
4. Record contradictions and unknowns verbatim enough to preserve the disagreement. Perform
   safe read-only evidence gathering where it can resolve fact, but do not use research to
   make a reserved business decision.
5. Build a decision frontier. For each unresolved semantic or authority question, state why
   it matters, the latest safe decision time, affected outcomes, recommended answer, no more
   than three meaningful alternatives, safe posture, and work permitted while waiting.
6. Elicit decisions in outcome language. Read the accepted meaning back to the operator and
   record confirmer, time, evidence, scope, and expiry. A lack of response is not acceptance.
7. Identify candidate capabilities and information responsibilities without prematurely
   assigning them to software. Label automation ideas as proposals for portfolio planning.
8. Publish a versioned operating-model review package. Report accepted meaning, unresolved
   decisions, evidence gaps, risks, and the exact next authorized planning action.
```

## Completion

Complete when every material outcome has provenance and acceptance status, authority is
named, contradictions are dispositioned or explicitly open, and unknowns have owners and
safe postures. Completion authorizes portfolio planning only.

## Change note

- **1.0 — 2026-08-24:** Initial organization-neutral business-plan elicitation workflow.
