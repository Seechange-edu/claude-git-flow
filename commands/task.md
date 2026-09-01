---
description: Start a Jira ticket — cut the prod-based branch across the repos you pick
argument-hint: "[paste the Jira ticket, a KEY-123, a browse URL, or a screenshot]"
---

Invoke the **`git-flow`** skill now, then run its **"new task"** trigger.

The ticket, if the user gave one here: $ARGUMENTS — otherwise read it from the
screenshot or text in their message.

Non-negotiable, from the skill:

1. Read the issue **key** and **summary** off whatever they gave you. **Never invent
   or auto-correct a key** — if the screenshot is illegible or only a URL was given
   and no Atlassian tool is available, ask for the title rather than guessing.
2. Derive **one** branch name, `<KEY>-<kebab-summary>`, and use that same name in
   every repo. One ticket, one branch name.
3. **Ask which repos** as a multi-select over the repos actually present in the
   workspace that have an `origin/prod`. Never infer the set from the ticket text.
4. `fetch --prune` each chosen repo, read the real `origin/prod` SHA, and check
   whether the branch already exists locally or on the remote. An existing branch is
   never re-created and never moved — report it and offer to switch to it.
5. **Render the approval plan in the skill's box format and STOP.** This command is a
   request for a plan, not authorization to write. Approval is per-invocation.
6. Only after the user approves: `git branch --no-track <name> origin/prod` in each
   repo, then `git switch` **only** where the worktree is clean. `--no-track` is
   required — without it the branch's upstream becomes `origin/prod` and a bare
   `git push` targets prod. Never `checkout -b`, never stash on the user's behalf,
   and never branch from `dev` or from current HEAD.
7. **Do not push.** The branch has no commits yet; `/dev` pushes it later.

Report per repo: created / already existed / created-but-not-switched, plus the
`origin/prod` SHA each branch starts from and the exact `git switch` command for any
repo left on its old branch.
