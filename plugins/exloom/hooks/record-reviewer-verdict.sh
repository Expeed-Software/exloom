#!/usr/bin/env bash
# exloom — PostToolUse hook (reviewer verdict receipts).
#
# OPT-IN: does nothing unless the repo created `.claude/exloom-gate.enabled`.
#
# WHY THIS EXISTS. Every other piece of review evidence in exloom is written by
# the same session that wrote the code: the checklist, the tier, the findings,
# the "Dispatched" boxes. That makes the gate an artifact check — it proves a
# document exists, never that a review happened — and the cheapest way to make it
# green is to write the document. This hook is the one exception. It fires when a
# reviewer subagent ACTUALLY completes, and it records that event to disk. The
# model does not write this file (protect-verdicts.sh denies direct writes to the
# directory), so a receipt is evidence of a dispatch, not an assertion of one.
#
# Receipt: .claude/reviews/<branch>.verdicts/<agent>.json — JSONL, one line per
# dispatch, each naming the HEAD commit the reviewer saw. lib.sh requires, per
# tier, one receipt per required reviewer covering the reviewed commit.
#
# NEVER blocks and never fails the tool call: always exit 0. A missing receipt
# surfaces later, at the gate, as a blocked push — not here as a broken workflow.

set -u

# ---------- read hook input ----------
HOOK_INPUT=""
if [[ -p /dev/stdin || ! -t 0 ]]; then
  HOOK_INPUT="$(cat 2>/dev/null || true)"
fi
[[ -n "$HOOK_INPUT" ]] || exit 0

# ---------- nested field extraction (jq -> python3 -> sed) ----------
# Args: <dotted-path> e.g. "tool_input.subagent_type". The sed fallback is a
# best-effort scan for the LAST path segment as a JSON key anywhere in the blob.
_field() {
  local path="$1" leaf="${1##*.}" out=""
  if command -v jq >/dev/null 2>&1; then
    out="$(printf '%s' "$HOOK_INPUT" | jq -r ".${path} // empty" 2>/dev/null || true)"
  fi
  if [[ -z "$out" ]] && command -v python3 >/dev/null 2>&1; then
    out="$(printf '%s' "$HOOK_INPUT" | PATH_ENV="$path" python3 -c '
import json, os, sys
try:
    d = json.load(sys.stdin)
    for k in os.environ["PATH_ENV"].split("."):
        d = d.get(k) if isinstance(d, dict) else None
        if d is None:
            break
    print(d if isinstance(d, str) else "")
except Exception:
    pass' 2>/dev/null || true)"
  fi
  if [[ -z "$out" ]]; then
    out="$(printf '%s' "$HOOK_INPUT" | sed -n "s/.*\"$leaf\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -1)"
  fi
  printf '%s' "$out"
}

TOOL="$(_field tool_name)"
case "$TOOL" in
  Task|Agent|task|agent) ;;
  *) exit 0 ;;
esac

SUBAGENT="$(_field tool_input.subagent_type)"
[[ -n "$SUBAGENT" ]] || exit 0

# Which reviewer is this? Suffix match, so both `l1-reviewer` and the namespaced
# `exloom:l1-reviewer` record against the same canonical name. An agent that is
# not one of exloom's four reviewers leaves no receipt — dispatching a
# general-purpose agent to "do an L1 review" deliberately does not satisfy the
# gate, because the gate cannot tell what such an agent was asked to do.
AGENT=""
case "$SUBAGENT" in
  *l1-reviewer)          AGENT="l1-reviewer" ;;
  *cross-layer-auditor)  AGENT="cross-layer-auditor" ;;
  *adversarial-reviewer) AGENT="adversarial-reviewer" ;;
  *security-auditor)     AGENT="security-auditor" ;;
  # plan-reviewer covers plans AND specs — see agents/plan-reviewer.md. There is
  # deliberately no `spec-reviewer`: accepting a name no agent answers to would
  # record receipts for a dispatch that cannot resolve.
  *plan-reviewer)        AGENT="plan-reviewer" ;;
  *) exit 0 ;;
esac

# ---------- repo + opt-in ----------
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
[[ -n "$REPO_ROOT" ]] || exit 0
cd "$REPO_ROOT" || exit 0
[[ -f ".claude/exloom-gate.enabled" ]] || exit 0

BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)" || exit 0
[[ -n "$BRANCH" && "$BRANCH" != "HEAD" ]] || exit 0

HEAD_SHA="$(git rev-parse HEAD 2>/dev/null)" || exit 0
[[ -n "$HEAD_SHA" ]] || exit 0

# ---------- append the receipt ----------
VDIR=".claude/reviews/${BRANCH}.verdicts"
mkdir -p "$VDIR" 2>/dev/null || exit 0

SESSION="$(_field session_id)"
STAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true)"

