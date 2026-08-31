# Changelog

## 1.1.0 — 2026-08-31

### Timestamps on every git write

- New `PostToolUse` hook (`hooks/git-flow-stamp.sh`) stamps the wall-clock time of
  every `git push`, `gh pr create`, `gh pr merge`, `git merge`, and
  `gh workflow run release-branch.yml` / `release.yml`, and shows it as it happens.
  Failed commands are stamped `✗ FAILED` so an attempt is never mistaken for a write.
- Each stamp is also appended to `~/.claude/git-flow-timestamps.log`, so "when did
  we push that?" outlives the session scrollback. Push, PR and merge times are the
  one part of this flow that is *not* recoverable locally afterwards — `git log`
  already holds commit times, which is why plain `git commit` is not stamped.
- SKILL.md and both commands now require the stamps to be quoted verbatim in the
  closing report, and a hard rule forbids reporting a push/PR/merge without one.

  This is a hook rather than a line of prose because an instruction to "report the
  time" is followed *most* of the time, and an audit trail with gaps in it is not
  an audit trail. The harness runs the hook whether or not the model remembers.

- Read-only commands (`git log`, `gh pr view`, `git merge-base`, anything with
  `--dry-run`) are not stamped, and neither is `git commit -m "…merge…"` — the
  matcher anchors `git` at a command boundary rather than searching the whole
  string. Requires `jq`; without it the hook exits silently rather than interfering.

## 1.0.1 — 2026-08-27

- Hook output no longer cites `CLAUDE.md §0g`, a section that only existed in one
  person's global config. It now reads `[git-flow]`.
- CONTRIBUTING: spell out that a version bump is what makes a change reach installed
  copies. `claude plugin update` compares versions, so a content-only change is
  silently skipped on every machine that already has the plugin.

## 1.0.0 — 2026-08-27

First packaged release. Previously a personal skill in `~/.claude/skills/`.

### The release flow changed on 2026-08-26

The skill was rewritten for the Actions-driven release flow now live in all four
repos (`think-and-speak-frontend`, `think-and-speak-backend`, `cms-frontend`,
`cms_backend`). Read from the workflow YAML, not from the announcement:

- **Release branches are cut by `release-branch.yml`, not by hand.** The workflow
  takes a *bump* (patch / minor / major / custom) and `repo-toolkit` computes the
  version. Guessing the version number locally is now wrong.
- **Releases are published by `release.yml`, not `gh release create`.** It publishes
  with `ACTION_TOKEN` specifically because a release published by `GITHUB_TOKEN`
  does not trigger the deploy. Going around the workflow risks a tag with no deploy.
- **Everything after the publish is automatic** — tag merged into `prod`, `prod`
  back-merged into `dev` and `uat`, merged branches pruned. The old "offer to create
  backmerge branches" behaviour is gone.
- **But a green Production run does not prove `prod` moved.** All three cleanup steps
  are `continue-on-error: true` and fail with only a `::warning::`. The skill now
  verifies with `merge-base --is-ancestor` instead of assuming.
- **Release branches must be read from `git ls-remote`, never `git branch -r`.** The
  prune job deletes them remotely; the local cache keeps showing branches that are
  gone. Observed: three stale `origin/release/*` refs, all cleared by one
  `fetch --prune`.
- Added: hotfix routing (same route as anything else — never straight to prod), and
  handling for the `backmerge/*` branches the automation opens on conflict.

### Packaging

- Added `/dev` and `/prod` commands.
- Added the SessionStart branch-health hook.
- Split the workflow input tables into `references/release-workflows.md` so they
  aren't loaded on every trigger.
