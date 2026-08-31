#!/usr/bin/env bash
# exloom — PreToolUse hook (review gate).
#
# OPT-IN: does nothing unless the repo created `.claude/exloom-gate.enabled`.
# When enabled, intercepts `git push`, `gh pr create`, and the GitHub MCP
# publish/PR tools; blocks (exit 2) if the review checklist for the branch being
# pushed is missing, incomplete, or not bound to the code. Shared validation
# logic lives in lib.sh (identical to the Stop hook — no drift).
#
# Exit codes:
#   0  — allow (gate off, not a publish action, checklist complete, protected/skip
#              branch, or any infrastructure parse failure — never block on infra)
#   2  — block with stderr message
#
# Bypass (when enabled): EXLOOM_REVIEW_SKIP=1

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=/dev/null
. "$SCRIPT_DIR/lib.sh"

# ---------- bypass ----------
if [[ "${EXLOOM_REVIEW_SKIP:-0}" == "1" ]]; then
  echo "exloom: push bypass via EXLOOM_REVIEW_SKIP=1 (audit)" >&2
  exit 0
fi

# ---------- read hook input ----------
HOOK_INPUT=""
if [[ -p /dev/stdin || ! -t 0 ]]; then
  HOOK_INPUT="$(cat 2>/dev/null || true)"
fi

# ---------- which tool fired? ----------
TOOL="$(exloom_json_field "$HOOK_INPUT" tool_name)"
IS_PUBLISH=0
CMD_MATCH=""
case "$TOOL" in
  # GitHub MCP write/PR tools (any server-name prefix). The tool call IS the
  # publish; there is no shell command to parse — go straight to the gate.
  *push_files|*create_or_update_file|*create_pull_request|*merge_pull_request|*delete_file)
    IS_PUBLISH=1 ;;
esac

if [[ "$IS_PUBLISH" -eq 0 ]]; then
  # Treat as a Bash command; match git push / gh pr create. The command may
  # contain quotes, so the sed fallback (which truncates at the first quote) is
  # unsafe here — fall back to the RAW hook input instead.
  CMD=""
  if command -v jq >/dev/null 2>&1; then
    CMD="$(printf '%s' "$HOOK_INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
  fi
  if [[ -z "$CMD" ]] && command -v python3 >/dev/null 2>&1; then
    CMD="$(printf '%s' "$HOOK_INPUT" | python3 -c 'import json,sys
try:
    d=json.load(sys.stdin)
    print((d.get("tool_input") or {}).get("command",""))
except Exception:
    pass' 2>/dev/null || true)"
  fi
  [[ -z "$CMD" ]] && CMD="$HOOK_INPUT"
  # Collapse newlines/tabs so a multi-line command still matches on one line.
  # (A backslash line-continuation can still evade this — documented limit; the
  # gate is a cooperating-team tool, not an obfuscation-proof boundary.)
  CMD_MATCH="${CMD//$'\n'/ }"; CMD_MATCH="${CMD_MATCH//$'\r'/ }"; CMD_MATCH="${CMD_MATCH//$'\t'/ }"
  # git push (allowing git global options) or gh pr create. Trailing boundary is
  # any non-word char or end-of-string, so `git push;`, `cd x && git push`,
  # `(git push)` all match; `git pushx` does not.
  if printf '%s' "$CMD_MATCH" | grep -Eq '(^|[^[:alnum:]_])git([[:space:]]+(-C|-c)[[:space:]]+[^[:space:]]+|[[:space:]]+-[^[:space:]]+)*[[:space:]]+push([^[:alnum:]_]|$)|(^|[^[:alnum:]_])gh[[:space:]]+pr[[:space:]]+create([^[:alnum:]_]|$)'; then
    IS_PUBLISH=1
  fi
fi

[[ "$IS_PUBLISH" -eq 0 ]] && exit 0

# ---------- repo + opt-in ----------
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
[[ -z "$REPO_ROOT" ]] && exit 0
cd "$REPO_ROOT" || exit 0
[[ -f ".claude/exloom-gate.enabled" ]] || exit 0

CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"

# ---------- which branch(es) does this push ship? ----------
# Only a parsed `git push` yields explicit targets; gh pr create / MCP publish
# tools ship the current branch.
declare -a VBRANCHES=()
TARGETS=""
[[ -n "$CMD_MATCH" ]] && TARGETS="$(exloom_push_target_branches "$CMD_MATCH")"
if [[ -z "$TARGETS" ]]; then
  VBRANCHES=( "$CURRENT_BRANCH" )
else
  while IFS= read -r tb; do
    [[ -z "$tb" || "$tb" == "__DELETE__" ]] && continue
    [[ "$tb" == "HEAD" ]] && tb="$CURRENT_BRANCH"
    VBRANCHES+=( "$tb" )
  done <<< "$TARGETS"
  # An all-deletion push ships no code.
  [[ ${#VBRANCHES[@]} -eq 0 ]] && exit 0
fi

# ---------- validate each branch being pushed ----------
for br in "${VBRANCHES[@]}"; do
  exloom_is_protected_branch "$br" && continue
  exloom_is_skip_branch "$br" && continue
  if [[ "$br" == "$CURRENT_BRANCH" ]]; then
    exloom_validate_checklist ".claude/reviews/${br}.md" "HEAD" 1 "push / open a PR for '$br'" || exit 2
  else
    # Pushing a branch other than the one checked out — validate ITS committed
    # checklist against ITS tip, from the ref (its working tree isn't present).
    exloom_validate_checklist ".claude/reviews/${br}.md" "refs/heads/${br}" 0 "push / open a PR for '$br'" || exit 2
  fi
done

exit 0
