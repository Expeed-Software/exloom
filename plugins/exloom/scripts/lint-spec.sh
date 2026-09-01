#!/usr/bin/env bash
# lint-spec.sh — structural checks on an exloom spec.
#
# Usage: bash lint-spec.sh <spec.md> [<spec.md> ...]
# Exit 0 when every file passes, 1 when any ERROR is found. WARNs never fail.
#
# WHY THIS IS A SCRIPT AND NOT A CHECKLIST ITEM. `reviewing-plans` already asks
# nine questions in prose, and prose checks do not run. The Keel spec format put
# the argument plainly: a spec whose requirements run R-1, R-2, R-4 is a lint
# error, and it is an error rather than a warning because both of those existed
# in the hand-written specs of the people who wrote the rule. If the authors of a
# convention drift from it, the agents will.
#
# WHAT IS AN ERROR VERSUS A WARN, and the line is deliberate. Errors are
# STRUCTURAL — a machine can be certain, and being wrong is impossible. Warns are
# JUDGEMENT — a machine has a hint, and being wrong is likely. A judgement call
# that blocks is how a linter becomes something people route around, and exloom
# has already learned that lesson at the review gate.
#
# ERRORS
#   - a ref that is not well-formed
#   - requirement or criterion refs that are not sequential and gapless
#   - a requirement with no acceptance criterion (it is unverifiable)
#   - a criterion with no Given/When/Then body
#   - TBD / TODO / FIXME / ??? anywhere in the document
#   - a missing required section
#
# WARNS
#   - no `unwanted` requirement where the spec's own words mention money,
#     permissions or deletion
#   - a requirement that names an implementation (Postgres, Redis, a class name)
#   - an approved spec whose ref does not match its filename

set -uo pipefail

