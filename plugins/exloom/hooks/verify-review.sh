#!/usr/bin/env bash
# exloom — Stop hook (review gate).
#
# OPT-IN: does nothing unless the repo created `.claude/exloom-gate.enabled`.
# When enabled: fires on a stop; if the last assistant message asserts done /
# complete / ready, verifies `.claude/reviews/<branch>.md` is complete and bound
# to the code. Shared validation logic lives in lib.sh (identical to the push
# hook — no drift).
#
# NOTE (honest limitation): this is a best-effort *advisory* nudge. It infers a
# done-claim by phrase-matching the last message, which is inherently unreliable —
# phrasings like "wrapped up" or simply stopping without a summary will not fire
# it. The push gate (block-unverified-push.sh) is the load-bearing check; this one
# just catches the common "it's done" claim before you move on.
#
# Exit codes:
#   0  — allow (gate off, not a done-claim, checklist complete, protected branch,
#              or any infrastructure parse failure — never block on infra)
#   2  — block with stderr message
#
# Bypass (when enabled): EXLOOM_REVIEW_SKIP=1

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=/dev/null
. "$SCRIPT_DIR/lib.sh"

# ---------- bypass ----------
if [[ "${EXLOOM_REVIEW_SKIP:-0}" == "1" ]]; then
  echo "exloom: review gate bypass via EXLOOM_REVIEW_SKIP=1 (audit)" >&2
  exit 0
fi

# ---------- read hook input ----------
HOOK_INPUT=""
if [[ -p /dev/stdin || ! -t 0 ]]; then
  HOOK_INPUT="$(cat 2>/dev/null || true)"
fi

# ---------- extract transcript_path ----------
# (sed fallback resolves POSIX paths; Windows paths arrive escaped and won't
# resolve — on Windows install jq or python3 for the Stop hook. The push gate is
# the primary enforcement and matches common push/PR forms even without them.)
TRANSCRIPT_PATH="$(exloom_json_field "$HOOK_INPUT" transcript_path)"
if [[ -z "$TRANSCRIPT_PATH" ]] || [[ ! -f "$TRANSCRIPT_PATH" ]]; then
  exit 0
fi

# ---------- extract last assistant message text from JSONL ----------
LAST_MSG=""
if command -v jq >/dev/null 2>&1; then
  LAST_MSG="$(tail -n 200 "$TRANSCRIPT_PATH" 2>/dev/null \
    | jq -rs '
        [ .[] | select((.type // .role // "") == "assistant") ] | last // empty
        | (.message.content // .content // [])
        | if type=="string" then .
          elif type=="array" then (map(select(.type=="text") | .text) | join(" "))
          else "" end
      ' 2>/dev/null || true)"
elif command -v python3 >/dev/null 2>&1; then
  LAST_MSG="$(tail -n 200 "$TRANSCRIPT_PATH" 2>/dev/null | python3 -c '
import json, sys
last = None
for line in sys.stdin:
    line=line.strip()
    if not line: continue
    try: d=json.loads(line)
    except Exception: continue
    if (d.get("type") or d.get("role") or "") == "assistant":
        last = d
if not last:
    sys.exit(0)
msg = last.get("message", last)
content = msg.get("content") if isinstance(msg, dict) else None
if isinstance(content, str):
    print(content)
elif isinstance(content, list):
    parts=[b.get("text","") for b in content if isinstance(b,dict) and b.get("type")=="text"]
    print(" ".join(parts))
' 2>/dev/null || true)"
fi

[[ -z "$LAST_MSG" ]] && exit 0

# ---------- done-claim detection (best-effort; see header note) ----------
DONE_PHRASES='\b(all done|work is (now )?(complete|done|ready)|feature is (ready|complete|shipped)|implementation is complete|ready to merge|ready to ship|ready to push|safe to merge|safe to ship|good to merge|good to ship|good to go|you.?re good to go|marking (this|it) (done|complete)|task complete|phase complete|plan complete|APPROVED for merge|ready to deploy|wrapped (this |it )?up|all wrapped up|that.?s (it,? (that.?s )?finished|finished|done)|this is (done|complete|finished|ready to ship)|it.?s (all )?(done|complete|finished)|finished (the |implementing |building ))\b'
printf '%s' "$LAST_MSG" | grep -Eiq "$DONE_PHRASES" || exit 0

# ---------- repo + opt-in ----------
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
[[ -z "$REPO_ROOT" ]] && exit 0
cd "$REPO_ROOT" || exit 0
[[ -f ".claude/exloom-gate.enabled" ]] || exit 0

BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
exloom_is_protected_branch "$BRANCH" && exit 0
exloom_is_skip_branch "$BRANCH" && exit 0

# ---------- shared checklist verification ----------
exloom_validate_checklist ".claude/reviews/${BRANCH}.md" "HEAD" 1 "mark this work complete" || exit 2

exit 0
