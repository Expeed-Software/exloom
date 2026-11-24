#!/usr/bin/env bash
# exloom — PostToolUse hook (reviewer dispatch log).
#
# OPT-IN: does nothing unless the repo created `.claude/exloom-gate.enabled`.
#
# Records that a reviewer was LAUNCHED. It does not record what the reviewer
# concluded: the reviewer writes its own verdict through scripts/record-verdict.sh,
# which protect-verdicts.sh permits only from inside a reviewer subagent.
#
# This hook used to read the reviewer's report and infer the verdict from it —
# which commit it read and which dispatch it answered were resolved by
# correlating async events, and a failed correlation wrote the line into the
# wrong receipt with a guessed commit. Nothing here infers anything now.
#
# Receipt: .claude/reviews/<branch>.verdicts/<agent>.json — JSONL. A line here
# says a reviewer started; it never satisfies the gate.
#
# NEVER blocks and always exits 0: a missing receipt surfaces later at the gate,
# not here as a broken workflow.

set -u

# ---------- read hook input ----------
HOOK_INPUT=""
if [[ -p /dev/stdin || ! -t 0 ]]; then
  IFS= read -r -d '' HOOK_INPUT || true
fi
[[ -n "$HOOK_INPUT" ]] || exit 0
_DIR="${BASH_SOURCE[0]%[/\\]*}"; [[ "$_DIR" == "${BASH_SOURCE[0]}" ]] && _DIR=.
case "$_DIR" in /*|[A-Za-z]:*) ;; *) _DIR="$PWD/$_DIR" ;; esac
# shellcheck source=/dev/null
. "$_DIR/prefilter.sh"
exloom_may_be_reviewer "$HOOK_INPUT" || exit 0
# shellcheck source=/dev/null
. "$_DIR/lib.sh"

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
    print("")' 2>/dev/null || true)"
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

# Exact names only: any agent whose name merely ends in `l1-reviewer` could
# otherwise write a valid receipt.
AGENT=""
case "$SUBAGENT" in
  exloom:l1-reviewer)          AGENT="l1-reviewer" ;;
  exloom:adversarial-reviewer) AGENT="adversarial-reviewer" ;;
  exloom:security-auditor)     AGENT="security-auditor" ;;
  *) exit 0 ;;
esac

# ---------- which repo is this review ABOUT? ----------
# NOT necessarily the one the session is sitting in. A reviewer dispatched at a
# worktree, or at a second repo in a multi-repo session, runs while the session's
# cwd is somewhere else entirely.
#
# Resolving from cwd alone would find no gate marker there and exit in silence,
# producing a deadlock with no diagnosis: the gate reports "never dispatched",
# and re-dispatching cannot help because every dispatch writes to the wrong repo.
#
# Resolution order, first gate-enabled repo wins:
#   1. the session's cwd, which is right for the ordinary single-repo case;
#   2. any absolute path the dispatch names, mapped back to its repo root.
_repo_is_gated() { [[ -n "$1" && -d "$1" ]] && ( cd "$1" && exloom_gate_active ); }

_repo_of_path() {
  # Walk up to the first real directory rather than dirname-ing once: a path can
  # arrive with JSON escape debris glued to it, so one level up is not reliably
  # a directory.
  local d="$1" up i=0
  while [[ -n "$d" && ! -d "$d" && $i -lt 12 ]]; do
    up="${d%/*}"; [[ "$up" == "$d" ]] && return 1; d="$up"; i=$((i + 1))
  done
  [[ -d "$d" ]] || return 1
  git -C "$d" rev-parse --show-toplevel 2>/dev/null
}

# Absolute paths named anywhere in the payload, Windows or POSIX. `tr` rather
# than sed: the payload's backslashes are JSON-escaped, and getting the escape
# count right through both this script's quoting and the shell's is a losing
# game. `\134` names the backslash, which tr warns about as a literal.
_cited_paths() {
  # Squeeze slashes BEFORE matching. JSON escapes each backslash, so a Windows
  # path arrives as `E:\\Projects` and becomes `E://Projects` here — at which
  # point `[A-Za-z]:/` no longer matches, the drive letter is silently lost, and
  # what is left is a `/Projects/...` that resolves to nothing.
  printf '%s' "$HOOK_INPUT" \
    | tr '\134' '/' | tr -s '/' \
    | grep -oE '([A-Za-z]:)?/[A-Za-z0-9_.@+-][A-Za-z0-9_./@+-]{3,240}' \
    | sort -u | head -40
}

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if ! _repo_is_gated "$REPO_ROOT"; then
  SESSION_REPO="$REPO_ROOT"
  REPO_ROOT=""
  while IFS= read -r cand; do
    [[ -n "$cand" ]] || continue
    r="$(_repo_of_path "$cand" || true)"
    if _repo_is_gated "$r"; then REPO_ROOT="$r"; break; fi
  done < <(_cited_paths)
  if [[ -z "$REPO_ROOT" ]]; then
    # LOUD, not silent. Without a receipt the gate blocks forever, so the one
    # thing that must never happen here is saying nothing.
    echo "exloom: ${AGENT} was dispatched, but no receipt was written - this session's repo (${SESSION_REPO:-none}) has no .claude/exloom-gate.enabled, and no gate-enabled repo was found among the paths the dispatch names." >&2
    echo "exloom: if the review is of another repo or a worktree, run the reviewer from a session rooted there, or the gate will report it as never dispatched." >&2
    exit 0
  fi
  echo "exloom: recording ${AGENT}'s dispatch in ${REPO_ROOT} - the repo the dispatch names, not this session's cwd." >&2
fi
cd "$REPO_ROOT" || exit 0

BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)" || exit 0
[[ -n "$BRANCH" && "$BRANCH" != "HEAD" ]] || exit 0
HEAD_SHA="$(git rev-parse HEAD 2>/dev/null)" || exit 0
[[ -n "$HEAD_SHA" ]] || exit 0

VDIR=".claude/reviews/${BRANCH}.verdicts"
mkdir -p "$VDIR" 2>/dev/null || exit 0
DLOG="${VDIR}/dispatches.jsonl"

# The agent id is only observable here, and guard-reviewer-message.sh resolves a
# message target through it, so the mapping is logged even though no verdict
# depends on it any more.
TUID="$(_field tool_use_id | tr -cd 'A-Za-z0-9_-')"
AID="$(_field tool_response.agentId | tr -cd 'A-Za-z0-9_-')"
MODEL="$(_field tool_response.resolvedModel | tr -cd 'A-Za-z0-9._-')"
if [[ -f "$DLOG" && -n "$TUID" && -n "$AID" ]] \
   && ! grep -qF "\"map\":true,\"tool_use_id\":\"${TUID}\"" "$DLOG"; then
  printf '{"map":true,"tool_use_id":"%s","agent_id":"%s","model":"%s"}\n' \
    "$TUID" "$AID" "$MODEL" >> "$DLOG" 2>/dev/null || true
fi

# ---------- sanitise every value that reaches the receipt ----------
# These are interpolated into JSON with printf and the gate matches receipt lines
# by substring, so a value containing a quote can close its field and append its
# own keys — forging coverage without ever writing to the guarded directory.
_safe() { printf '%s' "${1:-}" | tr -cd 'A-Za-z0-9:._-' | cut -c1-200; }
SUBAGENT="$(_safe "$SUBAGENT")"
SESSION="$(_safe "$(_field session_id)")"
[[ -n "$SUBAGENT" ]] || exit 0

# A per-task review is logged in <agent>.tasks.json, so it is never mistaken for
# a branch round. The task id is read from the dispatch prompt, which exloom
# writes.
TASK_ID="$(_field tool_input.prompt | head -1 \
  | sed -nE 's/^(Review|Verify fixes for) task[[:space:]]*([A-Za-z0-9.-]*).*/\2/p')"
