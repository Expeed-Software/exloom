#!/usr/bin/env bash
# exloom — SessionStart hook (activation)
#
# Injects the using-exloom meta-skill at the start of a session so exloom's
# skills are discoverable from the first turn. This is orientation only — it
# adds context, it never blocks. (The review gate is a separate, opt-in hook.)
#
# Fires on: startup | clear | compact.

set -u

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGIN_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SKILL_FILE="${PLUGIN_ROOT}/skills/using-exloom/SKILL.md"

[[ -f "$SKILL_FILE" ]] || exit 0

CONTENT="$(cat "$SKILL_FILE" 2>/dev/null || true)"
[[ -n "$CONTENT" ]] || exit 0

WRAPPED="You have exloom — a team-oriented development workflow. The using-exloom skill below tells you which skill to use when. For every other skill, use the Skill tool.

${CONTENT}"

# Emit Claude Code SessionStart context injection. Prefer jq for safe JSON
# encoding; fall back to python3; if neither exists, do nothing (never break the
# session over an infra gap).
if command -v jq >/dev/null 2>&1; then
  jq -n --arg c "$WRAPPED" \
    '{hookSpecificOutput: {hookEventName: "SessionStart", additionalContext: $c}}'
elif command -v python3 >/dev/null 2>&1; then
  CONTENT_ENV="$WRAPPED" python3 -c '
import json, os
print(json.dumps({"hookSpecificOutput": {"hookEventName": "SessionStart",
      "additionalContext": os.environ.get("CONTENT_ENV","")}}))'
fi
exit 0
