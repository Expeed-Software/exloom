#!/usr/bin/env bash
# exloom — PostToolUse hook (reviewer verdict receipts).
#
# OPT-IN: does nothing unless the repo created `.claude/exloom-gate.enabled`.
#
# Fires when a reviewer subagent actually completes and records that event, so a
# receipt is evidence of a dispatch rather than an assertion of one. Every other
# piece of review evidence is written by the session that wrote the code.
#
# Receipt: .claude/reviews/<branch>.verdicts/<agent>.json — JSONL, one line per
# dispatch, each naming the HEAD commit the reviewer saw.
#
# NEVER blocks and always exits 0: a missing receipt surfaces later at the gate,
# not here as a broken workflow.

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
  *adversarial-reviewer) AGENT="adversarial-reviewer" ;;
  *security-auditor)     AGENT="security-auditor" ;;
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
# These are interpolated into JSON with printf and the gate matches receipt lines
# by substring, so a value containing a quote can close its field and append its
# own keys — forging coverage without ever writing to the guarded directory.
# Stripped, not escaped: the goal is a value that cannot alter the line's shape
# however it is later parsed.
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

# ---------- is the report even available at this event? ----------
# On an ASYNC dispatch, PostToolUse fires when the agent is LAUNCHED, not when it
# finishes. The payload then carries
#   "tool_response":{"isAsync":true,"status":"async_launched","outputFile":"..."}
# and no report at all — the reviewer has not run yet.
#
# That must NOT be recorded as UNKNOWN. UNKNOWN means "the reviewer stated no
# verdict", which correctly blocks. This is "exloom could not observe a verdict
# at this event", which is our blindness, not the reviewer's omission. Recording
# UNKNOWN here made every real dispatch block with no path forward.
#
# So when there is no report text, omit the verdict keys entirely and record what
# WAS observed: a reviewer was dispatched at this commit. That is the receipt
# shape exloom wrote before it recorded verdicts, and the gate grandfathers it.
REPORT_SEEN=1
[[ -n "$(printf '%s' "$SCAN" | tr -d '[:space:]')" ]] || REPORT_SEEN=0

# ---------- what did the reviewer CONCLUDE? ----------
# Parsed against what the SHIPPED agents actually print. Their output block is a
# bare `VERDICT: APPROVED` or `VERDICT: REJECTED (n items)`.
#
# Three rules, each load-bearing: tolerate markdown decoration anywhere on the
# line (`**VERDICT: APPROVED**` is the modal form); require the remainder to be
# exactly APPROVED/REJECTED plus an optional parenthetical (so `APPROVED WITH
# CHANGES` is not an approval); and take the LAST match, not the first (a report
# quoting its own template would otherwise be scored on the template).
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

# ---------- the loop-termination signal ----------
# Every agent emits `ROUND NEEDED AFTER FIX: YES | NO`; recording it is what lets
# /review-complete decide the loop is over. UNKNOWN counts as YES to any
# consumer — a reviewer that did not answer has not said the loop can stop.
ROUND_NEEDED="UNKNOWN"
RLINE="$(printf '%s\n' "$SCAN" \
  | tr -d '*_`#>' \
  | sed -e 's/^[[:space:]-]*//' -e 's/[[:space:].]*$//' \
  | sed -n 's/^ROUND NEEDED AFTER FIX:[[:space:]]*\([A-Za-z]*\).*/\1/p' \
  | tr '[:lower:]' '[:upper:]' | grep -E '^(YES|NO)$' | tail -1 || true)"
case "$RLINE" in
  YES) ROUND_NEEDED="YES" ;;
  NO)  ROUND_NEEDED="NO" ;;
esac

# ---------- findings become data, not chat ----------
# Parsed against the shipped output format, which is:
#
#     ## Critical (must fix before merge)
#     - path/to/file.ext:123 — one sentence problem statement
#
# The severity is on the HEADING; the finding line carries only a cite. Requiring
# both on one line records nothing from any shipped agent.
ROUND="$(sed -n 's/.*"round":\([0-9]*\).*/\1/p' ".claude/reviews/${BRANCH}.state" 2>/dev/null | tail -1)"
[[ -n "$ROUND" ]] || ROUND=0

FINDINGS_FILE="${VDIR}/${AGENT}.findings.jsonl"
n_found=0
cur_sev=""
item_sev=""
cur_scope="IN-SCOPE"