RC=0
FILES=("$@")
if [[ ${#FILES[@]} -eq 0 ]]; then
  echo "usage: lint-spec.sh <spec.md> [...]" >&2
  exit 2
fi

err()  { echo "ERROR  $1:$2  $3"; RC=1; }
warn() { echo "WARN   $1:$2  $3"; }

for f in "${FILES[@]}"; do
  if [[ ! -r "$f" ]]; then
    echo "ERROR  $f:0  cannot read the file"; RC=1; continue
  fi

  # Normalise CRLF: Git Bash on Windows hands these back with \r, and every
  # anchored match below would silently miss.
  body="$(tr -d '\r' < "$f")"

  # ---------- required sections ----------
  for want in '^## Problem' '^## Chosen approach' '^## Rejected approaches' \
              '^## Requirements' '^## Non-goals'; do
    if ! printf '%s\n' "$body" | grep -qE "$want"; then
      err "$f" 0 "missing required section: ${want#^## }"
    fi
  done

  # ---------- placeholders ----------
  # The hard ones only. "appropriate" / "relevant" / "as needed" are judgement
  # and belong in review, not here: they are legitimate English about half the
  # time, and a linter that cries wolf on ordinary prose gets disabled.
  while IFS=: read -r n line; do
    [[ -n "$n" ]] || continue
    err "$f" "$n" "placeholder left in the document: $(printf '%s' "$line" | sed 's/^[[:space:]]*//' | cut -c1-60)"
  done < <(printf '%s\n' "$body" | grep -nE '\b(TBD|TODO|FIXME|\?\?\?)\b' || true)

  # ---------- ref well-formedness and sequence ----------
  # Requirements:  "R-<n> · <type>"   Criteria: "AC-<n> · <level>"
  # Criteria are numbered within their requirement, so the counter resets at
  # every R- line. A single flat counter was the first thing tried and it makes
  # every spec with two requirements look broken.
  expect_r=1
  expect_ac=1
  seen_ac_for_current_r=0
  cur_r_line=0
  cur_r=""

  while IFS= read -r entry; do
    n="${entry%%:*}"
    line="${entry#*:}"
    case "$line" in
      R-*)
        # Close the previous requirement: it must have had at least one criterion.
        if [[ -n "$cur_r" && "$seen_ac_for_current_r" -eq 0 ]]; then
          err "$f" "$cur_r_line" "requirement ${cur_r} has no acceptance criterion — it is unverifiable"
        fi
        got="$(printf '%s' "$line" | sed -n 's/^R-\([0-9][0-9]*\).*/\1/p')"
        if [[ -z "$got" ]]; then
          err "$f" "$n" "malformed requirement ref: $(printf '%s' "$line" | cut -c1-40)"
        else
          if [[ "$got" -ne "$expect_r" ]]; then
            err "$f" "$n" "requirement refs must be sequential and gapless — expected R-${expect_r}, found R-${got}"
            expect_r="$got"
          fi
          cur_r="R-${got}"; cur_r_line="$n"
          expect_r=$((expect_r + 1))
          expect_ac=1
          seen_ac_for_current_r=0
        fi
        ;;
      AC-*)
        if [[ -z "$cur_r" ]]; then
          err "$f" "$n" "criterion outside any requirement: $(printf '%s' "$line" | cut -c1-40)"
          continue
        fi
        got="$(printf '%s' "$line" | sed -n 's/^AC-\([0-9][0-9]*\).*/\1/p')"
        if [[ -z "$got" ]]; then
          err "$f" "$n" "malformed criterion ref: $(printf '%s' "$line" | cut -c1-40)"
        else
          if [[ "$got" -ne "$expect_ac" ]]; then
            err "$f" "$n" "criterion refs must be sequential within ${cur_r} — expected AC-${expect_ac}, found AC-${got}"
            expect_ac="$got"
          fi
          expect_ac=$((expect_ac + 1))
          seen_ac_for_current_r=1
        fi
        ;;
    esac
  done < <(printf '%s\n' "$body" | grep -nE '^[[:space:]]*(R|AC)-' | sed 's/^\([0-9]*\):[[:space:]]*/\1:/' || true)

  if [[ -n "$cur_r" && "$seen_ac_for_current_r" -eq 0 ]]; then
    err "$f" "$cur_r_line" "requirement ${cur_r} has no acceptance criterion — it is unverifiable"
  fi
  if [[ -z "$cur_r" ]]; then
    err "$f" 0 "no requirements — a spec with nothing to verify cannot be built against"
  fi

  # ---------- every criterion needs a body ----------
  # A criterion with no Given/When/Then is a heading, and a heading is not
  # testable. Checked by counting: one Gherkin-ish block per AC line.
  #
  # CASE-SENSITIVE, and that is the whole trick. EARS writes the keyword in caps
  # (`WHEN a discount is submitted THE SYSTEM SHALL …`) at column 0; Gherkin
  # writes it in title case inside the criterion. Matching case-insensitively
  # counted every requirement as its own criterion body, so a criterion that said
  # only "It should work." passed.
  n_ac="$(printf '%s\n' "$body" | grep -cE '^[[:space:]]*AC-[0-9]' || true)"
  n_when="$(printf '%s\n' "$body" | grep -cE '^[[:space:]]*(When|Then)\b' || true)"
  if [[ "${n_ac:-0}" -gt 0 && "${n_when:-0}" -lt "${n_ac:-0}" ]]; then
    err "$f" 0 "${n_ac} criteria but only ${n_when} When/Then lines — every criterion needs an observable body"
  fi

  # ---------- ref matches filename ----------
  fref="$(printf '%s\n' "$body" | sed -n 's/^ref:[[:space:]]*\([A-Z]-[0-9][0-9]*\).*/\1/p' | head -1)"
  base="$(basename "$f")"
  if [[ -n "$fref" && "$base" != "$fref"-* && "$base" != "$fref".md ]]; then
    warn "$f" 0 "front matter says ${fref} but the filename is ${base} — refs are how everything downstream finds this spec"
  fi

  # ---------- the negative space ----------
  # Keel's rule, and it earns its place: "unwanted requirements are mandatory for
  # anything involving money, permissions, or data loss. Most defects live in the
  # negative space and most specs never go there."
  #
  # A WARN, not an error. Whether a spec that says "delete" is really about data
  # loss is a judgement, and the cost of being wrong is a blocked spec that was
  # fine — which is precisely how a check gets switched off.
  if printf '%s\n' "$body" | grep -qiE '\b(payment|refund|invoice|charge|billing|price|discount|permission|role|tenant|authoris|authoriz|delete|deletion|purge|revoke)\b'; then
    if ! printf '%s\n' "$body" | grep -qE '^[[:space:]]*(IF|R-[0-9]+[[:space:]]*·[[:space:]]*unwanted)'; then
      warn "$f" 0 "mentions money, permissions or deletion but states no 'unwanted' (IF … THEN) requirement — most defects live in the negative space"
    fi
  fi

  # ---------- implementation detail in a requirement ----------
  while IFS=: read -r n line; do
    [[ -n "$n" ]] || continue
    warn "$f" "$n" "requirement names an implementation — say what the system does, not how: $(printf '%s' "$line" | sed 's/^[[:space:]]*//' | cut -c1-60)"
  done < <(printf '%s\n' "$body" \
    | grep -nE '(SHALL|shall)' \
    | grep -iE '\b(postgres|mysql|redis|kafka|mongodb|dynamodb|s3|rabbitmq|elasticsearch)\b' || true)
done

exit $RC
