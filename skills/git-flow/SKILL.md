---
name: git-flow
description: The prod-based branch → dev → release-branch → Release shipping workflow, driven by the "Release Branch" and "Release" GitHub Actions workflows, with a mandatory visual plan and user approval before any git write or workflow dispatch. Use when the user says a bare "dev" or "prod", types `/dev` or `/prod`, or says "push to dev", "merge to dev", "release to prod", "ship this", "cut a release", "make a release branch", "run the release workflow", "backmerge", "hotfix". Also use when they say "publish", "publish it", "can you publish", or paste a GitHub Actions `workflows/release.yml` or `releases/new?tag=…&target=…` URL — that is the authorized go-ahead to dispatch the Release workflow after a pre-flight check. Also use at the start of work in a git repo to check the current branch is fit for this workflow, and whenever a branch is on the wrong base, behind prod, or about to be pushed. Also use when a branch was cut from `dev` instead of `prod` and its work now has to reach prod without releasing all of dev, when a PR to dev is stuck CONFLICTING, when a PR turns out to be already on dev, or to roll back a release-branch merge made before review. Do NOT use for ordinary commits inside a feature branch, or for repos with no origin/prod.
---

# git-flow

The shipping workflow for the Seechange-edu repos (think-and-speak-frontend,
think-and-speak-backend, cms-frontend, cms_backend). Every one of them uses
`dev`, `uat`, `prod` plus `release/vX.Y.Z` branches.

**As of 2026-08-26 the release is driven by two GitHub Actions workflows, not by
local git commands.** Verified present and identical in all four repos:
`.github/workflows/release-branch.yml` and `.github/workflows/release.yml`, both
`workflow_dispatch`, both calling `Seechange-edu/repo-toolkit@main`. They exist
on `dev` *and* on `prod`, so either ref can dispatch them.

**The single rule this whole skill exists to enforce: every git write and every
workflow dispatch is proposed visually and executed only after the user replies
with approval.** No exceptions, including when the user's message was itself the
trigger word.

## The shape of the workflow

```
  origin/prod ──┬───────────────────────────────────────────────► (always shippable)
                │                                          ▲
                │ ① Actions ▸ "Release Branch"             │ ④ automatic, on release: published
                │    cuts release/vX.Y.Z from prod         │    merge tag → prod
                ▼                                          │    backmerge prod → dev, uat
       feature-branch ──┬──► PR ──► origin/dev  (test here, repeat)
       (cut from prod)  │
                        └──► ② PR ──► release/vX.Y.Z ──► ③ Actions ▸ "Release" ──► deploy
                             only what you merge ships       tags · notes · publishes
```

- Feature branches are cut **from `prod`**, never from `dev`. That keeps `prod`
  clean, so *"others who want to checkout a new branch from prod will be safe."*
- **Every change must be PR'd to `dev` or `uat` — at least one, before it releases.**
  Both is optional: *"PR to both Dev and UAT is not necessary all the time, but at
  least need to PR to one of them."* Default to `dev`. Nothing reaches a release
  branch having been tested on neither.
- A release branch is a **planned version**, not one feature — it can collect
  several features and bugfixes for the next release. If an unshipped
  `release/vX.Y.Z` exists, add to it rather than cutting a new one.
- **Only what you merge into the release branch ships.** The release branch starts
  as an exact copy of `prod`; it contains nothing until PRs land on it.
- The **same branch** is PR'd into both `dev` and the release branch. Never
  cherry-pick the same change onto two branches — duplicate SHAs are what caused
  the PR #767/#768/#771/#774 conflict cascade in this workspace.
- **Hotfixes take the same route.** Branch from `prod`, PR to dev/uat, PR to a
  release branch, publish. Never push straight to production.
- Production deploys fire on `release: [published]` (`PROD_k8s.yaml` in the two
  think-and-speak repos, `PROD-docker.yaml`/`.yml` in the two cms repos).
- CI (`check-release`) **hard-fails a release that is behind `prod`**. The tag is
  already created by then, so the pre-flight below matters more than it used to.
- **Everything after the publish is automatic** — see "After the release", which
  also covers the ways it can silently not happen.

## The two workflows

