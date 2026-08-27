## What changed

<!-- One or two lines. What behaviour is different after this PR? -->

## Why

<!-- If you added a rule: what failure does it prevent?
     If you removed one: what used to go wrong, and why can't it any more?
     "Seemed redundant" is not an answer — see CONTRIBUTING.md. -->

## The approval gate still holds

The skill's job is to refuse. Confirm these are still true after your change:

- [ ] A bare `dev` / `prod` renders a plan and writes **nothing**
- [ ] Approval is not reused across invocations
- [ ] Nothing pushes to `dev` / `uat` / `prod`, and nothing PRs into `prod`
- [ ] The **Release** workflow is dispatched only on an explicit "publish"
- [ ] A `-` line from `git cherry`, a merge conflict, or a failed pre-flight all stop

## Checks

- [ ] `claude plugin validate . --strict` exits 0
- [ ] `claude plugin details git-flow` — always-on token cost did not jump
- [ ] Version bumped in **both** `.claude-plugin/plugin.json` and `marketplace.json`
- [ ] `CHANGELOG.md` updated
- [ ] Tested by hand on a scratch branch (say what you ran below)

<!-- What did you actually run, and what did it do? -->