TASK_ID="$(_safe "$TASK_ID")"
RECEIPT="${VDIR}/${AGENT}.json"
[[ -n "$TASK_ID" ]] && RECEIPT="${VDIR}/${AGENT}.tasks.json"

# Once a dispatch is on file for this commit, launching again at the same commit
# says nothing further.
if [[ -f "$RECEIPT" ]] && grep -F "\"head\":\"${HEAD_SHA}\"" "$RECEIPT" 2>/dev/null \
     | grep -qF "\"agent\":\"${AGENT}\""; then
  exit 0
fi

# `"dispatch":true` marks the line as an observation of a LAUNCH, never of a
# conclusion, so a reader of the receipt file can tell the two apart at a glance.
# The gate refuses any verdict-less line regardless; the marker is what lets a
# message name the cause rather than reporting a stale approval.
printf '{"agent":"%s","subagent_type":"%s","head":"%s","dispatch":true,"at":"%s","session":"%s"}\n' \
  "$AGENT" "$SUBAGENT" "$HEAD_SHA" \
  "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true)" "$SESSION" \
  >> "$RECEIPT" 2>/dev/null || exit 0

echo "exloom: recorded ${AGENT} DISPATCH at ${HEAD_SHA:0:12} — a launch, not a review. This line does NOT satisfy the gate." >&2
echo "exloom: the verdict is written by the reviewer itself, through scripts/record-verdict.sh, when it finishes. If none follows, re-dispatch it — and check that this repo is the one the reviewer read, since a review of a worktree or a second repo records its receipt there." >&2
exit 0
