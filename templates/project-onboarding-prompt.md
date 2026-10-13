# Project onboarding prompt

Use through [AP-CONFORM-001/1.2](../playbooks/operator-workspace-conformance.md#project-onboarding-entrypoint).
Replace the fields; retain `audit_only` unless intentionally granting bounded adoption writes.
The agent identifies missing source facts instead of asking the operator to reconstruct them.

```text
Onboard this project to its organization's accepted development standard.

Project repository: {{absolute_project_path}}
Organization/master-plan source: {{repository_or_unknown}}
Workspace/account: {{current_workspace_and_account_or_discover}}
Mode: {{audit_only | adopt_with_scoped_grant}}
Adoption grant (empty for audit): {{exact repositories/files/action classes/limits/expiry}}
Execution mode: {{human-directed lane | human with coordinator | bounded orchestrator}}
Delegation grant: {{none | named_or_bounded_subtasks}}
Desired first outcome: {{concrete_operator_visible_result}}
Excluded effects: {{deployment/provider/customer/money/credentials/autonomy_or_specific_limits}}

1. Inspect before writing. Discover the actual account's global instruction file and its
   effective instruction chain; inspect project root and nested AGENTS applicable to likely
   changed paths, including overrides/configuration. For Codex, discover CODEX_HOME (default
   ~/.codex); global AGENTS.override.md takes precedence over AGENTS.md. For each directory
   from repository root through the actual working directory, select AGENTS.override.md,
   else AGENTS.md, else configured fallback names; only one instruction file per directory.
   Inventory other nested instruction files separately from that effective working-directory
   chain, and re-evaluate the chain for each affected subdirectory. Inspect only relevant
   safe configuration keys for fallback names and instruction-size cap; never dump config
   that may contain secrets. Do not assume another account's global path or memory authority.
   Record effective paths and inaccessible/unknown surfaces. Check size/loading limits when
   observable; do not claim loaded instructions without evidence. Changes require a fresh
   session; do not claim the current session's assembled chain automatically refreshed.
2. Fetch literal origin/main when accessible; reconcile exact head/base, status, registered
   worktrees, operator checkout, current reviews and active dependencies. Preserve dirty files,
   unique commits, experiments, runtime/process state and stronger local safety restrictions.
   Audit creates no Git state. No access is unknown-blocked, never a pass or assumed default.
3. Resolve the organization's explicit accepted adoption decision, standard/version, exact AP
   source revision, deviations and mixed-version posture from current owning records. Do not
   choose newest AP/main/experimental branches by default. Proposed or inaccessible sources
   are not adoption. Keep reusable rules in AP, organization authority in its master plan,
   and project implementation/evidence local. Stop only the boundary needing unresolved meaning.
4. Inspect actual CI workflows, classifiers, scripts, consumer reach, required checks and
   accessible hosting enforcement. A missing workflow or protection is reported absent, not
   enforced. For a new project, propose minimal checks; create their setup only if the grant
   covers it. Inventory duplicates and broader triggers with evidence;
   do not infer enforced checks from prose. If hosting/CI access is missing, say which claims
   remain unverified. Preserve stricter applicable gates until properly amended.
5. Compare global common floor, root/nested project instructions, accepted sources and CI.
   Classify pass/gap/stale/contradiction/unknown/not-applicable and intended_local_restriction.
   A valid stronger local restriction is intentional, not drift to erase. Explain consequences
   and the smallest repair. Never blindly overwrite global instructions, copy another account's
   preferences, weaken local restrictions, upgrade source pins, or activate experiments.
6. In audit_only, return a concise gap summary and proposed exact writes; make no changes.
   In adopt_with_scoped_grant, read back the concrete permitted targets/actions and proceed
   within that already supplied grant. Ask only for unresolved meaning or action outside it;
   do not request the same routine authorization again. Use bounded task branches/PRs for
   authorized repository changes from fetched main; preserve unrelated state. Do not merge
   without integration authority. Global edits require explicit inclusion in the grant.
7. Select the explicit execution mode and bound each authorized worker; no inherited scope,
   delegation permission, experiment activation, or independent operator queue. Default to
   human-directed lane when unspecified. Distinguish builder/checker/reviewer/observer roles
   from execution modes and use serial roles when delegation is not authorized.
8. Make local entrypoints concise: exact accepted source pins, mode, validation triggers,
   check commands, stops and external-effect posture. Routine work captures outcome/scope/
   checks/authority/stop inside its unit. Larger uncertain/coordinated work gets a package
   before execution with accepted scope and authority; the human need not approve every
   document. It may stay local with no separate planning PR/premerge. Missing
   paperwork is agent capture; missing meaning is a scoped question. Current human guidance
   steers the assignment and material changes are recorded before dependent durable work.
9. Validate changed instruction contracts, links/source bindings and affected consumers;
   run only reach-selected checks plus mandatory local/hosting gates. Declare test effects
   disposable local/isolated sandbox/live; default synthetic offline. Final candidate gates
   remain exact-source. Fresh-session instruction probes verify changes when accessible;
   report unperformed probes honestly rather than claiming conformance from edited files.
10. Return exact source versions, actual audit/adoption/integration state, changes/checks,
    remaining gates and one copy-paste first-assignment prompt. That prompt names the outcome,
    scope, execution/delegation mode, accepted sources, checks/stops and external-effect posture.
    Do not bury the operator in a repeated technical plan. No onboarding result proves
    deployment, activation, canary, production or autonomy.
```

## Example invocation

```text
Use AP-CONFORM-001 project onboarding for /absolute/path/project.
Organization master plan: /absolute/path/master-plan; discover its accepted source pins.
Mode: audit_only. Execution: human-directed lane; delegation: none.
Desired first outcome: the operator can correct an invalid quantity in the existing draft UI.
No deployment, provider/customer/money, credential or autonomy effects.
Return the actual instruction/CI gaps and a copy-paste assignment for that outcome.
```

For explicit adoption, replace `audit_only` with `adopt_with_scoped_grant` and name permitted
repositories/files, action classes, limits and expiry. Example: “Update this project's root
AGENTS and its governance source binding on one task branch/PR to the master plan's exact
accepted successor; no global edits or merge.” This is a bounded grant, not blanket consent.

The sample first outcome does not authorize implementation during the audit. The returned
assignment can be: “Fix draft quantity validation within this project. Human-directed lane;
no delegation. Use the verified accepted sources. Capture the in-unit brief, run the named
consumer and required checks, return the working UI and exact candidate for review. Stop for
unresolved acceptance meaning or effects outside the offline grant.” Adapt named checks to
actual evidence instead of inventing commands.

Instruction discovery reference for Codex: [official AGENTS.md configuration guide](https://learn.chatgpt.com/docs/agent-configuration/agents-md).
This identifies product precedence, not organization adoption or evidence that a session
loaded the complete chain.

## Sample outcome report

```text
Audit state: complete for accessible surfaces; no writes. Adoption state: unchanged.
Accepted source: <organization standard/version, adoption decision, exact AP revision>.
Effective chain: <actual global override-or-AGENTS, root selection, workdir selection>;
other nested files inventoried: <paths>; loading cap/fresh-session proof: <verified/unknown>.
Changes: none. Checks: <read-only source/CI/hosting inspections actually completed>.
Remaining drift: <specific gap and smallest repair>; intended local restrictions: <preserved>.
Enforcement: <observed required checks/protection, absent, or inaccessible>; no implied pass.
Next assignment: <copy-paste outcome/scope/mode/sources/named checks/stops/effect limits>.
```

For authorized adoption, replace “no writes/unchanged” with exact changed paths, candidate
and PR, checks performed, remaining gates and separately verified integration/adoption state.
These placeholders illustrate the report; they are not fabricated observations or conformance.
