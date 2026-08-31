#!/usr/bin/env bash
# git-flow-stamp.sh — PostToolUse hook on Bash.
# Stamps the wall-clock time of every git write the model actually performs —
# push, PR create, PR merge, local merge, and the two release workflow
# dispatches — and shows it to the user as it happens.
#
# Why this is a hook and not a line in SKILL.md: a prompt instruction to "report
# the time" is followed most of the time, which for an audit trail is the same as
# not having one. The harness runs this on every matching Bash call whether or not
# the model remembers. Push/PR/merge times are also the one part of the flow that
# is NOT recoverable locally afterwards — commit times live in `git log`, but the
# moment a branch reached the remote does not.
#
# Read-only with respect to git. Its only write is one append per event to the
# ledger below.
set -uo pipefail

# jq ships with macOS 15+ and most Linux images. If it is missing, degrade to
# silence rather than corrupting the tool result with a parse error.
command -v jq >/dev/null 2>&1 || exit 0

INPUT=$(cat)
[ -n "$INPUT" ] || exit 0

CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
[ -n "$CMD" ] || exit 0

# Cheap pre-filter: the vast majority of Bash calls are not git writes, and this
# hook runs on every single one of them.
printf '%s' "$CMD" | grep -qE '(git|gh)' || exit 0

# Flatten to one line so the patterns below never have to be multiline-aware.
# Newlines become `;` rather than spaces: a newline separates commands, so
# collapsing it to a space would hide `git push` on the second line of a
# two-command call behind the first command's arguments.
FLAT=$(printf '%s' "$CMD" | tr '\n' ';' | tr -s ' ')

IS_ERROR=$(printf '%s' "$INPUT" | jq -r '.tool_response.isError // false' 2>/dev/null)
if [ "$IS_ERROR" = "true" ]; then
  RESULT="✗ FAILED"
else
  RESULT="✓"
fi

STAMP=$(date "+%Y-%m-%d %H:%M:%S %Z (UTC%z)")

# classify — append one label per git write found in the command. A single Bash
# call can chain several (`git push && gh pr create`), so every pattern is tested
# rather than stopping at the first hit.
OPS=""
add() { OPS="${OPS}${1}"$'\n'; }

# `--dry-run` writes nothing, so it is not an event worth stamping.
case "$FLAT" in *--dry-run*) DRY=1 ;; *) DRY=0 ;; esac

# Anchor `git` at the start of a command in the chain, and allow only the two
# global options that realistically precede a subcommand. A looser gap would let
# `git commit -m "merge prod into branch"` read as a merge.
GIT='(^|[;&|] *)git( +-C +[^ ]+| +-c +[^ ]+)*'

[ "$DRY" = 0 ] && printf '%s' "$FLAT" | grep -qE "$GIT push( |$)"                          && add "PUSH"
printf '%s' "$FLAT" | grep -qE 'gh pr create'                                            && add "PR OPENED"
printf '%s' "$FLAT" | grep -qE 'gh pr merge'                                             && add "PR MERGED"
# Requiring a space after `merge` excludes the read-only `git merge-base`.
printf '%s' "$FLAT" | grep -qE "$GIT merge "                                             && add "MERGE (local)"
printf '%s' "$FLAT" | grep -qE 'gh workflow run [^ ]*release-branch\.yml'                && add "RELEASE BRANCH CUT (workflow dispatch)"
printf '%s' "$FLAT" | grep -qE 'gh workflow run [^ ]*release\.yml'                       && add "RELEASE PUBLISHED — PRODUCTION DEPLOY (workflow dispatch)"

[ -n "$OPS" ] || exit 0

# Keep the echoed command short enough to read at a glance; the full command is
# already in the transcript above this line.
SHORT=$(printf '%s' "$FLAT" | cut -c1-100)
[ "${#FLAT}" -gt 100 ] && SHORT="${SHORT}…"

LINES=""
while IFS= read -r op; do
  [ -n "$op" ] || continue
  LINES="${LINES}[git-flow] ⏱ ${op} ${RESULT} — ${STAMP}"$'\n'"           ${SHORT}"$'\n'
done <<< "$OPS"

# Durable ledger, so "when did we push that?" survives the session scrollback.
LEDGER="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/git-flow-timestamps.log"
if [ -d "$(dirname "$LEDGER")" ]; then
  while IFS= read -r op; do
    [ -n "$op" ] || continue
    printf '%s\t%s\t%s\t%s\n' "$STAMP" "$op" "$RESULT" "$FLAT" >> "$LEDGER" 2>/dev/null
  done <<< "$OPS"
fi

# systemMessage surfaces the stamp to the user immediately; additionalContext is
# what lets the model repeat it in its end-of-run report without re-deriving it.
jq -n --arg msg "$LINES" '{
  hookSpecificOutput: {
    hookEventName: "PostToolUse",
    systemMessage: $msg,
    additionalContext: ("Timestamped git write(s). Include these times verbatim in the report to the user:\n" + $msg)
  }
}'
exit 0
