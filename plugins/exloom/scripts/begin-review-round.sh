#!/usr/bin/env bash
# exloom — begin-review-round.sh
#
# Writes the token that authorises a reviewer dispatch, after verifying the
# author-side checks pass. `/review-complete` runs this before it dispatches;
# hooks/require-command-dispatch.sh refuses any reviewer dispatch without a valid
# token, so this is the only route to a review.
#
# WHY A TOKEN AT ALL. Nothing distinguished a `/review-complete` dispatch from a
# hand-written `Agent(subagent_type: "exloom:l1-reviewer", prompt: <my own brief>)`
# — both produced an identical receipt, so exloom recorded hand-rolling as
# compliance. Measured across these repos: 7 of 676 checklists have any receipt at
# all. Three agents asked why they hand-dispatched gave the same answer: "I thought
# my briefs were better than the agents' own." One did it forty times across twelve
# rounds. What that throws away is not style — it is tier derivation from the diff
# and per-receipt staleness tracking, so reviewers get dispatched against commits
# that have already moved and re-run when they were already current.
#
# WHY THE CHECKS RUN FIRST. Three review rounds on this plugin returned ~50
# findings; roughly 60% were things a script finds. Contract tests written on round
# three reproduced five of them the moment they existed. A reviewer that spends
# round one on a broken path or an unenforced placeholder is a round you pay for
# and learn nothing from. So: everything mechanical must pass before a human-shaped
# reviewer is asked to look.
#
# Usage: begin-review-round.sh [--focus "<what this round should concentrate on>"]
#                             [--skip-checks]   # records WHY in the token, audited
#
# Exit 0 and the token is written; exit 1 and no reviewer can be dispatched.

set -u

FOCUS=""; SKIP_CHECKS=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --focus)       FOCUS="${2:-}"; shift 2 ;;
    --skip-checks) SKIP_CHECKS=1; shift ;;
    *) echo "unknown argument: $1" >&2; exit 1 ;;
  esac
done

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "not a git repo" >&2; exit 1; }
cd "$ROOT" || exit 1
BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
[[ -n "$BRANCH" && "$BRANCH" != "HEAD" ]] || { echo "detached HEAD" >&2; exit 1; }
HEAD_SHA="$(git rev-parse HEAD 2>/dev/null)" || exit 1

# ---------- author-side checks ----------
# Discovered, not hardcoded: a repo declares its own in .claude/exloom-checks,
# one command per line. Absent, the well-known ones this repo ships are used.
CHECKS=()
if [[ -f ".claude/exloom-checks" ]]; then
  while IFS= read -r c; do
    c="${c%%#*}"; c="${c#"${c%%[![:space:]]*}"}"; c="${c%"${c##*[![:space:]]}"}"
    [[ -n "$c" ]] && CHECKS+=( "$c" )
  done < ".claude/exloom-checks"
else
  [[ -f scripts/validate-plugin.sh   ]] && CHECKS+=( "bash scripts/validate-plugin.sh" )
  [[ -f scripts/test-exloom-gate.sh  ]] && CHECKS+=( "bash scripts/test-exloom-gate.sh" )
  [[ -f package.json                 ]] && CHECKS+=( "npm test" )
  [[ -f gradlew                      ]] && CHECKS+=( "./gradlew check" )
  [[ -f go.mod                       ]] && CHECKS+=( "go test ./..." )
fi

FAILED=""
if [[ $SKIP_CHECKS -eq 1 ]]; then
  [[ -n "$FOCUS" ]] || { echo "--skip-checks requires --focus to record why" >&2; exit 1; }
  echo "exloom: author-side checks SKIPPED — reason recorded in the token (audit)" >&2
elif [[ ${#CHECKS[@]} -eq 0 ]]; then
  echo "exloom: no author-side checks found. Declare them in .claude/exloom-checks" >&2
  echo "        (one command per line) so reviewers are not spending round one on" >&2
  echo "        what a script would find." >&2
else
  for c in "${CHECKS[@]}"; do
    printf 'exloom: running %s ... ' "$c" >&2
    if ( eval "$c" ) >/dev/null 2>&1; then
      printf 'ok\n' >&2
    else
      printf 'FAILED\n' >&2
      FAILED="${FAILED}  - ${c}"$'\n'
    fi
  done
fi

if [[ -n "$FAILED" ]]; then
  cat >&2 <<EOF

exloom: NOT dispatching — author-side checks failed:

${FAILED}
A reviewer asked to look at a branch whose own checks fail spends the round on
findings a script already had. Fix these, then run this again.

If a check is failing for a reason unrelated to this branch, re-run with
  --skip-checks --focus "why the failure is unrelated"
and the reason is recorded in the token, where a reviewer reads it.
EOF
  exit 1
fi

# ---------- write the token ----------
VDIR=".claude/reviews/${BRANCH}.verdicts"
mkdir -p "$VDIR" 2>/dev/null || { echo "cannot create $VDIR" >&2; exit 1; }
SAFE_FOCUS="$(printf '%s' "$FOCUS" | tr -cd 'A-Za-z0-9 ._:/@=+,()-' | cut -c1-500)"
printf '{"head":"%s","checks":"%s","skipped":%s,"focus":"%s","at":"%s"}\n' \
  "$HEAD_SHA" \
  "$(printf '%s' "${CHECKS[*]:-none}" | tr -cd 'A-Za-z0-9 ._:/@=+-' | cut -c1-300)" \
  "$([[ $SKIP_CHECKS -eq 1 ]] && echo true || echo false)" \
  "$SAFE_FOCUS" \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true)" \
  >> "${VDIR}/dispatch.json" 2>/dev/null || exit 1

echo "exloom: review round authorised at ${HEAD_SHA:0:12}. Reviewer dispatch is now permitted for this commit." >&2
[[ -n "$SAFE_FOCUS" ]] && echo "exloom: focus recorded — pass it to each reviewer verbatim: ${SAFE_FOCUS}" >&2
exit 0
