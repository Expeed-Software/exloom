#!/usr/bin/env bash
# exloom — PreToolUse hook. Denies hand-writing a verdict receipt, which is what
# makes a receipt evidence rather than another author-written artifact.
#
# OPT-IN: no-op unless `.claude/exloom-gate.enabled` exists.
# Exit 0 = allow (including any parse failure), 2 = deny. Bypass: EXLOOM_REVIEW_SKIP=1.
#
# Matches the obvious write forms only; an obfuscated command can still get
# through. Cooperating-team gate, not a security boundary.

set -u

HOOK_INPUT=""
if [[ -p /dev/stdin || ! -t 0 ]]; then
  HOOK_INPUT="$(cat 2>/dev/null || true)"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=/dev/null
. "$SCRIPT_DIR/lib.sh"

# The bypass here lifts the one protection that makes a receipt evidence, so it
# is the bypass most worth leaving a trace of.
if [[ "${EXLOOM_REVIEW_SKIP:-0}" == "1" ]]; then
  echo "exloom: verdict-receipt protection bypassed via EXLOOM_REVIEW_SKIP=1" >&2
  exloom_bypass_receipt "verdict-write:$(exloom_json_field "$HOOK_INPUT" tool_name)"
  exit 0
fi

[[ -n "$HOOK_INPUT" ]] || exit 0

TOOL="$(exloom_json_field "$HOOK_INPUT" tool_name)"

_tool_input() { exloom_tool_input "$HOOK_INPUT" "$1"; }

# Bare `.verdicts/` rather than the full `.claude/reviews/` prefix: an absolute
# Windows path uses backslashes. `exloom-gate.enabled` is included because
# deleting it disables every other hook.
VERDICT_RE='\.verdicts[/\\]|\.claude[/\\]reviews[/\\].*\.state([^A-Za-z0-9]|$)|\.claude[/\\]exloom-gate\.enabled'

TARGET=""
case "$TOOL" in
  Write|Edit|NotebookEdit|MultiEdit)
    TARGET="$(_tool_input file_path)"
    [[ -z "$TARGET" ]] && TARGET="$(_tool_input notebook_path)"
    printf '%s' "$TARGET" | grep -Eq "$VERDICT_RE" || exit 0
    ;;
  Bash)
    CMD="$(_tool_input command)"
    [[ -z "$CMD" ]] && CMD="$HOOK_INPUT"
    # \r as well: exloom_tool_input normalises CRLF, but the raw-payload fallback
    # on line 78 does not, and a lone CR leaves the last word of every line as
    # `word\r` — so command-position anchors and terminator matches never fire.
    CMD="${CMD//$'\n'/ }"; CMD="${CMD//$'\r'/ }"; CMD="${CMD//$'\t'/ }"
    # Match TARGETS, not content: heredoc bodies and `-m` messages are stripped so
    # a command that merely NAMES the directory is allowed. Over-blocking is what
    # teaches people to reach for EXLOOM_REVIEW_SKIP.
    SCAN_CMD="$(exloom_strip_heredocs "$CMD")"
    SCAN_CMD="$(printf '%s' "$SCAN_CMD" | sed -E "s/(-m|--message=?)[[:space:]]*'[^']*'//g")"
    SCAN_CMD="$(printf '%s' "$SCAN_CMD" | sed -E 's/(-m|--message=?)[[:space:]]*"[^"]*"//g')"
    # Destroying the whole reviews tree names neither the verdicts dir nor the
    # state file, so it needs its own arm. The verb must be in COMMAND position
    # and the path must be named: `grep -rn rm .claude/reviews` is read-only, and
    # a bare-verb heuristic blocked `rm -f build.log && tar -xzf x.tgz`.
    if printf '%s' "$SCAN_CMD" | grep -Eq '[.]claude/reviews' \
       && printf '%s' "$SCAN_CMD" | grep -Eq '(^|[;&|(][[:space:]]*)(rm|mv|git[[:space:]]+(clean|checkout|restore|rm))([[:space:]]|$)'; then
      TARGET="$CMD"
    elif printf '%s' "$SCAN_CMD" | grep -Eq '(^|[;&|(][[:space:]]*)git[[:space:]]+clean([[:space:]]|$)' \
         && printf '%s' "$SCAN_CMD" | grep -Eq '(^|[[:space:]])-[a-zA-Z]*[dx]'; then
      # `git clean -fdx` removes untracked files repo-wide, which includes an
      # uncommitted checklist, state file and receipts, without naming them.
      TARGET="$CMD"
    elif ! printf '%s' "$SCAN_CMD" | grep -Eq "$VERDICT_RE"; then
      exit 0
    else
      # Reading, staging and committing receipts must keep working — only deny
      # the forms that create or change one.
      #
      # REDIRECT TARGETS, not "is there a > anywhere". Matching a bare `>` blocked
      # two read-only forms, both reported from real sessions and both dismissed
      # here once before they were reproduced:
      #
      #   ls -1 .claude/reviews/x.verdicts/ 2>/dev/null    a stderr redirect
      #   ls .claude/reviews/<branch>.verdicts/            `<branch>` contains a >
      #
      # The second is the form /review-complete literally instructs, so the
      # command told people to run something the gate refused.
      #
      # A redirect operator follows whitespace, a `&`, a digit (2>), or the start
      # of the command. Inside `<branch>` the `>` follows a letter, so it is not
      # one. `2>/dev/null` IS a redirect, and its target is /dev/null, which is
      # not a receipt.
      REDIR="$(printf '%s' "$SCAN_CMD"         | grep -oE '(^|[[:space:]]|&|[0-9])>>?[[:space:]]*[^[:space:];|&()]+'         | sed -E 's/^.*>>?[[:space:]]*//')"
      if ! printf '%s' "$REDIR" | grep -Eq "$VERDICT_RE"          && ! printf '%s' "$SCAN_CMD" | grep -Eq '(^|[^[:alnum:]_])(rm|mv|cp|tee|truncate|touch|install|dd|chmod)([^[:alnum:]_]|$)|sed[[:space:]]+[^|;]*-i|python[0-9.]*[[:space:]]+-c|perl[[:space:]]+-[a-z]*e'; then
        exit 0
      fi
      TARGET="$CMD"
    fi
    ;;
  *) exit 0 ;;
esac

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
[[ -n "$REPO_ROOT" ]] || exit 0
cd "$REPO_ROOT" || exit 0
[[ -f ".claude/exloom-gate.enabled" ]] || exit 0

cat >&2 <<EOF
exloom review gate: DENIED — cannot write a reviewer verdict receipt by hand.

Target: ${TARGET}

Receipts under .claude/reviews/<branch>.verdicts/ are written by exloom's
PostToolUse hook when a reviewer subagent actually completes. They are the only
review evidence the authoring session does not author, which is the entire reason
the gate trusts them.

To produce one, dispatch the reviewer for real:
  exloom:l1-reviewer
  exloom:adversarial-reviewer | exloom:security-auditor

Then commit the receipt alongside the checklist (git add/commit are not blocked).

Emergency bypass: set EXLOOM_REVIEW_SKIP=1 in your Claude Code session env
(settings.json "env"), then retry. It records itself in
.claude/reviews/<branch>.bypass.json — commit that with the change.
EOF
exit 2