while IFS= read -r fline; do
  # A heading switches the active severity, and closes it for non-finding sections.
  case "$fline" in
    '#'*)
      head_txt="$(printf '%s' "$fline" | tr '[:upper:]' '[:lower:]')"
      cur_sev=""
      item_sev=""
      cur_scope="IN-SCOPE"
      # Normalised across agents: l1 says Critical/Important/Minor, adversarial
      # says Blocking, security says High/Medium/Low. Unnormalised, the same
      # defect reported by two reviewers never matched as a re-find.
      case "$head_txt" in
        *non-blocking*|*advisory*)                 cur_sev="LOW" ;;
        *critical*|*blocking*|*" high"*|*"(high"*) cur_sev="HIGH" ;;
        *important*|*medium*)                      cur_sev="MED" ;;
        *minor*|*" low"*|*"(low"*)                 cur_sev="LOW" ;;
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
  cite="$(printf '%s' "$fline" | grep -oE '[A-Za-z0-9_./-]+\.[A-Za-z0-9]+:[0-9]+' | head -1)"
  if [[ -z "$cite" ]]; then
    # No cite: if the line names a severity, remember it for the lines that follow.
    # security-auditor emits `- [severity: High] [category]` and puts the cite on
    # the NEXT line, so a per-line-only rule recorded nothing from it.
    case "$(printf '%s' "$fline" | tr '[:upper:]' '[:lower:]')" in
      *severity:*critical*|*severity:*high*|*'[critical]'*|*'[high]'*) item_sev="HIGH" ;;
      *severity:*medium*|*'[medium]'*|*important*)                     item_sev="MED" ;;
      *severity:*low*|*'[low]'*)                                       item_sev="LOW" ;;
      '') item_sev="" ;;
    esac
    continue
  fi

  # Severity from the heading, else from the LINE. Requiring a severity-bearing
  # heading meant cross-layer-auditor (`## Grep 1 — Orphan fields`),
  # security-auditor (`## Findings`, severity per line) and plan-reviewer
  # (`REJECTED items:`) recorded zero findings each — three of five reviewers,
  # with a blocking re-find gate reading nothing.
  line_sev=""
  case "$(printf '%s' "$fline" | tr '[:upper:]' '[:lower:]')" in
    *critical*|*blocking*|*severity:\ high*|*\[high\]*|*" high "*) line_sev="HIGH" ;;
    *important*|*severity:\ medium*|*\[medium\]*|*" medium "*)     line_sev="MED" ;;
    *minor*|*severity:\ low*|*\[low\]*|*" low "*|*orphan*)         line_sev="LOW" ;;
    # The cross-layer check reports one line per item and marks the actual orphan
    # with `read at: NONE` / `called at: NONE` / `handled at: NONE`. Neither its
    # headings nor its lines carry a severity word, so keying on NONE is what
    # records the orphans while leaving the clean rows alone. A cite is required
    # above, so l1's `- Critical: none` cannot reach here.
    *": none"*|*":none"*)                                          line_sev="MED" ;;
  esac
  # A non-blocking line is LOW whatever else it says.
  case "$(printf '%s' "$fline" | tr '[:upper:]' '[:lower:]')" in *non-blocking*) line_sev="LOW" ;; esac
  sev="${cur_sev:-${line_sev:-$item_sev}}"
  [[ -n "$sev" ]] || continue

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
  fp="$(printf '%s|%s|%s' "$sev" "$(basename "$file")" "$text" | tr -cd 'A-Za-z0-9|._-')"

  printf '{"round":%s,"agent":"%s","severity":"%s","scope":"%s","cite":"%s","fingerprint":"%s","head":"%s","at":"%s"}\n' \
    "$ROUND" "$AGENT" "$sev" "$scope" "$cite" "$fp" "$HEAD_SHA" "$STAMP" \
    >> "$FINDINGS_FILE" 2>/dev/null || break
  n_found=$((n_found + 1))
done <<< "$SCAN"

if [[ $n_found -gt 0 ]]; then
  echo "exloom: recorded ${n_found} finding(s) from ${AGENT} (round ${ROUND}) in ${VDIR}/${AGENT}.findings.jsonl" >&2
fi

if [[ $REPORT_SEEN -eq 0 ]]; then
  printf '{"agent":"%s","subagent_type":"%s","head":"%s","at":"%s","session":"%s"}\n' \
    "$AGENT" "$SUBAGENT" "$HEAD_SHA" "$STAMP" "$SESSION" \
    >> "${VDIR}/${AGENT}.json" 2>/dev/null || exit 0
  echo "exloom: recorded ${AGENT} DISPATCH receipt at ${HEAD_SHA:0:12} — the reviewer's report is not available at this event (async dispatch), so no verdict was recorded. Read the findings yourself before marking the checklist complete." >&2
  exit 0
fi

printf '{"agent":"%s","subagent_type":"%s","head":"%s","verdict":"%s","round_needed":"%s","at":"%s","session":"%s"}\n' \
  "$AGENT" "$SUBAGENT" "$HEAD_SHA" "$VERDICT" "$ROUND_NEEDED" "$STAMP" "$SESSION" \
  >> "${VDIR}/${AGENT}.json" 2>/dev/null || exit 0

# The exit condition, stated where the session will read it. APPROVED with every
# reviewer saying NO is what "stop reviewing" looks like; nothing else is.
if [[ "$VERDICT" == "APPROVED" && "$ROUND_NEEDED" == "NO" ]]; then
  echo "exloom: ${AGENT} reports no further round is needed after fixes. If every required reviewer says the same at this commit, the loop is done — ship rather than running another round." >&2
elif [[ "$ROUND_NEEDED" == "UNKNOWN" ]]; then
  echo "exloom: ${AGENT} gave no 'ROUND NEEDED AFTER FIX:' line — treated as YES, because a reviewer that did not answer has not told you the loop can stop." >&2
fi


echo "exloom: recorded ${AGENT} verdict receipt at ${HEAD_SHA:0:12} (${VDIR}/${AGENT}.json) — commit it with the checklist" >&2
exit 0
