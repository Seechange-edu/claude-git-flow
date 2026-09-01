# git-flow

The Seechange-edu shipping workflow, as a Claude Code plugin.

Feature branch cut from `prod` → PR to `dev` → PR into a release branch →
**Actions ▸ Release** → production. Everything after the publish is automatic.

The point of this plugin is not to make Claude faster at git. It is to make Claude
**stop**: render a visual plan of every branch, PR and workflow dispatch it is about
to make, and wait for you to approve it. Every hard rule in here exists because
something went wrong once.

## Install

Two lines inside Claude Code, then a restart:

```
/plugin marketplace add Seechange-edu/claude-git-flow
/plugin install git-flow@seechange
```

That's everything — the skill, all three commands and both hooks come with it.
Nothing to configure, no keys, no per-repo setup.

**Check it landed.** In a terminal:

```
claude plugin list                  # git-flow@seechange should be enabled
claude plugin details git-flow      # what it adds, and what it costs per session
```

**Then start a session in your workspace and you should see this before your first
message is answered:**

```
[git-flow] Workspace branch state (remote refs just fetched):
  cms-frontend [AIO-2045-class-recordings-filters]  3 behind prod  2 uncommitted
  cms_backend [main]  ⚠ ON PROTECTED BRANCH
```

If that line never appears, see [Troubleshooting](#troubleshooting).

**To update later:** `/plugin update git-flow@seechange`, then restart. Confirm with
`claude plugin list` — if the version did not change, the update did not apply.

### Where to keep your repos

The session report and `/task` both scan **one level down from your workspace root**,
so keep the repos side by side in one folder and open Claude Code at that folder:

```
~/work-dir/gh/                ← open Claude Code here
├── cms-frontend/
├── cms_backend/
├── think-and-speak-backend/
└── think-and-speak-frontend/
```

Repos nested deeper, or opened one at a time, still work for `/dev` and `/prod` —
you just lose the cross-repo view, which is the thing that stops a backend shipping
without its frontend. Any folder without an `origin/prod` is ignored, so unrelated
projects sitting in the same workspace cost you nothing.

## What you get

| Component | What it does |
|---|---|
| `git-flow` skill | The full workflow. Triggers on a bare "dev" / "prod" / "publish" / "new task", or on "ship it", "cut a release", "backmerge", "hotfix". |
| `/task` | Start a Jira ticket. Reads the key + summary from a screenshot, pasted text or a URL, asks which repos, and cuts one prod-based branch in each. Plans first, always. |
| `/dev` | Get the current work onto `origin/dev` for testing. Plans first, always. |
| `/prod` | Cut the release branch and PR this work into it. Stops before the deploy. |
| SessionStart hook | One-line branch-health report per repo in the workspace — on a protected branch, behind `prod`, uncommitted, unpushed. Read-only apart from `git fetch`. |
| PostToolUse hook | Stamps the wall-clock time of every push, PR open, PR merge, local merge and release-workflow dispatch, and appends it to `~/.claude/git-flow-timestamps.log`. |

## How it behaves

Four trigger words, and they mean exactly this:

- **"new task"** or `/task` → paste a Jira ticket (screenshot, text, `KEY-123` or a
  browse URL). It derives one branch name from the key and summary, asks which repos
  in the workspace it applies to, then renders a plan and stops. On approval it
  creates that branch from `origin/prod` in each repo — locally, nothing pushed.
- **"dev"** or `/dev` → render a plan, stop for approval, then commit → push → PR to
  `dev` → merge only if `CLEAN`.
- **"prod"** or `/prod` → render a plan, stop for approval, then dispatch
  **Actions ▸ Release Branch**, PR the same branch into the release branch, and
  **hand you the publish URL and stop**.
- **"publish"** → this word *is* the approval. Runs the pre-flight and dispatches
  **Actions ▸ Release**, which is a live production deploy.

The trigger message is a request for a *plan*, never authorization to write.
Approval is per-invocation — a "yes" on the last `/dev` does not authorize the next.

## A ticket, start to finish

```
You    /task            + a screenshot of AIO-2101 "Class recordings: filter by teacher"
Claude reads the key and summary, asks which repos (multi-select), shows a plan, stops
You    yes
Claude branch AIO-2101-class-recordings-filter-by-teacher created from origin/prod
       in cms_backend and cms-frontend. Nothing pushed.

       …you write the code…

You    dev
Claude shows a plan — commit, push, PR to dev, in both repos — and stops
You    yes
Claude PR #412 and #98 merged to dev. Go test.

       …QA passes…

You    prod
Claude shows a plan — cut release/vX.Y.Z, PR the same branch into it — and stops
You    yes
Claude release/v4.9.0 cut and contains PR #413. Publish here to deploy: <URL>

You    publish
Claude runs the pre-flight and dispatches Actions ▸ Release. Production is deploying.
```

Same branch throughout — never a second copy of a change, which is the whole point.
Every step stops for you except `publish`, where your word *is* the approval.

If you would rather type it in your own words, you can: "new task", "start this
ticket", "push this to dev", "ship it", "cut a release" all land in the same place.
The slash commands just skip the guessing.

## Timestamps

Every git write is stamped as it happens, and the time is repeated in the closing
report:

```
[git-flow] ⏱ PUSH ✓ — 2026-08-31 12:22:37 HKT (UTC+0800)
           git push -u origin TNS-2073-thinking-lab
[git-flow] ⏱ PR OPENED ✓ — 2026-08-31 12:22:41 HKT (UTC+0800)
           gh pr create --base dev --head TNS-2073-thinking-lab
```

Covered: `git push`, `gh pr create`, `gh pr merge`, `git merge`, and both
`gh workflow run` dispatches. A failed command is stamped `✗ FAILED` so an attempt
is never read as a write. Read-only commands (`git log`, `gh pr view`,
`git merge-base`, `--dry-run`) are not stamped.

Plain `git commit` is deliberately left out — `git log` already records commit
times. Push, PR and merge times are the ones that are gone once the session
scrollback is, which is why they are also appended to
`~/.claude/git-flow-timestamps.log`:

```
tail ~/.claude/git-flow-timestamps.log
```

Requires `jq` on `PATH` (ships with macOS 15+). Without it the hook exits silently
rather than interfering.

## The rules it enforces

- Never push to `dev` / `uat` / `prod` directly. Always a branch + PR.
- Never cut a task branch from `dev` or from current HEAD — always from `origin/prod`.
- Never `checkout -b` onto a dirty worktree, and never stash on your behalf.
- Never leave a new branch tracking `origin/prod` — that turns a bare `git push`
  into a push to prod.
- Never PR **into** `prod`. It is written only by the release automation.
- Never cut a release branch or create a release by hand — a release not published
  by `ACTION_TOKEN` does not trigger the deploy.
- Never cherry-pick a change onto a second branch. PR the same branch twice.
- Never squash- or rebase-merge a PR that will also be released.
- Never resolve a merge conflict unasked.
- Run `git cherry -v` before opening any PR — a `-` line means a duplicate SHA is
  about to start a backmerge conflict cascade.

## Requirements

| | Why | Check |
|---|---|---|
| `git` 2.23+ | `git switch` | `git --version` |
| `gh` CLI, authenticated | every PR, merge and workflow dispatch | `gh auth status` |
| Push access to the repos | opening and merging PRs | `gh repo view <org>/<repo>` |
| `jq` on `PATH` | the timestamp hook (ships with macOS 15+) | `jq --version` |
| Repos on the `dev`/`uat`/`prod` + `release/vX.Y.Z` convention, with `release-branch.yml` and `release.yml` | `/prod` and `publish` dispatch them | `gh workflow list` |

Only the first two are needed to get value out of it. Without `jq` the timestamp hook
exits silently rather than interfering; without the release workflows, `/task` and
`/dev` still work and `/prod` will tell you what is missing.

**The skill no-ops on any repo with no `origin/prod`**, so installing it cannot
disturb your other projects.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| No `[git-flow]` branch report at session start | Plugin not enabled, or you restarted into a different workspace | `claude plugin list`; open Claude Code at the folder holding your repos |
| Report appears but a repo is missing from it | That repo has no `origin/prod`, or it is nested more than one level deep | `git -C <repo> fetch origin prod`; move it beside the others |
| `/task` doesn't offer the repo you wanted | Same — it only lists repos with an `origin/prod` | as above |
| An update didn't change anything | The version was not bumped, so `/plugin update` skipped it | Ask the author to bump `plugin.json`; check with `claude plugin list` |
| Claude asks to approve something you already approved | Working as intended — approval is per-invocation | Reply again; this is the one behaviour never to "fix" |
| A push/PR is reported with no `⏱` timestamp | `jq` missing | `brew install jq`, restart |
| It refuses to open a PR, citing a `-` line from `git cherry` | The same change exists twice under different SHAs | Do **not** merge past it — read the duplicate-SHA section in the skill |

## Contributing

See [CONTRIBUTING.md](./CONTRIBUTING.md). Short version: the behaviour that matters
is *refusal*, so changes are reviewed against whether the approval gate still holds.
