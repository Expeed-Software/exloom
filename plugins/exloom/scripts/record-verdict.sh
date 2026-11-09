#!/usr/bin/env bash
# Record a reviewer's verdict and findings, called by the reviewer itself.
#
# The hook that used to read reviewer reports had to infer two things it could
# not see: which commit the reviewer read, and which dispatch its report
# belonged to. It resolved both by correlating async events, and when that
# failed it wrote a line into the wrong receipt. The reviewer knows both.
#
# protect-verdicts.sh permits this script only when the caller is a reviewer
# subagent, so the authoring session still cannot write its own approval.
#
# What the reviewer states is checked, never taken: the head must be on this
# branch, a verify range must match what this agent last reviewed, and an
# APPROVED cannot stand over its own blocking findings.
set -u

_DIR="${BASH_SOURCE[0]%[/\\]*}"; [[ "$_DIR" == "${BASH_SOURCE[0]}" ]] && _DIR=.
# shellcheck source=/dev/null
. "$_DIR/../hooks/lib.sh"

AGENT=""; VERDICT=""; HEAD_SHA=""; ROUND=""; TASK=""; MODE="full"; FROM=""; FINDINGS_IN=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --agent)         AGENT="${2:-}"; shift 2 ;;
    --verdict)       VERDICT="${2:-}"; shift 2 ;;
    --head)          HEAD_SHA="${2:-}"; shift 2 ;;
    --round-needed)  ROUND="${2:-}"; shift 2 ;;
    --task)          TASK="${2:-}"; shift 2 ;;
    --mode)          MODE="${2:-}"; shift 2 ;;
    --from)          FROM="${2:-}"; shift 2 ;;
    --findings)      FINDINGS_IN="${2:-}"; shift 2 ;;
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
STAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true)"

VDIR=".claude/reviews/${BRANCH}.verdicts"
mkdir -p "$VDIR" 2>/dev/null || { echo "record-verdict: cannot create ${VDIR}" >&2; exit 2; }
RECEIPT="${VDIR}/${AGENT}.json"
[[ -n "$TASK" ]] && RECEIPT="${VDIR}/${AGENT}.tasks.json"
FINDINGS_FILE="${VDIR}/${AGENT}.findings.jsonl"
LEDGER=".claude/reviews/${BRANCH}.ledger.md"

[[ -n "$FROM" ]] && FROM="$(git rev-parse --verify -q "${FROM}^{commit}" 2>/dev/null || true)"

# A verify pass narrows what counts as blocking to the lines a fix touched, so
# an unchecked range is a way to make every finding non-blocking. It is accepted
# only when it starts where this agent's last review ended and ends somewhere
# else. Anything else is a full pass.
if [[ "$MODE" == "verify" ]]; then
  LAST_HEAD="$(grep -F '"verdict":' "$RECEIPT" 2>/dev/null \
    | { if [[ -n "$TASK" ]]; then grep -F "\"task\":\"${TASK}\""; else cat; fi; } \
    | tail -1 | sed -n 's/.*"head":"\([0-9a-f]*\)".*/\1/p')"
  if [[ -z "$FROM" || "$FROM" != "$LAST_HEAD" || "$FROM" == "$HEAD_SHA" ]]; then
    echo "record-verdict: --from does not match what ${AGENT} last reviewed; recording a full pass" >&2
    MODE="full"; FROM=""
  fi
fi

FIX_LINES=""
if [[ "$MODE" == "verify" && -n "$FROM" ]]; then
  OWN_FROM="$(exloom_own_base "$FROM" "$HEAD_SHA" 2>/dev/null || true)"
  FIX_LINES="$(git -c core.quotepath=false diff -U0 "${OWN_FROM:-$FROM}" "$HEAD_SHA" -- . ':(exclude).claude/reviews' 2>/dev/null \
    | awk '/^\+\+\+ b\//{f=substr($0,7); next} /^\+\+\+ /{f=""; next}
           /^@@/ && f!=""{split($3,a,","); s=substr(a[1],2)+0; n=(a[2]=="")?1:a[2]+0; for(i=0;i<n;i++) print f":"(s+i); if(n==0){print f":"s; print f":"(s+1)}}')"
fi
_in_fix() {   # is the cited line one the fix range added or changed?
  local pth="${1%:*}" ln="${1##*:}" f
  while IFS= read -r f; do
    [[ -n "$f" && "${f##*:}" == "$ln" ]] || continue
    [[ "$pth" == "${f%:*}" || "$pth" == */"${f%:*}" || "${f%:*}" == */"$pth" ]] && return 0
  done <<< "$FIX_LINES"
  return 1
}

