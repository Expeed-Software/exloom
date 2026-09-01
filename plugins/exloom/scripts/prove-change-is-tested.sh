#!/usr/bin/env bash
# exloom — prove-change-is-tested.sh
#
# Answers one question mechanically, before review:
#
#     If I take my source change away and keep my tests, do my tests fail?
#
# If they still pass, the tests do not test the change.
#
# NOT A SANDBOX. Everything runs in a throwaway `git worktree`, so your working
# tree is never modified — that is ALL it protects. A worktree isolates git
# state, not the process: `eval "$TESTCMD"` runs with your full filesystem,
# network and credential access, and $TESTCMD may come from a committed
# `.claude/exloom-test-command`. Only run this on a branch you would already be
# willing to run `npm test` on.
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

# Resolve to a commit id before ANY use: `--base` reaches the receipt, so a value
# that is not a commit must not be able to exist past this line.
BASE="$(git rev-parse --verify --quiet "${BASE}^{commit}" 2>/dev/null || true)"
[[ -n "$BASE" ]] || { echo "--base does not resolve to a commit in this repo" >&2; exit 2; }

# ---------- test command ----------
# A repo may pin its own, which is always better than detection.
# Must be TRACKED: this value is `eval`d with full filesystem and credential
# access, so an untracked file is arbitrary code execution that appears in no
# diff and no PR. Same rule as exloom-protected-branches / exloom-skip-branches.
if [[ -z "$TESTCMD" && -f ".claude/exloom-test-command" ]]; then
  if git ls-files --error-unmatch ".claude/exloom-test-command" >/dev/null 2>&1; then
    TESTCMD="$(head -1 .claude/exloom-test-command)"
  else
    echo "exloom: ignoring UNTRACKED .claude/exloom-test-command — this value is eval'd," >&2
    echo "        so it must be committed to be honoured. Run:" >&2
    echo "          git add .claude/exloom-test-command && git commit -m 'chore: pin exloom test command'" >&2
    echo "        or pass the command explicitly with --cmd." >&2
  fi
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
  # A production source root is never a test, whatever its subdirectories are
  # called. `orchestration/spec/` under src/main is production code; matching
  # */spec/* there reverted half a package and left the tree uncompilable, so
  # the proof failed for a reason that had nothing to do with the tests.
  case "$1" in
    */src/main/*|*/main/java/*|*/main/kotlin/*|*/main/scala/*|*/main/resources/*|*/app/src/main/*) return 1 ;;
  esac
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
# ---------- which acceptance criteria did the suite run? ----------
# The ref goes in the test NAME, so one JUnit-XML parser covers every runner
# instead of one annotation reader per framework. Both `F-012/R-3/AC-2` and
# `F012_R3_AC2` are read, since a method name cannot contain `/` or `-`.
# Only passing cases count.
_criteria_from_reports() {   # _criteria_from_reports <worktree>
  local wt="$1" glob="" reports=""
  glob="$(head -1 .claude/exloom-test-report 2>/dev/null | tr -d '\r[:space:]')"
  if [[ -n "$glob" ]]; then
    reports="$(cd "$wt" 2>/dev/null && find . -path "./$glob" -name '*.xml' 2>/dev/null)"
  fi
  if [[ -z "$reports" ]]; then
    # The conventional locations, in the order they are worth trying. Bounded so
    # a huge tree does not turn a proof run into a filesystem walk.
    reports="$(cd "$wt" 2>/dev/null && find . \
      \( -path '*/test-results/*' -o -path '*/surefire-reports/*' -o -path '*/failsafe-reports/*' \
         -o -path '*/junit*' -o -path '*/reports/*' \) \
      -name '*.xml' -type f 2>/dev/null | head -400)"
  fi
  [[ -n "$reports" ]] || return 0

  if command -v python3 >/dev/null 2>&1; then
    ( cd "$wt" && printf '%s\n' "$reports" | python3 -c '
import sys, re, xml.etree.ElementTree as ET
REF = re.compile(r"F-?(\d+)[/_]R-?(\d+)[/_]AC-?(\d+)")
# XXE and billion-laughs both need a DTD, and a JUnit report never has one — so
# refusing any file that declares one closes both without needing defusedxml,
# which cannot be assumed present on a developer machine or a CI image. These
# files are written by the repos test runner, but a proof run parses whatever is
# on disk and that is not the same trust boundary.
DTD = re.compile(rb"<!(DOCTYPE|ENTITY)", re.I)
found = set()
for line in sys.stdin:
    path = line.strip()
    if not path:
        continue
    try:
        with open(path, "rb") as fh:
            head = fh.read(8192)
        if DTD.search(head):
            continue
        root = ET.parse(path).getroot()
    except Exception:
        continue
    for tc in root.iter("testcase"):
        # A case with a child failure/error/skipped did not pass, so it covers
        # nothing. Absence of those children is what "passed" means in this format.
        if any(c.tag in ("failure", "error", "skipped") for c in tc):
            continue
        for attr in ("name", "classname"):
            for m in REF.finditer(tc.get(attr) or ""):
                found.add("F-%s/R-%s/AC-%s" % (m.group(1), m.group(2), m.group(3)))
print(" ".join(sorted(found)))
' 2>/dev/null )
  else
    # No python3: name-only scan. Cannot tell a passing case from a failing one,
    # so it reports nothing rather than reporting a criterion that failed as
    # covered. Silence is the honest answer; a wrong coverage number is not.
    return 0
  fi
}

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
  printf '{"check":"change-is-tested","result":"%s","base":"%s","head":"%s","cmd":"%s","cmd_hash":"%s","criteria":"%s","at":"%s"}\n' \
    "$result" "$BASE" "$head" \
    "$(printf '%s' "$TESTCMD" | tr -cd 'A-Za-z0-9 ._:/@=+-' | cut -c1-200)" \
    "$cmdhash" \
    "${CRITERIA_RAN:-}" \
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

# A ref in a test name is a claim. A test that passes against the BASE source
# does not notice the change, whatever it is called — so subtracting this set
# from run 3's leaves the criteria the runs actually prove. Captured now because
# run 3 reuses this worktree and overwrites the reports.
CRITERIA_BASE_OK="$(_criteria_from_reports "$WT")"

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
# Catches a command that inverts on the test file's existence (`[ ! -e tests/t.sh ]`
# passes runs 1 and 2 while testing nothing), and, on its own merit, tests that do
# not pass on the change they were written for.
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

# A BUILD failure proves only that the tests mention new code, not that they
# assert anything about it — `typeof f === 'function'` yields PROVED purely
# because `f` does not exist at base. Signatures cover the "symbol missing at
# base" form per language. Do NOT add `no such file or directory`: that is a
# normal assertion failure when a test checks for an output artifact.
if [[ $rc -ne 0 ]] && grep -qiE 'cannot find symbol|error: package .* does not exist|compilation failed|compileJava FAILED|ModuleNotFoundError|ImportError|NameError|AttributeError: module|cannot find module|unresolved reference|error TS[0-9]+|undefined reference|undefined: [A-Za-z_]|cannot find function|cannot find value|cannot find type|error CS[0-9]+|error\[E0[0-9]+\]|command not found' "$WT/.exloom-out" 2>/dev/null; then
  # A purely additive change cannot satisfy the three-run proof: its tests do not
  # compile at base. Mutation asks the same question without needing the code to
  # be absent. The contract is the EXIT CODE — the repo owns the tool and the
  # threshold, exloom does not parse reports.
  MUTCMD="$(head -1 .claude/exloom-mutation-command 2>/dev/null | tr -d '\r')"
  if [[ -n "$MUTCMD" ]] && git ls-files --error-unmatch .claude/exloom-mutation-command >/dev/null 2>&1; then
    echo
    echo "The base run failed to BUILD, so the three-run proof cannot apply here."
    echo "Falling back to mutation, which does not need the code to be absent."
    echo "run 3/3: mutation of the changed code…"
    # $WT already holds your change and your tests, and the suite passed there —
    # run 3 above put it in exactly that state before this branch was reached.
    ( cd "$WT" && eval "$MUTCMD" ) >"$WT/.mut-out" 2>&1
    mut_rc=$?
    if [[ $mut_rc -eq 0 ]]; then
      CRITERIA_RAN="$(_criteria_from_reports "$WT")"
      _receipt PROVED_BY_MUTATION
      echo
      echo "PROVED BY MUTATION — the tests kill the mutants your repo's threshold requires."
      echo "The three-run proof does not apply to a purely additive change; this answers"
      echo "the same question (would the tests notice this being wrong?) without needing"
      echo "the code to be absent."
      [[ -n "$CRITERIA_RAN" ]] && echo "criteria covered by passing tests: $CRITERIA_RAN"
      exit 0
    fi
    _receipt NOT_PROVED
    echo
    echo "NOT PROVED — mutants survived (exit $mut_rc)."
    echo "Tests exist and pass, but they do not notice the change being wrong."
    echo
    echo "command: $MUTCMD"
    echo "--- last 25 lines ---"; tail -25 "$WT/.mut-out" 2>/dev/null
    exit 1
  fi

  _receipt NOT_PROVED
  echo
  echo "NOT PROVED — the base run failed to BUILD, not to assert (exit $rc)."
  echo "Your tests reference code the change introduces, so they cannot compile"
  echo "without it. That shows the tests depend on the change; it does not show"
  echo "they would notice the change being WRONG."
  echo
  echo "Two ways forward:"
  echo "  1. If the change extends existing behaviour, exercise it through an"
  echo "     interface that exists at base and assert on an observable output."
  echo "  2. If the change is PURELY ADDITIVE — a new API, a new control — then"
  echo "     no such interface exists and this proof cannot apply, however the"
  echo "     test is written. Pin a mutation command in"
  echo "     .claude/exloom-mutation-command (committed) that exits 0 when your"
  echo "     threshold is met, and re-run: PIT, Stryker, mutmut, go-mutesting."
  echo
  echo "--- last 25 lines ---"; tail -25 "$WT/.exloom-out" 2>/dev/null
  exit 1
fi


if [[ $rc -ne 0 ]]; then
  # Read from the run-3 worktree, which holds your change and your tests and
  # passed, then drop anything that also passed at base — see CRITERIA_BASE_OK.
  CRITERIA_RAN="$(_criteria_from_reports "$WT")"
  CRITERIA_UNPROVED=""
  if [[ -n "$CRITERIA_RAN" ]]; then
    for _c in $CRITERIA_RAN; do
      case " $CRITERIA_BASE_OK " in
        *" $_c "*) CRITERIA_UNPROVED="${CRITERIA_UNPROVED} ${_c}" ;;
        *) CRITERIA_PROVED="${CRITERIA_PROVED:-} ${_c}" ;;
      esac
    done
    CRITERIA_RAN="$(printf '%s' "${CRITERIA_PROVED:-}" | tr -s ' ' | sed 's/^ //;s/ $//')"
    CRITERIA_UNPROVED="$(printf '%s' "$CRITERIA_UNPROVED" | tr -s ' ' | sed 's/^ //;s/ $//')"
  fi
  _receipt PROVED
  echo
  echo "PROVED — without the source change, the tests fail (exit $rc)."
  echo "The tests notice this change. That is the property; it is not a guarantee they assert the RIGHT thing."
  if [[ -n "$CRITERIA_RAN" ]]; then
    echo
    echo "criteria PROVED (their tests pass with the change and not without it):"
    printf '  %s\n' $CRITERIA_RAN
  fi
  if [[ -n "$CRITERIA_UNPROVED" ]]; then
    echo
    echo "criteria CLAIMED but not proved — these tests pass against the BASE source,"
    echo "so they do not notice the change whatever their name says. A ref in a test"
    echo "name is a claim; this is the check on it."
    printf '  %s\n' $CRITERIA_UNPROVED
  fi
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
