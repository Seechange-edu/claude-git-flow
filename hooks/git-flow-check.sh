#!/usr/bin/env bash
# git-flow-check.sh — SessionStart hook.
# Prints a compact branch-health report for every git repo in the workspace so the
# model knows, before touching anything, whether the working state fits the
# prod-based branching workflow (global CLAUDE.md §0g / the `git-flow` skill).
# Read-only apart from `git fetch`, which only updates remote-tracking refs.
set -uo pipefail

CWD="${CLAUDE_PROJECT_DIR:-$PWD}"
[ -d "$CWD" ] || exit 0

# find_repos — collect the workspace root plus its immediate subdirectories that
# are git repos. One level deep only: monorepo-of-repos is the layout here, and
# deeper recursion would walk node_modules.
find_repos() {
  [ -d "$CWD/.git" ] && printf '%s\n' "$CWD"
  for d in "$CWD"/*/; do
    [ -d "${d}.git" ] && printf '%s\n' "${d%/}"
  done
}

# macOS ships bash 3.2 — no mapfile, so read into the array the portable way.
REPOS=()
while IFS= read -r line; do
  [ -n "$line" ] && REPOS+=("$line")
done < <(find_repos)
[ "${#REPOS[@]}" -eq 0 ] && exit 0

# Refresh remote-tracking refs for the branches the workflow cares about, all
# repos at once — serial fetches cost ~5s each and would stall session start.
for r in "${REPOS[@]}"; do
  ( timeout 12 git -C "$r" fetch --quiet origin prod dev uat 2>/dev/null ) &
done
wait

OUT=""
FLAGS=""

for r in "${REPOS[@]}"; do
  name=$(basename "$r")
  g() { git -C "$r" "$@" 2>/dev/null; }

  branch=$(g rev-parse --abbrev-ref HEAD)
  [ -z "$branch" ] && continue

  # Skip repos that don't use the dev/prod convention — nothing to report.
  g show-ref --verify --quiet refs/remotes/origin/prod || continue

  dirty=$(g status --porcelain | wc -l | tr -d ' ')
  # rev-parse echoes the literal "@{u}" on stdout when there is no upstream, so
  # test its exit status rather than whether the output is empty.
  if upstream=$(g rev-parse --abbrev-ref --symbolic-full-name '@{u}'); then
    unpushed=$(g rev-list --count "$upstream..HEAD")
  else
    unpushed="no-upstream"
  fi

  behind_prod=$(g rev-list --count "HEAD..origin/prod")
  ahead_prod=$(g rev-list --count "origin/prod..HEAD")
  behind_dev=$(g rev-list --count "HEAD..origin/dev")

  line="  $name [$branch]"
  case "$branch" in
    dev|uat|prod|main|master)
      line="$line  ⚠ ON PROTECTED BRANCH"
      case "$FLAGS" in *on-protected-branch*) ;; *) FLAGS="${FLAGS}on-protected-branch " ;; esac
      ;;
  esac
  [ "${behind_prod:-0}" != "0" ] && {
    line="$line  ${behind_prod} behind prod"
    case "$FLAGS" in *behind-prod*) ;; *) FLAGS="${FLAGS}behind-prod " ;; esac
  }
  [ "${ahead_prod:-0}" != "0" ] && line="$line  ${ahead_prod} ahead of prod"
  [ "${behind_dev:-0}" != "0" ] && line="$line  ${behind_dev} behind dev"
  [ "${dirty}" != "0" ] && line="$line  ${dirty} uncommitted"
  if [ "$unpushed" = "no-upstream" ]; then
    line="$line  never pushed"
  elif [ "$unpushed" != "0" ]; then
    line="$line  ${unpushed} unpushed"
  fi

  OUT="${OUT}${line}"$'\n'
done

[ -z "$OUT" ] && exit 0

printf '[git-flow §0g] Workspace branch state (remote refs just fetched):\n%s' "$OUT"

if [ -n "$FLAGS" ]; then
  printf 'Issues: %s\n' "$FLAGS"
  printf 'Mention these in ONE short line before the first task and offer to fix them. Do not fix unprompted.\n'
fi
printf 'On a bare "dev" or "prod" from the user: invoke the `git-flow` skill, render the plan, wait for approval.\n'
exit 0
