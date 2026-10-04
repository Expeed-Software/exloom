#!/usr/bin/env bash
# exloom — PreToolUse hook on Bash. While a review has REJECTED findings with no
# ruling, code is committed by exloom:fixer, not by the main session. A subagent's
# payload carries agent_id; the main session's does not.
#
# OPT-IN: no-op unless `.claude/exloom-gate.enabled` exists.
# Exit 0 = allow, 2 = refuse. Bypass: EXLOOM_REVIEW_SKIP=1.

set -u

HOOK_INPUT=""
if [[ -p /dev/stdin || ! -t 0 ]]; then
  IFS= read -r -d '' HOOK_INPUT || true
fi
case "$HOOK_INPUT" in *commit*) ;; *) exit 0 ;; esac
[[ "${EXLOOM_REVIEW_SKIP:-0}" == "1" ]] && exit 0
case "$HOOK_INPUT" in *'"agent_id"'*) exit 0 ;; esac

SCRIPT_DIR="${BASH_SOURCE[0]%[/\\]*}"; [[ "$SCRIPT_DIR" == "${BASH_SOURCE[0]}" ]] && SCRIPT_DIR=.
# shellcheck source=/dev/null
. "$SCRIPT_DIR/lib.sh"

CMD="$(exloom_tool_input "$HOOK_INPUT" command)"
printf '%s' "$CMD" | grep -Eq '(^|[;&|(][[:space:]]*)git([[:space:]]+-[^[:space:]]+([[:space:]]+[^-][^[:space:]]*)?)*[[:space:]]+commit([[:space:]]|$)' || exit 0

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
cd "$REPO_ROOT" || exit 0
[[ -f ".claude/exloom-gate.enabled" ]] || exit 0
BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)" || exit 0
exloom_is_protected_branch "$BRANCH" && exit 0

# Only code counts; review files are the session's to commit.
code="$(git diff --cached --name-only -- . ':(exclude).claude' 2>/dev/null)"
if printf '%s' "$CMD" | grep -Eq '(^|[[:space:]])(-a|--all|-[a-zA-Z]*a[a-zA-Z]*)([[:space:]]|$)'; then
  code="${code}$(git diff --name-only -- . ':(exclude).claude' 2>/dev/null)"
fi
[[ -n "$code" ]] || exit 0

CL=".claude/reviews/${BRANCH}.md"
VDIR="$(exloom_verdict_dir "$CL")"
latest="$(cat "$VDIR"/*.json 2>/dev/null | grep -F '"verdict":' | grep -F '"at":"' \
  | sed -n 's/.*"at":"\([^"]*\)".*/\1 &/p' | sort | tail -1 | cut -d' ' -f2-)"
[[ "$latest" == *'"verdict":"REJECTED"'* ]] || exit 0
agent="$(printf '%s' "$latest" | sed -n 's/.*"agent":"\([a-z0-9-]*\)".*/\1/p')"
head="$(printf '%s' "$latest" | sed -n 's/.*"head":"\([0-9a-f]*\)".*/\1/p')"
open="$(_exloom_unruled_findings "$CL" HEAD "$agent" "$head" 0)"; rc=$?
[[ $rc -eq 1 ]] || exit 0

cat >&2 <<EOF
exloom: refused — ${agent} rejected ${head:0:12} and these findings have no ruling:
$(printf '%s\n' "$open" | sed 's/^/  /')
During the fix loop the fix is made by exloom:fixer, not this session: dispatch it
with the findings verbatim (see /review-complete). Commit review files under
.claude/ on their own; rulings under '## Rulings' close findings without a fix.
EOF
exit 2
