#!/usr/bin/env bash
# Record a reviewer's verdict, called by the reviewer itself as its last action.
#
# The hook that reads reviewer reports has to infer two things it cannot see:
# which commit the reviewer read, and which dispatch its report belongs to. It
# resolves both by correlating async events, and when that fails it writes a
# line into the wrong receipt. The reviewer knows both facts outright.
#
# protect-verdicts.sh permits this script only when the caller is a reviewer
# subagent, so the authoring session still cannot write its own approval.
set -u

_DIR="${BASH_SOURCE[0]%[/\\]*}"; [[ "$_DIR" == "${BASH_SOURCE[0]}" ]] && _DIR=.
# shellcheck source=/dev/null
. "$_DIR/../hooks/lib.sh"

AGENT=""; VERDICT=""; HEAD_SHA=""; ROUND=""; TASK=""; MODE="full"; FROM=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --agent)         AGENT="${2:-}"; shift 2 ;;
    --verdict)       VERDICT="${2:-}"; shift 2 ;;
    --head)          HEAD_SHA="${2:-}"; shift 2 ;;
    --round-needed)  ROUND="${2:-}"; shift 2 ;;
    --task)          TASK="${2:-}"; shift 2 ;;
    --mode)          MODE="${2:-}"; shift 2 ;;
    --from)          FROM="${2:-}"; shift 2 ;;
    *) echo "record-verdict: unknown argument '$1'" >&2; exit 2 ;;
  esac
done

case "$AGENT" in
  l1-reviewer|adversarial-reviewer|security-auditor) ;;
  *) echo "record-verdict: --agent must name a reviewer, not '${AGENT}'" >&2; exit 2 ;;
esac
case "$VERDICT" in APPROVED|REJECTED) ;; *)
  echo "record-verdict: --verdict must be APPROVED or REJECTED, not '${VERDICT}'" >&2; exit 2 ;;
esac
case "$ROUND" in YES|NO) ;; *)
  echo "record-verdict: --round-needed must be YES or NO, not '${ROUND}'" >&2; exit 2 ;;
esac

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "record-verdict: not a git repository" >&2; exit 2; }
cd "$ROOT" || exit 2
BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
[[ -n "$BRANCH" && "$BRANCH" != "HEAD" ]] || { echo "record-verdict: no branch here" >&2; exit 2; }

# A stated head is checked, never taken. A reviewer that names a commit this
# branch does not contain has reviewed something else, and a receipt saying
# otherwise would vouch for code nobody read.
HEAD_SHA="$(git rev-parse --verify -q "${HEAD_SHA}^{commit}" 2>/dev/null)" \
  || { echo "record-verdict: --head does not name a commit in this repository" >&2; exit 2; }
git merge-base --is-ancestor "$HEAD_SHA" HEAD 2>/dev/null \
  || { echo "record-verdict: --head is not an ancestor of this branch's HEAD" >&2; exit 2; }

_safe() { printf '%s' "${1:-}" | tr -cd 'A-Za-z0-9:._-' | cut -c1-200; }
TASK="$(_safe "$TASK")"; MODE="$(_safe "$MODE")"

VDIR=".claude/reviews/${BRANCH}.verdicts"
mkdir -p "$VDIR" 2>/dev/null || { echo "record-verdict: cannot create ${VDIR}" >&2; exit 2; }
RECEIPT="${VDIR}/${AGENT}.json"
[[ -n "$TASK" ]] && RECEIPT="${VDIR}/${AGENT}.tasks.json"

# The same conclusion twice for the same commit is one fact. The key matches the
# substring the report-reading hook tests, so whichever writes first wins and the
# other is a no-op while both paths exist.
if [[ -f "$RECEIPT" ]] && grep -F "\"head\":\"${HEAD_SHA}\"" "$RECEIPT" 2>/dev/null \
     | grep -qF "\"verdict\":\"${VERDICT}\",\"round_needed\":\"${ROUND}\""; then
  echo "exloom: ${AGENT} verdict already recorded at ${HEAD_SHA:0:12}" >&2
  exit 0
fi

EXTRA=""
if [[ -n "$FROM" ]]; then
  FROM="$(git rev-parse --verify -q "${FROM}^{commit}" 2>/dev/null || true)"
  [[ -n "$FROM" ]] && EXTRA=",\"range\":\"${FROM}..${HEAD_SHA}\""
fi
[[ -n "$TASK" ]] && EXTRA="${EXTRA},\"task\":\"${TASK}\""

printf '{"agent":"%s","subagent_type":"exloom:%s","head":"%s","verdict":"%s","round_needed":"%s","at":"%s","session":"%s","mode":"%s","via":"reviewer"%s}\n' \
  "$AGENT" "$AGENT" "$HEAD_SHA" "$VERDICT" "$ROUND" \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true)" \
  "$(_safe "${CLAUDE_SESSION_ID:-}")" "${MODE:-full}" "$EXTRA" \
  >> "$RECEIPT" || { echo "record-verdict: could not write ${RECEIPT}" >&2; exit 2; }

echo "exloom: recorded ${AGENT} ${VERDICT} at ${HEAD_SHA:0:12} (${RECEIPT}) — commit it with the checklist" >&2
