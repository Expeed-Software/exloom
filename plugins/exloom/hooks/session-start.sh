#!/usr/bin/env bash
# exloom — SessionStart hook (orientation).
#
# Says exloom exists, names the flow, and reports whether the gate is on HERE.
# Orientation only: it adds context, never blocks.
#
# Kept deliberately short. Injecting a whole skill here would cost kilobytes of
# context in every session, and injecting nothing leaves the workflow invisible —
# a session would only find it by loading a skill whose trigger description
# happened to match what the user typed, and "add a field to the order form"
# matches none of them. These few lines carry the one thing a session cannot
# infer: that this repo has a gate, and what the sequence is.

set -u

GATE="off — nothing blocks; the skills and commands still work when you ask for them"
if git rev-parse --show-toplevel >/dev/null 2>&1; then
  ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
  [[ -f "${ROOT}/.claude/exloom-gate.enabled" ]] && \
    GATE="ON — git push is blocked until .claude/reviews/<branch>.md is complete"
fi

read -r -d '' MSG <<EOF || true
exloom is installed in this session. It produces the evidence a team needs to
trust a change: a spec, a plan, a mechanical proof the tests notice the change,
and reviewer receipts.

Review gate in this repo: ${GATE}

The flow for a feature, start to finish:

  1. exloom:brainstorming            spec — what and why
  2. exloom:planning-for-handoff     plan — files, tasks, acceptance criteria
  3. exloom:isolating-execution      feature branch (the gate skips protected branches)
  4. /review-init                    checklist + tier
  5. exloom:executing-handoff-plans  build it — not more, not less; log deviations
  6. prove-change-is-tested.sh       proof the tests fail without the change
  7. exloom:auditing-plan-fidelity   diff vs plan; report drift
  8. /smoke-test                     run it; paste what you saw
  9. /review-complete                dispatch reviewers, fix, mark complete
  10. git push / open the PR

Small changes skip 1-2 and start at 3. A one-line fix is a one-line fix: a review
finding is a defect report, not a design brief.

Load exloom:using-exloom for which skill applies when.
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
