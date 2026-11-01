#!/usr/bin/env bash
# exloom — PreToolUse hook on SendMessage.
#
# OPT-IN: does nothing unless the repo created `.claude/exloom-gate.enabled`.
#
# A reviewer is dispatched, never resumed. A resumed reviewer carries its own
# earlier conclusion and the session's framing into the verify pass, which is
# how a REJECTED finding gets talked into ADDRESSED without the code changing.
# A verify pass is a fresh dispatch, so it leaves its own receipt naming the
# commit it saw.
#
# The recipient is matched against the recorded dispatches, so only agents this
# branch actually dispatched as reviewers are refused. Every other agent — the
# fixer included — is none of this hook's business.

set -u

HOOK_INPUT=""
if [[ -p /dev/stdin || ! -t 0 ]]; then
  IFS= read -r -d '' HOOK_INPUT || true
fi
[[ -n "$HOOK_INPUT" ]] || exit 0
case "$HOOK_INPUT" in *SendMessage*) ;; *) exit 0 ;; esac

_DIR="${BASH_SOURCE[0]%[/\\]*}"; [[ "$_DIR" == "${BASH_SOURCE[0]}" ]] && _DIR=.
case "$_DIR" in /*|[A-Za-z]:*) ;; *) _DIR="$PWD/$_DIR" ;; esac

_field() {
  local path="$1" out=""
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
    print(d if isinstance(d, str) else "")
except Exception:
    print("")' 2>/dev/null || true)"
  fi
  printf '%s' "$out"
}

# With no JSON parser the recipient cannot be read safely — a sed-based read
# stops at the first quote — so the decision is made on the raw payload, scoped
# to the `to` field so that merely naming a reviewer in the message body cannot
# trigger it.
if ! command -v jq >/dev/null 2>&1 && ! command -v python3 >/dev/null 2>&1; then
  printf '%s' "$HOOK_INPUT" \
    | grep -Eqi '"to"[[:space:]]*:[[:space:]]*"[^"]*(l1-reviewer|adversarial-reviewer|security-auditor|spec-reviewer)' \
    || exit 0
  echo "exloom: a reviewer is dispatched, never resumed. Dispatch a fresh reviewer in MODE: VERIFY <from>..<to>." >&2
  echo "exloom: (no JSON parser on PATH, so this was decided on the raw payload)" >&2
  exit 2
fi

[[ "$(_field tool_name)" == "SendMessage" ]] || exit 0
TO="$(_field tool_input.to)"
[[ -n "$TO" ]] || exit 0

git rev-parse --show-toplevel >/dev/null 2>&1 || exit 0
ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
cd "$ROOT" 2>/dev/null || exit 0
_XLDIR="${BASH_SOURCE[0]%[/\\]*}"; [[ "$_XLDIR" == "${BASH_SOURCE[0]}" ]] && _XLDIR=.
# shellcheck source=/dev/null
. "$_XLDIR/lib.sh"
exloom_gate_active || exit 0

REVIEWERS='l1-reviewer|adversarial-reviewer|security-auditor|spec-reviewer'

# Named outright — `exloom:l1-reviewer`, or a name the operator chose that
# carries the agent's own name. Matched without regard to case or prefix: the
# recipient string comes from whoever typed it, not from the dispatch log.
HIT=""
TO_N="$(printf '%s' "$TO" | tr '[:upper:]' '[:lower:]' | sed -e 's/^plugin://' -e 's/^exloom://')"
printf '%s' "$TO_N" | grep -Eq "(^|[^a-z-])(${REVIEWERS})([^a-z-]|$)" && HIT="$TO"

# Otherwise an opaque agent id: resolve it through the dispatch log, which maps
# agent_id to the tool call that launched it, and that call to the agent name.
if [[ -z "$HIT" ]]; then
  BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
  DLOG=".claude/reviews/${BRANCH}.verdicts/dispatches.jsonl"
  if [[ -f "$DLOG" ]]; then
    SAFE_TO="$(printf '%s' "$TO" | tr -cd 'A-Za-z0-9_-')"
    TUID="$(grep -F '"map":true' "$DLOG" 2>/dev/null | grep -F "\"agent_id\":\"${SAFE_TO}\"" | tail -1 \
      | sed -n 's/.*"tool_use_id":"\([^"]*\)".*/\1/p')"
    if [[ -n "$TUID" ]]; then
      AGENT="$(grep -F "\"tool_use_id\":\"${TUID}\"" "$DLOG" 2>/dev/null | grep -F '"dispatch_head"' | tail -1 \
        | sed -n 's/.*"agent":"\([^"]*\)".*/\1/p')"
      printf '%s' "$AGENT" | tr '[:upper:]' '[:lower:]' | grep -Eq "^(${REVIEWERS})$" && HIT="$AGENT"
    fi
  fi
fi

[[ -n "$HIT" ]] || exit 0

cat >&2 <<EOF
exloom: refusing to message ${HIT} — a reviewer is dispatched, never resumed.

A resumed reviewer brings its own earlier verdict and this session's framing
into the next pass, so a rejection can be argued down without the code changing,
and the pass leaves no receipt of its own.

To check whether fixes landed, dispatch a FRESH reviewer in verify mode:
  MODE: VERIFY <reviewed-sha>..<current-sha>
It records a new receipt naming the commit it saw, and findings it marks
ADDRESSED close on their own.
EOF
exit 2
