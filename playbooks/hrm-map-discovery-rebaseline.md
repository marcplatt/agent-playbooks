---
playbook_id: AP-HRM-MAP-001
title: HRM Map Discovery and Rebaseline
version: "1.2"
status: active
owner: Adopting organization
mode: hrm-map-governance
human_readable: true
machine_readable: true
required_inputs: [project_hrm_map, discovery_or_change]
optional_inputs: [current_hrm_session, operator_decision, affected_projects]
controls: [complete-as-presently-knowable, append-only-history, milestone-claim-disposition, sequenced-obligation, early-escalation, compatible-work-only]
---

# HRM Map Discovery and Rebaseline

“Publish all HRMs at inception” means complete as presently knowable, not clairvoyant.
Use this playbook when evidence reveals a potentially distinct operator-visible milestone.

## Is it a new HRM?

A new or split HRM is justified when the discovery creates a distinct operator-visible
outcome, separate human acceptance or closure effect, different authority/evidence state,
or independent downstream release effect. A defect, implementation lane, alternate design,
test gap, contract request, or remediation item normally remains inside the existing HRM.
Unknown API or implementation behavior also normally remains inside the existing HRM as a
disposable discovery spike. It creates no PR unless retained evidence is published as a
bounded change unit.

Inside an existing HRM, classify the discovery before changing implementation: it may be a
defect against the accepted claim, an operator-approved amendment to horizontal breadth, a
necessary sequenced obligation for a named later HRM or release, or evidence that a distinct
HRM now exists. A sequenced obligation is not permission to leave unsafe reachable behavior;
that behavior must be narrowed or corrected in the current change.

## Prompt

```text
Assess and govern an HRM map discovery.

Project HRM map: {{project_hrm_map}}
Discovery: {{discovery_or_change}}
Current session: {{current_hrm_session_or_none}}

1. Timestamp when the discovery was first observed and when a distinct HRM became foreseeable.
   Preserve evidence, source revisions, affected requirements, and current safe posture.
2. Freeze only the affected boundary. Continue work only where compatibility with every
   plausible disposition is evidenced; do not create a branch, worktree, or lane for an
   unaccepted HRM proposal.
3. Test whether the existing map can absorb the discovery without changing outcome, closure
   authority, closure effect, evidence state, or downstream release. Record why or why not.
4. Classify as defect/remediation within the accepted milestone claim, claim-scope amendment,
   sequenced obligation, requirement or contract amendment, HRM addition, HRM split,
   dependency change, supersession/removal, or no map change.
4a. For a claim-scope amendment, show the added or removed input contracts, variants,
    cardinality, real-system effects, evidence, exclusions, tests, and reachable-code impact.
    Obtain operator semantic read-back before non-disposable implementation. For a sequenced
    obligation, record owner, target HRM or release, latest safe point, promotion trigger,
    and safe interim posture.
5. For a material map change, prepare `HRM_DISCOVERY` with proposed outcome, dependencies,
   review questions, closure and release effects, authority, evidence/unknowns, affected work,
   permitted continuation, recommendation, and no more than three alternatives.
6. Escalate immediately when the critical path or non-disposable work is at risk; otherwise
   batch the proposal at the decision frontier. Read accepted meaning back to the operator.
7. Publish a new map version that supersedes rather than rewrites the prior version. Rebaseline
   affected requirements, milestones, manifests, contracts, sessions, and downstream projects.
   Preserve closed evidence and record invalidated assumptions.
8. Only after acceptance and publication may the new HRM derive implementation change units.
```

## Measure

Track non-disposable work performed after the new HRM became foreseeable but before the map
was amended. Discovery itself is expected; late controlled response is the failure signal.

## Change note

- **1.2 — 2026-08-25:** Routes discoveries within an HRM as in-claim defects, milestone-
  claim amendments, owned sequenced obligations, or distinct HRM changes, while prohibiting
  unsafe reachable behavior from being deferred.
- **1.1 — 2026-08-24:** Keeps unforeseen API and implementation discovery inside the
  current HRM by default, allows disposable spikes with no PR, and publishes only retained
  evidence as a bounded change unit.
- **1.0 — 2026-08-24:** Initial emergent-HRM discovery and supersession workflow.
