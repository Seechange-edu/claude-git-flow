---
description: Cut the release branch and PR this work into it — stops before the deploy
argument-hint: "[optional: 'minor' / 'major' / a custom version like v3.12.0, or a repo name]"
---

Invoke the **`git-flow`** skill now, then run its **"prod"** trigger.

Extra instruction from the user, if any: $ARGUMENTS — treat `minor`, `major`, or
an explicit `vX.Y.Z` here as the bump/version to propose in the plan. Default is
a **patch** bump when nothing is given.

Non-negotiable, from the skill:

1. Run **Step 0** across **every repo in the workspace that has changes**, plus
   `git ls-remote --heads origin 'refs/heads/release/*'`. These repos ship
   together — one plan covering all of them.
2. **If a live `release/*` branch already exists, add to it.** Do not cut a second
   one.
3. Verify the work has reached `dev` (or `uat`) first. Nothing releases having
   been tested on neither.
4. Run the **duplicate-SHA guard** and the stale-version diff. Any `-` line →
   stop and report.
5. **Render the approval plan in the skill's box format and STOP.** Name the
   *bump*, not a version number you cannot know — repo-toolkit computes it. This
   command is a request for a plan, not authorization to write.
6. Only after the user approves:
   - dispatch **Actions ▸ Release Branch** (`gh workflow run release-branch.yml`)
     — never `git branch release/… && git push` by hand
   - read the real branch name back from `git ls-remote`, not from the run title
   - `gh pr create --base release/vX.Y.Z --head <branch>`, merge with `--merge`
     only on `CLEAN`
   - if `origin/prod` moved since the cut, merge it into the release branch —
     CI hard-fails a release that is behind prod
7. **STOP before publishing.** Hand over the Release-workflow URL and say plainly
   that dispatching it is the production deploy. Never dispatch `release.yml`
   yourself as part of this command — that needs a separate, explicit "publish"
   from the user.
8. On any conflict or failure: stop and report. Do not improvise a recovery.