# A round is a distinct reviewed commit, counted from l1-reviewer's receipt so
# that every agent's findings agree on which pass they belong to.
ROUND_N="$(sed -n 's/.*"head"[[:space:]]*:[[:space:]]*"\([0-9a-f]\{7,40\}\)".*/\1/p' \
             "${VDIR}/l1-reviewer.json" 2>/dev/null \
           | grep -v "^${HEAD_SHA}$" | sort -u | awk 'END{print NR+1}')"
[[ "$ROUND_N" =~ ^[0-9]+$ ]] || ROUND_N=1

# ---------- findings, before the verdict ----------
# Stated by the reviewer, one per line, TAB separated:
#
#     SEVERITY<TAB>SCOPE<TAB>path/file.ext:123<TAB>one sentence
#
# SEVERITY is HIGH, MED or LOW; SCOPE is IN-SCOPE, PRE-EXISTING or ADDRESSED.
# Severity used to be read from the report's headings, which each agent words
# differently, and scope from prose. Stated outright, neither can be misread.
#
# They are processed first because a verdict that contradicts them cannot stand.
PENDING="$(mktemp 2>/dev/null || echo "${VDIR}/.pending.$$")"
PENDING_LEDGER="$(mktemp 2>/dev/null || echo "${VDIR}/.ledger.$$")"
: > "$PENDING"; : > "$PENDING_LEDGER"
SEEN_CITES=""
n_found=0; n_blocking=0

if [[ -n "$FINDINGS_IN" && -f "$FINDINGS_IN" ]]; then
  while IFS=$'\t' read -r sev scope cite reason || [[ -n "${sev:-}" ]]; do
    [[ -n "${cite:-}" ]] || continue
    sev="$(printf '%s' "$sev" | tr -cd 'A-Za-z' | tr '[:lower:]' '[:upper:]')"
    case "$sev" in HIGH|MED|LOW) ;; *) sev="MED" ;; esac
    scope="$(printf '%s' "$scope" | tr -cd 'A-Za-z-' | tr '[:lower:]' '[:upper:]')"
    case "$scope" in IN-SCOPE|PRE-EXISTING|ADDRESSED) ;; *) scope="IN-SCOPE" ;; esac
    cite="$(printf '%s' "$cite" | grep -oE '[A-Za-z0-9_./-]+\.[A-Za-z0-9]+:[0-9]+' | head -1)"
    [[ -n "$cite" ]] || continue
    reason="$(printf '%s' "${reason:-}" | tr -d '"\\' | LC_ALL=C tr -cd ' -~' | cut -c1-300)"
    SEEN_CITES="${SEEN_CITES}${cite}"$'\n'

    if [[ "$scope" == "ADDRESSED" ]]; then
      prev="$(grep -F "\"cite\":\"${cite}\"" "$FINDINGS_FILE" 2>/dev/null | grep -vF '"scope":"ADDRESSED"' | tail -1)"
      psev="$(printf '%s' "$prev" | sed -n 's/.*"severity":"\([A-Z]*\)".*/\1/p')"
      printf '{"round":%s,"agent":"%s","severity":"%s","scope":"ADDRESSED","cite":"%s","fingerprint":"","head":"%s","at":"%s"}\n' \
        "$ROUND_N" "$AGENT" "${psev:-MED}" "$cite" "$HEAD_SHA" "$STAMP" >> "$PENDING"
      n_found=$((n_found + 1)); continue
    fi

    # On a verify pass, a finding away from the lines the fix touched is not
    # what this pass is for. Never demoted when the range produced no lines:
    # that is a failure to compute the range, not evidence about the finding.
    if [[ "$MODE" == "verify" && -n "$FIX_LINES" && "$scope" == "IN-SCOPE" ]] \
       && { [[ "$sev" == "LOW" ]] || ! _in_fix "$cite"; }; then
      scope="OUT-OF-SCOPE"
    fi

    # Fingerprinted on the reason alone. Including the cite would let a long
    # path fill the window, so two unrelated findings in one deeply-nested file
    # would collapse into a fabricated re-find.
    text="$(printf '%s' "$reason" | tr -cd 'A-Za-z' | tr '[:upper:]' '[:lower:]' | cut -c1-48)"
    fp="$(printf '%s|%s|%s' "$sev" "$(basename "${cite%%:*}")" "$text" | tr -cd 'A-Za-z0-9|._-')"
    printf '{"round":%s,"agent":"%s","severity":"%s","scope":"%s","cite":"%s","fingerprint":"%s","head":"%s","at":"%s","reason":"%s"}\n' \
      "$ROUND_N" "$AGENT" "$sev" "$scope" "$cite" "$fp" "$HEAD_SHA" "$STAMP" "$reason" >> "$PENDING"
    n_found=$((n_found + 1))

    # Minor, out-of-scope and pre-existing findings go to the ledger, never the
    # fix loop.
    if [[ "$sev" == "LOW" || "$scope" != "IN-SCOPE" ]]; then
      case "$scope" in IN-SCOPE) label="minor" ;; *) label="$(printf '%s' "$scope" | tr '[:upper:]' '[:lower:]')" ;; esac
      printf '%s\t%s\n' "${cite} — ${label} — ${AGENT}" "$reason" >> "$PENDING_LEDGER"
    else
      n_blocking=$((n_blocking + 1))
    fi
  done < "$FINDINGS_IN"
