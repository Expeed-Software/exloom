#!/usr/bin/env bash
# exloom — write the commit list, stat, and full diff for a range to one file.
# Prints the path it wrote. Hand that path to a reviewer subagent so the diff
# never enters the controller's context.
#
# Usage: review-package.sh <base> <head>

set -euo pipefail

BASE="${1:?usage: review-package.sh <base> <head>}"
HEAD_REF="${2:?usage: review-package.sh <base> <head>}"
# reject option-like refs so they cannot be parsed as git options
case "$BASE" in -*) echo "invalid base ref: $BASE" >&2; exit 1;; esac
case "$HEAD_REF" in -*) echo "invalid head ref: $HEAD_REF" >&2; exit 1;; esac

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo .)"
OUTDIR="$ROOT/.exloom/execution"
mkdir -p "$OUTDIR"

SB="$(git rev-parse --short "$BASE" 2>/dev/null || echo "$BASE")"
SH="$(git rev-parse --short "$HEAD_REF" 2>/dev/null || echo "$HEAD_REF")"
OUT="$OUTDIR/review-${SB}-${SH}.md"

{
  echo "# Review package: ${SB}..${SH}"
  echo
  echo "## Commits"
  echo '```'
  git log --oneline "${BASE}..${HEAD_REF}"
  echo '```'
  echo
  echo "## Stat"
  echo '```'
  git diff --stat "${BASE}..${HEAD_REF}"
  echo '```'
  echo
  echo "## Diff (with context)"
  echo '```diff'
  git diff -U10 "${BASE}..${HEAD_REF}"
  echo '```'
} > "$OUT"

echo "$OUT"
