# Current system review

This is the stable operator index for the project. Update it before every operator
notification; do not require the operator to locate a worker branch or worktree.

## Milestone

- System: `{{system_reference}}`
- HRM map/version: `{{map_path_and_version}}`
- Current HRM: `{{current_hrm_or_none}}`
- Target HRM: `{{target_hrm}}`
- Outcome: {{operator_visible_outcome}}
- Milestone claim/version: `{{milestone_claim_id_and_version}}`
- Proof spine: `{{accepted_input_to_ordered_real_system_effects}}`
- Supported breadth/cardinality: `{{input_contracts_variants_and_counts}}`
- Explicit exclusions: `{{exclusions}}`
- Status: `planned | executing | review_ready | in_review | remediation | awaiting_closure | closed | deferred | blocked`

## Operator action

- Operator access: `not_ready | operator_access_ready | operator_access_blocked | in_review | withdrawn | superseded`
- Access purpose: `semantic_decision | discovery_disposition | provisional_feedback | formal_integrated_review`
- Operator packet published at: `{{time_or_not_applicable}}`
- Decision packet IDs: `{{ids_or_none}}`
- Function/UI/UX review: `{{not_ready_or_exact_action}}`
- Latest safe response time: `{{time_or_not_applicable}}`
- Recommended response: `{{recommendation_and_reply_syntax}}`
- Next meaningful operator interaction: `{{event_and_forecast}}`
- Time to formal HRM review: `{{forecast_or_unknown_with_reason}}`

## Review candidate

- Validation profile: `review_packet | executable_contract | runtime_change`
- Integration validation: `not_started | running | passed | failed | not_applicable`
- Accepted CI scope: `targeted | affected | full`
- CI-scope authority/basis: `{{reference_and_bounded_reason}}`
- CI evidence binding: `{{candidate_base_policy_claim_gate_set_check_definition_environment_and_expiry}}`
- Checker/merge controller: `{{task_id_lifecycle_state_and_candidate_or_none}}`
- Controller writer lease: `{{canonical_remote_target_ref_lease_id_epoch_expiry_or_none}}`
- Controller exception/route: `{{exception_classification_and_orchestrator_route_or_none}}`
- Validation subject: `{{kind_id_version_content_hash_provenance_and_optional_repository_sha}}`
- Review package: `{{path_or_url}}`
- Operator-access candidate head/artifact digest: `{{candidate_revision}}`
- Integrated HRM head/artifact digest: `{{integrated_revision_or_not_integrated}}`
- Active change units/branches/PRs: `{{ids_branches_prs_or_none}}`
- Integration receipts: `{{ids_or_none}}`
- Controller receipt: `{{check_merge_main_cleanup_receipt_or_none}}`
- Preview command or URL: `{{preview}}`
- Configuration and data window: `{{configuration_and_data_window}}`

## Current posture

- Blockers: `{{blockers_or_none}}`
- Input requirements/CTRQs: `{{ids_or_none}}`
- HRM-discovery proposals: `{{ids_or_none}}`
- Sequenced obligations: `{{ids_targets_and_latest_safe_points_or_none}}`
- Activation posture: `{{planning_only_local_read_only_shadow_canary_enabled}}`
- External mutations: `{{count}}`
- Safe work continuing: `{{work_or_none}}`
- Next authorized action: `{{action}}`

## Workspace exceptions

- Operator checkout: `{{absolute_path_branch_sha_and_state}}`
- Retained worktrees: `{{path_reason_and_recovery_or_none}}`
- Unexplained workspace entries: `{{none_or_blocker}}`
