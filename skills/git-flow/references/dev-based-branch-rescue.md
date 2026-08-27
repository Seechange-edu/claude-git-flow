# Rescue: work that was branched from `dev`, not `prod`

The workflow assumes feature branches are cut from `prod`. When one is cut from
`dev` instead, it inherits every unreleased dev commit as an ancestor — and git
cannot ship a descendant without its ancestors. Selective release becomes
impossible by normal means. This file is the verified way out.

**Worked once, end to end, on 2026-08-25** — think-and-speak-backend v3.11.7 and
cms-frontend v3.7.71 (PRs #778/#780 and #818/#820). Every command below was run.

---

## Phase 1 — diagnose before proposing anything

```bash
B=origin/<feature-branch>
git fetch --quiet origin prod dev "$B"
git merge-base --is-ancestor origin/prod $B && echo "cut from prod - normal flow" || echo "NOT prod-based"
git rev-list --count origin/prod..$B   # commits it carries beyond prod
git rev-list --count origin/dev..$B    # commits it has that dev lacks
git rev-list --count $B..origin/dev    # how far behind dev it is
```

`NOT prod-based` + a large `prod..$B` count = this file applies.

### 1a. First check whether the PR is already redundant

A branch far behind `dev` is often a **stale snapshot** — its content already
reached dev by another route, and dev has moved on. Merging it would be a
*regression*, not an addition. Check per file, never by commit subject:

```bash
git show --format="" --name-only $B | grep -v '^$' | while read -r f; do
  if git cat-file -e origin/dev:"$f" 2>/dev/null; then
    git diff --quiet origin/dev:"$f" $B:"$f" && echo "IDENTICAL $f" || echo "DIFFERS   $f"
  else echo "ABSENT    $f"; fi
done
git diff --stat origin/dev $B -- <the PR's files>   # '-' heavy = dev has MORE
```

Mostly `IDENTICAL`, and the `DIFFERS` ones showing dev with more lines →
**close the PR, do not merge it.** Say what supersedes it. `git cherry` will
still mark such a commit `+` (its whole-commit patch-id is unique), so it is not
a substitute for this per-file check.

### 1b. Measure what shipping the work actually costs

```bash
LAST=$(git log --format=%H -1 origin/prod..origin/dev -- '<feature path globs>')
git rev-list --count --no-merges origin/prod..$LAST     # ships if cut there
git rev-list --count --no-merges $LAST..origin/dev      # stays behind
git log --first-parent --format='%h %s' origin/dev | head -14 | while read -r sha rest; do
  git merge-base --is-ancestor origin/prod "$sha" && echo "HAS-PROD $sha $rest" || echo "no-prod  $sha $rest"
done
```

If the feature is the **newest** thing on dev, cutting at it still ships nearly
everything — trimming saves a handful of commits, not a meaningful reduction.
Report the real numbers and let the user choose. Only if they reject "release
all of dev" does Phase 2 apply.

---

## Phase 2 — the file-level port (the fix)

**Do not cherry-pick the commits.** They depend on the commits beneath them and
will conflict. Instead take dev's *file content* for the feature surface and land
it as **one commit on a `prod` base**. A file-level copy cannot conflict.

```bash
git worktree add -b port/<feature>-to-prod "$SCRATCH/port" origin/prod
cd "$SCRATCH/port"
git diff --name-status origin/prod origin/dev -- '<feature globs>' | while read -r st f; do
  if [ "$st" = "D" ]; then git rm -q --ignore-unmatch "$f"; else git checkout origin/dev -- "$f"; fi
done
# MUST be empty — proves the branch now matches dev exactly on every ported path
git diff --stat origin/dev -- $(git diff --cached --name-only | tr '\n' ' ')
```

Handle `D` rows explicitly or files dev deleted stay alive on the release branch.

### Find the dependency closure by compiling, not by reading

Path globs miss files whose names don't match (entities, orchestrators). Compile,
read the missing symbol, add that file, repeat until green. Before adding a file,
diff it — if `prod → dev` on it contains unrelated work, stop and ask.

```bash
mvn -o test-compile -DskipTests          # backend
npx tsc --noEmit -p tsconfig.json        # frontend (symlink node_modules from the main checkout)
```

Real example: the ThinkingLab glob missed `Lesson.java` (entity columns) and
`NotebookLmVideoOrchestrator.java`. Both diffs were purely feature fields, so both
were safe to add. 13 files → 15.

Distinguish port failures from environment failures. `Could not resolve
placeholder 'X'` (missing env file) and `Cannot find module 'exceljs'` (declared
but not installed) fail on plain `prod` too — verify, then say so; don't report
them as port breakage.

### Migration ordering

Ported migrations are often back-dated relative to migrations prod already ran.
That only works with out-of-order enabled — check, don't assume:

```bash
git grep -n "out-of-order" origin/prod -- 'src/main/resources/*'
```

---

## Phase 3 — the two mandatory gates

**Gate 1 — the port must merge into `dev` as a no-op.** Test it in a throwaway
worktree *before* opening anything:

```bash
git commit -m "port(<feature>): land dev's <feature> surface on a prod base"
P=$(git rev-parse HEAD)
git worktree add --detach "$SCRATCH/merge-test" origin/dev
cd "$SCRATCH/merge-test" && git merge --no-edit "$P" && git diff --stat origin/dev HEAD
```

Required: **CLEAN merge and zero files changed.** Zero changes proves the port is
byte-identical to dev. A conflict or any changed file means the port drifted —
stop and re-derive it.

**Gate 2 — build green on the prod base** (Phase 2). Both gates before any PR.

---

## Phase 4 — PR the SAME branch into dev, then into the release branch

Order matters. Dev first.

```bash
git cherry -v origin/dev origin/port/<feature>-to-prod        # any '-' line = STOP
git push -u origin port/<feature>-to-prod
gh pr create --base dev --head port/<feature>-to-prod
gh pr merge <n> --merge                                       # only on MERGEABLE CLEAN
git fetch origin dev && git diff --stat <dev-sha-before> origin/dev   # MUST be empty

git push origin origin/prod:refs/heads/release/vX.Y.Z
gh pr create --base release/vX.Y.Z --head port/<feature>-to-prod
gh pr merge <n> --merge
git merge-base --is-ancestor origin/prod origin/release/vX.Y.Z        # CI needs this
```

### Why the dev PR is not optional

It changes zero files, so it looks skippable. It is the entire point.

Merging the port into `dev` puts that commit into **both** `dev` and `prod`
ancestry. Without it, prod holds a commit dev has never seen. That is survivable
only while the two copies stay byte-identical — git merges identical changes
cleanly. **The first edit to any ported file on `dev` breaks it**: the copies
diverge, neither side has the other in its ancestry, and every later
`prod`→`dev` backmerge conflicts on those hunks. That is exactly how
#765/#766 → #767/#771/#774 happened — #766 edited files #765 had already shipped.

If the user says the release PR alone is enough: state this consequence in two
sentences, name the cost (one no-op PR), and let them decide. Do not skip it
silently, and do not refuse if they insist.

---

## Rollback: a release PR was merged before the user reviewed it

Safe only while nothing is published. Verify all four, and stop on any failure:

```bash
gh release view vX.Y.Z >/dev/null 2>&1 && echo "STOP: published"
git ls-remote --tags origin vX.Y.Z | grep -q . && echo "STOP: tag exists"
git log --format='%an' origin/prod..origin/release/vX.Y.Z | sort -u   # only the user's?
git rev-list --count origin/prod..origin/release/vX.Y.Z               # how much to drop
```

Then reset the release branch to prod and reopen the review:

```bash
git push --force-with-lease=release/vX.Y.Z:<current-tip> origin <prod-sha>:refs/heads/release/vX.Y.Z
gh pr create --base release/vX.Y.Z --head port/<feature>-to-prod    # leave OPEN
```

This is a force-push: get explicit confirmation naming the consequence first.
**GitHub cannot un-merge a PR** — the old one stays marked "Merged" forever, so
comment on it pointing at the replacement. Leave the `dev` merge alone unless
asked; it is the ancestry link, and undoing it re-opens the duplicate-SHA risk.

---

## What to tell the user at the end

- The port is compile/typecheck-verified, **not runtime-verified**. Name the flows
  that need a UAT pass before publishing.
- Name any screens or endpoints the port **deletes** that prod serves today.
- If backend and frontend both ported, say plainly that they ship together.
- Stop at the publish URLs. Never publish without an explicit "publish".
