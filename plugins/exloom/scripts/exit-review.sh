#!/usr/bin/env bash
# exloom — exit-review.sh
#
# Leaves REVIEW and returns the branch to DEVELOPMENT so source edits are allowed
# again. This is deliberately an explicit, recorded act rather than something that
# happens by itself: the whole point of the review state is that "I am now writing
# code in response to a review" is a decision someone makes, not a thing that
# quietly happens between two tool calls.
#
# The round counter is never reset. A branch that has entered review nine times
# says so permanently, and that number is the cheapest early warning there is.
#
# Usage: bash exit-review.sh ["reason"]

set -u

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "not a git repo" >&2; exit 1; }
cd "$ROOT" || exit 1

BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
[[ -n "$BRANCH" && "$BRANCH" != "HEAD" ]] || { echo "detached HEAD" >&2; exit 1; }

STATE_FILE=".claude/reviews/${BRANCH}.state"
[[ -f "$STATE_FILE" ]] || { echo "branch '$BRANCH' has no review state — nothing to exit." >&2; exit 0; }

CURRENT="$(sed -n 's/.*"state":"\([A-Z]*\)".*/\1/p' "$STATE_FILE" | tail -1)"
ROUND="$(sed -n 's/.*"round":\([0-9]*\).*/\1/p' "$STATE_FILE" | tail -1)"
[[ -n "$ROUND" ]] || ROUND=0

if [[ "$CURRENT" != "REVIEW" ]]; then
  echo "branch '$BRANCH' is already in DEVELOPMENT (after ${ROUND} review round(s))."
  exit 0
fi

REASON="${1:-acting on review findings}"
printf '{"state":"DEVELOPMENT","round":%s,"at":"%s","reason":"%s"}\n' \
  "$ROUND" "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true)" \
  "$(printf '%s' "$REASON" | tr -cd 'A-Za-z0-9 ._:/@=+-' | cut -c1-200)" \
  >> "$STATE_FILE"

cat <<EOF
branch '$BRANCH' left REVIEW after round ${ROUND}. Source edits are allowed again.

Before you write anything, two questions this transition exists to force:

  1. Is each thing you are about to change IN SCOPE for this branch?
     A finding the reviewer marked PRE-EXISTING is a backlog entry, not work.
     "While I'm in here" is how a bug fix becomes three features.

  2. Are you fixing the instance, or the rule?
     Fixing the instance is what makes the next round find the adjacent case.

Anything outside the branch's scope goes to the backlog. Re-dispatching reviewers
will start round $((ROUND + 1)) and freeze the artifact again.
EOF
