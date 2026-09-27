#!/usr/bin/env bash
# exloom — PreToolUse hook on Task|Agent. Enforces the review budgets at dispatch
# and records each reviewer dispatch, so its receipt can be bound to the commit
# the reviewer was shown.
#
# OPT-IN: no-op unless `.claude/exloom-gate.enabled` exists.
# Exit 0 = allow, 2 = refuse. Bypass: EXLOOM_REVIEW_SKIP=1.

set -u

HOOK_INPUT=""
if [[ -p /dev/stdin || ! -t 0 ]]; then
  IFS= read -r -d '' HOOK_INPUT || true
fi
[[ -n "$HOOK_INPUT" ]] || exit 0

SCRIPT_DIR="${BASH_SOURCE[0]%[/\\]*}"; [[ "$SCRIPT_DIR" == "${BASH_SOURCE[0]}" ]] && SCRIPT_DIR=.
# shellcheck source=/dev/null
. "$SCRIPT_DIR/prefilter.sh"
exloom_may_be_reviewer "$HOOK_INPUT" || exit 0
# shellcheck source=/dev/null
. "$SCRIPT_DIR/lib.sh"

if [[ "${EXLOOM_REVIEW_SKIP:-0}" == "1" ]]; then
  exloom_bypass_receipt "dispatch"
  exit 0
fi

SUB="$(exloom_tool_input "$HOOK_INPUT" subagent_type)"
case "$SUB" in
  exloom:l1-reviewer)          AGENT="l1-reviewer" ;;
  exloom:adversarial-reviewer) AGENT="adversarial-reviewer" ;;
  exloom:security-auditor)     AGENT="security-auditor" ;;
  *) exit 0 ;;
esac

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
cd "$REPO_ROOT" || exit 0
[[ -f ".claude/exloom-gate.enabled" ]] || exit 0
BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)" || exit 0
exloom_is_protected_branch "$BRANCH" && exit 0
exloom_is_skip_branch "$BRANCH" && exit 0
HEAD_SHA="$(git rev-parse HEAD 2>/dev/null)" || exit 0

PROMPT="$(exloom_tool_input "$HOOK_INPUT" prompt)"
FIRST="$(printf '%s\n' "$PROMPT" | sed -n '/[^[:space:]]/{p;q;}')"
TUID="$(exloom_json_field "$HOOK_INPUT" tool_use_id | tr -cd 'A-Za-z0-9_-')"
TASK="$(printf '%s' "$FIRST" | sed -nE 's/^(Review|Verify fixes for) task[[:space:]]*([A-Za-z0-9.-]*).*/\2/p')"
KEY="final"; [[ -n "$TASK" ]] && KEY="task:${TASK}"
KIND="review"; [[ "$FIRST" == "Verify fixes"* ]] && KIND="verify"

CHECKLIST=".claude/reviews/${BRANCH}.md"
VDIR="$(exloom_verdict_dir "$CHECKLIST")"
DLOG="${VDIR}/dispatches.jsonl"
mkdir -p "$VDIR" 2>/dev/null || exit 0

# A dispatch counts once it launched (PostToolUse mapped it); a denied or failed one does not.
prior() {
  local t n=0
  while IFS= read -r t; do
    if [[ -z "$t" ]] || grep -qF "\"map\":true,\"tool_use_id\":\"${t}\"" "$DLOG"; then n=$((n + 1)); fi
  done < <(grep -F "\"agent\":\"${AGENT}\",\"key\":\"${KEY}\",\"kind\":\"$1\"" "$DLOG" 2>/dev/null \
             | sed -n 's/.*"tool_use_id":"\([^"]*\)".*/\1/p')
  echo "$n"
}
REASON=""
MAX="$(exloom_max_rounds)"
if [[ "$KIND" == "review" && "$(prior review)" -ge 1 ]]; then
  if [[ "$KEY" == "final" ]]; then
    REASON="${AGENT} has already run its whole-branch review. Re-dispatch it only in verify mode, once."
  else
    REASON="task ${TASK} has already been reviewed by ${AGENT}. Re-dispatch it only in verify mode."
  fi
elif [[ "$KIND" == "verify" && "$KEY" == "final" && "$(prior verify)" -ge 1 ]]; then
  REASON="the final review gets one fix wave and one scoped re-review, and ${AGENT} has had it."
elif [[ "$KIND" == "verify" && "$KEY" != "final" && "$(prior verify)" -ge "$MAX" ]]; then
  REASON="task ${TASK} has used its ${MAX} fix rounds with ${AGENT}."
fi

START="$(grep -F '"key":"final"' "$DLOG" 2>/dev/null | sed -n 's/.*"dispatch_head":"\([0-9a-f]\{40\}\)".*/\1/p' | head -1)"
if [[ -z "$REASON" && "$KEY" == "final" && -n "$START" ]] && git cat-file -e "${START}^{commit}" 2>/dev/null; then
  lines() { git diff --numstat "$1" "$2" -- . ':(exclude).claude' 2>/dev/null | awk '{a+=$1+$2} END{print a+0}'; }
  FORK="$(exloom_fork_point "$START" 2>/dev/null || true)"
  SIZE=0; [[ -n "$FORK" ]] && SIZE="$(lines "$FORK" "$START")"
  GROWTH="$(lines "$START" "$HEAD_SHA")"
  LIMIT=$(( SIZE / 2 )); [[ $LIMIT -lt 100 ]] && LIMIT=100
  if [[ "$GROWTH" -gt "$LIMIT" ]]; then
    REASON="the branch has grown by ${GROWTH} changed lines since review started (limit ${LIMIT}). Fixes are exceeding the findings."
  fi
fi

EXTRA=false
if [[ -n "$REASON" ]]; then
  granted="$(grep -cE '^- Extra round[[:space:]]*—[[:space:]]*[^[:space:]]' "$CHECKLIST" 2>/dev/null)"
  used="$(grep -c '"extra":true' "$DLOG" 2>/dev/null)"
  if [[ "${granted:-0}" -gt "${used:-0}" ]]; then
    EXTRA=true
    echo "exloom: dispatch allowed by an 'Extra round' line in ${CHECKLIST} ($((used + 1)) of ${granted})." >&2
  else
    cat >&2 <<EOF
exloom: reviewer dispatch REFUSED — ${REASON}

Another round is not how this review ends. Rule on each open finding under
'## Rulings' in ${CHECKLIST} (PARKED, DEFERRED <ticket>, or FIXED), and the
gate accepts the REJECTED receipt. If the user wants another round anyway, ask
them, record their answer under '## Rulings' as
  - Extra round — "<their words>"
and dispatch again. Do not write that line unless they said it.
EOF
    exit 2
  fi
fi

HASH="$(printf '%s' "$PROMPT" | git hash-object --stdin 2>/dev/null)"
STAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true)"
printf '{"agent":"%s","key":"%s","kind":"%s","tool_use_id":"%s","dispatch_head":"%s","prompt_hash":"%s","extra":%s,"at":"%s"}\n' \
  "$AGENT" "$KEY" "$KIND" "$TUID" "$HEAD_SHA" "$HASH" "$EXTRA" "$STAMP" >> "$DLOG" 2>/dev/null
exit 0
