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

# ---------- read the reviewer's report ----------
# Shape-agnostic, and with a python3 fallback for the same reason every other
# extractor in this codebase has one: jq is NOT present by default on Windows Git
# Bash, and without a fallback the scan silently degraded to the RAW PAYLOAD —
# which contains `tool_input.prompt`, i.e. author-written text. A dispatch prompt
# that merely quoted the required output format flipped a rejection into an
# approval. The raw scan is now a last resort AND has tool_input removed first.
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
  if [[ -z "$out" ]] && command -v python3 >/dev/null 2>&1; then
    out="$(printf '%s' "$HOOK_INPUT" | python3 -c '
import json,sys
def flat(v):
    if isinstance(v,str): return v
    if isinstance(v,list): return "\n".join(flat(x) for x in v)
    if isinstance(v,dict):
        if "text" in v and isinstance(v["text"],str): return v["text"]
        return "\n".join(flat(v.get(k,"")) for k in ("content","output","text"))
    return ""
try:
    d=json.load(sys.stdin)
    for k in ("tool_output","tool_response","tool_result","response"):
        if k in d:
            print(flat(d[k])); break
except Exception:
    pass' 2>/dev/null || true)"
  fi
  # NO raw-payload fallback. Stripping tool_input with a brace-delimited pattern
  # stops at the first `}`, so any prompt containing a brace (a code sample, a
  # ${...}, JSON) left author-written text in the scan, and a prompt quoting the
  # required output format then supplied the verdict. Reachable exactly where it
  # matters: Git Bash with neither jq nor python3. UNKNOWN is the honest answer,
  # and it blocks rather than opens.
  printf '%s' "$out"
}

SCAN="$(_response_text)"
# JSON-escaped newlines become real ones so line-anchored matching works.
SCAN="$(printf '%s' "$SCAN" | sed 's/\\n/\n/g')"

# ---------- what did the reviewer CONCLUDE? ----------
# Parsed against what the SHIPPED agents actually print. Their output block is a
# bare `VERDICT: APPROVED` or `VERDICT: REJECTED (n items)`.
#
# Three defects this replaces, each reproduced:
#   - `**VERDICT: APPROVED**` recorded UNKNOWN. Bold is the single most likely
#     form an LLM emits, so the common case silently blocked a real approval and
#     the block message then advertised EXLOOM_REVIEW_SKIP.
#   - `VERDICT: APPROVED WITH CHANGES` recorded APPROVED — a non-approval opening
#     the gate.
#   - `grep -m1` took the FIRST match, so a report quoting its own template before
#     stating a real verdict was scored on the template.
#
# So: tolerate markdown decoration before the keyword, require the remainder of
# the line to be exactly APPROVED/REJECTED with an optional parenthetical, and
# take the LAST such line in the report.
VERDICT="UNKNOWN"
# Decoration is stripped from the WHOLE line before matching. Tolerating it only at
# the edges left `VERDICT: **APPROVED**`, `**VERDICT:** REJECTED (2 items)`,
# `- **VERDICT:** APPROVED` and `VERDICT: APPROVED.` all recording UNKNOWN — only the
# single form the fixture covered worked, so the parser was fitted to its own test a
# second time. A missed APPROVED is a false block, and the block message answers a
# false block by naming EXLOOM_REVIEW_SKIP.
VLINE="$(printf '%s\n' "$SCAN" \
  | tr -d '*_`#>' \
  | sed -e 's/^[[:space:]-]*//' -e 's/[[:space:].]*$//' \
  | sed -n 's/^VERDICT:[[:space:]]*\([A-Za-z]*\)[[:space:]]*\((.*)\)\{0,1\}$/\1/p' \
  | tr '[:lower:]' '[:upper:]' | grep -E '^(APPROVED|REJECTED)$' | tail -1 || true)"
case "$VLINE" in
  APPROVED) VERDICT="APPROVED" ;;
  REJECTED) VERDICT="REJECTED" ;;
esac

