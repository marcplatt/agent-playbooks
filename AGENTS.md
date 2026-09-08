# Agent Playbooks development

- This repository owns reusable workflows and tooling. Project repositories own their business requirements and implementation evidence.
- Develop requested changes at their natural scope. Do not run the HRM kernel to authorize work on the kernel itself, or create a planning/receipt PR before implementing an already authorized change.
- For the interaction-kernel pilot, use `playbooks/hrm-interaction-kernel.md`. Its command protocol is separate from the historical AP-EXEC experiments; never append new-protocol commands to an RC ledger.
- Run the focused Ruby tests for changed modules. Changes to the interaction kernel require its state, store, and command-line acceptance tests. Changes to historical AP-EXEC require `ruby tests/test_hrm_experiment.rb`.
- Keep operator decisions bound to their original request and revision. A technical implementation gap is an engineering assignment unless investigation identifies a genuinely unanswered business or authority decision.
- Preserve existing experiments, worktrees, private evidence, and running review environments. Adoption in another repository is a separate release step; creating a new template does not install it there.
