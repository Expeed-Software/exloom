#!/usr/bin/env bash
# test-all.sh — run every suite, in parallel, with the gate suite split by section.
# Usage: bash scripts/test-all.sh [-j N] [--changed [BASE]] [--only REGEX] [--list] [--native]
#   --changed  run only what the files changed since BASE (default: merge-base
#              with main, plus uncommitted work) can affect
#   --only     run only gate sections whose title matches REGEX
#   --native   run on this host even when Docker is available
# With Docker available it runs in a Linux container: on Windows each process
# start costs ~85 ms, which puts the native suite at 8-12 minutes. Run --native
# before a release, since the container cannot catch Windows-only behaviour.
# Exits 0 when every selected job passes, 1 otherwise.

set -u
cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." || exit 1

NATIVE=0
for a in "$@"; do [[ "$a" == "--native" ]] && NATIVE=1; done
if [[ $NATIVE -eq 0 && -z "${EXLOOM_IN_CONTAINER:-}" ]] && command -v docker >/dev/null 2>&1 \
   && docker info >/dev/null 2>&1; then
  if docker image inspect exloom-test >/dev/null 2>&1 \
     || docker build -q -t exloom-test scripts/test-image >/dev/null; then
    echo "running in a Linux container (--native to run on this host)"
    SRC="$(pwd -W 2>/dev/null || pwd)"
    MSYS_NO_PATHCONV=1 exec docker run --rm -e EXLOOM_IN_CONTAINER=1 -v "$SRC:/src:ro" exloom-test \
      bash -c 'cp -r /src /repo && cd /repo \
        && find . -path ./.git -prune -o -type f \( -name "*.sh" -o -name "*.md" -o -name "*.json" -o -name "*.yml" \) -exec sed -i "s/\r$//" {} + \
        && exec bash scripts/test-all.sh "$@"' _ "$@"
  fi
  echo "could not build the test image; running on this host" >&2
fi

GATE=scripts/test-exloom-gate.sh
JOBS=8; CHANGED=0; BASE=""; ONLY=""; LIST=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --native) shift ;;
    -j) JOBS="$2"; shift 2 ;;
    -j*) JOBS="${1#-j}"; shift ;;
    --changed) CHANGED=1; shift
               if [[ $# -gt 0 && "$1" != -* ]]; then BASE="$1"; shift; fi ;;
    --only) ONLY="$2"; shift 2 ;;
    --list) LIST=1; shift ;;
    *) echo "unknown argument: $1" >&2; exit 2 ;;
  esac
