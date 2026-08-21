# {{target_hrm}} — {{milestone_title}}

Status: `planned | review_ready | in_review | remediation | awaiting_closure | closed | deferred`

## Session

- System: `{{system_reference}}`
- Session: `{{milestone_session_id}}`
- Current HRM: `{{current_hrm_or_none}}`
- Target HRM: `{{target_hrm}}`
- Review head: `{{exact_integrated_sha}}`
- Configuration and data window: `{{configuration_and_data_window}}`
- Activation posture: `{{local_read_only_shadow_canary_enabled}}`
- External mutations: `{{count}}`

## Outcome under review

{{operator_visible_outcome}}

## Decisions requested

- {{specific_human_decision}}

## Capabilities completed

| Capability | Requirement/acceptance IDs | Implementing lanes | Evidence |
|---|---|---|---|
| {{capability}} | {{ids}} | {{lane_ids}} | {{artifact_or_scenario}} |

## Review scenarios

| Scenario | Starting state | Operator action | Expected result | Evidence |
|---|---|---|---|---|
| {{scenario}} | {{state}} | {{action}} | {{result}} | {{artifact}} |

## Validation evidence

| Change or risk class | Exact head | Command or scenario | Result | Artifact |
|---|---|---|---|---|
| {{class}} | {{sha}} | {{check}} | {{result}} | {{artifact}} |

## Known limitations and blockers

- {{limitation_or_blocker}}

## Findings

- Ledger: `{{findings_ledger}}`
- Blocking: `{{blocking_finding_ids_or_none}}`
- Open non-blocking: `{{open_nonblocking_finding_ids_or_none}}`

## Integration and cleanup receipt

- Integrated main SHA: `{{main_sha}}`
- Worktrees removed: `{{paths_or_none}}`
- Worktrees retained: `{{path_and_reason_or_none}}`
- Primary checkout: `{{path_branch_sha_clean_pull_result}}`
- Other projects touched: `0`

## Closure

- Closure criteria: `{{criteria}}`
- What closure releases: `{{next_bundle_or_authority}}`
- What closure does not authorize: `{{canary_deployment_provider_write_migration_activation}}`
- Decision: `pending | closed | deferred`
- Decided by/date: `{{operator_and_time}}`
- Rationale and residual risk: `{{rationale}}`
