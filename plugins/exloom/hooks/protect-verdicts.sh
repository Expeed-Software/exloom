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
VERDICT_RE='\.verdicts[/\\]'

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
    printf '%s' "$CMD" | grep -Eq "$VERDICT_RE" || exit 0
    # Reading, staging and committing receipts must keep working — only deny the
    # forms that create or change one.
    printf '%s' "$CMD" | grep -Eq '>>?|(^|[^[:alnum:]_])(rm|mv|cp|tee|truncate|touch|install|dd|chmod)([^[:alnum:]_]|$)|sed[[:space:]]+[^|;]*-i|python[0-9.]*[[:space:]]+-c|perl[[:space:]]+-[a-z]*e' || exit 0
    TARGET="$CMD"
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
