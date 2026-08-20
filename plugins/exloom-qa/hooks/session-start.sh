#!/usr/bin/env bash
# exloom-qa — SessionStart hook (activation)
#
# Injects the using-exloom-qa meta-skill so the QA skills are discoverable from
# the first turn. Orientation only — it adds context, it never blocks. The
# publish gate is a separate PreToolUse hook.
#
# Fires on: startup | clear | compact.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SKILL_FILE="${PLUGIN_ROOT}/skills/using-exloom-qa/SKILL.md"

[[ -f "$SKILL_FILE" ]] || exit 0

CONTENT="$(cat "$SKILL_FILE" 2>/dev/null || true)"
[[ -n "$CONTENT" ]] || exit 0

WRAPPED="You have exloom-qa — a QA workflow that turns a user story into reviewed, human-executable manual test cases. The using-exloom-qa skill below tells you which skill to use when. For every other skill, use the Skill tool.

${CONTENT}"

# Resolve Python by execution, not by name — see lib.sh for why `python3` cannot
# be trusted on Windows.
PY=""
for candidate in python3 python; do
  if command -v "$candidate" >/dev/null 2>&1 && [[ "$("$candidate" -c 'print(1)' 2>/dev/null)" == "1" ]]; then
    PY="$candidate"; break
  fi
done

if command -v jq >/dev/null 2>&1; then
  jq -n --arg c "$WRAPPED" \
    '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $c}}'
elif [[ -n "$PY" ]]; then
  CONTENT_ENV="$WRAPPED" "$PY" -c '
import json, os
print(json.dumps({"hookSpecificOutput": {"hookEventName": "SessionStart",
      "additionalContext": os.environ.get("CONTENT_ENV","")}}))'
fi
exit 0
