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

printf '{"agent":"%s","subagent_type":"%s","head":"%s","at":"%s","session":"%s"}\n' \
  "$AGENT" "$SUBAGENT" "$HEAD_SHA" "$STAMP" "$SESSION" \
  >> "${VDIR}/${AGENT}.json" 2>/dev/null || exit 0

echo "exloom: recorded ${AGENT} verdict receipt at ${HEAD_SHA:0:12} (${VDIR}/${AGENT}.json) — commit it with the checklist" >&2
exit 0
