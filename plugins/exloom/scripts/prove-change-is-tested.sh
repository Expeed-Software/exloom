#!/usr/bin/env bash
# exloom — prove-change-is-tested.sh
#
# Answers one question mechanically, before review, in the author's own session:
#
#     If I take my source change away and keep my tests, do my tests fail?
#
# If they still pass, the tests do not test the change. That is the author's own
# item 4 ("my tests assert text, not behaviour") turned into a command instead of
# a resolution — and a resolution is exactly the thing that does not hold.
#
# WHY THIS AND NOT MORE REVIEW. Real review transcripts show rounds 2..7 spent on
# defects a script catches before the first commit:
#   - a test asserting `hasMessageContaining("a")` on an object named `a`,
#     satisfied by the letter "a" in any sentence — a reviewer gutted the code and
#     the suite stayed green;
#   - a committed test proving a value reached the builder, none proving it came
#     back out;
#   - a Gradle test task reported UP-TO-DATE for javadoc-only edits, so the suite
#     silently did not run for precisely the change class it existed to catch.
# All three fail this check. None of them needed a reviewer.
#
# SAFE BY CONSTRUCTION. Everything runs in a throwaway `git worktree`. The working
# tree is never modified, so there is nothing to restore and no way to leave the
# repo dirty if this is interrupted. No reviewer-written command is executed —
# only the test command this repo already runs.
#
# Usage:
#   bash prove-change-is-tested.sh [--base <ref>] [--cmd "<test command>"]
#
#   --base  what to compare against (default: merge-base with the upstream
#           default branch, else HEAD~1)
#   --cmd   the test command (default: auto-detected, see below)
#
# Exit codes:
#   0  proved: removing the source change makes the tests fail
#   1  NOT proved: tests still pass without the change  <-- the finding
#   2  could not run (no test command, no changed sources, worktree failure)

set -u

BASE=""; TESTCMD=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --base) BASE="${2:-}"; shift 2 ;;
    --cmd)  TESTCMD="${2:-}"; shift 2 ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "not a git repo" >&2; exit 2; }
cd "$ROOT" || exit 2

# ---------- base ----------
if [[ -z "$BASE" ]]; then
  for r in origin/main origin/master origin/dev origin/develop; do
    BASE="$(git merge-base HEAD "$r" 2>/dev/null)" && [[ -n "$BASE" ]] && break
    BASE=""
  done
  [[ -n "$BASE" ]] || BASE="$(git rev-parse HEAD~1 2>/dev/null || true)"
fi
[[ -n "$BASE" ]] || { echo "cannot determine a base commit; pass --base" >&2; exit 2; }

# ---------- test command ----------
# A repo may pin its own, which is always better than detection.
if [[ -z "$TESTCMD" && -f ".claude/exloom-test-command" ]]; then
  TESTCMD="$(head -1 .claude/exloom-test-command)"
fi
if [[ -z "$TESTCMD" ]]; then
  # `--rerun-tasks` / `--force` are deliberate: a cached "BUILD SUCCESSFUL" is the
  # exact failure this check exists to expose, so never let the build skip work.
  if   [[ -f gradlew        ]]; then TESTCMD="./gradlew test --rerun-tasks"
  elif [[ -f mvnw           ]]; then TESTCMD="./mvnw -q test"
  elif [[ -f package.json   ]]; then TESTCMD="npm test"
  elif [[ -f pytest.ini || -f pyproject.toml || -f setup.cfg ]]; then TESTCMD="pytest -q"
  elif [[ -f go.mod         ]]; then TESTCMD="go test ./... -count=1"
  elif [[ -f Cargo.toml     ]]; then TESTCMD="cargo test"
  fi
fi
[[ -n "$TESTCMD" ]] || {
  echo "no test command detected — pass --cmd or commit .claude/exloom-test-command" >&2; exit 2; }

# ---------- classify the diff ----------
CHANGED="$(git diff --name-only "$BASE" -- . 2>/dev/null; git diff --name-only --cached "$BASE" -- . 2>/dev/null; git ls-files --others --exclude-standard 2>/dev/null)"
CHANGED="$(printf '%s\n' "$CHANGED" | sed '/^$/d' | sort -u)"
[[ -n "$CHANGED" ]] || { echo "no changes against ${BASE:0:12}" >&2; exit 2; }

