#!/usr/bin/env bash
# exloom — record-full-suite.sh: run the whole suite once and record the result.
#
# Usage: bash record-full-suite.sh [-- <command> [args...]]
#
# With no command it runs the pinned .claude/exloom-test-command. Writes
# .claude/reviews/<branch>.verdicts/full-suite.json (one line per run: the
# command, its exit code, the commit) and full-suite.out (the last 60 lines).
#
# Only needed where committed .claude/exloom-ci says `none`. With CI the suite
# belongs to branch protection, which runs after the push and so cannot be
# evidence for it.

set -u
[[ "${1:-}" == "--" ]] && shift

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "not in a git repository" >&2; exit 2; }
cd "$ROOT" || exit 2

if [[ $# -eq 0 ]]; then
  if [[ -f .claude/exloom-test-command ]] \
     && git ls-files --error-unmatch .claude/exloom-test-command >/dev/null 2>&1; then
    TESTCMD="$(head -1 .claude/exloom-test-command 2>/dev/null | tr -d '\r')"
  fi
  [[ -n "${TESTCMD:-}" ]] || {
    echo "record-full-suite.sh: no command given and no committed .claude/exloom-test-command" >&2
    exit 2
  }
  set -- bash -c "$TESTCMD"
fi

BRANCH="$(git rev-parse --abbrev-ref HEAD)"
HEAD_SHA="$(git rev-parse HEAD)"
VDIR=".claude/reviews/${BRANCH}.verdicts"
mkdir -p "$VDIR" || exit 2

OUT="$(mktemp)"; trap 'rm -f "$OUT"' EXIT
if command -v timeout >/dev/null 2>&1; then
  timeout 3600 "$@" >"$OUT" 2>&1; rc=$?
else
  "$@" >"$OUT" 2>&1; rc=$?
fi
tail -60 "$OUT" | tr -d '\r' > "$VDIR/full-suite.out"

CMD="$(printf '%s ' "$@" | tr -cd 'A-Za-z0-9 ._:/@=+,-' | cut -c1-200)"
printf '{"check":"full-suite","method":"agent-run","head":"%s","cmd":"%s","exit":%s,"output":"full-suite.out","at":"%s"}\n' \
  "$HEAD_SHA" "${CMD% }" "$rc" "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true)" >> "$VDIR/full-suite.json"

cat "$VDIR/full-suite.out"
echo "exloom: recorded full-suite run (exit $rc) at ${HEAD_SHA:0:12} in $VDIR/full-suite.json — commit it with the checklist" >&2
exit "$rc"
