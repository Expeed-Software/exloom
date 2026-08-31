#!/usr/bin/env bash
# exloom — PreToolUse hook (reviewer dispatch must come through the command).
#
# OPT-IN: does nothing unless the repo created `.claude/exloom-gate.enabled`.
#
# WHY THIS EXISTS. A hand-written `Agent(subagent_type: "exloom:l1-reviewer",
# prompt: <my own brief>)` and a dispatch made by `/review-complete` produced
# byte-identical receipts. exloom could not tell them apart, so hand-rolling was not
# a deviation the gate could see — it WAS compliance, as far as the machine was
# concerned. Measured across these repos: 7 of 676 checklists carry any receipt.
#
# Three separate sessions, asked why they hand-dispatched, gave the same answer:
# "I thought my briefs were better than the agents' own." One did it forty times
# across twelve rounds. The author of this hook did it six times in one day, with
# the rule against it loaded in context the whole time.
#
# What it costs is not style. `/review-complete` derives the tier from the diff
# instead of the author guessing it, and tracks which receipt covers which SHA so
# only stale reviewers re-run. Hand-dispatching threw both away: two rounds were
# spent reviewing commits that had already moved, and reviewers were re-run when
# they were already current. On this very branch, two of four required reviewers
# were never dispatched at all for two whole rounds, because the author picked them
# by hand — and the two skipped ones found the largest defect class in the change.
#
# THE BLOCK MUST CARRY A WORKING ALTERNATIVE. A gate that refuses without one is
# how EXLOOM_REVIEW_SKIP becomes routine, so the message names the exact command,
# resolved to a real path, and `--focus` exists precisely because "my brief was
# better" is the reason people go around it.
#
# Exit codes: 0 allow, 2 block. Fails OPEN on any infrastructure error.
# Bypass (audited): EXLOOM_REVIEW_SKIP=1

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

if [[ "${EXLOOM_REVIEW_SKIP:-0}" == "1" ]]; then
  echo "exloom: dispatch gate bypassed via EXLOOM_REVIEW_SKIP=1 (audit)" >&2
  exit 0
fi

HOOK_INPUT=""
if [[ -p /dev/stdin || ! -t 0 ]]; then
  HOOK_INPUT="$(cat 2>/dev/null || true)"
fi
[[ -n "$HOOK_INPUT" ]] || exit 0

_f() {
  printf '%s' "$HOOK_INPUT" \
    | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -1
}

TOOL="$(_f tool_name)"
case "$TOOL" in Task|Agent|task|agent) ;; *) exit 0 ;; esac

SUBAGENT="$(_f subagent_type)"
case "$SUBAGENT" in
  *l1-reviewer|*cross-layer-auditor|*adversarial-reviewer|*security-auditor|*plan-reviewer) ;;
  *) exit 0 ;;   # not an exloom reviewer: not this hook's business
esac

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
cd "$REPO_ROOT" || exit 0
[[ -f ".claude/exloom-gate.enabled" ]] || exit 0

BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)" || exit 0
[[ -n "$BRANCH" && "$BRANCH" != "HEAD" ]] || exit 0
HEAD_SHA="$(git rev-parse HEAD 2>/dev/null)" || exit 0

TOKEN=".claude/reviews/${BRANCH}.verdicts/dispatch.json"
if [[ -f "$TOKEN" ]] && grep -qF "\"head\":\"${HEAD_SHA}\"" "$TOKEN" 2>/dev/null; then
  FOCUS="$(grep -F "\"head\":\"${HEAD_SHA}\"" "$TOKEN" | tail -1 \
           | sed -n 's/.*"focus":"\([^"]*\)".*/\1/p')"
  [[ -n "$FOCUS" ]] && echo "exloom: dispatching under recorded focus — ${FOCUS}" >&2
  exit 0
fi

cat >&2 <<EOF
exloom review gate: BLOCKED — dispatch reviewers through /review-complete, not by hand.

Agent requested: ${SUBAGENT}
Commit:          ${HEAD_SHA:0:12}
No dispatch token covers this commit.

A hand-written dispatch produces a receipt identical to a command-issued one, so
exloom cannot tell them apart — which is why hand-rolling has never registered as a
deviation. What it actually costs:

  - the TIER is guessed instead of derived from the diff, so required reviewers get
    skipped (on this plugin's own branch, two of four never ran for two rounds, and
    the two skipped ones found the largest defect class in the change);
  - per-receipt STALENESS is lost, so reviewers are dispatched against commits that
    have already moved, and re-run when they were already current.

Run this instead — it runs the author-side checks first, then authorises dispatch:

    bash "$SCRIPT_DIR/../scripts/begin-review-round.sh"

If you want this round pointed at something specific — which is the usual reason
for writing a brief by hand — pass it, and every reviewer receives it verbatim:

    bash "$SCRIPT_DIR/../scripts/begin-review-round.sh" --focus "concentrate on X"

Then dispatch, or let /review-complete dispatch for you.

Emergency bypass (audited): set EXLOOM_REVIEW_SKIP=1 in your Claude Code session
env (settings.json "env"), then retry.
EOF
exit 2
