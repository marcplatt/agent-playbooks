# Current system review

This is the stable operator index for the project. Update it before every operator
notification; do not require the operator to locate a worker branch or worktree.

## Milestone

- System: `{{system_reference}}`
- HRM map/version: `{{map_path_and_version}}`
- Current HRM: `{{current_hrm_or_none}}`
- Target HRM: `{{target_hrm}}`
- Outcome: {{operator_visible_outcome}}
- Status: `planned | executing | review_ready | in_review | remediation | awaiting_closure | closed | deferred | blocked`

## Operator action

- Decision packet IDs: `{{ids_or_none}}`
- Function/UI/UX review: `{{not_ready_or_exact_action}}`
- Latest safe response time: `{{time_or_not_applicable}}`
- Recommended response: `{{recommendation_and_reply_syntax}}`

## Review candidate

- Review package: `{{path_or_url}}`
- Branch: `{{branch}}`
- Exact SHA/artifact digest: `{{revision}}`
- Preview command or URL: `{{preview}}`
- Configuration and data window: `{{configuration_and_data_window}}`

## Current posture

- Blockers: `{{blockers_or_none}}`
- Input requirements/CTRQs: `{{ids_or_none}}`
- HRM-discovery proposals: `{{ids_or_none}}`
- Activation posture: `{{planning_only_local_read_only_shadow_canary_enabled}}`
- External mutations: `{{count}}`
- Safe work continuing: `{{work_or_none}}`
- Next authorized action: `{{action}}`

## Workspace exceptions

- Operator checkout: `{{absolute_path_branch_sha_and_state}}`
- Retained worktrees: `{{path_reason_and_recovery_or_none}}`
- Unexplained workspace entries: `{{none_or_blocker}}`