# ---------- sanitise every value that reaches the receipt ----------
# These fields are interpolated into JSON with printf, and the gate matches
# receipt lines by substring. A `subagent_type` containing a quote can therefore
# CLOSE the field and append its own `"artifact"` / `"artifact_hash"` keys,
# forging coverage for a plan that was never reviewed — without ever writing to
# the verdicts directory that protect-verdicts.sh guards. Verified: the forged
# line opened the gate.
#
# Real agent and session names are alphanumerics plus `:._-`; anything else is
# stripped rather than escaped, because the goal is a value that cannot alter
# the shape of the line no matter how it is later parsed.
_safe() { printf '%s' "$1" | tr -cd 'A-Za-z0-9:._-' | cut -c1-200; }
SUBAGENT="$(_safe "$SUBAGENT")"
SESSION="$(_safe "$SESSION")"
[[ -n "$SUBAGENT" ]] || exit 0

# ---------- artifact reviewers bind to CONTENT, not to a commit ----------
# A plan or spec is reviewed and then executed, usually before anything is
# committed — so a commit SHA cannot express "this review covers this document".
# The blob hash can, and it invalidates itself the moment the document is edited.
# That is the FREEZE rule as a mechanism rather than a paragraph.
#
# The artifact is named in the dispatch prompt. If the prompt does not name one,
# NO artifact is recorded — the receipt then covers nothing and the execution
# gate stays shut. That is deliberate: a reviewer dispatched without naming what
# it reviewed has not produced reviewable evidence.
# ---------- what did the reviewer CONCLUDE? ----------
# Until now the receipt recorded that a reviewer RAN, never what it found — so a
# REJECTED verdict opened the gate exactly like an APPROVED one. "A reviewer was
# dispatched" is not "the work was reviewed", and the gap between those two is
# where a session gets nine findings back, decides they are nits, and proceeds.
#
# Shape-agnostic on purpose: the subagent's report may arrive as a string, as
# {"content":[{"type":"text","text":...}]}, or under a different key entirely.
# Rather than assume one, try the structured paths, then fall back to scanning
# the raw payload. If none of them yields a verdict the answer is UNKNOWN, which
# is treated as NOT approved — a gate may not guess in the permissive direction.
_response_text() {
  local out=""
  if command -v jq >/dev/null 2>&1; then
    out="$(printf '%s' "$HOOK_INPUT" | jq -r '
      (.tool_output // .tool_response // .tool_result // .response // empty)
      | if   type == "string" then .
        elif type == "array"  then ([.[] | if type=="object" then (.text // "") else tostring end] | join("\n"))
        elif type == "object" then
          (((.content // []) | if type=="array" then ([.[] | (.text // "")] | join("\n")) else "" end)
           + "\n" + (.output // "") + "\n" + (.text // ""))
        else "" end' 2>/dev/null || true)"
  fi
  printf '%s' "$out"
}

VERDICT="UNKNOWN"
SCAN="$(_response_text)"
[[ -n "$SCAN" ]] || SCAN="$HOOK_INPUT"
# Match a real verdict LINE, and reject any line containing `|` — the agent's own
# output-format template reads "VERDICT: APPROVED | REJECTED (n items)", and
# matching that would hand out an APPROVED for a reviewer echoing its instructions.
VLINE="$(printf '%s\n' "$SCAN" | grep -m1 -iE '(^|\\n)[[:space:]]*VERDICT:[[:space:]]*(APPROVED|REJECTED)' | grep -v '|' || true)"
case "$(printf '%s' "$VLINE" | tr '[:lower:]' '[:upper:]')" in
  *VERDICT:*APPROVED*) VERDICT="APPROVED" ;;
  *VERDICT:*REJECTED*) VERDICT="REJECTED" ;;
esac

# ---------- findings become data, not chat ----------
# Findings currently live in a transcript, so nobody can see that round 8 is
# re-reporting what round 7 declared fixed. On one real branch, three of the four
# blocking findings in rounds 8 and 9 were re-finds — visible only because the
# author reconstructed it by hand at the end.
#
# A finding is recorded when a line carries BOTH a severity word and a file:line
# cite. That joint signal is deliberately conservative: prose about severity, and
# bare file references, are both ignored. The fingerprint drops line numbers (they
# shift under edits) and keeps severity + filename + the first words of the text,
# so the same defect re-reported next round matches even after the file moves.
ROUND="$(sed -n 's/.*"round":\([0-9]*\).*/\1/p' ".claude/reviews/${BRANCH}.state" 2>/dev/null | tail -1)"
[[ -n "$ROUND" ]] || ROUND=0

FINDINGS_FILE="${VDIR}/${AGENT}.findings.jsonl"
n_found=0
while IFS= read -r fline; do
  [[ -n "$fline" ]] || continue
  sev="$(printf '%s' "$fline" | grep -oiE '\b(Critical|Blocking|Important|High|Medium|Minor|Low)\b' | head -1 | tr '[:lower:]' '[:upper:]')"
  [[ -n "$sev" ]] || continue
  cite="$(printf '%s' "$fline" | grep -oE '[A-Za-z0-9_./-]+\.[A-Za-z0-9]+:[0-9]+' | head -1)"
  [[ -n "$cite" ]] || continue
  scope="IN-SCOPE"
  printf '%s' "$fline" | grep -qiE 'PRE-EXISTING' && scope="PRE-EXISTING"
  file="${cite%%:*}"
  # Fingerprint: severity + basename + first 48 LETTERS of the finding text.
  # Digits are dropped entirely, not merely the cite: the same defect re-reported
  # next round almost always carries a different line number (the file moved under
  # the fix), and keeping digits made `:42` and `:57` two different findings — which
  # is precisely the re-find this is built to catch.
  fp="$(printf '%s|%s|%s' "$sev" "$(basename "$file")" \
        "$(printf '%s' "$fline" | tr -cd 'A-Za-z' | tr '[:upper:]' '[:lower:]' | cut -c1-48)")"
  printf '{"round":%s,"agent":"%s","severity":"%s","scope":"%s","cite":"%s","fingerprint":"%s","head":"%s","at":"%s"}\n' \
    "$ROUND" "$AGENT" "$sev" "$scope" "$cite" \
    "$(printf '%s' "$fp" | tr -cd 'A-Za-z0-9|._-')" \
    "$HEAD_SHA" "$STAMP" >> "$FINDINGS_FILE" 2>/dev/null || break
  n_found=$((n_found + 1))
done < <(printf '%s\n' "$SCAN" | sed 's/\\n/\n/g')

if [[ $n_found -gt 0 ]]; then
  echo "exloom: recorded ${n_found} finding(s) from ${AGENT} (round ${ROUND}) — see /review-ledger" >&2
fi

ARTIFACTS=""
case "$AGENT" in
  plan-reviewer)
    PROMPT="$(_field tool_input.prompt)"
    # Normalise before matching. Reproduced in a scratch repo: the previous
    # boundary class excluded `/` and `.`, so `./docs/plans/p.md` and an ABSOLUTE
    # path both matched nothing — and this harness's own guidance tells agents to
    # use absolute paths, which made the correct-looking dispatch the failing one.
    PROMPT="${PROMPT//\\\\//}"
    PROMPT="${PROMPT//\\//}"
    PROMPT="${PROMPT//"$REPO_ROOT"\//}"
    PROMPT="${PROMPT// .\// }"
    # Record EVERY plan/spec path named, not `head -1`. "Per docs/specs/s.md,
    # review docs/plans/p.md" recorded the spec and left the plan uncovered —
    # a real review that reads as no review.
    ARTIFACTS="$(printf '%s' "$PROMPT" \
      | grep -oE '(docs/(exloom/)?(plans|specs)|\.claude/plans)/[A-Za-z0-9 ._()/-]+\.md' \
      | sed 's/[[:space:]]*$//' | sort -u)"
    ;;
esac

if [[ -n "$ARTIFACTS" ]]; then
  WROTE=0
  while IFS= read -r art; do
    [[ -n "$art" && -f "$art" ]] || continue
    ahash="$(git hash-object "$art" 2>/dev/null || true)"
    [[ -n "$ahash" ]] || continue
    printf '{"agent":"%s","subagent_type":"%s","head":"%s","artifact":"%s","artifact_hash":"%s","verdict":"%s","at":"%s","session":"%s"}\n' \
      "$AGENT" "$SUBAGENT" "$HEAD_SHA" "$art" "$ahash" "$VERDICT" "$STAMP" "$SESSION" \
      >> "${VDIR}/${AGENT}.json" 2>/dev/null || exit 0
    echo "exloom: recorded ${AGENT} receipt for ${art} @ ${ahash:0:12} — verdict ${VERDICT}" >&2
    [[ "$VERDICT" == "APPROVED" ]] || \
      echo "exloom: verdict is ${VERDICT}, so this does NOT unlock execution. Address the findings and re-dispatch (UNKNOWN means no 'VERDICT: APPROVED' line was found in the reviewer's report)." >&2
    WROTE=1
  done <<< "$ARTIFACTS"
  [[ $WROTE -eq 1 ]] && exit 0
fi

printf '{"agent":"%s","subagent_type":"%s","head":"%s","verdict":"%s","at":"%s","session":"%s"}\n' \
  "$AGENT" "$SUBAGENT" "$HEAD_SHA" "$VERDICT" "$STAMP" "$SESSION" \
  >> "${VDIR}/${AGENT}.json" 2>/dev/null || exit 0

case "$AGENT" in
  plan-reviewer)
    echo "exloom: recorded ${AGENT} receipt but the dispatch prompt named no plan/spec file — this receipt covers NO artifact and will not unlock execution. Re-dispatch naming the exact path." >&2
    exit 0 ;;
esac

echo "exloom: recorded ${AGENT} verdict receipt at ${HEAD_SHA:0:12} (${VDIR}/${AGENT}.json) — commit it with the checklist" >&2
exit 0
