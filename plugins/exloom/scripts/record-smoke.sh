#!/usr/bin/env bash
# exloom — record-smoke.sh: run a smoke check and record what it printed.
#
# Usage: bash record-smoke.sh [--method e2e] -- <command> [args...]
#
# Writes .claude/reviews/<branch>.verdicts/smoke.json (one line per run: the
# command, its exit code, the commit) and smoke.out (the last 60 lines of
# output). Only this script writes them; the gate accepts an agent-run receipt
# for a CLI or API change at Tier 0-2. A UI change below Tier 3 needs the e2e
# method (an end-to-end test of the user action) or a pasted result; Tier 3 needs
# a pasted result.

set -u
METHOD="agent-run"; LIMIT=300
if [[ "${1:-}" == "--method" ]]; then
  [[ "${2:-}" == "e2e" ]] || { echo "record-smoke.sh: the only method is e2e" >&2; exit 2; }
  METHOD="e2e"; LIMIT=900; shift 2
fi
[[ "${1:-}" == "--" ]] && shift
[[ $# -gt 0 ]] || { echo "usage: record-smoke.sh [--method e2e] -- <command> [args...]" >&2; exit 2; }

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "not in a git repository" >&2; exit 2; }
cd "$ROOT" || exit 2
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
HEAD_SHA="$(git rev-parse HEAD)"
VDIR=".claude/reviews/${BRANCH}.verdicts"
mkdir -p "$VDIR" || exit 2

OUT="$(mktemp)"; trap 'rm -f "$OUT"' EXIT
if command -v timeout >/dev/null 2>&1; then
  timeout "$LIMIT" "$@" >"$OUT" 2>&1; rc=$?
else
  "$@" >"$OUT" 2>&1; rc=$?
fi
tail -60 "$OUT" | tr -d '\r' > "$VDIR/smoke.out"

CMD="$(printf '%s ' "$@" | tr -cd 'A-Za-z0-9 ._:/@=+,-' | cut -c1-200)"
printf '{"check":"smoke","method":"%s","head":"%s","cmd":"%s","exit":%s,"output":"smoke.out","at":"%s"}\n' \
  "$METHOD" "$HEAD_SHA" "${CMD% }" "$rc" "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true)" >> "$VDIR/smoke.json"

cat "$VDIR/smoke.out"
echo "exloom: recorded smoke run (exit $rc) at ${HEAD_SHA:0:12} in $VDIR/smoke.json — commit it with the checklist" >&2
exit "$rc"