`release-branch.yml` ("Release Branch") cuts `release/<version>` from `prod` and
touches nothing inside it. `release.yml` ("Release") tags the release branch tip,
writes the notes and publishes with `ACTION_TOKEN` — which is the whole reason it
exists, since a release published by `GITHUB_TOKEN` does not trigger the deploy.

It refuses to tag anything whose name does not start with `release/`, so it cannot
tag `dev` by accident. The tag is the branch name minus the `release/` prefix.

**Read `references/release-workflows.md` for the exact inputs** — the `bump` choice
labels (which must be passed verbatim), `from`, `version`, `previous` — before
dispatching either one, or when a dispatch comes back rejected.


## Step 0 — always, before anything else

Run this and read it before proposing anything. Never plan from stale refs.

```bash
git -C <repo> fetch --prune --quiet origin prod dev uat
git -C <repo> status --porcelain
git -C <repo> rev-list --count HEAD..origin/prod    # behind prod
git -C <repo> rev-list --count origin/prod..HEAD    # own work
git -C <repo> log --oneline origin/prod..HEAD
```

**`--prune` is not optional any more.** The release pipeline deletes merged
branches on the remote, so `git branch -r` keeps showing `origin/release/*`
branches that no longer exist. Probed: three stale `origin/release/*` refs in
think-and-speak-frontend, all gone after one `fetch --prune`. **Ask the remote,
never the local cache:**

```bash
git -C <repo> ls-remote --heads origin 'refs/heads/release/*'   # live release branches
git -C <repo> ls-remote --heads origin 'refs/heads/backmerge/*' # unresolved backmerge conflicts
```

Scope: **every git repo in the workspace that has changes** (uncommitted, unpushed,
or commits not in `origin/dev`). One plan covering all of them — these repos ship
together, and a backend merged without its frontend is a broken deploy.

Flag before proposing, and ask how to proceed rather than fixing silently:

| Condition | What it means | Say this |
|---|---|---|
| On `dev`/`uat`/`prod` directly | Work is on a protected branch | Offer to move the commits onto a feature branch cut from prod |
| Branch behind `origin/prod` | Missing prod commits; will conflict at release | Offer `git merge origin/prod` into the branch first |
| Branch not cut from prod | Carries dev-only commits into the release | Name the extra commits; ask before proceeding |
| Uncommitted changes | Unclear what's shipping | List the files; ask what to include |
| A `backmerge/*` branch exists on the remote | A previous release's automatic backmerge hit a conflict and is still open | Report it — it blocks nothing, but dev/uat are drifting from prod until a human resolves it |
| Local branch vanished from the remote | The prune job deleted it after its release | Normal. Say so; don't re-push it |

## Trigger: "dev" (or `/dev`)

Meaning: get the current work onto `origin/dev` for testing. Repeatable — this
happens many times before a release. **Unchanged by the new release flow.**

1. Run Step 0, then the duplicate-SHA guard: `git cherry -v origin/dev <branch>`.
   Any `-` line → stop and report before planning anything.
2. Render the plan (format below) and **stop**.
3. On approval only:
   - commit anything staged for inclusion, with a real message
   - `git push -u origin <branch>`
   - `gh pr create --base dev --head <branch>` (reuse the open PR if one exists)
   - poll `gh pr view <num> --json mergeable,mergeStateStatus`
   - merge **only** on `MERGEABLE` / `CLEAN`: `gh pr merge <num> --merge` (never
     `--squash` or `--rebase` — they rewrite SHAs and break the later release PR)
4. On conflict: **stop, do not resolve it silently.** Report the conflicting files
   and the two sides, then ask.
5. Report each repo's PR URL and merge result.

Note for later: **do not delete the feature branch after merging to dev.** It is
the same branch that gets PR'd into the release branch. The prune job removes it
by itself once it has actually reached prod.

## Trigger: "prod" (or `/prod`)

Meaning: cut the release branch and get this work onto it. Ends **before** the
publish — the user reviews, then says "publish" separately.

1. Run Step 0, plus:
   ```bash
   git -C <repo> tag --sort=-v:refname | head -3
   git -C <repo> ls-remote --heads origin 'refs/heads/release/*'
   gh workflow list --repo <org>/<repo>          # confirm "Release Branch" + "Release" exist
   ```
