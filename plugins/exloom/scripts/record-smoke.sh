#!/usr/bin/env bash
# exloom — record-smoke.sh: run a smoke check and record what it printed.
#
# Usage: bash record-smoke.sh [--method e2e] -- <command> [args...]
#        bash record-smoke.sh --method browser --observed <file>
#
# Writes .claude/reviews/<branch>.verdicts/smoke.json (one line per run: the
# command, its exit code, the commit) and smoke.out (the last 60 lines of
# output). Only this script writes them; the gate accepts an agent-run receipt
# for a CLI or API change at Tier 0-2. A UI change at any tier needs the e2e
# method (an end-to-end test of the user action), the browser method (what the
# agent saw driving a browser tool) or a pasted result; any other Tier 3 change
# needs a pasted result.

set -u
METHOD="agent-run"; LIMIT=300; OBSERVED=""
if [[ "${1:-}" == "--method" ]]; then
  case "${2:-}" in
    e2e) METHOD="e2e"; LIMIT=900; shift 2 ;;
    browser)
      METHOD="browser"; shift 2
      [[ "${1:-}" == "--observed" && -s "${2:-}" ]] \
        || { echo "usage: record-smoke.sh --method browser --observed <file>" >&2; exit 2; }
      OBSERVED="$2"; shift 2
      for label in Tool: URL: Observed:; do
        grep -q "^${label}[[:space:]]*[^[:space:]]" "$OBSERVED" \
          || { echo "record-smoke.sh: ${OBSERVED} needs a line starting '${label}' with what it was" >&2; exit 2; }
      done ;;
    *) echo "record-smoke.sh: the methods are e2e and browser" >&2; exit 2 ;;
  esac
fi
if [[ -z "$OBSERVED" ]]; then
  [[ "${1:-}" == "--" ]] && shift
  [[ $# -gt 0 ]] || { echo "usage: record-smoke.sh [--method e2e] -- <command> [args...]" >&2; exit 2; }
fi

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "not in a git repository" >&2; exit 2; }
cd "$ROOT" || exit 2
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
HEAD_SHA="$(git rev-parse HEAD)"
VDIR=".claude/reviews/${BRANCH}.verdicts"
mkdir -p "$VDIR" || exit 2

OUT="$(mktemp)"; trap 'rm -f "$OUT"' EXIT
if [[ -n "$OBSERVED" ]]; then
  head -60 "$OBSERVED" | tr -d '\r' > "$VDIR/smoke.out"; rc=0
  set -- "observed with $(sed -n 's/^Tool:[[:space:]]*//p' "$OBSERVED" | head -1)"
elif command -v timeout >/dev/null 2>&1; then
  timeout "$LIMIT" "$@" >"$OUT" 2>&1; rc=$?
  tail -60 "$OUT" | tr -d '\r' > "$VDIR/smoke.out"
else
  "$@" >"$OUT" 2>&1; rc=$?
  tail -60 "$OUT" | tr -d '\r' > "$VDIR/smoke.out"
fi

CMD="$(printf '%s ' "$@" | tr -cd 'A-Za-z0-9 ._:/@=+,-' | cut -c1-200)"
printf '{"check":"smoke","method":"%s","head":"%s","cmd":"%s","exit":%s,"output":"smoke.out","at":"%s"}\n' \
  "$METHOD" "$HEAD_SHA" "${CMD% }" "$rc" "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true)" >> "$VDIR/smoke.json"

cat "$VDIR/smoke.out"
echo "exloom: recorded smoke run (exit $rc) at ${HEAD_SHA:0:12} in $VDIR/smoke.json — commit it with the checklist" >&2
exit "$rc"
