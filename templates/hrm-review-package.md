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

## Accepted milestone claim

- Claim/version: `{{milestone_claim_id_and_version}}`
- Proof spine: `{{accepted_input_through_ordered_real_system_effects}}`
- Supported breadth and cardinality: `{{input_contracts_variants_and_counts}}`
- Distinct seams and equivalence: `{{owned_seams_equivalence_and_limits}}`
- Explicit exclusions: `{{exclusions}}`
- Human-observable destination proof: `{{required_observations_or_not_applicable}}`
- Reachable implementation matches claim: `{{yes_or_blocker}}`

## Outcome under review

{{operator_visible_outcome}}

## Decisions requested

- Function/UI/UX acceptance: `accept | withhold with findings | defer`
- {{specific_human_decision}}

| Decision | S-class | First foreseeable/notified | Latest safe time | Recommendation | Safe posture |
|---|---|---|---|---|---|
| `{{decision_id}}` | {{s_class}} | {{times}} | {{latest_safe}} | {{recommendation}} | {{safe_posture}} |

Semantic read-back: `{{accepted_meaning_scope_exclusions_and_expiry}}`

## Capabilities completed

| Capability | Requirement/acceptance IDs | Implementing lanes | Evidence |
|---|---|---|---|
| {{capability}} | {{ids}} | {{lane_ids}} | {{artifact_or_scenario}} |

## Review scenarios

| Scenario | Starting state | Operator action | Expected result | Evidence |
|---|---|---|---|---|
| {{scenario}} | {{state}} | {{action}} | {{result}} | {{artifact}} |

## Validation evidence

- Accepted CI scope: `targeted | affected | full`
- CI-scope authority and basis: `{{reference_coverage_exclusions_freshness_and_policy}}`
- CI evidence binding: `{{candidate_base_policy_claim_gate_set_check_definition_environment_and_expiry}}`
- Checker/merge-controller receipt: `{{check_hosted_merge_main_cleanup_receipt}}`

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
- Reused stronger compatible implementation: `{{component_requirement_and_evidence_map}}`
- New implementation limited to missing delta: `{{yes_or_finding}}`
- Replacements: `{{none_or_approved_basis_parity_migration_rollback_and_consumer_evidence}}`

| Requirement/capability | Existing component and tests | Disposition | Missing delta | Replacement authority/evidence |
|---|---|---|---|---|
| {{ids}} | {{component_and_evidence}} | {{reuse_adapter_evidence_extension_gap_or_replacement}} | {{delta_or_none}} | {{authority_and_evidence_or_not_applicable}} |

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

## HRM discoveries and map changes

| Discovery | Classification | Affected boundary | Recommendation | Map effect/status |
|---|---|---|---|---|
| `{{discovery_id}}` | {{classification}} | {{boundary}} | {{recommendation}} | {{map_effect_and_status}} |

## Findings

- Ledger: `{{findings_ledger}}`
- Blocking: `{{blocking_finding_ids_or_none}}`
- Open non-blocking: `{{open_nonblocking_finding_ids_or_none}}`

## Sequenced obligations

| Obligation | Source | Why not a current blocker | Target/owner | Latest safe point and trigger | Safe interim posture |
|---|---|---|---|---|---|
| `{{obligation_id}}` | {{finding_or_discovery}} | {{reason}} | {{target_and_owner}} | {{safe_point_and_trigger}} | {{posture}} |

## Operator desk, integration, and cleanup receipt

- Stable current-review index: `{{path}}`
- Review branch and exact SHA: `{{branch_and_sha}}`
- Preview command or URL: `{{preview}}`
- Integrated main SHA: `{{main_sha}}`
- Worktrees removed: `{{paths_or_none}}`
- Worktrees retained: `{{path_and_reason_or_none}}`
- Operator checkout: `{{path_branch_sha_clean_review_posture}}`
- Unexplained workspace entries: `{{none_or_blockers}}`
- Other projects touched: `0`

## Closure

- Closure criteria: `{{criteria}}`
- Operator function/UI/UX acceptance: `pending | accepted | withheld`
- Closure effect: `{{current_hrm_state_change}}`
- Downstream release effect: `{{next_hrm_or_bundle_eligibility}}`
- Decision-transition receipt: `{{receipt_id_effect_newly_eligible_work_and_authorized_hrms}}`
- Builder start or blocker within target: `{{assignment_or_blocker_receipt_and_latency}}`
- What closure does not authorize: `{{canary_deployment_provider_write_migration_activation}}`
- Decision: `pending | closed | deferred`
- Decided by/date: `{{operator_and_time}}`
- Rationale and residual risk: `{{rationale}}`