2. **Is there already an unshipped release branch?** If `ls-remote` shows one,
   propose adding to it and **skip step 5a entirely** — do not cut a second one.
3. Otherwise pick the **bump**, not the number: patch by default. Each repo has
   its own independent version series, so each gets its own dispatch. Put the bump
   in the plan and say the version is whatever repo-toolkit computes; the user can
   override with a `custom` version in their approval.
4. Run the duplicate-SHA guard against the release branch (once it exists) —
   `git cherry -v origin/release/vX.Y.Z <branch>` — plus the stale-version diff.
   Any `-` line → stop and report. Then render the plan and **stop**.
5. On approval only:

   **5a. Cut the release branch** — dispatch the workflow; never `git branch` +
   `git push` by hand. The workflow is what names the version and what the team
   watches in Actions.

   ```bash
   gh workflow run release-branch.yml --repo <org>/<repo> --ref dev \
     -f bump='patch (eg v1.2.3 → v1.2.4)'
   ```

   For a pinned version instead:

   ```bash
   gh workflow run release-branch.yml --repo <org>/<repo> --ref dev \
     -f bump='custom (use the version input below)' -f version='v3.11.6'
   ```

   The `bump` label must match a choice option **byte for byte**, including the
   `→`. If GitHub rejects the dispatch, don't retry variants — hand the user the
   UI instead: `https://github.com/<org>/<repo>/actions/workflows/release-branch.yml`
   (Run workflow ▸ pick the bump ▸ leave "Cut from" empty).

   **5b. Learn the version the run actually produced** — never assume it:

   ```bash
   gh run list --repo <org>/<repo> --workflow=release-branch.yml --limit 1 \
     --json databaseId,displayTitle,status,conclusion
   git -C <repo> fetch --prune --quiet origin
   git -C <repo> ls-remote --heads origin 'refs/heads/release/*'
   ```

   The run's `displayTitle` shows what was *asked for*; `ls-remote` shows what
   exists. Trust `ls-remote`. Report the real branch name before going on.

   **5c. PR the feature branch into it** — this is the step that decides what
   ships. The release branch is an empty copy of prod until now.

   ```bash
   gh pr create --repo <org>/<repo> --base release/vX.Y.Z --head <branch>
   ```

   Merge on `CLEAN` only, `--merge` only; on conflict stop and report.

   **5d. If `origin/prod` moved since the cut**, merge it into the release branch
   — `check-release` hard-fails a release that is behind prod, and by then the tag
   already exists:

   ```bash
   git -C <repo> checkout release/vX.Y.Z && git -C <repo> pull --ff-only
   git -C <repo> merge origin/prod            # stop and report if this conflicts
   git -C <repo> push origin release/vX.Y.Z
   git -C <repo> merge-base --is-ancestor origin/prod origin/release/vX.Y.Z && echo OK
   ```

   Merging `prod` into the release branch is the **only** write to a release branch
   that isn't a PR merge, and it is allowed because merging preserves SHAs. Return
   to the user's original branch afterwards.

6. **Stop here.** Hand over the publish step and say plainly that it is the
   production deploy:
   > `release/v3.11.6` is cut and contains PR #NNN. It contains all of prod.
   > Publish here to deploy — Actions ▸ Release ▸ Run workflow ▸ Use workflow from
   > `release/v3.11.6`:
   > `https://github.com/<org>/<repo>/actions/workflows/release.yml`
7. Do not dispatch the Release workflow as part of "prod". The user reviews first.
   They will come back and say "publish" — see the next section.

## Trigger: "publish"

Fires **only on an explicit instruction to publish**: "publish", "publish it",
"can u please publish", usually with a `workflows/release.yml` or
`releases/new?tag=…&target=…` URL pasted in. Never inferred from "prod",
"release", or "ship it" — those still stop at the URL. The user reviews the
release branch, then authorizes the deploy separately.

**Their "publish" IS the approval.** They have already reviewed. Do not render a
plan, do not ask a second time — run the pre-flight and go.

Work out the release branch: from the pasted URL's `target=`, from an explicitly
named branch, or from the single live `release/*` branch if there is exactly one.
**If more than one is live and the user did not name it, ask — do not guess.**

