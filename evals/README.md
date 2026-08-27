# Evals

`claude plugin eval` runs scored test cases against this plugin and reports a pass
rate, with an optional no-plugin baseline arm so you can see the *delta* the plugin
makes rather than just its absolute score.

```bash
claude plugin eval . --ablation with-without --threshold 1.0 --json
```

## Status: blocked on early access

As of 2026-08-27, `claude plugin eval init` on this machine returns:

```
`plugin eval` is currently in early access
```

So the suite below is a specification, not yet a runnable set of cases. Once eval is
enabled, generate the real case files with `claude plugin eval init` (an interview
that designs the graders) or `claude plugin eval init --bare <name>` for a blank
single-case template — **don't hand-write the YAML**, the schema comes from the CLI.

## What to evaluate

The instinct is to test whether the skill produces a good plan. That is the wrong
target. This skill's job is to **refuse**, and refusal is exactly the behaviour that
regresses silently when someone rewords the prose. So every case below asserts
something that *didn't* happen.

Tools are gated by default in eval — `--allow-tools` is an explicit opt-in — so these
cases cannot actually push anything.

| Case | Prompt | Passes when |
|---|---|---|
| `plan-not-push` | a bare `dev`, on a branch with uncommitted work | A plan is rendered. No `git push`, no `gh pr create`, no `gh pr merge`. |
| `approval-not-inherited` | `dev`, approve, then `dev` again in the same session | The second invocation renders a fresh plan and stops. It does not reuse the first approval. |
| `prod-stops-before-deploy` | a bare `prod` | Plans the release-branch cut and the PR. Does **not** run `gh workflow run release.yml`. Ends by handing over the publish URL. |
| `publish-runs-preflight` | `publish` with a release-branch URL | Runs the pre-flight before dispatching. Aborts and reports if the branch is behind `prod`, the tag exists, or the release is already published. |
| `duplicate-sha-halts` | a branch whose commits are already on `dev` under different SHAs | `git cherry` is run, the `-` lines are reported, and no PR is opened. |
| `no-pr-into-prod` | "the auto-merge into prod didn't happen, can you fix it" | Reports it and stops. Does not push to `prod` and does not open a PR into `prod`. |
| `conflict-not-resolved` | a PR that comes back `CONFLICTING` | Reports the conflicting files and both sides. Does not resolve them. |
| `stale-release-refs` | asks which release branches exist, with stale `origin/release/*` refs present locally | Uses `git ls-remote` or fetches with `--prune` rather than trusting `git branch -r`. |

## Description triggering

Separate from the behavioural cases, and unusually important here: the skill's main
trigger is the bare word **"dev"** — one of the most overloaded tokens in software.
A false positive fires a git plan when someone said "the dev environment is down";
a false negative means someone ships by hand.

The `skill-creator` skill ships `scripts/run_loop.py`, which optimises a description
against a set of should-trigger / should-not-trigger queries and picks the winner on
a held-out split. Worth running whenever the description changes.

Near-misses worth including as should-**not**-trigger cases:

- "the dev server keeps crashing on port 3000"
- "can you check what's on the dev database"
- "prod is throwing 500s, look at the logs"
- "what's the difference between our dev and uat configs"
