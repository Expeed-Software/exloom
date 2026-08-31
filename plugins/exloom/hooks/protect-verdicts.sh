#!/usr/bin/env bash
# exloom — PreToolUse hook (verdict receipt protection).
#
# OPT-IN: does nothing unless the repo created `.claude/exloom-gate.enabled`.
#
# Verdict receipts under `.claude/reviews/<branch>.verdicts/` are the only review
# evidence exloom does not let the authoring session author. They are written by
# record-reviewer-verdict.sh when a reviewer subagent actually completes. This
# hook denies direct writes to that directory, so the difference between "a
# reviewer ran" and "a reviewer did not run" cannot be closed by writing a file.
#
# Without this, receipts are just another author-written artifact and buy nothing
# over the checkbox they replace.
#
# Exit codes:
#   0  — allow (gate off, path not a receipt, or any infrastructure parse failure)
#   2  — deny with stderr message
#
# Bypass (when enabled): EXLOOM_REVIEW_SKIP=1
#
# Known limit, stated plainly: this matches the direct file-writing tools and the
# obvious shell write forms. A deliberately obfuscated shell command can still
# reach the directory, exactly as with the push gate. exloom is a cooperating-team
# gate, not an adversarial security boundary — the goal is that forging a receipt
# has to be a deliberate act, not the path of least resistance.

set -u

if [[ "${EXLOOM_REVIEW_SKIP:-0}" == "1" ]]; then
  echo "exloom: verdict-receipt protection bypassed via EXLOOM_REVIEW_SKIP=1 (audit)" >&2
  exit 0
fi

HOOK_INPUT=""
if [[ -p /dev/stdin || ! -t 0 ]]; then
  HOOK_INPUT="$(cat 2>/dev/null || true)"
fi
[[ -n "$HOOK_INPUT" ]] || exit 0

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=/dev/null
. "$SCRIPT_DIR/lib.sh"

TOOL="$(exloom_json_field "$HOOK_INPUT" tool_name)"

# Pull a nested tool_input string field. The shared sed fallback truncates at the
# first quote, which is fine for a path but not for a shell command — the command
# path falls back to the raw hook input instead (same approach as the push gate).
_tool_input() {
  local key="$1" out=""
  if command -v jq >/dev/null 2>&1; then
    out="$(printf '%s' "$HOOK_INPUT" | jq -r --arg k "$key" '.tool_input[$k] // empty' 2>/dev/null || true)"
  fi
  if [[ -z "$out" ]] && command -v python3 >/dev/null 2>&1; then
    out="$(printf '%s' "$HOOK_INPUT" | KEY="$key" python3 -c '
import json, os, sys
try:
    v = (json.load(sys.stdin).get("tool_input") or {}).get(os.environ["KEY"], "")
    print(v if isinstance(v, str) else "")
except Exception:
    pass' 2>/dev/null || true)"
  fi
  printf '%s' "$out"
}

# `.verdicts/` is distinctive enough to match on its own; requiring the full
# `.claude/reviews/` prefix would miss an absolute path on Windows, where the
# separator is a backslash.
# Matches the verdicts dir, the review STATE file, and the reviews directory
# itself. The state file was writable with the Edit tool, which lifted a review
# freeze without a record and reset the round counter — the one number the
# feature exists to surface. And `rm -rf .claude/reviews` / `git clean -fdx`
# contain no `.verdicts` substring, so both destroyed every receipt unopposed.
# `exloom-gate.enabled` is included deliberately: it is the switch that decides
# whether any hook runs at all. A session that can delete it can disable the gate
# silently, which makes every other protection here decorative.
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
    CMD="${CMD//$'\n'/ }"; CMD="${CMD//$'\t'/ }"
    # Match TARGETS, not content. This guard matches on command text, so a command
    # that merely MENTIONS the guarded directory was denied as an attempt to forge a
    # receipt. It blocked a comment being written into this hook's own source, then
    # blocked the commit message that documented the block. Any session working on
    # exloom hits it, as does any repo whose documentation names the directory — and
    # an over-block is exactly what makes people reach for EXLOOM_REVIEW_SKIP.
    #
    # Two forms carry CONTENT rather than a target, and both are stripped first:
    #   - a heredoc body: everything from `<<` onward. Real targets appear BEFORE the
    #     heredoc (`cat > path <<EOF`), so stripping the body keeps them.
    #   - a commit message: `-m "..."` or `--message=...`.
    # A quoted target still matches: only these two forms are removed.
    SCAN_CMD="${CMD%%<<*}"
    SCAN_CMD="$(printf '%s' "$SCAN_CMD" | sed -E "s/(-m|--message=?)[[:space:]]*'[^']*'//g")"
    SCAN_CMD="$(printf '%s' "$SCAN_CMD" | sed -E 's/(-m|--message=?)[[:space:]]*"[^"]*"//g')"
    # Destruction of the reviews tree names neither the verdicts dir nor the state
    # file, so it passed both checks below. Reproduced as ALLOWED: `rm -rf
    # .claude/reviews`, `mv .claude/reviews /tmp`, `git checkout -- .claude/reviews`.
    # All three destroy every receipt, the round counter and the findings ledger.
    #
    # The verb must be in COMMAND position: `grep -rn rm .claude/reviews` merely
    # mentions `rm` as an argument and is read-only.
    # Requires the path to be NAMED, deliberately. An earlier version matched a bare
    # `rm` plus a loose flag heuristic and blocked `rm -f build.log && tar -xzf x.tgz`
    # — over-blocking is what teaches people to reach for the bypass.
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
      printf '%s' "$SCAN_CMD" | grep -Eq '>>?|(^|[^[:alnum:]_])(rm|mv|cp|tee|truncate|touch|install|dd|chmod)([^[:alnum:]_]|$)|sed[[:space:]]+[^|;]*-i|python[0-9.]*[[:space:]]+-c|perl[[:space:]]+-[a-z]*e' || exit 0
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
  exloom:l1-reviewer | exloom:cross-layer-auditor
  exloom:adversarial-reviewer | exloom:security-auditor

Then commit the receipt alongside the checklist (git add/commit are not blocked).

Emergency bypass (audited): set EXLOOM_REVIEW_SKIP=1 in your Claude Code session
env (settings.json "env"), then retry.
EOF
exit 2