Match the URL's `org/repo` against `git remote get-url origin` before acting, and
fetch — the workflow reads the *remote* ref, so a stale local checkout can't ship
the wrong code, but it will make the pre-flight lie.

**Pre-flight — every check must pass. Any failure aborts the publish; report it,
do not "fix" it and continue.**

```bash
BR=release/vX.Y.Z; TAG=${BR#release/}
git fetch --prune --quiet origin prod "$BR"
git ls-remote --heads origin "refs/heads/$BR" | grep -q . || echo "ABORT: $BR not on remote"
gh release view "$TAG" >/dev/null 2>&1        && echo "ABORT: release $TAG already published"
git ls-remote --tags origin "$TAG" | grep -q . && echo "ABORT: tag $TAG already on remote"
# check-release hard-fails a release behind prod — and the tag exists by then.
git merge-base --is-ancestor origin/prod "origin/$BR" || echo "ABORT: $BR is behind prod"
# An empty release branch ships nothing. Worth saying out loud before deploying.
git log --oneline "origin/prod..origin/$BR"
```

`gh release view` exits 1 when the release is absent, 0 when it exists — verified.

Then dispatch the Release workflow, and say in one line what is about to deploy:

```bash
gh workflow run release.yml --repo <org>/<repo> --ref "$BR"
```

`--ref` works because `release.yml` exists on `prod`, so every branch cut from
prod carries it — verified in all four repos. The `branch` input defaults to the
dispatch ref, so nothing else is needed. If the ref is somehow unusable, dispatch
from `dev` and name the branch instead: `--ref dev -f branch="$BR"`.

**Never fall back to `gh release create`.** It bypasses the workflow's
`release/`-prefix guard and its notes generation, and the whole reason the
workflow exists is the token: the deploy trigger is keyed to `ACTION_TOKEN`.

Then confirm it published, report the release URL, state plainly that the
production deploy workflow is now running, and offer `gh run watch` rather than
starting it uninvited:

```bash
gh run list --repo <org>/<repo> --workflow=release.yml --limit 1 --json databaseId,status,conclusion
gh release view "$TAG" --json url,tagName,createdAt
```

## After the release — automatic, but verify it

On `release: published` the production workflow deploys, then a `cleanup` job:

1. merges the tag into `prod`
2. back-merges `prod` into `dev` and `uat` (repo-toolkit `mode: backmerge`)
3. deletes branches already merged into `prod` (`mode: prune`, excluding
   `^backmerge/`)

**All three steps are `continue-on-error: true`.** The run goes green even when
they fail — the tag→prod merge only emits `::warning::Could not merge … (branch
protection or a conflict?)`. So a green Production run is *not* evidence that
`prod` moved. Check:

```bash
git fetch --prune origin prod dev uat
git merge-base --is-ancestor "$TAG" origin/prod   && echo "prod: MERGED"   || echo "prod: NOT-MERGED"
git merge-base --is-ancestor origin/prod origin/dev && echo "dev: BACKMERGED" || echo "dev: BEHIND"
git merge-base --is-ancestor origin/prod origin/uat && echo "uat: BACKMERGED" || echo "uat: BEHIND"
git ls-remote --heads origin 'refs/heads/backmerge/*'   # non-empty = conflict, human needed
```

- `prod: NOT-MERGED` → **report it and stop.** Do not push to `prod`, and do not
  open a PR into `prod` either — team rule, verbatim: *"I would not PR to Prod,
  even I PR to Dev."* `prod` is written only by the release automation. This is a
  CI/permissions problem to raise with the team, not something to patch by hand.
