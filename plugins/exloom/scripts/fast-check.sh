#!/usr/bin/env bash
# exloom — the fast check that runs after each task.
#
# ADVISORY. It always exits 0 and never routes exloom_next_step. A fast signal
# that blocks when it is wrong gets routed around, and routing around is what
# produces bypass requests.
#
# Target: under 60 seconds. Compile or type-check, lint, and the tests the
# change touches — not the suite, which belongs to the gate or to CI.

set -u

BRANCH=""; CL=""; QUIET=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --quiet) QUIET=1; shift ;;
    --cmd)   FASTCMD="${2:-}"; shift 2 ;;
    *) shift ;;
  esac
done

git rev-parse --show-toplevel >/dev/null 2>&1 || { echo "fast-check: not a git repository" >&2; exit 0; }

# A committed command wins: the repo knows its own toolchain, and an uncommitted
# one would mean each developer checks something different.
FASTCMD="${FASTCMD:-}"
if [[ -z "$FASTCMD" && -f .claude/exloom-fast-command ]] \
   && git ls-files --error-unmatch .claude/exloom-fast-command >/dev/null 2>&1; then
  FASTCMD="$(head -1 .claude/exloom-fast-command 2>/dev/null | tr -d '\r')"
fi

if [[ -z "$FASTCMD" ]]; then
  if   [[ -f gradlew ]]; then FASTCMD="./gradlew compileJava compileTestJava"
  elif [[ -f mvnw ]]; then FASTCMD="./mvnw -q test-compile"
  elif [[ -f tsconfig.json ]]; then FASTCMD="./node_modules/.bin/tsc --noEmit"
  elif [[ -f go.mod ]]; then FASTCMD="go build ./..."
  elif [[ -f Cargo.toml ]]; then FASTCMD="cargo check"
  elif [[ -f pyproject.toml || -f setup.cfg ]]; then FASTCMD="python3 -m compileall -q ."
  fi
fi

if [[ -z "$FASTCMD" ]]; then
  echo "fast-check: no fast command for this stack. Pin one in .claude/exloom-fast-command and commit it."
  exit 0
fi

echo "fast-check: $FASTCMD"
START="$(date +%s 2>/dev/null || echo 0)"
OUT="$(eval "$FASTCMD" 2>&1)"; RC=$?
END="$(date +%s 2>/dev/null || echo 0)"
SECS=$(( END - START )); [[ $SECS -lt 0 ]] && SECS=0

if [[ $RC -eq 0 ]]; then
  RESULT="pass"
  echo "fast-check: pass (${SECS}s)"
else
  RESULT="warn"
  echo "fast-check: WARNING — exit $RC after ${SECS}s. This does not block anything."
  printf '%s\n' "$OUT" | tail -15
fi

if [[ $SECS -gt 60 ]]; then
  echo "fast-check: that took ${SECS}s. Over 60s this stops being used; narrow the command."
fi

# One line per run in the checklist, so the branch carries what was checked and
# when. No receipt: a receipt would imply the gate reads this, and it does not.
BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
CL=".claude/reviews/${BRANCH}.md"
if [[ -n "$BRANCH" && "$BRANCH" != "HEAD" && -f "$CL" && $QUIET -eq 0 ]]; then
  printf -- '- Fast check: `%s` — %s (%ss) at %s\n' \
    "$(printf '%s' "$FASTCMD" | tr -cd 'A-Za-z0-9 ._:/@=+-' | cut -c1-120)" \
    "$RESULT" "$SECS" "$(git rev-parse --short HEAD 2>/dev/null)" >> "$CL" 2>/dev/null \
    && echo "fast-check: recorded in ${CL}"
fi

exit 0
