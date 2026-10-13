# Agent Playbooks working agreements

This repository owns reusable organization-neutral process. Business meaning, organization
adoption, source pins, and project implementation belong in their owning repositories.

- Fetch literal `origin/main` and inspect status/worktrees before deriving changes. Preserve
  operator checkouts, experimental branches, active review runtimes, and private evidence.
- Use one bounded task branch/PR per independently reviewable change unit; never push main.
- Follow AP-SYSBUILD-001/2.6 delivery policy in `playbooks/system-build-standard.md`, with
  AP-LANE-001/4.6, AP-VALIDATE-001/1.3 and AP-DECIDE-001/1.3 at their existing entrypoints.
  Their successor binding governs conflicts with older body text. Human-directed lane is
  the default; delegation and bounded orchestration require named/bounded authorization.
- Routine assignments carry outcome/scope/checks/authority/stops inside the unit. Larger
  packages precede execution but require no separate planning merge. Ask for missing meaning;
  capture missing paperwork. Preserve final exact-source gates and human acceptance.
- Do not activate or upgrade an experimental kernel through this policy amendment.
- Material playbook edits update version and change note. Preserve historical revisions.
- Classify changed surfaces and consumers. Check changed front matter, relative links,
  source/version bindings, privacy, internal consistency and `git diff --check`. Run
  `ruby tests/test_hrm_experiment.rb` when scripts, schemas, templates, examples, or their
  executable contracts change; broader checks follow demonstrated reach or an explicit gate.
- Declare test effects local/sandbox/live; default synthetic offline. No document publication
  authorizes deployment, providers, customers, money, credentials, or autonomy effects.
- Merge only under established authority after final candidate/hosting gates. Report PR/main
  identity separately from organization adoption and project intake. Never create a receipt
  PR solely to record integration.