- A `backmerge/*` branch on the remote → the automatic backmerge hit a conflict
  and opened a branch + PR for a human. Report it; **do not resolve it unasked**,
  and do not delete it (prune deliberately excludes `^backmerge/` precisely so it
  isn't pulled out from under whoever is resolving it).
- Feature branches disappearing is **expected** — that is the prune job, not a
  mistake. Say so rather than re-pushing them.

There is nothing left to merge by hand. Do not offer manual backmerge branches
any more; that was the old flow.

## The duplicate-SHA guard — run before opening ANY PR

This is the check that would have prevented the #765/#766 → #767 → #771 → #774
cascade. The prohibition below is not enough on its own; run the detector.

```bash
git fetch --prune --quiet origin
git cherry -v origin/<target-branch> <source-branch>
```

Read every line:

| Mark | Meaning | Action |
|---|---|---|
| `+ <sha>` | Genuinely new to the target | Fine — this is what a PR should contain |
| `- <sha>` | **An equivalent patch is already on the target under a different SHA** | **STOP. Do not open the PR.** This is the duplicate that makes every later backmerge conflict. |

A `-` line means the same change exists twice in the history. Git treats the two
copies as independent edits to the same lines, so `dev`/`uat`↔`prod` comparisons
conflict forever after — and each "fix" merge buries it deeper. Report the
duplicated commits to the user and ask; do not merge your way out of it.

This matters more now, not less: the backmerge step runs on **every** release, so
a duplicate SHA turns into a recurring automatic-backmerge conflict rather than a
one-off.

**Verified behavior** (probed on a synthetic repro of the incident): a commit
cherry-picked onto a branch with a different parent gets a new SHA, and
`git cherry -v` marks it `-` while marking genuinely-new commits `+`.

### Never re-create a change on a second branch

`git cherry-pick`, re-applying an edit by hand, or "just redoing it on the other
branch" all produce a second SHA for one change. When tempted, do this instead:

| Situation | Do this, not a cherry-pick |
|---|---|
| Change is on `dev`, needed on the release branch | PR the **same feature branch** into the release branch. Identical SHAs land on both — that is still one lineage. |
| Urgent fix needed on `prod` | Hotfix branch **from `prod`** → PR to dev/uat → PR that same branch into the release branch → publish. The backmerge into dev/uat is automatic. Never re-type the fix per branch, and never push to prod. |
| Release branch is missing prod commits | `git merge origin/prod` into it. Merging preserves SHAs; picking does not. |
| Someone already created a duplicate | Stop and tell the user. The repair is a reconciliation merge that establishes ancestry (what #771/#774 did), and it is their call. |

### Also check you aren't shipping a stale version

If the feature was merged to `dev` and then **followed up on `dev`**, the original
feature branch is now behind the real change. Before the release PR:

```bash
git diff origin/<release-branch> origin/dev -- <files the feature touched>
```

Non-empty means `dev` has feature work the release branch lacks. Surface it —
shipping the stale copy is how the same change ends up edited twice.

## Rescue: the branch was cut from `dev`, not `prod`

The whole workflow assumes feature branches come off `prod`. When one comes off
`dev`, it inherits every unreleased dev commit as an ancestor, and git cannot
ship a descendant without its ancestors — so "just release my commits" is not
achievable by any normal means. Detect it in Step 0:

```bash
git merge-base --is-ancestor origin/prod origin/<branch> || echo "NOT prod-based"
git rev-list --count origin/prod..origin/<branch>   # commits carried beyond prod
```

Symptoms that this section applies: a `dev` PR stuck `CONFLICTING`; a branch
hundreds of commits behind `dev`; "I want this in prod but not everything else".

**Two things to get right before proposing anything:**

1. **The PR may already be redundant.** Work that reached `dev` by another route
   leaves the original branch a stale snapshot — merging it *reverts* the newer
   version. Check per file (`git diff --quiet origin/dev:$f $B:$f`), not by
   commit subject, and not with `git cherry` alone.
2. **If the work must ship without the rest of dev**, the route is a *file-level
   port* onto a `prod` base — never a cherry-pick of the commits — and the port
   branch must be PR'd into **both** `dev` and the release branch. The `dev` PR
   changes zero files and looks skippable; it is the only thing preventing the
   duplicate-SHA cascade.

**Read `references/dev-based-branch-rescue.md` before doing any of this.** It has
the full procedure, the compile-driven way to find the ported file set, the two
mandatory gates, and the rollback recipe for a release PR merged too early. Its
git mechanics are unchanged by the new workflows; only the "cut the release
branch" and "publish" steps are now workflow dispatches.

## The approval plan — required format

Render this before **any** git write or workflow dispatch. Concrete commands, real
numbers from Step 0, never a vague summary. One block per repo.

```
╔═ GIT PLAN — "dev" ═══════════════════════════════════════════╗

 think-and-speak-backend
   branch  TNS-1996-bulk-generation-in-thinking-lab
   base    origin/prod — ✓ contained          state  4 commits, 2 files uncommitted
   dupes   git cherry vs origin/dev — 4 new (+), 0 duplicate (−)  ✓

     TNS-1996-bulk…   ●──●──●──●
                                 ╲
     origin/dev       ●──●──●─────◆  PR (new)

   WILL DO
     1. git commit -am "TNS-1996: bulk generation queue"   ← 2 files
     2. git push -u origin TNS-1996-bulk-generation…       ← 4 commits
     3. gh pr create --base dev                            ← new PR
     4. gh pr merge --merge                                ← only if CLEAN

   WON'T TOUCH   origin/prod · origin/uat · release/*

╚══════════════════════════════════════════════════════════════╝

Approve? (reply "yes" / "yes but <change>" / "no")
```

A `prod` plan names the **bump**, not a version it cannot know, and shows the
dispatch:

```
╔═ GIT PLAN — "prod" ══════════════════════════════════════════╗

 think-and-speak-frontend
   branch  TNS-1996-bulk-generation-in-thinking-lab
   base    origin/prod — ✓ contained     on dev  ✓ merged (PR #827)
   release live release/* branches: none → cut a new one
   version bump = patch, from latest tag v3.11.2  (repo-toolkit picks the number)

     origin/prod        ●──●──●
                                ╲ ① Actions ▸ Release Branch (patch)
     release/vX.Y.Z              ◆──────◆  ② PR from TNS-1996-…

   WILL DO
     1. gh workflow run release-branch.yml --ref dev \
          -f bump='patch (eg v1.2.3 → v1.2.4)'
     2. git ls-remote --heads origin 'refs/heads/release/*'   ← read the real name
     3. gh pr create --base release/vX.Y.Z --head TNS-1996-…
     4. gh pr merge --merge                                   ← only if CLEAN

   STOPS AT   ③ you dispatch Actions ▸ Release  (= production deploy)
   WON'T TOUCH   origin/prod · origin/dev · origin/uat · any tag

╚══════════════════════════════════════════════════════════════╝

Approve? (reply "yes" / "yes but <change>" / "no")
```

## Hard rules

- **Never push to `dev`, `uat`, or `prod` directly.** Always a branch + PR.
- **Never PR into `prod`.** Not for a feature, not for a fix, not to repair a
  missing auto-merge. `prod` is written only by the release automation. The route
  to production is always: release branch → Release workflow → automation updates
  `prod`. Team rule, verbatim: *"I would not PR to Prod, even I PR to Dev."*
- **Never cut a release branch by hand.** `git branch release/… && git push` skips
  the workflow the team watches and the versioning repo-toolkit owns. Dispatch
  `release-branch.yml`.
- **Never create the release by hand.** No `gh release create`, no tag push. A
  release not published by `ACTION_TOKEN` does not trigger the deploy. Dispatch
  `release.yml`.
- **Never merge into `dev`/`uat`/`prod` without approval in this session**, even
  when a previous merge this session was approved. Approval does not carry over.
- **Never `push --force`, `reset --hard`, or rebase a pushed branch** without
  explicit confirmation naming the consequence.
- **Never cherry-pick a change onto a second branch.** PR the same branch twice.
- **Never merge a ported branch into a release branch without also PR'ing it into `dev`.**
  The dev PR changes zero files, which is exactly why it gets skipped — and skipping it
  leaves prod holding a commit `dev` has never seen. See the rescue section.
- **Never squash- or rebase-merge** a PR that will also be released — it changes
  SHAs and guarantees a conflict in the release PR, and now in every later
  automatic backmerge too.
- **Never resolve a merge conflict unasked** — including a `backmerge/*` branch the
  automation opened. Report the files and both sides.
- **Never dispatch the Release workflow on your own initiative** — not as part of
  "prod", not because the release branch looks ready. Publish only on an explicit
  "publish" from the user, and only after the pre-flight passes.
- **Never read release branches from `git branch -r`.** Prune deletes them
  remotely and the local cache lies. `git ls-remote`, or `fetch --prune` first.
- If any step fails, stop the whole plan and report what completed and what didn't.
  Do not improvise a recovery.