done

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mapfile -t STARTS < <(grep -n '^section "' "$GATE" | cut -d: -f1)
FOOT="$(grep -n '^echo "PASS=\$PASS' "$GATE" | cut -d: -f1)"
PRE=$((STARTS[0] - 1))
NSEC=${#STARTS[@]}
sec_end() { if (( $1 + 1 < NSEC )); then echo $((STARTS[$1 + 1] - 1)); else echo $((FOOT - 2)); fi; }
sec_title() { sed -n "${STARTS[$1]}s/^section \"\(.*\)\"$/\1/p" "$GATE"; }
sec_body() { sed -n "${STARTS[$1]},$(sec_end "$1")p" "$GATE"; }

declare -A WANT_SEC=() WANT_SUITE=()

# Names a gate section may use to reach FILE: its basename, variables the suite
# assigns to it, and preamble helpers built on either.
names_for_file() {
  local base; base="$(basename "$1")"
  printf '%s\n' "$base"
  grep -oE '^[[:space:]]*[A-Z_]+=.*'"${base//./\\.}" "$GATE" | sed -E 's/^[[:space:]]*([A-Z_]+)=.*/\1/'
}
helpers_using() {   # helpers_using <name>... — one-line preamble functions that reference a name
  [[ $# -gt 0 ]] || return 0
  sed -n "1,${PRE}p" "$GATE" | grep -E '^[a-z_]+\(\)' | grep -F -f <(printf '%s\n' "$@" | sed '/^$/d') \
    | sed -E 's/^([a-z_]+)\(\).*/\1/'
}
# Functions of a sourced library that a diff touched, plus every function in it
# that calls one of those, transitively.
lib_functions_touched() {   # lib_functions_touched <file> <base>
  local f="$1" b="$2" defs lines out="" added=1 fn
  defs="$(grep -nE '^[a-z_][a-z0-9_]*\(\)' "$f" | sed -E 's/^([0-9]+):([a-z0-9_]+).*/\1 \2/')"
  lines="$(git diff -U0 "$b" -- "$f" | sed -nE 's/^@@ -[0-9,]+ \+([0-9]+)(,([0-9]+))? @@.*/\1 \3/p')"
  while read -r start count; do
    [[ -n "$start" ]] || continue
    [[ -z "$count" ]] && count=1
    [[ "$count" -eq 0 ]] && count=1
    fn="$(printf '%s\n' "$defs" | awk -v l="$start" '$1<=l{n=$2} END{print n}')"
    [[ -z "$fn" ]] && { echo "__ALL__"; return; }
    out+="$fn"$'\n'
  done <<< "$lines"
  while [[ $added -eq 1 ]]; do
    added=0
    while read -r _ fn; do
      grep -qx "$fn" <<< "$out" && continue
      if awk -v n="$fn" 'BEGIN{p=0} $0 ~ "^"n"\\(\\)"{p=1;next} p && /^[a-z_][a-z0-9_]*\(\)/{p=0} p' "$f" \
         | grep -qwF -f <(printf '%s' "$out" | sed '/^$/d'); then
        out+="$fn"$'\n'; added=1
      fi
    done <<< "$defs"
  done
  printf '%s' "$out" | sed '/^$/d' | sort -u
}
want_sections_naming() {   # want_sections_naming <name>...
  local i n
  for ((i = 0; i < NSEC; i++)); do
    for n in "$@"; do
      [[ -n "$n" ]] || continue
      if sec_body "$i" | grep -qwF -- "$n"; then WANT_SEC[$i]=1; break; fi
    done
  done
}
want_all_sections() { local i; for ((i = 0; i < NSEC; i++)); do WANT_SEC[$i]=1; done; }

if [[ $CHANGED -eq 1 ]]; then
  [[ -n "$BASE" ]] || BASE="$(git merge-base HEAD main 2>/dev/null)" || { echo "--changed: cannot resolve main; pass a base, e.g. --changed origin/main" >&2; exit 2; }
  CHANGED_FILES="$( { git diff --name-only "$BASE"; git ls-files --others --exclude-standard; } | sort -u)"
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    case "$f" in
      *.md|*.json) WANT_SUITE[validate]=1 ;;&
      plugins/exloom-qa/hooks/*|scripts/test-qa-gate.sh) WANT_SUITE[qa]=1 ;;
      plugins/exloom/hooks/policy.sh|scripts/test-exloom-policy.sh) WANT_SUITE[policy]=1 ;;&
      plugins/exloom/hooks/lib.sh|plugins/exloom/hooks/policy.sh)
        mapfile -t fns < <(lib_functions_touched "$f" "$BASE")
        if printf '%s\n' "${fns[@]}" | grep -qx '__ALL__'; then want_all_sections
        else
          mapfile -t hooks < <(for h in plugins/exloom/hooks/*.sh plugins/exloom/scripts/*.sh; do
            grep -qwF -f <(printf '%s\n' "${fns[@]}") "$h" 2>/dev/null && basename "$h"; done)
          want_sections_naming "${fns[@]}" "${hooks[@]}" $(helpers_using "${hooks[@]}")
        fi ;;
      plugins/exloom/hooks/*.sh|plugins/exloom/scripts/*.sh)
        mapfile -t nm < <(names_for_file "$f")
        want_sections_naming "${nm[@]}" $(helpers_using "${nm[@]}") ;;
      plugins/exloom/templates/*|plugins/exloom/agents/*)
        want_sections_naming "$(basename "$f")" TPL AGENTS_DIR ;;
      scripts/test-exloom-gate.sh|scripts/test-all.sh|scripts/fixtures/*) want_all_sections ;;
      scripts/validate-plugin.sh) WANT_SUITE[validate]=1 ;;
    esac
  done <<< "$CHANGED_FILES"
else
  WANT_SUITE=([validate]=1 [qa]=1 [policy]=1)
  want_all_sections
fi

if [[ -n "$ONLY" ]]; then
  for i in "${!WANT_SEC[@]}"; do sec_title "$i" | grep -Eq -- "$ONLY" || unset "WANT_SEC[$i]"; done
  WANT_SUITE=()
fi

JOBLIST="$TMP/jobs"; : > "$JOBLIST"
for s in validate qa policy; do
  [[ -n "${WANT_SUITE[$s]:-}" ]] || continue
  case "$s" in
    validate) printf 'bash scripts/validate-plugin.sh\n' > "$TMP/$s.sh" ;;
    qa)       printf 'bash scripts/test-qa-gate.sh\n' > "$TMP/$s.sh" ;;
    policy)   printf 'bash scripts/test-exloom-policy.sh\n' > "$TMP/$s.sh" ;;
  esac
  echo "$s" >> "$JOBLIST"
done
for i in $(printf '%s\n' "${!WANT_SEC[@]}" | sort -n); do
  id="gate-$(printf '%02d' "$i")"
  { sed -n "1,${PRE}p" "$GATE"; sec_body "$i"; echo 'echo "PASS=$PASS FAIL=$FAIL"'; echo '[[ $FAIL -eq 0 ]]'; } > "$TMP/$id.sh"
  echo "$id" >> "$JOBLIST"
done

if [[ $LIST -eq 1 ]]; then
  while read -r id; do
    case "$id" in gate-*) echo "$id  $(sec_title "$((10#${id#gate-}))")" ;; *) echo "$id" ;; esac
  done < "$JOBLIST"
  exit 0
fi
[[ -s "$JOBLIST" ]] || { echo "nothing to run for these changes"; exit 0; }

# Longest first, using the durations the previous run left behind.
TIMES="${TMPDIR:-/tmp}/exloom-test-all.times"
if [[ -f "$TIMES" ]]; then
  awk 'NR==FNR{t[$1]=$2; next} {print (($1 in t)?t[$1]:999), $1}' "$TIMES" "$JOBLIST" | sort -rn | cut -d' ' -f2 > "$JOBLIST.sorted"
  mv "$JOBLIST.sorted" "$JOBLIST"
fi

START=$SECONDS
export TMP
xargs -P "$JOBS" -I{} bash -c 's=$SECONDS; bash "$TMP/{}.sh" > "$TMP/{}.out" 2>&1; echo $? > "$TMP/{}.rc"; echo "{} $((SECONDS - s))" > "$TMP/{}.t"' < "$JOBLIST"

FAILED=0; PASSES=0
: > "$TMP/times.new"
while read -r id; do
  cat "$TMP/$id.t" >> "$TMP/times.new"
  rc="$(cat "$TMP/$id.rc" 2>/dev/null || echo 1)"
  p="$(sed -n -e 's/^PASS=\([0-9]*\) FAIL=.*/\1/p' -e 's/^== \([0-9]*\) passed, .*/\1/p' "$TMP/$id.out" | tail -1)"
  PASSES=$((PASSES + ${p:-0}))
  if [[ "$rc" != "0" ]]; then
    FAILED=$((FAILED + 1))
    echo "---- FAILED: $id ----"
    grep -E 'FAIL|error|unbound' "$TMP/$id.out" | head -40
  fi
done < "$JOBLIST"
if [[ -f "$TIMES" ]]; then
  awk 'NR==FNR{t[$1]=$2; next} {t[$1]=$2} END{for (k in t) print k, t[k]}' "$TIMES" "$TMP/times.new" > "$TIMES.new"
  mv "$TIMES.new" "$TIMES"
else
  cp "$TMP/times.new" "$TIMES"
fi

echo "$(wc -l < "$JOBLIST") jobs, $FAILED failed, $PASSES counted assertions passed, $((SECONDS - START))s"
[[ $FAILED -eq 0 ]]