fi

# An earlier blocking finding this pass did not mention is carried forward:
# silence is not a fix, and the author writes the verify prompt. Matched on the
# whole cite, so src/a.go:1 is not answered by src/a.go:12.
if [[ "$MODE" == "verify" && -n "$FROM" ]]; then
  while IFS= read -r prev; do
    pcite="$(printf '%s' "$prev" | sed -n 's/.*"cite":"\([^"]*\)".*/\1/p')"
    [[ -n "$pcite" ]] || continue
    printf '%s' "$SEEN_CITES" | grep -qxF -- "$pcite" && continue
    printf '%s\n' "$prev" \
      | sed -e "s/\"head\":\"[0-9a-f]*\"/\"head\":\"${HEAD_SHA}\"/" \
            -e "s/\"round\":[0-9]*/\"round\":${ROUND_N}/" >> "$PENDING"
    n_blocking=$((n_blocking + 1))
  done < <(grep -F "\"head\":\"${FROM}\"" "$FINDINGS_FILE" 2>/dev/null \
           | grep -F '"scope":"IN-SCOPE"' | grep -vF '"severity":"LOW"')
fi

# A verdict cannot contradict the findings recorded with it. Approving over an
# open blocking finding is the one combination that would let the fix loop end
# with the defect still there.
if [[ "$VERDICT" == "APPROVED" && $n_blocking -gt 0 ]]; then
  echo "record-verdict: ${n_blocking} blocking finding(s) stand at this commit — recording REJECTED, not APPROVED." >&2
  VERDICT="REJECTED"; ROUND="YES"
fi

EXTRA=""
[[ -n "$FROM" ]] && EXTRA=",\"range\":\"${FROM}..${HEAD_SHA}\""
[[ -n "$TASK" ]] && EXTRA="${EXTRA},\"task\":\"${TASK}\""

# The same conclusion twice for the same commit is one fact.
if [[ -f "$RECEIPT" ]] && grep -F "\"head\":\"${HEAD_SHA}\"" "$RECEIPT" 2>/dev/null \
     | grep -qF "\"verdict\":\"${VERDICT}\",\"round_needed\":\"${ROUND}\""; then
  echo "exloom: ${AGENT} verdict already recorded at ${HEAD_SHA:0:12}" >&2
else
  printf '{"agent":"%s","subagent_type":"exloom:%s","head":"%s","verdict":"%s","round_needed":"%s","at":"%s","session":"%s","mode":"%s","via":"reviewer"%s}\n' \
    "$AGENT" "$AGENT" "$HEAD_SHA" "$VERDICT" "$ROUND" "$STAMP" \
    "$(_safe "${CLAUDE_SESSION_ID:-}")" "${MODE:-full}" "$EXTRA" \
    >> "$RECEIPT" || { rm -f "$PENDING" "$PENDING_LEDGER"; echo "record-verdict: could not write ${RECEIPT}" >&2; exit 2; }
  echo "exloom: recorded ${AGENT} ${VERDICT} at ${HEAD_SHA:0:12} (${RECEIPT}) — commit it with the checklist" >&2
fi

if [[ -s "$PENDING" ]]; then
  cat "$PENDING" >> "$FINDINGS_FILE"
  while IFS=$'\t' read -r key ltext; do
    [[ -n "$key" ]] || continue
    if ! grep -F -e "] ${key}, round" "$LEDGER" 2>/dev/null | grep -qF -- "— ${ltext}"; then
      [[ -f "$LEDGER" ]] || printf '# Review ledger — %s\n\nNon-blocking findings. The final review triages each: fix, ticket or drop.\n\n' "$BRANCH" > "$LEDGER"
      printf -- '- [ ] %s, round %s — %s\n' "$key" "$ROUND_N" "$ltext" >> "$LEDGER"
    fi
  done < "$PENDING_LEDGER"
  echo "exloom: recorded ${n_found} finding(s) from ${AGENT} (round ${ROUND_N}), ${n_blocking} blocking" >&2
fi
rm -f "$PENDING" "$PENDING_LEDGER"
