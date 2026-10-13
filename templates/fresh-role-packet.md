# Opt-in fresh role packet

Use only when selected under [AP-SYSBUILD-001/2.7 delivery policy](https://github.com/marcplatt/agent-playbooks/blob/8364121bd3b95bb9371be6b7915d1e4272f58a39/playbooks/system-build-standard.md#delivery-policy-proportional-planning-and-explicit-execution).
This is a capture template, not a machine schema, runtime upgrade, new authority grant, or
permission to delegate. Fill material facts; mark unknowns explicitly. Project-owned packets
hold project evidence. Keep credentials, private payloads and private pilot data out of AP.

```text
Packet ID/revision and creation/evidence time:
Assigned role, execution mode, configured model/capability and fallback:
Outcome and acceptance meaning:
Current effective requirements (IDs/revisions):
Superseded requirements and why no longer effective:
Ordered representative journey: stage -> owner -> input -> action -> authoritative result:
Current stage; eligible next action; blocked/ineligible actions and reason:
Accepted source refs/versions/SHAs and frozen excerpts needed by this role:
Frozen artifact refs and immutable identity (separate from source excerpts):
Candidate source/head:
Observed runtime/artifact/environment identity (or unknown; distinct from source):
Environment initialization revision, previous orientation and relevant changes:
Observation tools/capabilities; inaccessible or unverified surfaces:
Effect classification/targets/limits/expiry (local/sandbox/live):
Authority, delegation grant, protected boundaries and stop conditions:
Current findings, repaired classes, observed results and remaining unknowns:
Conditional reads required before action and references retained for questions:
Aggregate accounting revision (shared by all roles/continuations):
Role/repair/recovery/time/call limits:
Already-debited amounts, original operation IDs, remaining allowances:
Current session already debited: yes/no/unknown; debit operation ID:
Selected stall trigger and evidence; prior approaches; recovery already used:
Next evidence required; completion/blocker report route:
```

A new role/session carries forward debits and effective requirements. It does not restore
superseded meaning, refill allowances, or infer runtime identity from a source SHA. A concise
projection retains essential facts and available references; byte size does not measure total
context. Initialize once per relevant environment revision, orient each new session, and read
conditional excerpts needed for its stage rather than unrelated history.

## Fictional use

A persistence reviewer receives a synthetic offline draft journey: edit -> save -> reload ->
confirm, with stage owners and an exact candidate plus observed runtime identity. Its grant
covers unseen equivalent quantities and errors inside that draft, not provider delivery.
A repaired stale-save defect is checked across its relevant class. If the UI adapter is
unavailable, the reviewer reports that limitation and cannot call screenshots a persistence
pass. A recovery role consumes the same remaining call/time budget, never a fresh allowance.
