# git-flow

The Seechange-edu shipping workflow, as a Claude Code plugin.

Feature branch cut from `prod` → PR to `dev` → PR into a release branch →
**Actions ▸ Release** → production. Everything after the publish is automatic.

The point of this plugin is not to make Claude faster at git. It is to make Claude
**stop**: render a visual plan of every branch, PR and workflow dispatch it is about
to make, and wait for you to approve it. Every hard rule in here exists because
something went wrong once.

## Install

```
/plugin marketplace add Seechange-edu/claude-git-flow
/plugin install git-flow@seechange
```

Restart Claude Code. That's it — the skill, both commands and the session hook come
with it.

To update later: `/plugin update git-flow@seechange`.

## What you get

| Component | What it does |
|---|---|
| `git-flow` skill | The full workflow. Triggers on a bare "dev" / "prod" / "publish", or on "ship it", "cut a release", "backmerge", "hotfix". |
| `/dev` | Get the current work onto `origin/dev` for testing. Plans first, always. |
| `/prod` | Cut the release branch and PR this work into it. Stops before the deploy. |
| SessionStart hook | One-line branch-health report per repo in the workspace — on a protected branch, behind `prod`, uncommitted, unpushed. Read-only apart from `git fetch`. |

## How it behaves

Three trigger words, and they mean exactly this:

- **"dev"** or `/dev` → render a plan, stop for approval, then commit → push → PR to
  `dev` → merge only if `CLEAN`.
- **"prod"** or `/prod` → render a plan, stop for approval, then dispatch
  **Actions ▸ Release Branch**, PR the same branch into the release branch, and
  **hand you the publish URL and stop**.
- **"publish"** → this word *is* the approval. Runs the pre-flight and dispatches
  **Actions ▸ Release**, which is a live production deploy.

The trigger message is a request for a *plan*, never authorization to write.
Approval is per-invocation — a "yes" on the last `/dev` does not authorize the next.

## The rules it enforces

- Never push to `dev` / `uat` / `prod` directly. Always a branch + PR.
- Never PR **into** `prod`. It is written only by the release automation.
- Never cut a release branch or create a release by hand — a release not published
  by `ACTION_TOKEN` does not trigger the deploy.
- Never cherry-pick a change onto a second branch. PR the same branch twice.
- Never squash- or rebase-merge a PR that will also be released.
- Never resolve a merge conflict unasked.
- Run `git cherry -v` before opening any PR — a `-` line means a duplicate SHA is
  about to start a backmerge conflict cascade.

## Requirements

- `git` and the `gh` CLI, authenticated against `Seechange-edu`
- Repos using the `dev` / `uat` / `prod` + `release/vX.Y.Z` convention, with the
  `release-branch.yml` and `release.yml` workflows installed

The skill no-ops on repos with no `origin/prod`.

## Contributing

See [CONTRIBUTING.md](./CONTRIBUTING.md). Short version: the behaviour that matters
is *refusal*, so changes are reviewed against whether the approval gate still holds.
