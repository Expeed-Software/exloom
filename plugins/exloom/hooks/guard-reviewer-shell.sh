#!/usr/bin/env bash
# exloom — PreToolUse hook on Bash, scoped to reviewer subagents.
#
# OPT-IN: does nothing unless the repo created `.claude/exloom-gate.enabled`.
#
# A reviewer reads a diff; it has no reason to check one out. Reviewers were
# creating a worktree apiece and removing them inconsistently, which is how a
# repository collects working copies nobody can account for.
#
# A PreToolUse payload raised inside a subagent carries agent_type, so this is
# scoped to the reviewers by name. The fixer, the session itself and the proof
# script's own throwaway worktree are untouched because they are not reviewers,
# not because of a carve-out.

set -u

HOOK_INPUT=""
if [[ -p /dev/stdin || ! -t 0 ]]; then
  IFS= read -r -d '' HOOK_INPUT || true
fi
[[ -n "$HOOK_INPUT" ]] || exit 0
case "$HOOK_INPUT" in *worktree*) ;; *) exit 0 ;; esac
case "$HOOK_INPUT" in
  *l1-reviewer*|*adversarial-reviewer*|*security-auditor*|*spec-reviewer*) ;;
  *) exit 0 ;;
esac

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
  # No JSON parser is a real case on a bare Windows shell. Falling through to an
  # empty agent would let the guard off, so the field is read with sed instead.
  if [[ -z "$out" ]]; then
    out="$(printf '%s' "$HOOK_INPUT" \
      | sed -n "s/.*\"${path##*.}\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -1)"
  fi
  printf '%s' "$out"
}

AGENT="$(_field agent_type)"
case "$AGENT" in
  exloom:l1-reviewer|exloom:adversarial-reviewer|exloom:security-auditor|exloom:spec-reviewer) ;;
  *) exit 0 ;;
esac

CMD="$(_field tool_input.command)"
# Matched on the two words appearing, not on a token sequence. `git` takes
# options before its subcommand and options take values, so any exact sequence
# is one `git -C <path> worktree add` away from being bypassed. `worktree
# remove` and `worktree list` carry no `add`, so tidying up still works, and the
# cost of a false refusal is a reviewer being told to use `git diff`.
printf '%s' "$CMD" | grep -Eq '(^|[^A-Za-z-])worktree([^A-Za-z-]|$)' || exit 0
printf '%s' "$CMD" | grep -Eq '(^|[^A-Za-z-])add([^A-Za-z-]|$)' || exit 0

git rev-parse --show-toplevel >/dev/null 2>&1 || exit 0
ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
[[ -f "${ROOT}/.claude/exloom-gate.enabled" ]] || exit 0

cat >&2 <<EOF
exloom: ${AGENT} may not create a worktree.

A review reads code; it never needs a second working copy, and the ones made
here were not reliably removed.

Read the change with:
  git diff <base>..<head> -- <paths>     the change itself
  git show <sha>:<path>                  any file as it is at a commit
  git log --oneline <base>..<head>       what landed, in order

If a review genuinely cannot be done this way, say so in the report rather than
checking the tree out — that is a finding about the review, not a reason.
EOF
exit 2
