# {{target_hrm}} — {{milestone_title}}

Status: `planned | review_ready | in_review | remediation | awaiting_closure | closed | deferred`

## Session

- System: `{{system_reference}}`
- Project HRM map/version: `{{hrm_map_path_and_version}}`
- Session: `{{milestone_session_id}}`
- Current HRM: `{{current_hrm_or_none}}`
- Target HRM: `{{target_hrm}}`
- Independently closable: `{{yes_or_no}}`
- Closure effect: `{{current_milestone_state_change}}`
- Downstream release effect: `{{eligibility_released_or_none}}`
- Review head: `{{exact_integrated_sha}}`
- Configuration and data window: `{{configuration_and_data_window}}`
- Activation posture: `{{local_read_only_shadow_canary_enabled}}`
- External mutations: `{{count}}`

## Outcome under review

{{operator_visible_outcome}}

## Decisions requested

- Function/UI/UX acceptance: `accept | withhold with findings | defer`
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

## Brownfield capability parity

- Inventory: `{{capability_inventory_path_or_not_applicable}}`
- Required operator journeys reachable: `{{evidence}}`
- Approved removals or relocations: `{{ids_or_none}}`
- Unknown parity obligations: `{{ids_or_none}}`

## Standalone and local system nodes

| Node | Kind/workflow | Contract owner | Deployment owner | Interface | Readiness/deployment boundary |
|---|---|---|---|---|---|
| `{{node_id}}` | {{kind_and_workflow}} | {{contract_owner}} | {{deployment_owner}} | {{versioned_interface}} | {{evidence_and_boundary}} |

## Input requirements

| Input | Observation | Affected HRM/scenario | Safe posture | Owner/consequence | Disposition |
|---|---|---|---|---|---|
| `{{input_id}}` | {{observation}} | {{hrm_and_scenario}} | {{safe_posture}} | {{owner_and_consequence}} | {{disposition_and_reference}} |

## Contract-update requests

| Request | Provider/owner | Missing promise | HRM impact | Safe posture | Status |
|---|---|---|---|---|---|
| `{{ctrq_id}}` | {{provider_or_role}} | {{gap}} | {{impact}} | {{safe_posture}} | {{status}} |

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
- Operator function/UI/UX acceptance: `pending | accepted | withheld`
- Closure effect: `{{current_hrm_state_change}}`
- Downstream release effect: `{{next_hrm_or_bundle_eligibility}}`
- What closure does not authorize: `{{canary_deployment_provider_write_migration_activation}}`
- Decision: `pending | closed | deferred`
- Decided by/date: `{{operator_and_time}}`
- Rationale and residual risk: `{{rationale}}`
