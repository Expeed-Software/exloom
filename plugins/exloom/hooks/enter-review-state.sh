#!/usr/bin/env bash
# exloom — PreToolUse hook (review state: freeze on dispatch).
#
# OPT-IN: does nothing unless the repo created `.claude/exloom-gate.enabled`.
#
# WHY THIS EXISTS. "A review examines a finished artifact and reports findings
# against it. The artifact is frozen. The review itself produces no code."
#
# What actually happens instead is a development loop wearing review's clothes:
# dispatch reviewers -> write new code in response -> introduce new defects ->
# dispatch again. On one real branch, the code that rounds 8 and 9 found bugs in
# was created by the round-6 and round-7 FIX COMMITS. The reviewers were not
# missing things early; the target kept moving. The author's own summary:
#
#     "The thing that ships has never actually been reviewed —
#      only its predecessor has."
#
# The control case is in the same branch: the original bug fix was present from
# round 1, was found in round 1, and produced no finding in the four rounds after.
# Stable artifact converged immediately. Moving artifact never converged.
#
# So this hook makes the state explicit and mutually exclusive:
#   DEVELOPMENT — you write code, no reviewer is running.
#   REVIEW      — artifact frozen, source edits blocked, findings accumulate.
# Leaving REVIEW is a deliberate, COUNTED transition (scripts/exit-review.sh), so
# "this branch has entered review 9 times" is visible at round 2 rather than
# discovered at round 9.
#
# NEVER blocks: this hook only records state. The blocking is done by
# block-unreviewed-execution.sh, which reads it. Always exit 0.

set -u

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
  *) exit 0 ;;
esac

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
cd "$REPO_ROOT" || exit 0
[[ -f ".claude/exloom-gate.enabled" ]] || exit 0

BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)" || exit 0
[[ -n "$BRANCH" && "$BRANCH" != "HEAD" ]] || exit 0

STATE_FILE=".claude/reviews/${BRANCH}.state"
mkdir -p "$(dirname "$STATE_FILE")" 2>/dev/null || exit 0

# ---------- is this round necessary at all? ----------
# The loop terminates on a round that returns APPROVED and requires no fix: you
# change nothing, the tip does not move, the receipts stay valid, you ship. The
# failure was never that the exit does not exist — it is that nobody is told when
# they have reached it, so they run another round, it surfaces more cosmetics, and
# those get treated as work.
#
# "Three full rounds of four reviewers on one story. Each round found more, most of
# it cosmetic, and I kept chasing it."
HEAD_NOW="$(git rev-parse HEAD 2>/dev/null || true)"
VDIR=".claude/reviews/${BRANCH}.verdicts"
if [[ -n "$HEAD_NOW" && -d "$VDIR" ]]; then
  approved_here=0
  for f in "$VDIR"/*.json; do
    [[ -f "$f" ]] || continue
    case "$(basename "$f")" in *.findings.jsonl|proof.json) continue ;; esac
    if grep -q "\"head\":\"${HEAD_NOW}\"" "$f" 2>/dev/null \
       && grep "\"head\":\"${HEAD_NOW}\"" "$f" 2>/dev/null | grep -q '"verdict":"APPROVED"'; then
      approved_here=$((approved_here + 1))
    fi
  done
  if [[ $approved_here -gt 0 ]]; then
    cat >&2 <<EOF
exloom: NOTE — ${approved_here} reviewer(s) have ALREADY APPROVED this exact commit
(${HEAD_NOW:0:12}). Nothing has changed since.

Another round on unchanged code cannot make it more reviewed. It will return
findings, because a reviewer asked to look will always find something — and those
findings will be thinner than the last round's, which is a property of the reviewer
rather than evidence the code got worse.

If the tier's required reviewers have all approved this commit, you are done:
ship it. Run another round only if a reviewer is genuinely missing for this tier.
EOF
  fi
fi

CURRENT="DEVELOPMENT"; ROUND=0
if [[ -f "$STATE_FILE" ]]; then
  CURRENT="$(sed -n 's/.*"state":"\([A-Z]*\)".*/\1/p' "$STATE_FILE" | tail -1)"
  ROUND="$(sed -n 's/.*"round":\([0-9]*\).*/\1/p' "$STATE_FILE" | tail -1)"
  [[ -n "$CURRENT" ]] || CURRENT="DEVELOPMENT"
  [[ -n "$ROUND"   ]] || ROUND=0
fi

# Re-dispatching inside an existing review round does not increment the counter —
# a Tier 2 round dispatches three reviewers and that is one round, not three.
if [[ "$CURRENT" != "REVIEW" ]]; then
  ROUND=$((ROUND + 1))
  printf '{"state":"REVIEW","round":%s,"at":"%s","head":"%s"}\n' \
    "$ROUND" "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true)" \
    "$(git rev-parse HEAD 2>/dev/null || true)" >> "$STATE_FILE" 2>/dev/null || exit 0
  echo "exloom: branch '$BRANCH' entered REVIEW — round ${ROUND}. The artifact is now frozen: source edits are blocked until you leave review." >&2
  if [[ "$ROUND" -ge 3 ]]; then
    echo "exloom: this is review round ${ROUND} on one branch. Rounds that keep finding defects usually mean the branch grew during review, not that review is working — check what has been added since round 1 before starting another." >&2
  fi
fi
exit 0
