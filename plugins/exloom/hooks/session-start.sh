#!/usr/bin/env bash
# exloom — SessionStart hook (orientation). Says exloom exists, whether the gate
# is on here, and the one command that runs the flow. Never blocks. Kept short:
# it is injected into every session.

set -u

GATE="off — nothing blocks; run /exloom-setup to turn it on"
if git rev-parse --show-toplevel >/dev/null 2>&1; then
  ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
  [[ -f "${ROOT}/.claude/exloom-gate.enabled" ]] && \
    GATE="ON — git push is blocked until the branch's review evidence is complete"
fi

read -r -d '' MSG <<EOF || true
exloom is installed in this session. It produces the evidence a team needs to
trust a change: a spec, a plan, a mechanical proof the tests notice the change,
and reviewer receipts.

Review gate in this repo: ${GATE}

On a feature branch, run /exloom: it runs the next step (checklist, proof, smoke
test, review, fix, rulings) until the branch can be pushed. /exloom status prints
one line. For a new feature, start with exloom:brainstorming (spec) and
exloom:planning-for-handoff (plan); exloom:executing-handoff-plans builds it.

A one-line fix is a one-line fix: a review finding is a defect report, not a
design brief. Load exloom:using-exloom for which skill applies when.
EOF

if command -v jq >/dev/null 2>&1; then
  jq -n --arg c "$MSG" \
    '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$c}}'
elif command -v python3 >/dev/null 2>&1; then
  MSG="$MSG" python3 -c 'import json,os
print(json.dumps({"hookSpecificOutput":{"hookEventName":"SessionStart",
  "additionalContext":os.environ["MSG"]}}))'
fi
exit 0