# ---------- findings become data, not chat ----------
# Parsed against the shipped output format, which is:
#
#     ## Critical (must fix before merge)
#     - path/to/file.ext:123 — one sentence problem statement
#
# The severity is the HEADING; the finding line carries only a cite. The previous
# parser required both on one line, so NO shipped agent produced a single
# recorded finding — the ledger was empty and re-find detection was inert. The
# suite passed because its fixture put severity and cite on one line, a format
# nothing emits.
ROUND="$(sed -n 's/.*"round":\([0-9]*\).*/\1/p' ".claude/reviews/${BRANCH}.state" 2>/dev/null | tail -1)"
[[ -n "$ROUND" ]] || ROUND=0

FINDINGS_FILE="${VDIR}/${AGENT}.findings.jsonl"
n_found=0
cur_sev=""
cur_scope="IN-SCOPE"

while IFS= read -r fline; do
  # A heading switches the active severity, and closes it for non-finding sections.
  case "$fline" in
    '#'*)
      head_txt="$(printf '%s' "$fline" | tr '[:upper:]' '[:lower:]')"
      cur_sev=""
      cur_scope="IN-SCOPE"
      # Normalised across agents: l1 says Critical/Important/Minor, adversarial
      # says Blocking, security says High/Medium/Low. Unnormalised, the same
      # defect reported by two reviewers never matched as a re-find.
      case "$head_txt" in
        *critical*|*blocking*|*" high"*|*"(high"*) cur_sev="HIGH" ;;
        *important*|*medium*)                      cur_sev="MED" ;;
        *minor*|*" low"*|*"(low"*|*advisory*)      cur_sev="LOW" ;;
      esac
      # A pre-existing section carries no severity word ("## Pre-existing
      # (backlog, not this branch)"), so without this its findings were dropped
      # entirely and the ledger's pre-existing column was permanently zero. They
      # are recorded — they are simply never blocking.
      case "$head_txt" in
        *pre-existing*) cur_scope="PRE-EXISTING"; [[ -n "$cur_sev" ]] || cur_sev="MED" ;;
      esac
      case "$head_txt" in *nothing\ to\ flag*) cur_sev="" ;; esac
      continue ;;
  esac
  [[ -n "$cur_sev" ]] || continue

  cite="$(printf '%s' "$fline" | grep -oE '[A-Za-z0-9_./-]+\.[A-Za-z0-9]+:[0-9]+' | head -1)"
  [[ -n "$cite" ]] || continue

  scope="$cur_scope"
  printf '%s' "$fline" | grep -qiE 'PRE-EXISTING' && scope="PRE-EXISTING"
  printf '%s' "$fline" | grep -qiE 'IN-SCOPE'     && scope="IN-SCOPE"

  file="${cite%%:*}"
  # Fingerprint from the text AFTER the cite is removed. Keeping the cite meant
  # the path dominated the 48-character window, so two unrelated findings in one
  # deep-path file collapsed into a fabricated re-find, and a moved file never
  # matched itself.
  text="$(printf '%s' "$fline" | sed "s|[A-Za-z0-9_./-]*\.[A-Za-z0-9]*:[0-9]*||g" \
          | tr -cd 'A-Za-z' | tr '[:upper:]' '[:lower:]' | cut -c1-48)"
  fp="$(printf '%s|%s|%s' "$cur_sev" "$(basename "$file")" "$text" | tr -cd 'A-Za-z0-9|._-')"

  printf '{"round":%s,"agent":"%s","severity":"%s","scope":"%s","cite":"%s","fingerprint":"%s","head":"%s","at":"%s"}\n' \
    "$ROUND" "$AGENT" "$cur_sev" "$scope" "$cite" "$fp" "$HEAD_SHA" "$STAMP" \
    >> "$FINDINGS_FILE" 2>/dev/null || break
  n_found=$((n_found + 1))
done <<< "$SCAN"

if [[ $n_found -gt 0 ]]; then
  echo "exloom: recorded ${n_found} finding(s) from ${AGENT} (round ${ROUND}) — run scripts/findings-ledger.sh from the repo root" >&2
fi
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
