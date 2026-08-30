#!/usr/bin/env bash
# exloom — findings-ledger.sh
#
# Renders every finding recorded on this branch, across every review round, with
# re-finds flagged. Derived entirely from the receipts written by
# hooks/record-reviewer-verdict.sh — nobody maintains this by hand, so it cannot
# drift from what the reviewers actually said.
#
# WHY. Findings live in a transcript today, which means nobody can see the two
# things that decide whether another round is worth running:
#
#   1. RE-FINDS. "Three of the four blocking findings in rounds 8 and 9 were
#      re-findings of something I'd already declared fixed." A re-find is not a
#      new defect — it is evidence the previous fix addressed the instance and not
#      the rule, and another round of the same shape will produce another one.
#
#   2. THE SEVERITY TREND. "Each round found more, most of it cosmetic, and I kept
#      chasing it." Findings degrade in severity as rounds go on because that is a
#      property of the reviewer, not of the code. When a round's blocking count
#      hits zero, more rounds buy nothing.
#
# Usage: bash findings-ledger.sh [--branch <name>]

set -u

BRANCH=""
[[ "${1:-}" == "--branch" ]] && BRANCH="${2:-}"

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "not a git repo" >&2; exit 1; }
cd "$ROOT" || exit 1
[[ -n "$BRANCH" ]] || BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"

VDIR=".claude/reviews/${BRANCH}.verdicts"
STATE=".claude/reviews/${BRANCH}.state"

if [[ ! -d "$VDIR" ]]; then
  echo "No review receipts for branch '${BRANCH}'."
  exit 0
fi

ROUNDS="$(grep -c '"state":"REVIEW"' "$STATE" 2>/dev/null || echo 0)"
echo "Findings ledger — branch '${BRANCH}'"
echo "Review rounds entered: ${ROUNDS}"
echo

ALL="$(cat "$VDIR"/*.findings.jsonl 2>/dev/null || true)"
if [[ -z "$ALL" ]]; then
  echo "No findings recorded. (Reviewers record a finding when a line carries both a"
  echo "severity word and a file:line cite — a report in prose leaves nothing to track.)"
  exit 0
fi

_field() { printf '%s' "$1" | sed -n "s/.*\"$2\":\"\{0,1\}\([^\",}]*\).*/\1/p" | head -1; }

# ---------- per-round severity trend ----------
echo "Per-round severity (blocking severities are CRITICAL / BLOCKING / IMPORTANT / HIGH):"
printf '  %-7s %-9s %-9s %-9s %s\n' round blocking other pre-exist verdict
for r in $(printf '%s\n' "$ALL" | sed -n 's/.*"round":\([0-9]*\).*/\1/p' | sort -un); do
  rows="$(printf '%s\n' "$ALL" | grep "\"round\":${r}," || true)"
  blocking=0; other=0; pre=0
  while IFS= read -r row; do
    [[ -n "$row" ]] || continue
    if [[ "$row" == *'"scope":"PRE-EXISTING"'* ]]; then pre=$((pre+1)); continue; fi
    case "$row" in
      *'"severity":"CRITICAL"'*|*'"severity":"BLOCKING"'*|*'"severity":"IMPORTANT"'*|*'"severity":"HIGH"'*)
        blocking=$((blocking+1)) ;;
      *) other=$((other+1)) ;;
    esac
  done <<< "$rows"
  v="$(grep -h "\"head\"" "$VDIR"/*.json 2>/dev/null | sed -n 's/.*"verdict":"\([A-Z]*\)".*/\1/p' | tail -1)"
  printf '  %-7s %-9s %-9s %-9s %s\n' "$r" "$blocking" "$other" "$pre" "${v:-—}"
done
echo

# ---------- re-finds ----------
echo "Re-finds (the same finding reported in more than one round):"
found_refind=0
while IFS= read -r fp; do
  [[ -n "$fp" ]] || continue
  rows="$(printf '%s\n' "$ALL" | grep -F "\"fingerprint\":\"${fp}\"" || true)"
  rlist="$(printf '%s\n' "$rows" | sed -n 's/.*"round":\([0-9]*\).*/\1/p' | sort -un | tr '\n' ',' | sed 's/,$//')"
  [[ "$rlist" == *,* ]] || continue
  found_refind=1
  one="$(printf '%s\n' "$rows" | head -1)"
  printf '  rounds %-10s %-10s %s\n' "$rlist" "$(_field "$one" severity)" "$(_field "$one" cite)"
done < <(printf '%s\n' "$ALL" | sed -n 's/.*"fingerprint":"\([^"]*\)".*/\1/p' | sort -u)

if [[ $found_refind -eq 0 ]]; then
  echo "  none — every finding was reported once."
else
  cat <<'EOF'

  A re-find means the previous fix addressed the instance, not the rule. Another
  round of the same shape will find the next instance. Fix the class instead, and
  add a test that quantifies over it.
EOF
fi
echo

# ---------- open list ----------
echo "All findings, newest round first:"
printf '%s\n' "$ALL" | sort -t: -k2 -rn | while IFS= read -r row; do
  [[ -n "$row" ]] || continue
  printf '  r%-3s %-10s %-12s %-26s %s\n' \
    "$(_field "$row" round)" "$(_field "$row" severity)" "$(_field "$row" scope)" \
    "$(_field "$row" cite)" "$(_field "$row" agent)"
done