is_test() {
  case "$1" in
    */test/*|*/tests/*|*/spec/*|*/__tests__/*|test/*|tests/*|spec/*) return 0 ;;
    *Test.java|*Tests.java|*IT.java|*Spec.groovy|*_test.go|*_test.py|test_*.py) return 0 ;;
    *.test.ts|*.test.js|*.test.tsx|*.spec.ts|*.spec.js|*.spec.tsx) return 0 ;;
  esac
  return 1
}

SRC=""; TST=""
while IFS= read -r f; do
  [[ -z "$f" ]] && continue
  case "$f" in *.md|docs/*|.claude/*) continue ;; esac
  if is_test "$f"; then TST+="$f"$'\n'; else SRC+="$f"$'\n'; fi
done <<< "$CHANGED"
SRC="$(printf '%s' "$SRC" | sed '/^$/d')"
TST="$(printf '%s' "$TST" | sed '/^$/d')"

_receipt_early() {
  local result="$1" branch vdir head
  branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)" || return 0
  [[ -n "$branch" && "$branch" != "HEAD" ]] || return 0
  [[ -f ".claude/exloom-gate.enabled" ]] || return 0
  head="$(git rev-parse HEAD 2>/dev/null)" || return 0
  vdir=".claude/reviews/${branch}.verdicts"
  mkdir -p "$vdir" 2>/dev/null || return 0
  printf '{"check":"change-is-tested","result":"%s","base":"%s","head":"%s","cmd":"no-test-file-changed","at":"%s"}\n' \
    "$result" "$BASE" "$head" "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true)" \
    >> "${vdir}/proof.json" 2>/dev/null || return 0
}

[[ -n "$SRC" ]] || { echo "no source changes to prove (docs/tests only)" >&2; exit 2; }
if [[ -z "$TST" ]]; then
  BASE="$BASE" TESTCMD="${TESTCMD:-none}" _receipt_early NOT_PROVED
  echo "NOT PROVED: this change touches source but adds or changes NO test."
  printf '  source changed:\n%s\n' "$(printf '%s\n' "$SRC" | sed 's/^/    /')"
  exit 1
fi

# ---------- build the counterfactual in a throwaway worktree ----------
WT="$(mktemp -d "${TMPDIR:-/tmp}/exloom-proof.XXXXXX")" || exit 2
cleanup() { git worktree remove --force "$WT" >/dev/null 2>&1 || rm -rf "$WT"; }
trap cleanup EXIT

git worktree add --detach -q "$WT" "$BASE" >/dev/null 2>&1 || { echo "worktree failed" >&2; exit 2; }

# Source stays at BASE (the change removed); tests come from the working tree.
copied=0
while IFS= read -r t; do
  [[ -z "$t" ]] && continue
  [[ -f "$t" ]] || continue
  mkdir -p "$WT/$(dirname "$t")" 2>/dev/null
  cp "$t" "$WT/$t" 2>/dev/null && copied=$((copied+1))
done <<< "$TST"
[[ $copied -gt 0 ]] || { echo "could not stage test files into the worktree" >&2; exit 2; }

echo "base:    ${BASE:0:12}"
echo "command: $TESTCMD"
echo "source held at base; $copied test file(s) taken from the working tree"
echo "running…"

( cd "$WT" && eval "$TESTCMD" ) >"$WT/.exloom-out" 2>&1
rc=$?

# ---------- write the receipt ----------
# Into the SAME protected directory as reviewer receipts, for the same reason:
# protect-verdicts.sh denies writing there by hand, so this file is evidence that
# the check ran, not an assertion that it did. Only this script writes it, and
# the gate requires one covering the commit being shipped.
#
# Without this the check is a script somebody has to remember to run — which is
# the category of thing this whole mechanism exists because nobody remembers.
_receipt() {
  local result="$1" branch vdir head
  branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)" || return 0
  [[ -n "$branch" && "$branch" != "HEAD" ]] || return 0
  [[ -f ".claude/exloom-gate.enabled" ]] || return 0
  head="$(git rev-parse HEAD 2>/dev/null)" || return 0
  vdir=".claude/reviews/${branch}.verdicts"
  mkdir -p "$vdir" 2>/dev/null || return 0
  printf '{"check":"change-is-tested","result":"%s","base":"%s","head":"%s","cmd":"%s","at":"%s"}\n' \
    "$result" "$BASE" "$head" \
    "$(printf '%s' "$TESTCMD" | tr -cd 'A-Za-z0-9 ._:/@=+-' | cut -c1-200)" \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true)" \
    >> "${vdir}/proof.json" 2>/dev/null || return 0
  echo "exloom: recorded proof receipt (${result}) at ${vdir}/proof.json — commit it with the checklist" >&2
}

if [[ $rc -ne 0 ]]; then
  _receipt PROVED
  echo
  echo "PROVED — without the source change, the tests fail (exit $rc)."
  echo "The tests notice this change. That is the property; it is not a guarantee they assert the RIGHT thing."
  exit 0
fi
_receipt NOT_PROVED

echo
echo "NOT PROVED — the tests PASS without the source change (exit 0)."
echo
echo "One of these is true, and all three cause review rounds:"
echo "  1. the tests do not actually exercise the change (assertions too weak to notice it);"
echo "  2. the test runner did not run them (cached / UP-TO-DATE / filtered out) — check the tail below;"
echo "  3. the change genuinely has no observable behaviour, in which case say so explicitly."
echo
echo "--- last 25 lines of the run ---"
tail -25 "$WT/.exloom-out" 2>/dev/null
exit 1
