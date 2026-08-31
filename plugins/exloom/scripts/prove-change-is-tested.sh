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
# WHAT THE WORKTREE PROTECTS, AND WHAT IT DOES NOT. Everything runs in a throwaway
# `git worktree`, so your working tree is never modified and there is nothing to
# restore if this is interrupted. That is ALL it protects.
#
# It is NOT a sandbox. A worktree isolates git state, not the process: `eval
# "$TESTCMD"` runs with your full filesystem, network and credential access, and
# $TESTCMD may come from `.claude/exloom-test-command` — a file the branch under
# review authors. Only run this on a branch you would already be willing to run
# `npm test` on.
#
# The previous version of this comment asserted "no reviewer-written command is
# executed", directly above the eval. Security review flagged that confident, wrong
# claim as the reason the risk was easy to wave through in review.
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

# Resolve to a commit id before ANY use. `--base` was interpolated raw into the
# proof receipt while every other value on that line was sanitised, so
#
#   --base '","result":"PROVED","x":"'
#
# minted a receipt carrying both the real NOT_PROVED and an injected PROVED —
# and exloom_check_proof tests for PROVED first, so the forgery won. The early
# receipt path is reachable with an unresolvable ref because `CHANGED` is also
# fed by `git ls-files --others`, so the failed `git diff` does not abort.
#
# Sanitising the string would leave the next caller to remember. Resolving it
# means a value that is not a commit cannot exist past this line, so neither
# receipt writer can emit one — and an unresolvable base now fails loudly
# instead of proceeding with a ref git never accepted.
BASE="$(git rev-parse --verify --quiet "${BASE}^{commit}" 2>/dev/null || true)"
[[ -n "$BASE" ]] || { echo "--base does not resolve to a commit in this repo" >&2; exit 2; }

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

echo "base:    ${BASE:0:12}"
echo "command: $TESTCMD"

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
  local cmdhash="none"
  [[ -f ".claude/exloom-test-command" ]] && cmdhash="$(git hash-object .claude/exloom-test-command 2>/dev/null || echo none)"
  printf '{"check":"change-is-tested","result":"%s","base":"%s","head":"%s","cmd":"%s","cmd_hash":"%s","at":"%s"}\n' \
    "$result" "$BASE" "$head" \
    "$(printf '%s' "$TESTCMD" | tr -cd 'A-Za-z0-9 ._:/@=+-' | cut -c1-200)" \
    "$cmdhash" \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true)" \
    >> "${vdir}/proof.json" 2>/dev/null || return 0
  echo "exloom: recorded proof receipt (${result}) at ${vdir}/proof.json — commit it with the checklist" >&2
}

# ---------- RUN 1: base source + base tests. MUST PASS. ----------
# Without this control the whole check was meaningless. The decision used to be
# `rc != 0 -> PROVED`, so ANY failure in the base worktree minted the receipt:
#   - the new test references a symbol the change introduced, so it does not
#     compile at base (the modal case for every change that adds a function);
#   - `git worktree add` does not copy gitignored files, so node_modules/.venv/
#     vendor/target are absent and every run fails on a missing dependency —
#     a repo with gitignored deps got an unconditional PROVED forever;
#   - a broken runner, an OOM, a daemon crash, or `--cmd false`.
# Reproduced twice by review. This control turns all of those into "the
# environment cannot run the suite", which is not evidence of anything.
echo "run 1/2: base source + base tests (control — must pass)…"
( cd "$WT" && eval "$TESTCMD" ) >"$WT/.base-out" 2>&1
base_rc=$?
if [[ $base_rc -ne 0 ]]; then
  echo
  echo "PROOF VOID — the suite does not pass at the base commit (exit $base_rc)."
  echo "Nothing can be concluded: a failure with your tests added would be"
  echo "indistinguishable from the environment simply not working here."
  echo
  echo "Most common cause: the throwaway worktree has no gitignored dependencies"
  echo "(node_modules/, .venv/, vendor/, target/). Install them there, pin a"
  echo "self-contained command in .claude/exloom-test-command, or run this from a"
  echo "checkout where the suite passes."
  echo
  echo "--- last 25 lines ---"; tail -25 "$WT/.base-out" 2>/dev/null
  exit 2                      # deliberately NO receipt: not proved, not disproved
fi

# ---------- RUN 2: base source + NEW tests. MUST FAIL, and for the right reason.
copied=0
while IFS= read -r t; do
  [[ -z "$t" ]] && continue
  [[ -f "$t" ]] || continue
  mkdir -p "$WT/$(dirname "$t")" 2>/dev/null
  cp "$t" "$WT/$t" 2>/dev/null && copied=$((copied+1))
