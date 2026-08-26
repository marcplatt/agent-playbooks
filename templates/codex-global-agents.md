# Global working agreements

- For read-only, review, explanation, or diagnostic work: inspect and fetch as needed; do not create Git state.
- For authorized repository changes: start from fetched `origin/main` on a task branch unless repository policy says otherwise.
- Never push directly to `main` or create a documentation or receipt change solely to record process.
- Preserve unrelated changes, branches, worktrees, and private evidence.
- For implementation work, documentation and tests are evidence; completion requires the declared deliverable or an explicit terminal blocker.
- Derive the active HRM from the accepted project map's `current_target_hrm`; vague prompt language never overrides it, and only an exact explicitly named HRM ID may select a non-current milestone.
- A delegated HRM run advances routine in-scope work through the next genuine human gate without asking for capsule creation, branch/worktree setup, implementation, commit, PR publication, declared CI, bounded correction, waiting, or post-authorized-merge read-back.
- Human gates are limited to unresolved business meaning, operator-facing function review, exact-head merge release when policy requires it, exact live-effect authority, and HRM closure. Present the exact decision and effect; never ask only “approve” or “proceed.”
- Keep the execution capsule stable across routine workflow transitions; mutable progress belongs in the derived session state. Bind later merge or live-effect permission as an exact authority grant instead of rotating the capsule.
- Run repository-declared checks selected by changed reach; do not add broad suites merely for reassurance.
- Keep raw logs and the append-only state ledger out of active context; return digest-bound summaries and artifact paths.
- Repository-local `AGENTS.md` instructions govern project-specific workflow.
