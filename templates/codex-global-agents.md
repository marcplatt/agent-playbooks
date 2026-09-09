# Global working agreements

- For read-only, review, explanation, or diagnostic work: inspect and fetch as needed; do not create Git state.
- For authorized repository changes: start from fetched `origin/main` on a task branch unless repository policy says otherwise.
- Never push directly to `main` or create a documentation or receipt change solely to record process.
- Preserve unrelated changes, branches, worktrees, and private evidence.
- For implementation work, documentation and tests are evidence; completion requires the declared deliverable or an explicit terminal blocker.
- For Canary runs, use a small set of easy, controlled inputs through the real production workflow and verify the declared final destination. Synthetic customer details are allowed; simulated providers are rehearsal evidence. Do not substitute a narrower acceptance outcome or turn the Canary into exhaustive failure testing.
- Run repository-declared checks selected by changed reach; do not add broad suites merely for reassurance.
- Repository-local `AGENTS.md` instructions govern project-specific workflow.