done <<< "$TST"
[[ $copied -gt 0 ]] || { echo "could not stage test files into the worktree" >&2; exit 2; }

echo "run 2/2: base source + your $copied test file(s) (must fail)…"
( cd "$WT" && eval "$TESTCMD" ) >"$WT/.exloom-out" 2>&1
rc=$?

# 126/127 are "not executable" / "command not found" — a broken command, never a
# test noticing anything.
if [[ $rc -eq 126 || $rc -eq 127 ]]; then
  _receipt NOT_PROVED
  echo; echo "NOT PROVED — the test command could not run (exit $rc)."
  tail -10 "$WT/.exloom-out" 2>/dev/null
  exit 1
fi

# RUN 3: your change + your tests. MUST PASS.
#
# This replaces an output heuristic that asked whether the failure "looked like" a
# test failing. It rejected the forgery and also rejected `[ "$(calc)" = "5" ]` —
# a perfectly good shell assertion that fails silently. Guessing from output was
# the wrong instrument; behaviour is the right one.
#
# The forgery security review demonstrated is `[ ! -e tests/t.sh ]`: exit 0 at base
# because the test file is absent, exit 1 in run 2 because it has been copied in.
# It survives runs 1 and 2. It cannot survive this one — with the change AND the
# tests both present, it still exits 1, so the branch fails its own tests.
#
# This also catches something worth catching on its own: tests that do not actually
# pass on the change they were written for.
if [[ $rc -ne 0 ]]; then
  while IFS= read -r sf; do
    [[ -n "$sf" && -f "$sf" ]] || continue
    mkdir -p "$WT/$(dirname "$sf")" 2>/dev/null
    cp "$sf" "$WT/$sf" 2>/dev/null
  done <<< "$SRC"
  ( cd "$WT" && eval "$TESTCMD" ) >"$WT/.now-out" 2>&1
  now_rc=$?
  if [[ $now_rc -ne 0 ]]; then
    _receipt NOT_PROVED
    echo
    echo "NOT PROVED — your tests do not pass on your own change (exit $now_rc)."
    echo
    echo "The suite passed at the base commit and failed with your tests added, but"
    echo "it also fails with the change itself applied. So the failure is not your"
    echo "tests noticing the change — either the change is broken, or the command"
    echo "does not run tests at all (a command that inverts on a file's existence"
    echo "produces exactly this shape)."
    echo
    echo "command: $TESTCMD"
    echo "--- last 25 lines ---"; tail -25 "$WT/.now-out" 2>/dev/null
    exit 1
  fi
fi

# Signatures cover the modal "symbol does not exist at base" form in each language
# the script auto-detects. Go says `undefined: Foo`, Python NameError/AttributeError,
# Rust `cannot find function` / error[E0425], C# error CS0103 — none of which the
# first list had, so those repos still minted a false PROVED. `no such file or
# directory` was REMOVED: it is a normal assertion failure when a test checks that
# the change produces an output artifact, and matching it misreported a real proof.
#
# A failure that is a BUILD failure rather than a test failure proves only that
# the tests mention new code — not that they assert anything about its behaviour.
# The vacuous case is real: a test asserting `typeof f === 'function'` against a
# deliberately broken `f` produced PROVED, because at base `f` did not exist.
if [[ $rc -ne 0 ]] && grep -qiE 'cannot find symbol|error: package .* does not exist|compilation failed|compileJava FAILED|ModuleNotFoundError|ImportError|NameError|AttributeError: module|cannot find module|unresolved reference|error TS[0-9]+|undefined reference|undefined: [A-Za-z_]|cannot find function|cannot find value|cannot find type|error CS[0-9]+|error\[E0[0-9]+\]|command not found' "$WT/.exloom-out" 2>/dev/null; then
  _receipt NOT_PROVED
  echo
  echo "NOT PROVED — the base run failed to BUILD, not to assert (exit $rc)."
  echo "Your tests reference code the change introduces, so they cannot compile"
  echo "without it. That shows the tests depend on the change; it does not show"
  echo "they would notice the change being WRONG."
  echo
  echo "To prove that, the test must be able to run against the old code and fail"
  echo "on the assertion — e.g. exercise behaviour through an interface that"
  echo "exists at base, or assert on an observable output rather than on a symbol."
  echo
  echo "--- last 25 lines ---"; tail -25 "$WT/.exloom-out" 2>/dev/null
  exit 1
fi


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
