# Contributing

This plugin gates production deploys. A sloppy edit here does not produce a bad
suggestion — it produces a push nobody approved. Please read this before opening a PR.

## The thing to protect

Almost every rule in `skills/git-flow/SKILL.md` is there because something went wrong
once. The `git cherry` duplicate-SHA detector exists because of the
#765/#766 → #767 → #771 → #774 conflict cascade. The "never PR into prod" rule is a
team decision, quoted verbatim. The pre-flight before dispatching **Release** exists
because `check-release` hard-fails a release that is behind `prod` *after* the tag
has already been created.

So: **when you delete a rule, say in the PR what used to go wrong and why it can't
any more.** "This seemed redundant" is the one review comment that will always get a
change reverted. If you are not sure why a line is there, ask — the history is
usually recoverable and worth recovering.

The corollary: when you *add* a rule, write down the failure it prevents. A rule
whose reason isn't stated is a rule the next person will delete.

## What "correct" means here

The skill's value is **refusal**, not output quality. It is working when it declines
to act. So the behaviours to preserve, in rough order of importance:

1. It renders a plan and stops. The trigger message is never authorization.
2. It never pushes to `dev` / `uat` / `prod`, and never PRs into `prod`.
3. It never dispatches the **Release** workflow without an explicit "publish".
4. It stops on a `-` line from `git cherry`, on any merge conflict, and on any
   pre-flight failure — rather than working around it.
5. Approval does not carry across invocations.

A change that makes the skill more helpful at the cost of any of those is a
regression, even if it reads better.

## Making a change

1. Edit under `skills/git-flow/`, `commands/`, or `hooks/`.
2. Run `claude plugin validate . --strict` — it must exit 0.
3. Install your working copy (below) and run `claude plugin details git-flow` to check the always-on token cost
   hasn't jumped. This is loaded into every session, so growth is a real cost.
4. Bump `version` in **both** `.claude-plugin/plugin.json` and the matching entry in
   `.claude-plugin/marketplace.json`. `claude plugin tag` validates that they agree
   and will refuse to tag if they don't.
5. Add a line to `CHANGELOG.md`.
6. Test it for real on a scratch branch before opening the PR — see below.

## Testing a change

There is no way to unit-test "did Claude refuse". Until the eval suite lands (see
`evals/README.md`), test by hand:

- Install your working copy: `/plugin marketplace add /path/to/your/clone`
- Say a bare `dev` on a branch with real uncommitted work, and confirm it renders a
  plan and writes **nothing**. Check `git status` and `git log` afterwards.
- Say `prod` and confirm it stops at the publish URL without dispatching anything.
- Check `gh run list` afterwards — no dispatch should have happened.

Do this against a scratch branch, never against work you care about.

## Keeping SKILL.md readable

`SKILL.md` is loaded in full every time the skill triggers, so size is a running cost
paid by everyone. Detail that is only needed occasionally belongs in
`skills/git-flow/references/` with a pointer from `SKILL.md` saying when to read it —
that's how the dev-based-branch rescue and the workflow input tables are handled.

Command sequences that get *run* should stay inline. Background, history, and
decision tables can move out.

## Releasing

```bash
claude plugin validate . --strict
claude plugin tag --push -m "git-flow v%s"
```

`claude plugin tag` creates a `git-flow--vX.Y.Z` tag and refuses if the working tree
is dirty, the tag exists, or the two manifests disagree. Installed copies pick the
change up on `/plugin update git-flow@seechange`.
