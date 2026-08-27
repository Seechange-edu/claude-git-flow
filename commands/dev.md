---
description: Ship the current work to origin/dev — plan first, merge only after approval
argument-hint: "[optional: repo name, or 'only <repo>', or a note about what to include]"
---

Invoke the **`git-flow`** skill now, then run its **"dev"** trigger.

Extra instruction from the user, if any: $ARGUMENTS

Non-negotiable, from the skill:

1. Run **Step 0** across **every repo in the workspace that has changes** — one
   plan covering all of them. Fetch with `--prune`; never plan from stale refs.
2. Run the **duplicate-SHA guard** (`git cherry -v origin/dev <branch>`) before
   proposing any PR. Any `-` line → stop and report, do not plan around it.
3. **Render the approval plan in the skill's box format and STOP.** This command
   is a request for a plan, not authorization to write. Approval is per-invocation
   — a "yes" earlier in this session does not carry over.
4. Only after the user approves: commit → push → `gh pr create --base dev` →
   merge with `--merge` **only** on `MERGEABLE`/`CLEAN`. Never `--squash` or
   `--rebase`; they rewrite SHAs and break the later release PR.
5. On any conflict or failure: stop and report. Do not resolve it unasked, do not
   improvise a recovery.
6. Do **not** delete the feature branch afterwards — the same branch is what gets
   PR'd into the release branch later, and the release pipeline prunes it itself
   once it reaches prod.

Report each repo's PR URL and merge result at the end.
