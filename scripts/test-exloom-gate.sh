#!/usr/bin/env bash
# test-exloom-gate.sh — behavioural tests for exloom's review gate.
# Usage: bash scripts/test-exloom-gate.sh
# Exits 0 if every case behaves as specified, 1 otherwise.
#
# Covers the two checks the gate does NOT take the author's word on:
#   1. the tier, derived from the diff rather than declared, and
#   2. reviewer verdict receipts, written by a hook on a real dispatch and
#      unwritable by hand.
# Everything else in the checklist is self-attested and can only be checked for
# presence; these two are what separate review from self-certification, so they
# are tested by running them, never by reading them.
#
# The fixture is a throwaway git repo under $TMPDIR — nothing touches this repo.

set -u

# The hooks honour EXLOOM_REVIEW_SKIP unconditionally, so a developer who has the
# bypass set in their session sees ten phantom failures here and no indication
# why. The suite tests what the gate does when it is ON; the bypass is tested by
# setting it deliberately, never by inheriting it.
unset EXLOOM_REVIEW_SKIP
export EXLOOM_VERBOSE=1

LIB="plugins/exloom/hooks/lib.sh"
HOOKS="plugins/exloom/hooks"

if [[ ! -f "$LIB" ]]; then
  echo "FAIL: run this from the repository root (no $LIB)"
  exit 1
fi

LIB_ABS="$(cd "$(dirname "$LIB")" && pwd)/$(basename "$LIB")"
HOOKS_ABS="$(cd "$HOOKS" && pwd)"
WORK="${TMPDIR:-/tmp}/exloom-gate-fixture.$$"
# Scratch root for the per-section throwaway repos. Declared here rather than in
# a section, because most sections build one.
REG="${TMPDIR:-/tmp}/exloom-gate-repos.$$"
mkdir -p "$REG"

# A minimal gate-enabled repo on a feature branch. Named `feat/plan` regardless
# of the argument — several sections hardcode that path.
subrepo() {   # subrepo <name> [noorigin]
  local d="$REG/$1"; rm -rf "$d"; mkdir -p "$d"; cd "$d" || return 1
  git init -q -b main . 2>/dev/null
  git config user.email t@e.com; git config user.name t
  mkdir -p .claude src docs/plans
  : > .claude/exloom-gate.enabled
  printf 'x\n' > src/base.txt
  git add -A >/dev/null 2>&1; git commit -qm base >/dev/null 2>&1
  [[ "${2:-withorigin}" == "withorigin" ]] && git update-ref refs/remotes/origin/main HEAD
  git checkout -q -b feat/plan
}

PASS=0; FAIL=0
ok() {
  if [[ "$2" == "$3" ]]; then
    echo "  PASS  $1"
    PASS=$((PASS + 1))
  else
    echo "  FAIL  $1 — got '$2', want '$3'"
    FAIL=$((FAIL + 1))
  fi
}

cleanup() { cd / 2>/dev/null; rm -rf "$WORK" "$REG"; }
trap cleanup EXIT

# ---------- fixture ----------
rm -rf "$WORK"; mkdir -p "$WORK"; cd "$WORK" || exit 1
git init -q -b main . 2>/dev/null
git config user.email test@example.com
git config user.name "exloom test"
mkdir -p .claude src
: > .claude/exloom-gate.enabled
printf 'x\n' > src/base.txt
git add -A; git commit -qm base
# The derivation needs a fork point; a local ref stands in for a real remote.
git update-ref refs/remotes/origin/main HEAD
git checkout -q -b feat/x

# shellcheck source=/dev/null
. "$LIB_ABS"

section() { echo "== $1 =="; }
PRVS="$(cd "$(dirname "$LIB_ABS")/../scripts" && pwd)/prove-change-is-tested.sh"
istest() {   # istest <path> -> test|source, using the script's own function
  bash -c 'set -u; '"$(sed -n '/^is_test() {/,/^}/p' "$PRVS")"'
    is_test "$1" && echo test || echo source' _ "$1"
}
sp() {   # sp <path> -> derived tier for a branch changing only that path
  git checkout -q -B "t/$RANDOM" main
  mkdir -p "$(dirname "$1")"; printf 'x\n' > "$1"; git add -A >/dev/null 2>&1; git commit -qm p >/dev/null 2>&1
  exloom_derive_tier HEAD 2>/dev/null
}

deny() { printf '%s' "$1" | bash "$HOOKS_ABS/protect-verdicts.sh" >/dev/null 2>&1; echo $?; }

PROVE="$(cd "$(dirname "$LIB_ABS")/../scripts" && pwd)/prove-change-is-tested.sh"

proofrepo() {   # proofrepo <name> <base-test-body> <base-src-body>
  local d="$REG/$1"; rm -rf "$d"; mkdir -p "$d/src" "$d/tests" "$d/.claude"; cd "$d" || return 1
  git init -q -b main . 2>/dev/null
  git config user.email t@e.com; git config user.name t
  # The gate marker and a feature branch are REQUIRED, not decoration:
  # prove-change-is-tested.sh returns before writing a receipt when either is
  # missing. Without them a fixture asserts exit codes on a path where the
  # receipt-minting branch is dead code — and a fixture that never reaches the
  # code it names is worse than none, because it reports green.
  : > .claude/exloom-gate.enabled
  : > .claude/exloom-proof.enabled
  printf 'bash tests/calc_test.sh\n' > .claude/exloom-test-command
  printf '%s\n' "$3" > src/calc.sh
  printf '%s\n' "$2" > tests/calc_test.sh
  git add -A >/dev/null 2>&1; git commit -qm base >/dev/null 2>&1
  git checkout -q -b feat/proof 2>/dev/null
  # Sets a global rather than echoing: `$(proofrepo ...)` would run the whole
  # function in a subshell and its `cd` would not survive, so the fixture files
  # would land in the wrong directory.
  BASESHA="$(git rev-parse HEAD)"
}
prove() { bash "$PROVE" --base "$1" >/dev/null 2>&1; echo $?; }
# The exit code is the smaller half of the contract. What the gate actually reads
# is the receipt, so assert on that too — an exit code alone cannot distinguish
# "proved" from "wrote nothing and happened to return 0".
proofres() { sed -n 's/.*"result":"\([A-Z_]*\)".*/\1/p' \
               ".claude/reviews/feat/proof.verdicts/proof.json" 2>/dev/null | tail -1; }

section "tier derivation (declared tier cannot go below this)"

printf 'a\n' > README.md; git add -A; git commit -qm docs
ok "docs-only -> 0" "$(exloom_derive_tier HEAD)" "0"

printf 'a\n' > src/one.go; git add -A; git commit -qm one
ok "one small code file -> 1" "$(exloom_derive_tier HEAD)" "1"

printf 'a\n' > src/two.go; printf 'a\n' > src/three.go; printf 'a\n' > src/four.go
git add -A; git commit -qm more
ok "five-file blast radius -> 2" "$(exloom_derive_tier HEAD)" "2"

mkdir -p api; printf 'a\n' > api/user_controller.go; git add -A; git commit -qm ctrl
ok "controller / API surface -> 2" "$(exloom_derive_tier HEAD)" "2"

mkdir -p src/auth; printf 'a\n' > src/auth/login.go; git add -A; git commit -qm auth
ok "auth path -> 3" "$(exloom_derive_tier HEAD)" "3"

mkdir -p db/changelog; printf 'a\n' > db/changelog/001.sql; git add -A; git commit -qm mig
ok "migration -> 3" "$(exloom_derive_tier HEAD)" "3"

# A markdown file living under an auth/ path must not score Tier 3 on the path
# match — docs-only is checked first, deliberately.
git checkout -q -b docs/under-auth main
mkdir -p src/auth; printf 'z\n' > src/auth/NOTES.md; git add -A; git commit -qm notes
ok "markdown under auth/ -> 0, not 3" "$(exloom_derive_tier HEAD)" "0"
git checkout -q feat/x

# `auth` must match as a WORD, not a substring. A bare substring match puts any
# path containing `authoring` or `author` at Tier 3 — and the tier has no escape
# hatch, so the gate becomes unsatisfiable for a docs change.
git checkout -q -b docs/authoring main
mkdir -p skills/authoring-claude-md
printf 'z
' > skills/authoring-claude-md/SKILL.md
printf 'z
' > skills/authoring-claude-md/notes.md
git add -A; git commit -qm authoring
ok "'authoring' path -> 0, not a false Tier 3" "$(exloom_derive_tier HEAD)" "0"

git checkout -q -b feat/realauth main
mkdir -p src/auth; printf 'a
' > src/auth/login.go; git add -A; git commit -qm realauth
ok "a real auth/ path -> 3" "$(exloom_derive_tier HEAD)" "3"

git checkout -q -b feat/authz main
printf 'a
' > src/authz.go; git add -A; git commit -qm authz
ok "authz -> 3" "$(exloom_derive_tier HEAD)" "3"
git checkout -q feat/x

section "verdict receipts (dispatch is recorded, not claimed)"

CHECK=".claude/reviews/feat/x.md"
mkdir -p "$(dirname "$CHECK")"
VD="$(exloom_verdict_dir "$CHECK")"
ok "receipt dir derived from checklist path" "$VD" ".claude/reviews/feat/x.verdicts"
ok "tier 2 reviewer set" "$(exloom_required_reviewers 2)" \
   "l1-reviewer adversarial-reviewer"

REVIEWED="$(git rev-parse HEAD)"
exloom_check_verdicts "$CHECK" 1 HEAD "$REVIEWED" "test" 2>/dev/null
ok "no receipt -> blocked" "$?" "2"

mkdir -p "$VD"
# A receipt with no verdict records a LAUNCH. It says a reviewer started, never
# what it concluded, and "we do not know what it concluded" is not approval.
printf '{"agent":"l1-reviewer","head":"%s","at":"now","session":"s"}\n' "$REVIEWED" > "$VD/l1-reviewer.json"
git add -A; git commit -qm receipt
exloom_check_verdicts "$CHECK" 1 HEAD "$REVIEWED" "test" 2>/dev/null
ok "a receipt with no verdict -> blocked" "$?" "2"

printf '{"agent":"l1-reviewer","head":"%s","verdict":"APPROVED","round_needed":"NO","at":"now","session":"s"}\n' "$REVIEWED" > "$VD/l1-reviewer.json"
git add -A; git commit -qm verdict
exloom_check_verdicts "$CHECK" 1 HEAD "$REVIEWED" "test" 2>/dev/null
ok "receipt with a verdict covering the reviewed commit -> allowed" "$?" "0"

exloom_check_verdicts "$CHECK" 2 HEAD "$REVIEWED" "test" 2>/dev/null
ok "tier 2 with only the L1 receipt -> blocked" "$?" "2"

# A checklist-only commit must not invalidate a real review...
printf 'note\n' >> "$CHECK"; git add -A; git commit -qm checklist-only-commit
exloom_check_verdicts "$CHECK" 1 HEAD "$(git rev-parse HEAD)" "test" 2>/dev/null
ok "checklist-only commit after review -> still allowed" "$?" "0"

# ...but a code commit must.
printf 'changed\n' > src/one.go; git add -A; git commit -qm codechange
exloom_check_verdicts "$CHECK" 1 HEAD "$(git rev-parse HEAD)" "test" 2>/dev/null
ok "code commit after review -> blocked" "$?" "2"

# Receipts are read from the ref, so an uncommitted one does not exist.
git checkout -q -b feat/y main
C2=".claude/reviews/feat/y.md"; mkdir -p "$(dirname "$C2")"
V2="$(exloom_verdict_dir "$C2")"; mkdir -p "$V2"
printf 'a\n' > src/y.go; git add src/y.go; git commit -qm y
R2="$(git rev-parse HEAD)"
printf '{"agent":"l1-reviewer","head":"%s"}\n' "$R2" > "$V2/l1-reviewer.json"
exloom_check_verdicts "$C2" 1 HEAD "$R2" "test" 2>/dev/null
ok "uncommitted receipt -> blocked" "$?" "2"
git checkout -q feat/x

section "staleness by change class (a typo fix must not demand another round)"

# Invalidating a review on ANY code change, combined with fixing findings,
# guarantees another round after every round — the loop has no terminating state.
# A comment or a test-name fix must therefore leave a review standing.
git checkout -q -b feat/class main
printf 'package x\nfunc F() int { return 1 }\n' > src/c.go
git add -A; git commit -qm base-code
CB="$(git rev-parse HEAD)"

printf 'package x\n// explains F\nfunc F() int { return 1 }\n' > src/c.go
git add -A; git commit -qm comment-only
ok "comment-only commit -> not behavioural" \
   "$(exloom_diff_is_behavioural "$CB" HEAD && echo yes || echo no)" "no"

printf 'package x\n// explains F\nfunc F() int { return 2 }\n' > src/c.go
git add -A; git commit -qm real-change
ok "changed return value -> behavioural" \
   "$(exloom_diff_is_behavioural "$CB" HEAD && echo yes || echo no)" "yes"

# Whitespace and blank lines alone are not behavioural either.
CB2="$(git rev-parse HEAD)"
printf 'package x\n\n// explains F\n\nfunc F() int {  return 2  }\n' > src/c.go
git add -A; git commit -qm whitespace
ok "whitespace/blank-line churn -> not behavioural" \
   "$(exloom_diff_is_behavioural "$CB2" HEAD && echo yes || echo no)" "no"

# ...but only where indentation is not syntax. Reading the blank-line case alone
# would pin "any change `git diff -w` cannot see" as the rule. In Python a
# de-indent moves a statement out of an `if` branch; in YAML it re-parents a key.
# Both are behavioural, both are invisible to -w, and both would otherwise leave
# a stale receipt valid over changed behaviour.
CB3="$(git rev-parse HEAD)"
printf 'def pay(o):\n    if o.ok:\n        charge(o)\n        refund(o)\n' > src/p.py
git add -A; git commit -qm pybase
CB3="$(git rev-parse HEAD)"
printf 'def pay(o):\n    if o.ok:\n        charge(o)\n    refund(o)\n' > src/p.py
git add -A; git commit -qm dedent
ok "python de-indent moves a call out of a branch -> behavioural" \
   "$(exloom_diff_is_behavioural "$CB3" HEAD && echo yes || echo no)" "yes"

printf 'security:\n  auth:\n    required: true\n' > src/cfg.yaml
git add -A; git commit -qm ybase
CB4="$(git rev-parse HEAD)"
printf 'security:\n  auth:\nrequired: true\n' > src/cfg.yaml
git add -A; git commit -qm renest
ok "yaml re-nest lifts a key out of its parent -> behavioural" \
   "$(exloom_diff_is_behavioural "$CB4" HEAD && echo yes || echo no)" "yes"

# A comment change that ALSO touches a code line is behavioural — the classifier
# is conservative, and being wrong here costs one review rather than shipping
# unreviewed code.
CB3="$(git rev-parse HEAD)"
printf 'package x\n\n// explains F better\n\nfunc F() int {  return 3  }\n' > src/c.go
git add -A; git commit -qm mixed
ok "comment + code together -> behavioural" \
   "$(exloom_diff_is_behavioural "$CB3" HEAD && echo yes || echo no)" "yes"

# End to end: a review stays valid across a comment-only commit.
CC=".claude/reviews/feat/class.md"; mkdir -p "$(dirname "$CC")"
CCD="$(exloom_verdict_dir "$CC")"; mkdir -p "$CCD"
RC="$(git rev-parse HEAD)"
printf '{"agent":"l1-reviewer","head":"%s","verdict":"APPROVED"}\n' "$RC" > "$CCD/l1-reviewer.json"
git add -A; git commit -qm receipt
exloom_check_verdicts "$CC" 1 HEAD "$(git rev-parse HEAD)" "test" 2>/dev/null
ok "review valid at the reviewed commit" "$?" "0"

printf 'package x\n\n// a better sentence entirely\n\nfunc F() int {  return 3  }\n' > src/c.go
git add -A; git commit -qm doc-fix
exloom_check_verdicts "$CC" 1 HEAD "$(git rev-parse HEAD)" "test" 2>/dev/null
ok "comment-only commit after review -> review still valid" "$?" "0"

printf 'package x\n\n// a better sentence entirely\n\nfunc F() int {  return 4  }\n' > src/c.go
git add -A; git commit -qm behaviour-fix
exloom_check_verdicts "$CC" 1 HEAD "$(git rev-parse HEAD)" "test" 2>/dev/null
ok "behavioural commit after review -> review invalidated" "$?" "2"
git checkout -q feat/x

section "code-reviewer verdicts (a REJECTED review does not satisfy the gate)"

# A receipt states a conclusion or it states nothing. REJECTED and UNKNOWN both
# fail the gate, and a line with no verdict key at all records a launch rather
# than a review — none of the three is an approval.
git checkout -q -b feat/verd main
CV=".claude/reviews/feat/verd.md"; mkdir -p "$(dirname "$CV")"
CVD="$(exloom_verdict_dir "$CV")"; mkdir -p "$CVD"
printf 'a\n' > src/v.go; git add -A; git commit -qm v
RV="$(git rev-parse HEAD)"
# Receipts reach the consumer the way they do in production: minted by the
# PRODUCER from a reviewer report. Hand-writing them here would only ever show
# exloom_check_verdicts a shape record-reviewer-verdict.sh does not write, so
# drift between the two would be invisible — and the suite would be performing
# the exact forgery the gate exists to prevent.
mint() {   # mint <report-text>
  rm -f "$CVD/l1-reviewer.json"
  python3 -c "
import json,sys
print(json.dumps({'tool_name':'Task','session_id':'s',
  'tool_input':{'subagent_type':'exloom:l1-reviewer','prompt':'review the diff'},
  'tool_response':[{'type':'text','text':sys.argv[1]}]}))" "$1" \
    | bash "$HOOKS_ABS/record-reviewer-verdict.sh" >/dev/null 2>&1
  git add -A >/dev/null 2>&1; git commit -qm r >/dev/null 2>&1
}
# Only for receipts the CURRENT producer cannot write — an older on-disk shape.
# Anything the producer can emit must go through mint(), or the suite is testing
# a receipt shape that never reaches the gate in production.
put_legacy() { printf '%s\n' "$1" > "$CVD/l1-reviewer.json"; git add -A >/dev/null 2>&1; git commit -qm r >/dev/null 2>&1; }
chk() { exloom_check_verdicts "$CV" 1 HEAD "$(git rev-parse HEAD)" "test" 2>/dev/null; echo $?; }

mint 'No findings.

VERDICT: APPROVED'
ok "APPROVED code review -> allowed" "$(chk)" "0"

mint '## Critical
- src/v.go:1 — real defect

VERDICT: REJECTED (1 items)'
ok "REJECTED code review -> blocked" "$(chk)" "2"

# No verdict line at all: the parser records UNKNOWN rather than guessing, and a
# gate may not guess in the permissive direction.
mint 'I looked at the diff and it seems fine to me.'
ok "UNKNOWN code review -> blocked" "$(chk)" "2"

# The exact key set and order exloom 2.0.0 wrote. A simplified stand-in would
# pass while the real shape failed on a key the parser did not expect.
put_legacy "{\"agent\":\"l1-reviewer\",\"subagent_type\":\"exloom:l1-reviewer\",\"head\":\"$RV\",\"at\":\"2026-08-28T18:24:11Z\",\"session\":\"00000000-0000-0000-0000-000000000000\"}"
# Byte-for-byte an older shape, and it is not accepted. An exemption for these
# would admit receipts whose review outcome was never captured — refusing one
# costs a single re-dispatch, accepting one ships code nobody has been shown to
# have reviewed.
ok "legacy 2.0.0 receipt (no verdict key) -> blocked, not grandfathered" "$(chk)" "2"

# An APPROVED receipt from an EARLIER commit must not vouch for a REJECTED
# review of the current one. Verdict and commit are read from the same line.
OLD="$RV"
printf 'b\n' > src/v.go; git add -A; git commit -qm v2
NEW="$(git rev-parse HEAD)"
printf '{"agent":"l1-reviewer","head":"%s","verdict":"APPROVED"}\n{"agent":"l1-reviewer","head":"%s","verdict":"REJECTED"}\n' "$OLD" "$NEW" > "$CVD/l1-reviewer.json"
git add -A; git commit -qm r2
ok "old APPROVED does not vouch for a new REJECTED" "$(chk)" "2"
git checkout -q feat/x

section "a remedy the reviewer left open is not the author's to pick"

subrepo choices noorigin
CH=".claude/reviews/feat/ch.md"; mkdir -p "$(dirname "$CH")"
CHD="$(exloom_verdict_dir "$CH")"; mkdir -p "$CHD"
printf 'a
' > src/c.go
printf '**Tier:** 1
' > "$CH"
git add -A >/dev/null 2>&1; git commit -qm base >/dev/null 2>&1
cchk() { exloom_check_choices "$CH" HEAD "test" >/dev/null 2>&1; echo $?; }

ok "no choices recorded -> nothing to answer" "$(cchk)" "0"

printf '{"round":1,"agent":"adversarial-reviewer","cite":"src/c.go:12","options":"widen the read root :: refuse the combination","head":"h","at":"t"}
' > "$CHD/adversarial-reviewer.choices.jsonl"
git add -A >/dev/null 2>&1; git commit -qm rec >/dev/null 2>&1
ok "an unanswered choice blocks the push" "$(cchk)" "2"
ok "...and the block carries the reviewer's own options"    "$(exloom_check_choices "$CH" HEAD test 2>&1 >/dev/null | grep -c 'refuse the combination')" "1"

printf '**Tier:** 1

## Remedy choices
- src/c.go:12 - CHOSE: widen the read root
' > "$CH"
git add -A >/dev/null 2>&1; git commit -qm answer >/dev/null 2>&1
ok "a recorded answer clears it" "$(cchk)" "0"

# The answer has to name the cite it answers, or one decision would silently
# close every open choice on the branch.
printf '{"round":1,"agent":"l1-reviewer","cite":"src/other.go:4","options":"one :: two"}
' > "$CHD/l1-reviewer.choices.jsonl"
git add -A >/dev/null 2>&1; git commit -qm second >/dev/null 2>&1
ok "an answer to one cite does not answer another" "$(cchk)" "2"

# Uncommitted, like every other thing the gate reads.
printf '**Tier:** 1

## Remedy choices
- src/c.go:12 - CHOSE: widen the read root
- src/other.go:4 - CHOSE: one
' > "$CH"
ok "an uncommitted answer does not count" "$(cchk)" "2"
git add -A >/dev/null 2>&1; git commit -qm both >/dev/null 2>&1
ok "...and counts once committed" "$(cchk)" "0"

cd "$WORK" || exit 1

section "proof receipt (the tested-ness check cannot be skipped by forgetting)"

git checkout -q -b feat/proof main
CP=".claude/reviews/feat/proof.md"; mkdir -p "$(dirname "$CP")"
CPD="$(exloom_verdict_dir "$CP")"; mkdir -p "$CPD"
pchk() { exloom_check_proof "$CP" HEAD "$(git rev-parse HEAD)" "test" "${1:-1}" 2>/dev/null; echo $?; }

printf 'a\n' > src/p.go; git add -A; git commit -qm p
RP="$(git rev-parse HEAD)"
ok "the proof is required by default, and no receipt blocks" "$(pchk)" "2"
: > .claude/exloom-proof.disabled
ok "an untracked opt-out marker does not turn it off" "$(pchk)" "2"
git add -A; git commit -qm disable
ok "a committed opt-out marker turns it off" "$(pchk)" "0"
git rm -q .claude/exloom-proof.disabled; git commit -qm reenable

printf '{"check":"change-is-tested","result":"NOT_PROVED","head":"%s"}\n' "$RP" > "$CPD/proof.json"
git add -A; git commit -qm p2
ok "NOT_PROVED receipt -> blocked" "$(pchk)" "2"

printf '{"check":"change-is-tested","result":"PROVED","head":"%s"}\n' "$RP" > "$CPD/proof.json"
git add -A; git commit -qm p3
ok "PROVED receipt covering the commit -> allowed" "$(pchk)" "0"

# A build failure at base is not the same finding as a test that passed without
# the change, and must not produce the same outcome. The first says the question
# cannot be asked here - the tests reference code the branch introduces, so they
# do not compile without it. The second says the tests are weak. Collapsing them
# left an author with a new class or a new endpoint holding a blocking result
# they could not clear except by bypassing, which records less than this does.
printf '{"check":"change-is-tested","result":"NOT_APPLICABLE","method":"not-applicable","head":"%s"}
' "$RP" > "$CPD/proof.json"
git add -A; git commit -qm pna
ok "NOT_APPLICABLE receipt -> allowed at Tier 1" "$(pchk)" "0"
ok "...and at Tier 2" "$(pchk 2)" "0"
ok "...and at Tier 3" "$(pchk 3)" "0"
ok "...and says so rather than passing silently"    "$(exloom_check_proof "$CP" HEAD "$(git rev-parse HEAD)" test 2>&1 >/dev/null | grep -c 'NOT_APPLICABLE')" "1"

# The weak result is still bound to the commit. Accepting it must not also mean
# accepting it forever - that would make it a waiver rather than a record.
printf 'na
' > src/p.go; git add -A; git commit -qm pna2
ok "NOT_APPLICABLE goes stale on a code commit" "$(pchk)" "2"

# NOT_PROVED keeps its meaning: the tests ran at base and passed anyway.
printf '{"check":"change-is-tested","result":"NOT_PROVED","method":"three-run","head":"%s"}
' "$(git rev-parse HEAD)" > "$CPD/proof.json"
git add -A; git commit -qm pnp
ok "NOT_PROVED still blocks" "$(pchk)" "2"

printf '{"check":"change-is-tested","result":"PROVED","head":"%s"}
' "$(git rev-parse HEAD)" > "$CPD/proof.json"
git add -A; git commit -qm pback

# A proof from before the last code change must not vouch for the new code.
printf 'b\n' > src/p.go; git add -A; git commit -qm p4
ok "PROVED receipt goes stale on a code commit" "$(pchk)" "2"

# An uncommitted receipt does not exist, same rule as reviewer receipts.
printf '{"check":"change-is-tested","result":"PROVED","head":"%s"}\n' "$(git rev-parse HEAD)" > "$CPD/proof.json"
ok "uncommitted proof receipt -> blocked" "$(pchk)" "2"
git add -A; git commit -qm p5
ok "...and allowed once committed" "$(pchk)" "0"

# The proof receipt lives in the guarded directory, so it cannot be typed.
ok "hand-writing a proof receipt -> denied" \
  "$(printf '%s' '{"tool_name":"Write","tool_input":{"file_path":".claude/reviews/feat/proof.verdicts/proof.json"}}' | bash "$HOOKS_ABS/protect-verdicts.sh" >/dev/null 2>&1; echo $?)" "2"
git checkout -q feat/x

section "protect-verdicts hook (a receipt cannot be written by hand)"

ok "Write to a receipt -> denied" \
  "$(deny '{"tool_name":"Write","tool_input":{"file_path":".claude/reviews/feat/x.verdicts/l1-reviewer.json"}}')" "2"
ok "Edit of a receipt (absolute path) -> denied" \
  "$(deny '{"tool_name":"Edit","tool_input":{"file_path":"E:/x/.claude/reviews/b.verdicts/security-auditor.json"}}')" "2"
ok "shell redirect into a receipt -> denied" \
  "$(deny '{"tool_name":"Bash","tool_input":{"command":"echo {} > .claude/reviews/feat/x.verdicts/adversarial-reviewer.json"}}')" "2"
ok "rm of a receipt -> denied" \
  "$(deny '{"tool_name":"Bash","tool_input":{"command":"rm .claude/reviews/feat/x.verdicts/l1-reviewer.json"}}')" "2"
ok "Write to the checklist -> allowed" \
  "$(deny '{"tool_name":"Write","tool_input":{"file_path":".claude/reviews/feat/x.md"}}')" "0"
ok "git add of receipts -> allowed" \
  "$(deny '{"tool_name":"Bash","tool_input":{"command":"git add .claude/reviews/feat/x.verdicts"}}')" "0"
ok "reading a receipt -> allowed" \
  "$(deny '{"tool_name":"Bash","tool_input":{"command":"cat .claude/reviews/feat/x.verdicts/l1-reviewer.json"}}')" "0"
ok "unrelated command -> allowed" \
  "$(deny '{"tool_name":"Bash","tool_input":{"command":"go test ./..."}}')" "0"

section "protection: state file and wholesale deletion"

# Guarding `.verdicts/` alone is not enough: `rm -rf .claude/reviews` and
# `git clean -fdx` name neither the directory nor the state file, and either one
# destroys every receipt, the round counter and the findings ledger.
ok "writing the review STATE file -> denied"   "$(deny '{"tool_name":"Write","tool_input":{"file_path":".claude/reviews/feat/x.state"}}')" "2"
ok "editing the CHECKLIST is still allowed"   "$(deny '{"tool_name":"Edit","tool_input":{"file_path":".claude/reviews/feat/x.md"}}')" "0"
ok "rm -rf of the reviews tree -> denied"   "$(deny '{"tool_name":"Bash","tool_input":{"command":"rm -rf .claude/reviews"}}')" "2"
ok "git clean -fdx -> denied"   "$(deny '{"tool_name":"Bash","tool_input":{"command":"git clean -fdx"}}')" "2"
ok "reading the state file -> allowed"   "$(deny '{"tool_name":"Bash","tool_input":{"command":"cat .claude/reviews/feat/x.state"}}')" "0"

section "remediation commands in block messages must actually run"

# Claude Code substitutes ${CLAUDE_PLUGIN_ROOT} in plugin.json and in command,
# agent and SKILL.md bodies only; never in hook output, other files, or the Bash
# environment, where a command built from it fails "No such file or directory".
#
# The pattern lives in a variable. Written inline it sits inside a nested
# single-quoted `$(...)`, where an escaped `\$` becomes a LITERAL BACKSLASH to
# ERE — a pattern that matches nothing and a guard that can never fail. This test
# asserts against a known violation below precisely so that cannot recur.
PLUGIN_ROOT_DIR="$(cd "$HOOKS_ABS/.." && pwd)"
CPR_RE='(bash|sh|cat|find|cp|\.)[[:space:]]+"?\$\{CLAUDE_PLUGIN_ROOT\}'

# The guard must FAIL on a real violation. A guard proven only against a clean
# tree is indistinguishable from one that matches nothing.
CPR_PROBE="$REG/cpr-probe"; mkdir -p "$CPR_PROBE"
printf 'bash "${CLAUDE_PLUGIN_ROOT}/scripts/prove-change-is-tested.sh"\n' > "$CPR_PROBE/violation.md"
ok "the guard actually matches a real \${CLAUDE_PLUGIN_ROOT} invocation" \
   "$(grep -rlE "$CPR_RE" "$CPR_PROBE" 2>/dev/null | wc -l | tr -d ' ')" "1"
# ...and must not fire on prose that merely names the variable, which several
# files legitimately do when explaining why it cannot be used.
printf 'The harness sets ${CLAUDE_PLUGIN_ROOT} in plugin.json only.\n' > "$CPR_PROBE/violation.md"
ok "...and does not fire on prose that merely names it" \
   "$(grep -rlE "$CPR_RE" "$CPR_PROBE" 2>/dev/null | wc -l | tr -d ' ')" "0"

ok "no unsubstituted file tells a session to run \${CLAUDE_PLUGIN_ROOT}" \
   "$(grep -rlE "$CPR_RE" "$PLUGIN_ROOT_DIR" 2>/dev/null \
      | grep -vE '\.claude-plugin/plugin\.json$|/(commands|agents)/[^/]*\.md$|/skills/[^/]*/SKILL\.md$' | wc -l | tr -d ' ')" "0"
# Counted against the manifest's own command lines rather than a fixed number,
# so registering a hook cannot pass by forgetting the variable.
ok "...while the manifest, where it IS interpolated, still uses it" \
   "$(grep -cE '\$\{CLAUDE_PLUGIN_ROOT\}' "$PLUGIN_ROOT_DIR/.claude-plugin/plugin.json" | head -1)" \
   "$(grep -cE '"command":' "$PLUGIN_ROOT_DIR/.claude-plugin/plugin.json" | head -1)"
ok "prove-change-is-tested.sh exists where the message points"   "$([[ -f "$HOOKS_ABS/../scripts/prove-change-is-tested.sh" ]] && echo yes || echo no)" "yes"

section "record-reviewer-verdict hook (a real dispatch writes one)"

git checkout -q -b feat/rec main
RVD=".claude/reviews/feat/rec.verdicts"
rm -rf "$RVD"
record() { printf '%s' "$1" | bash "$HOOKS_ABS/record-reviewer-verdict.sh" >/dev/null 2>&1; }

record '{"tool_name":"Task","session_id":"s1","tool_input":{"subagent_type":"exloom:adversarial-reviewer"}}'
ok "reviewer dispatch -> receipt written" "$([[ -f "$RVD/adversarial-reviewer.json" ]] && echo yes || echo no)" "yes"
ok "receipt names the dispatched-at commit" \
   "$(grep -c "$(git rev-parse HEAD)" "$RVD/adversarial-reviewer.json" 2>/dev/null | head -1)" "1"

record '{"tool_name":"Task","session_id":"s","tool_input":{"subagent_type":"general-purpose"}}'
ok "general-purpose agent -> no receipt" "$(ls "$RVD" | wc -l | tr -d ' ')" "1"

record '{"tool_name":"Task","session_id":"s","tool_input":{"subagent_type":"l1-reviewer"}}'
ok "an unprefixed reviewer name writes no receipt" "$([[ -f "$RVD/l1-reviewer.json" ]] && echo yes || echo no)" "no"

record '{"tool_name":"Read","tool_input":{"file_path":"x"}}'
ok "non-Task tool ignored" "$(ls "$RVD" | wc -l | tr -d ' ')" "1"

# The whole gate is opt-in; with the marker gone, neither hook does anything.
mv .claude/exloom-gate.enabled .claude/gate-off
rm -rf "$RVD"
record '{"tool_name":"Task","session_id":"s","tool_input":{"subagent_type":"exloom:l1-reviewer"}}'
ok "gate off -> no receipt written" "$([[ -d "$RVD" ]] && echo yes || echo no)" "no"
ok "gate off -> receipt writes allowed" \
  "$(deny '{"tool_name":"Write","tool_input":{"file_path":".claude/reviews/feat/x.verdicts/l1-reviewer.json"}}')" "0"
mv .claude/gate-off .claude/exloom-gate.enabled

section "verdicts (a dispatch is not a review)"

# A receipt that records only that a reviewer RAN enforces attendance, not
# review: a REJECTED report would open the gate exactly like an approval. The
# verdict is what makes it evidence.
subrepo verdict; printf '# plan\n- src/one.go\n' > docs/plans/p.md
VF=".claude/reviews/feat/plan.verdicts/l1-reviewer.json"
disp() {   # disp <report-text>
  rm -rf .claude/reviews
  python3 -c "
import json,sys
print(json.dumps({'tool_name':'Task','session_id':'s',
  'tool_input':{'subagent_type':'exloom:l1-reviewer','prompt':'Review the diff'},
  'tool_response':[{'type':'text','text':sys.argv[1]}]}))" "$1" \
  | bash "$HOOKS_ABS/record-reviewer-verdict.sh" >/dev/null 2>&1
}

disp 'REVIEWED: docs/plans/p.md
VERDICT: APPROVED

Nothing further.'
ok "APPROVED verdict recorded" "$(grep -c '"verdict":"APPROVED"' "$VF" 2>/dev/null | head -1)" "1"

disp 'VERDICT: REJECTED (3 items)

Item 2 (Acceptance Criteria): not testable.'
ok "REJECTED verdict recorded" "$(grep -c '"verdict":"REJECTED"' "$VF" 2>/dev/null | head -1)" "1"

disp 'The plan looks broadly fine to me, shipping notes below.'
ok "no verdict line -> UNKNOWN" "$(grep -c '"verdict":"UNKNOWN"' "$VF" 2>/dev/null | head -1)" "1"

# A reviewer that echoes its own output-format template must not be read as an
# approval: that template line literally contains "VERDICT: APPROVED | REJECTED".
disp 'My output format is:

VERDICT: APPROVED | REJECTED (n items)

and I could not complete the review.'
ok "echoed format template is not an approval" \
   "$(grep -c '"verdict":"APPROVED"' "$VF" 2>/dev/null | head -1)" "0"

# A verdict line that trails commentary is still a verdict. A strict end-anchor
# scored every one of these UNKNOWN, which blocks a passing branch and sends the
# author to the bypass.
for t in 'VERDICT: APPROVED - no blocking findings' \
         'VERDICT: APPROVED — clean' \
         '**VERDICT: APPROVED** ✅' \
         'VERDICT: APPROVED.'; do
  disp "$t"
  ok "trailing commentary still approves: ${t:0:34}" \
     "$(grep -c '"verdict":"APPROVED"' "$VF" 2>/dev/null | head -1)" "1"
done

disp 'VERDICT: REJECTED - 1 critical finding'
ok "trailing commentary still rejects" "$(grep -c '"verdict":"REJECTED"' "$VF" 2>/dev/null | head -1)" "1"

# A QUALIFIED verdict is not a verdict. Each must stay UNKNOWN, which blocks: a
# conditional approval is a condition, not an approval.
for t in 'VERDICT: APPROVED WITH CHANGES' \
         'VERDICT: APPROVED, with reservations' \
         'VERDICT: APPROVED - pending CI' \
         'VERDICT: APPROVED (conditional on fixes)' \
         'VERDICT: APPROVED unless the migration lands'; do
  disp "$t"
  ok "qualified verdict is not an approval: ${t:9:30}" \
     "$(grep -c '"verdict":"APPROVED"' "$VF" 2>/dev/null | head -1)" "0"
done

# A reviewer may hand its report over as a `SubagentHandback` call instead of
# writing it as text. The run then has NO assistant text, so the report lives
# only in the agent's own transcript. Missing it recorded UNKNOWN, or nothing at
# all, for every review on such a build — a passing branch blocked with no path
# forward but the bypass.
HBT="$REG/handback.jsonl"
mkhb() {   # mkhb <role-of-the-handback-turn> <verdict-line>
  printf '%s\n' \
    '{"message":{"role":"user","content":[{"type":"text","text":"Emit exactly: VERDICT: REJECTED (9 items)"}]}}' \
    "{\"message\":{\"role\":\"$1\",\"content\":[{\"type\":\"tool_use\",\"name\":\"SubagentHandback\",\"input\":{\"message\":\"$2\n\nROUND NEEDED AFTER FIX: NO\n\"}}]}}" \
    > "$HBT"
}
stop() {   # stop <transcript-path> <last_assistant_message>
  rm -rf .claude/reviews
  printf '{"session_id":"s","hook_event_name":"SubagentStop","agent_type":"exloom:l1-reviewer","agent_id":"a1","agent_transcript_path":"%s","last_assistant_message":"%s"}' "$1" "$2" \
    | bash "$HOOKS_ABS/record-reviewer-verdict.sh" >/dev/null 2>&1
}

mkhb assistant 'VERDICT: APPROVED'
stop "$HBT" ""
ok "handback report read when there is no assistant text" \
   "$(grep -c '"verdict":"APPROVED","round_needed":"NO"' "$VF" 2>/dev/null | head -1)" "1"

# Interim text stating no verdict must not mask the handback.
stop "$HBT" "Starting the review now."
ok "handback beats verdictless assistant text" \
   "$(grep -c '"verdict":"APPROVED"' "$VF" 2>/dev/null | head -1)" "1"

mkhb assistant 'VERDICT: REJECTED (2 items)'
stop "$HBT" ""
ok "a handback rejection is recorded as one" \
   "$(grep -c '"verdict":"REJECTED"' "$VF" 2>/dev/null | head -1)" "1"

# The agent's transcript OPENS with the dispatch prompt, which quotes the
# required output format. Reading that would let an author forge a verdict.
mkhb user 'VERDICT: APPROVED'
stop "$HBT" ""
ok "a handback from a non-assistant role is not a verdict" \
   "$(grep -c '"verdict":' "$VF" 2>/dev/null | head -1)" "0"

rm -f "$HBT"
stop "$HBT" "VERDICT: REJECTED (1 items)"
ok "assistant text still read when no transcript exists" \
   "$(grep -c '"verdict":"REJECTED"' "$VF" 2>/dev/null | head -1)" "1"


section "classifier: real code the old version called non-behavioural"

# Each case below is a line a naive comment-stripper reads as inert. Getting any
# of them wrong keeps a stale reviewer receipt "covering" a commit whose
# behaviour changed.
git checkout -q -b feat/cls main
mkdir -p csrc
beh() { git add -A >/dev/null 2>&1; git commit -qm "$1" >/dev/null 2>&1;
        exloom_diff_is_behavioural "$2" HEAD && echo yes || echo no; }

printf '#define TIMEOUT 5\n#include <stdio.h>\nint main(){return 0;}\n' > csrc/a.c
git add -A >/dev/null 2>&1; git commit -qm c-base >/dev/null 2>&1; CB="$(git rev-parse HEAD)"
printf '#define TIMEOUT 300\n#include <stdio.h>\nint main(){return 0;}\n' > csrc/a.c
ok "C #define change -> behavioural" "$(beh cdef "$CB")" "yes"

CB="$(git rev-parse HEAD)"
printf '#define TIMEOUT 300\n#include <stdlib.h>\nint main(){return 0;}\n' > csrc/a.c
ok "C #include change -> behavioural" "$(beh cinc "$CB")" "yes"

CB="$(git rev-parse HEAD)"
printf '#login{display:block}\n' > csrc/s.css
git add -A >/dev/null 2>&1; git commit -qm cssbase >/dev/null 2>&1; CB="$(git rev-parse HEAD)"
printf '#login{display:none}\n' > csrc/s.css
ok "CSS #id rule change -> behavioural" "$(beh css "$CB")" "yes"

printf '//go:build linux\npackage m\n' > csrc/m.go
git add -A >/dev/null 2>&1; git commit -qm gobase >/dev/null 2>&1; CB="$(git rev-parse HEAD)"
printf '//go:build ignore\npackage m\n' > csrc/m.go
ok "Go build directive -> behavioural" "$(beh godir "$CB")" "yes"

printf '#!/bin/sh\necho hi\n' > csrc/r.sh
git add -A >/dev/null 2>&1; git commit -qm shbase >/dev/null 2>&1; CB="$(git rev-parse HEAD)"
printf '#!/usr/bin/env bash\necho hi\n' > csrc/r.sh
ok "shebang change -> behavioural" "$(beh shebang "$CB")" "yes"

printf 'BINARY-v1\x00\x01' > csrc/lib.jar
git add -A >/dev/null 2>&1; git commit -qm binbase >/dev/null 2>&1; CB="$(git rev-parse HEAD)"
printf 'TOTALLY-DIFFERENT-v2\x00\x02' > csrc/lib.jar
ok "binary file swap -> behavioural" "$(beh bin "$CB")" "yes"

CB="$(git rev-parse HEAD)"
git mv csrc/a.c csrc/renamed.c >/dev/null 2>&1
ok "pure rename -> behavioural" "$(beh ren "$CB")" "yes"

# And the true negatives must still hold.
printf '// explains it\npackage m\n' > csrc/m2.go
git add -A >/dev/null 2>&1; git commit -qm m2 >/dev/null 2>&1; CB="$(git rev-parse HEAD)"
printf '// explains it much better\npackage m\n' > csrc/m2.go
ok "Go // comment change -> NOT behavioural" "$(beh gocmt "$CB")" "no"

printf '# a python comment\nx = 1\n' > csrc/p.py
git add -A >/dev/null 2>&1; git commit -qm pbase >/dev/null 2>&1; CB="$(git rev-parse HEAD)"
printf '# a different python comment\nx = 1\n' > csrc/p.py
ok "Python # comment change -> NOT behavioural" "$(beh pycmt "$CB")" "no"
git checkout -q feat/x

section "reviewer output parsed as the shipped agents actually print it"

# Fixtures copied from agents/l1-reviewer.md's own "Output format — strict"
# block. Severity sits on the HEADING and the finding line carries only a cite;
# a fixture that puts both on one line is a shape no agent emits, and a parser
# tested against it passes while recording nothing from a real report.
subrepo realfmt
printf '# plan\n- src/one.go\n' > docs/plans/p.md
RVD=".claude/reviews/feat/plan.verdicts"
rpt() { rm -rf .claude/reviews
  python3 -c "
import json,sys
print(json.dumps({'tool_name':'Task','session_id':'s',
 'tool_input':{'subagent_type':'exloom:l1-reviewer','prompt':'Review. Format: VERDICT: APPROVED'},
 'tool_response':[{'type':'text','text':sys.argv[1]}]}))" "$1" | bash "$HOOKS_ABS/record-reviewer-verdict.sh" >/dev/null 2>&1; }
vof() { sed -n 's/.*"verdict":"\([A-Z]*\)".*/\1/p' "$RVD/l1-reviewer.json" 2>/dev/null | tail -1; }
nf()  { grep -c . "$RVD/l1-reviewer.findings.jsonl" 2>/dev/null | head -1; }

rpt '## Critical (must fix before merge)
- src/one.go:42 — null deref when the list is empty
- src/two.go:17 — unclosed reader on the error path

## Minor (may defer with a reason in the checklist)
- src/three.go:5 — name could be clearer

## Nothing to flag in
- src/four.go

VERDICT: REJECTED (3 items)'
ok "shipped format -> findings recorded" "$(nf)" "3"
ok "shipped format -> REJECTED" "$(vof)" "REJECTED"
ok "'Nothing to flag in' is not a finding" \
   "$(grep -c 'four.go' "$RVD/l1-reviewer.findings.jsonl" 2>/dev/null | head -1)" "0"
ok "severity comes from the heading" \
   "$(grep -c '"severity":"HIGH"' "$RVD/l1-reviewer.findings.jsonl" 2>/dev/null | head -1)" "2"

rpt '## Critical (must fix before merge)
- src/one.go:9 — boom

**VERDICT: REJECTED (1 items)**'
ok "bold verdict is read" "$(vof)" "REJECTED"

rpt 'VERDICT: APPROVED WITH CHANGES'
ok "APPROVED WITH CHANGES is not an approval" "$(vof)" "UNKNOWN"

rpt 'My output format is:
VERDICT: APPROVED
VERDICT: REJECTED (n items)

## Critical (must fix before merge)
- src/one.go:3 — real defect

VERDICT: REJECTED (1 items)'
ok "echoed template does not win over the real verdict" "$(vof)" "REJECTED"

cd "$WORK" || exit 1

section "classifier: near-misses of the comment-marker rules"

# Each case sits one character away from a rule above it. These are the shapes a
# marker-based classifier gets wrong once it has been made to handle the obvious
# ones, so they stay as permanent guards.

git checkout -q -b feat/r2 main
mkdir -p r2
r2beh() { git add -A >/dev/null 2>&1; git commit -qm "$1" >/dev/null 2>&1
          exloom_diff_is_behavioural "$2" HEAD && echo yes || echo no; }

# `*o = 1` opens with a star, exactly like a javadoc continuation line. One is a
# dereference and the other is a comment, and only the following character tells
# them apart.
printf 'int f(int *o){ *o = 1; return 0; }\n' > r2/d.c
git add -A >/dev/null 2>&1; git commit -qm dbase >/dev/null 2>&1; RB="$(git rev-parse HEAD)"
printf 'int f(int *o){ *o = 999; return 0; }\n' > r2/d.c
ok "pointer deref -> behavioural" "$(r2beh deref "$RB")" "yes"

printf '/**\n * explains f\n */\nint f(void){ return 1; }\n' > r2/j.java
git add -A >/dev/null 2>&1; git commit -qm jbase >/dev/null 2>&1; RB="$(git rev-parse HEAD)"
printf '/**\n * explains f much better\n */\nint f(void){ return 1; }\n' > r2/j.java
ok "javadoc continuation -> NOT behavioural" "$(r2beh javadoc "$RB")" "no"

# A shell script emitting markdown from a heredoc: `#` opens a comment in shell
# and a heading inside the body, so a marker rule that does not know where the
# body starts misreads the whole file.
printf 'cat <<EOF\n# heading one\nEOF\n' > r2/e.sh
git add -A >/dev/null 2>&1; git commit -qm ebase >/dev/null 2>&1; RB="$(git rev-parse HEAD)"
printf 'cat <<EOF\n# heading TWO CHANGED\nEOF\n' > r2/e.sh
ok "heredoc body in .sh -> behavioural" "$(r2beh heredoc "$RB")" "yes"
git checkout -q feat/x

section "verdict decoration: every form an LLM actually emits"

subrepo vdec
printf '# plan\n- src/one.go\n' > docs/plans/p.md
VVD=".claude/reviews/feat/plan.verdicts"
vsay() { rm -rf .claude/reviews
  python3 -c "
import json,sys
print(json.dumps({'tool_name':'Task','session_id':'s',
 'tool_input':{'subagent_type':'exloom:l1-reviewer','prompt':'review'},
 'tool_response':[{'type':'text','text':sys.argv[1]}]}))" "$1" | bash "$HOOKS_ABS/record-reviewer-verdict.sh" >/dev/null 2>&1
  sed -n 's/.*"verdict":"\([A-Z]*\)".*/\1/p' "$VVD/l1-reviewer.json" 2>/dev/null | tail -1; }

ok "VERDICT: **APPROVED**"         "$(vsay 'VERDICT: **APPROVED**')" "APPROVED"
ok "**VERDICT:** REJECTED (2)"     "$(vsay '**VERDICT:** REJECTED (2 items)')" "REJECTED"
ok "- **VERDICT:** APPROVED"       "$(vsay '- **VERDICT:** APPROVED')" "APPROVED"
ok "VERDICT: APPROVED."            "$(vsay 'VERDICT: APPROVED.')" "APPROVED"
ok "APPROVED WITH CHANGES -> UNKNOWN" "$(vsay 'VERDICT: APPROVED WITH CHANGES')" "UNKNOWN"

# A heading may contain a word the severity matcher also looks for. "Critical
# (cleanup of stale handlers)" is a Critical section, and keying on "clean"
# inside it would drop every finding beneath.
rm -rf .claude/reviews
python3 -c "
import json
print(json.dumps({'tool_name':'Task','session_id':'s',
 'tool_input':{'subagent_type':'exloom:l1-reviewer','prompt':'review'},
 'tool_response':[{'type':'text','text':'## Critical (cleanup of stale handlers)\n- src/one.go:4 — real defect\n\nVERDICT: REJECTED (1 items)'}]}))" \
 | bash "$HOOKS_ABS/record-reviewer-verdict.sh" >/dev/null 2>&1
ok "'Critical (cleanup...)' still records findings" \
   "$(grep -c . "$VVD/l1-reviewer.findings.jsonl" 2>/dev/null | head -1)" "1"

section "proof: the three-run protocol"

PRV="$(cd "$(dirname "$LIB_ABS")/../scripts" && pwd)/prove-change-is-tested.sh"
prv() { local d="$REG/$1"; rm -rf "$d"; mkdir -p "$d/src" "$d/tests" "$d/.claude"; cd "$d" || return 1
        git init -q -b main . 2>/dev/null; git config user.email t@e.com; git config user.name t
        : > .claude/exloom-gate.enabled; printf 'bash tests/t.sh\n' > .claude/exloom-test-command; }
prvrun() { bash "$PRV" --base "$1" >/dev/null 2>&1; echo $?; }

prv void
printf 'g(){ return 0; }\n' > src/l.sh
printf '. ./missing/dep.sh\ng\n' > tests/t.sh
git add -A >/dev/null 2>&1; git commit -qm b >/dev/null 2>&1; PB="$(git rev-parse HEAD)"
printf 'g(){ return 0; }\nh(){ return 0; }\n' > src/l.sh
printf '. ./missing/dep.sh\ng && h\n' > tests/t.sh
git add -A >/dev/null 2>&1; git commit -qm c >/dev/null 2>&1
ok "base suite cannot run -> PROOF VOID" "$(prvrun "$PB")" "2"

prv real
printf 'calc(){ echo 4; }\n' > src/l.sh
printf '. ./src/l.sh\n[ "$(calc)" = "4" ]\n' > tests/t.sh
git add -A >/dev/null 2>&1; git commit -qm b >/dev/null 2>&1; PB="$(git rev-parse HEAD)"
printf 'calc(){ echo 5; }\n' > src/l.sh
printf '. ./src/l.sh\n[ "$(calc)" = "5" ]\n' > tests/t.sh
git add -A >/dev/null 2>&1; git commit -qm c >/dev/null 2>&1
ok "genuine behavioural test -> PROVED" "$(prvrun "$PB")" "0"
ok "--cmd false -> PROOF VOID" \
   "$(bash "$PRV" --base "$PB" --cmd false >/dev/null 2>&1; echo $?)" "2"


section "proof: run-2 classification comes from a structured report, never from text"

# A run-2 failure is scored today by one cross-language regex: match means the
# tests could not build (NOT_APPLICABLE), no match means they asserted (PROVED).
# A broken fixture, a bad config or a crashed harness therefore scores PROVED.
# PROOF_ERROR closes that, but only on a machine-readable signal — a text match
# must never reach it, or a repo whose assertion message happens to contain the
# wrong word becomes unpushable.
CLS="$(sed -n '/^_classify_run2() {/,/^}/p' "$PRVS")"
cls() {   # cls <report-file> <exit-code> -> proved|error|unknown
  bash -c 'set -u; '"$CLS"'
    _classify_run2 "$1" "$2"' _ "$1" "${2:-1}"
}
RP="$REG/reports"; rm -rf "$RP"; mkdir -p "$RP"

# JUnit XML — Gradle, Maven, pytest --junitxml. `errors` and `failures` are
# separate attributes precisely because the two outcomes are different.
printf '<testsuite tests="3" failures="1" errors="0"><testcase name="a"/></testsuite>\n' > "$RP/j-fail.xml"
ok "junit: a plain assertion failure is PROVED" "$(cls "$RP/j-fail.xml")" "proved"
printf '<testsuite tests="3" failures="0" errors="1"><testcase name="a"/></testsuite>\n' > "$RP/j-err.xml"
ok "junit: an error with no failure is an ERROR" "$(cls "$RP/j-err.xml")" "error"
printf '<testsuite tests="3" failures="2" errors="1"><testcase name="a"/></testsuite>\n' > "$RP/j-both.xml"
ok "junit: a failure alongside an error is still PROVED" "$(cls "$RP/j-both.xml")" "proved"
printf '<testsuite tests="0" failures="0" errors="0"></testsuite>\n' > "$RP/j-none.xml"
ok "junit: nothing ran -> no opinion" "$(cls "$RP/j-none.xml")" "unknown"

# Jest and Vitest, --json. A suite that throws before any test runs reports
# testExecError and zero failed tests.
printf '{"numFailedTests":1,"numFailedTestSuites":1,"testResults":[{"status":"failed"}]}\n' > "$RP/jest-fail.json"
ok "jest: a plain assertion failure is PROVED" "$(cls "$RP/jest-fail.json")" "proved"
printf '{"numFailedTests":0,"numFailedTestSuites":1,"testResults":[{"status":"failed","testExecError":{"message":"boom"}}]}\n' > "$RP/jest-crash.json"
ok "jest: a suite that crashed before asserting is an ERROR" "$(cls "$RP/jest-crash.json")" "error"

# .NET, --logger trx. Counters carries failed and error separately.
printf '<TestRun><ResultSummary><Counters total="3" failed="1" error="0" aborted="0"/></ResultSummary></TestRun>\n' > "$RP/t-fail.trx"
ok "trx: a plain assertion failure is PROVED" "$(cls "$RP/t-fail.trx")" "proved"
printf '<TestRun><ResultSummary><Counters total="3" failed="0" error="1" aborted="0"/></ResultSummary></TestRun>\n' > "$RP/t-err.trx"
ok "trx: an error with no failure is an ERROR" "$(cls "$RP/t-err.trx")" "error"

# Flutter, --machine. One JSON event per line.
printf '{"type":"testDone","result":"failure"}\n' > "$RP/f-fail.jsonl"
ok "flutter: a plain assertion failure is PROVED" "$(cls "$RP/f-fail.jsonl")" "proved"
printf '{"type":"error","error":"boom"}\n' > "$RP/f-err.jsonl"
ok "flutter: a harness error is an ERROR" "$(cls "$RP/f-err.jsonl")" "error"

# No opinion is the default, and the only route to the existing text check.
ok "a missing report has no opinion" "$(cls "$RP/absent.xml")" "unknown"
printf 'not a report at all\n' > "$RP/garbage.txt"
ok "an unparseable report has no opinion" "$(cls "$RP/garbage.txt")" "unknown"
printf '<testsuite tests="3" failures="1" errors="0"/>\n' > "$RP/j-ok.xml"
ok "a report from a PASSING run has no opinion" "$(cls "$RP/j-ok.xml" 0)" "unknown"

section "proof: the tests a run executes are the ones the diff touches"

SELF="$(sed -n '/^is_test() {/,/^}/p' "$PRVS"; sed -n '/^_selected_tests() {/,/^}/p' "$PRVS")"
sel() {   # sel <side> -> the selected paths for base or head
  bash -c 'set -u; '"$SELF"'
    _selected_tests "$1"' _ "$1"
}
subrepo seltest
mkdir -p tests
printf 'x\n' > src/keep.sh
printf 'echo old\n' > tests/old.sh
printf 'echo gone\n' > tests/gone.sh
printf 'echo moved\n' > tests/moved.sh
git add -A >/dev/null 2>&1; git commit -qm b >/dev/null 2>&1; SB="$(git rev-parse HEAD)"
printf 'echo old2\n' > tests/old.sh
printf 'echo brand new\n' > tests/fresh.sh
git rm -q tests/gone.sh >/dev/null 2>&1
git mv tests/moved.sh tests/renamed.sh >/dev/null 2>&1
git add -A >/dev/null 2>&1; git commit -qm c >/dev/null 2>&1
export BASE="$SB"
ok "a modified test is selected at head"   "$(sel head | grep -c '^tests/old.sh$')"     "1"
ok "a new test is selected at head"        "$(sel head | grep -c '^tests/fresh.sh$')"   "1"
ok "a new test is NOT selected at base"    "$(sel base | grep -c '^tests/fresh.sh$')"   "0"
ok "a deleted test is selected nowhere"    "$(sel head | grep -c '^tests/gone.sh$')$(sel base | grep -c '^tests/gone.sh$')" "00"
ok "a rename selects the new path at head" "$(sel head | grep -c '^tests/renamed.sh$')" "1"
ok "a rename selects the old path at base" "$(sel base | grep -c '^tests/moved.sh$')"   "1"
ok "a source file is never selected"       "$(sel head | grep -c 'keep.sh')"            "0"
unset BASE


section "fast-check: advisory, and advisory means it cannot stop anything"

FC="$(cd "$(dirname "$LIB_ABS")/../scripts" && pwd)/fast-check.sh"
subrepo fastcheck
FCB="$(git rev-parse --abbrev-ref HEAD)"; FCL=".claude/reviews/${FCB}.md"
mkdir -p "$(dirname "$FCL")"
printf '# checklist\n' > "$FCL"
ok "a failing fast check still exits 0" \
   "$(bash "$FC" --cmd false >/dev/null 2>&1; echo $?)" "0"
ok "a passing fast check exits 0" \
   "$(bash "$FC" --cmd true >/dev/null 2>&1; echo $?)" "0"
printf '# checklist\n' > "$FCL"; bash "$FC" --cmd false >/dev/null 2>&1
ok "a failing fast check is recorded in the checklist" \
   "$(grep -c 'Fast check:.*warn' "$FCL" 2>/dev/null)" "1"
printf '# checklist\n' > "$FCL"; bash "$FC" --cmd true >/dev/null 2>&1
ok "a passing fast check is recorded too" \
   "$(grep -c 'Fast check:.*pass' "$FCL" 2>/dev/null)" "1"
ok "fast-check writes no verdict receipt" \
   "$(ls -d .claude/reviews/*.verdicts 2>/dev/null | wc -l | tr -d ' ')" "0"
ok "no fast command is reported, not fatal" \
   "$(bash "$FC" 2>&1 | grep -c 'no fast command')" "1"

# An uncommitted setting is not a setting: each developer would check something
# different, and the branch could not say what was checked.
printf 'false\n' > .claude/exloom-fast-command
ok "an uncommitted fast command is ignored" \
   "$(bash "$FC" 2>&1 | grep -c 'fast-check: false')" "0"
git add .claude/exloom-fast-command >/dev/null 2>&1
git commit -qm fc >/dev/null 2>&1
ok "a committed fast command is used" \
   "$(bash "$FC" 2>&1 | grep -c 'fast-check: false')" "1"


section "exloom-ci: the full suite is owned by CI, or by the gate, never by nobody"

# Honoured only when committed, like every other setting: an uncommitted one
# would mean the gate asked a different question of each developer.
subrepo cisettings
printf 'none\n' > .claude/exloom-ci
ok "an uncommitted exloom-ci is not read" "$(exloom_repo_ci)" ""
git add .claude/exloom-ci >/dev/null 2>&1; git commit -qm ci >/dev/null 2>&1
ok "a committed exloom-ci is read"        "$(exloom_repo_ci)" "none"
printf 'github\n' > .claude/exloom-ci; git add -A >/dev/null 2>&1; git commit -qm ci2 >/dev/null 2>&1
ok "github is read"                       "$(exloom_repo_ci)" "github"
printf 'nonsense\n' > .claude/exloom-ci; git add -A >/dev/null 2>&1; git commit -qm ci3 >/dev/null 2>&1
ok "an unknown value is not honoured"     "$(exloom_repo_ci)" ""

# With no CI, the suite has to run somewhere, and the only place left is here.
ok "none demands a recorded full suite"   "$(exloom_full_suite_required none; echo $?)" "0"
ok "github does not"                      "$(exloom_full_suite_required github; echo $?)" "1"
ok "an absent setting does not"           "$(exloom_full_suite_required ''; echo $?)" "1"

# The receipt is written by record-full-suite.sh and committed; prose under
# `## Full suite` is a summary for a reader, not what the gate reads.
RFS="$(cd "$(dirname "$LIB_ABS")/../scripts" && pwd)/record-full-suite.sh"
subrepo fullsuite
CLF=".claude/reviews/$(git rev-parse --abbrev-ref HEAD).md"
VD=".claude/reviews/$(git rev-parse --abbrev-ref HEAD).verdicts"
mkdir -p "$(dirname "$CLF")"; printf '# checklist\n' > "$CLF"
bash "$RFS" -- true >/dev/null 2>&1
ok "a passing run is recorded with exit 0" \
   "$(grep -c '"check":"full-suite".*"exit":0,' "$VD/full-suite.json" 2>/dev/null)" "1"
bash "$RFS" -- false >/dev/null 2>&1
ok "a failing run records its exit code" \
   "$(tail -1 "$VD/full-suite.json" | grep -c '"exit":1,')" "1"
ok "output is captured beside the receipt" \
   "$([[ -f "$VD/full-suite.out" ]] && echo yes || echo no)" "yes"

# Only a committed receipt counts, and only a passing one.
git add -A >/dev/null 2>&1; git commit -qm fs1 >/dev/null 2>&1
ok "a failing receipt does not cover the tip" \
   "$(exloom_full_suite_ok "$CLF" HEAD HEAD; echo $?)" "1"
# The receipt names HEAD as it was when the suite ran, and committing it makes
# a further commit — so what must not stale it is the receipt's own commit.
printf 'notes\n' > NOTES.md; git add -A >/dev/null 2>&1; git commit -qm notes >/dev/null 2>&1
: > "$VD/full-suite.json"; bash "$RFS" -- true >/dev/null 2>&1
git add -A >/dev/null 2>&1; git commit -qm fs2 >/dev/null 2>&1
ok "a passing receipt at the tip covers it" \
   "$(exloom_full_suite_ok "$CLF" HEAD HEAD; echo $?)" "0"

# A comment-only edit on top must not force the suite again. The existing rule
# is narrower than it sounds: a new file is behavioural whatever its extension,
# a .md edit is behavioural because markdown has no comment syntax, and `#` is
# not treated as a comment at all because of shebangs and #define.
printf 'class A {\n  int x = 1;\n}\n' > src/A.java
git add -A >/dev/null 2>&1; git commit -qm java >/dev/null 2>&1
: > "$VD/full-suite.json"; bash "$RFS" -- true >/dev/null 2>&1
git add -A >/dev/null 2>&1; git commit -qm fs3 >/dev/null 2>&1
printf 'class A {\n  // a new comment\n  int x = 1;\n}\n' > src/A.java
git add -A >/dev/null 2>&1; git commit -qm comment >/dev/null 2>&1
ok "a non-behavioural commit since does not stale it" \
   "$(exloom_full_suite_ok "$CLF" HEAD HEAD; echo $?)" "0"

# Documentation is dropped from the diff for THIS check only. A README edit
# cannot change what the suite does, and on a repo with no CI the suite is
# expensive enough that re-running it for a typo is how the gate gets bypassed.
: > "$VD/full-suite.json"; bash "$RFS" -- true >/dev/null 2>&1
git add -A >/dev/null 2>&1; git commit -qm fs4 >/dev/null 2>&1
printf '# readme\nnew line\n' > README.md
git add -A >/dev/null 2>&1; git commit -qm readme >/dev/null 2>&1
ok "a README-only commit does not force a re-run" \
   "$(exloom_full_suite_ok "$CLF" HEAD HEAD; echo $?)" "0"
mkdir -p docs; printf 'flow\n' > docs/diagram.mmd
git add -A >/dev/null 2>&1; git commit -qm mmd >/dev/null 2>&1
ok "an .mmd diagram does not either" \
   "$(exloom_full_suite_ok "$CLF" HEAD HEAD; echo $?)" "0"
printf 'package m\nfunc Y() int { return 2 }\n' > src/y.go
git add -A >/dev/null 2>&1; git commit -qm code2 >/dev/null 2>&1
ok "a code commit among the docs still does" \
   "$(exloom_full_suite_ok "$CLF" HEAD HEAD; echo $?)" "1"
printf 'package m\nfunc X() int { return 1 }\n' > src/real.go
git add -A >/dev/null 2>&1; git commit -qm code >/dev/null 2>&1
ok "a behavioural commit since does stale it" \
   "$(exloom_full_suite_ok "$CLF" HEAD HEAD; echo $?)" "1"

section "settings a .gitignore would silently drop"

# Every setting is honoured only when committed, so one that .gitignore keeps
# out is a setting the author thinks is on and the gate never sees.
subrepo ignoredsettings
printf '.claude/exloom-*\n' > .gitignore
git add .gitignore >/dev/null 2>&1; git commit -qm gi >/dev/null 2>&1
IGN="$(exloom_ignored_settings "$(git rev-parse --abbrev-ref HEAD)")"
for s in exloom-ci exloom-fast-command exloom-test-select; do
  ok "an ignored .claude/$s is reported" "$(printf '%s\n' "$IGN" | grep -c "^\.claude/$s$")" "1"
done


section "changing the gate's own settings is a Tier 3 change"

# Every setting decides what the gate asks for. A change to one is a change to
# the protection itself, so it earns the tier that has no escape hatch.
subrepo settingstier
ok "a change to .claude/exloom-ci is Tier 3"       "$(sp .claude/exloom-ci)" "3"
ok "a change to .claude/exloom-min-tier is Tier 3" "$(sp .claude/exloom-min-tier)" "3"
ok "a change to .claude/exloom-lane is Tier 3"     "$(sp .claude/exloom-lane)" "3"
ok "an ordinary source file is not"                "$(sp src/ordinary.go)" "1"

section "exloom-min-tier: a floor, and the one tier it can never skip"

subrepo mintier
printf '2\n' > .claude/exloom-min-tier
ok "an uncommitted floor is not read"  "$(exloom_min_tier)" "0"
git add .claude/exloom-min-tier >/dev/null 2>&1; git commit -qm mt >/dev/null 2>&1
ok "a committed floor is read"         "$(exloom_min_tier)" "2"
printf '3\n' > .claude/exloom-min-tier; git add -A >/dev/null 2>&1; git commit -qm mt3 >/dev/null 2>&1
ok "a floor above 2 is capped at 2"    "$(exloom_min_tier)" "2"
printf '9\n' > .claude/exloom-min-tier; git add -A >/dev/null 2>&1; git commit -qm mt9 >/dev/null 2>&1
ok "so Tier 3 is never skippable"      "$(exloom_min_tier)" "2"
printf 'abc\n' > .claude/exloom-min-tier; git add -A >/dev/null 2>&1; git commit -qm mtx >/dev/null 2>&1
ok "a non-numeric floor is no floor"   "$(exloom_min_tier)" "0"

# Certified and strict buy rigour deliberately; a floor would sell it back.
printf '2\n' > .claude/exloom-min-tier
printf 'certified\n' > .claude/exloom-lane
git add -A >/dev/null 2>&1; git commit -qm cert >/dev/null 2>&1
ok "Certified ignores the floor"       "$(exloom_min_tier)" "0"
git rm -q .claude/exloom-lane >/dev/null 2>&1
: > .claude/exloom-strict
git add -A >/dev/null 2>&1; git commit -qm strict >/dev/null 2>&1
ok "strict mode ignores the floor"     "$(exloom_min_tier)" "0"


section "exloom-min-tier: what a floor skips, and what it records"

PJ='{"session_id":"s","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"git push"}}'
pushrc() { printf '%s' "$PJ" | bash "$HOOKS_ABS/block-unverified-push.sh" >/dev/null 2>&1; echo $?; }

# A Tier 1 branch under a floor of 2 needs no review and no proof.
subrepo mintierpush
git checkout -q main
printf '2\n' > .claude/exloom-min-tier
git add -A >/dev/null 2>&1; git commit -qm floor >/dev/null 2>&1
SETSHA="$(git rev-parse HEAD)"
git update-ref refs/remotes/origin/main HEAD
git checkout -qB feat/plan main
printf 'a\n' > src/ordinary.txt; git add -A >/dev/null 2>&1; git commit -qm work >/dev/null 2>&1
ok "a push below the floor is allowed"       "$(pushrc)" "0"
SK=".claude/reviews/$(git rev-parse --abbrev-ref HEAD).skip.json"
ok "...and a skip receipt is written"        "$([[ -f "$SK" ]] && echo yes || echo no)" "yes"
ok "...naming the derived tier"              "$(grep -c '"tier":1' "$SK" 2>/dev/null)" "1"
ok "...naming the floor"                     "$(grep -c '"min_tier":2' "$SK" 2>/dev/null)" "1"
ok "...naming the commit that set it"        "$(grep -c "\"set_in\":\"${SETSHA}\"" "$SK" 2>/dev/null)" "1"
ok "...and who set it"                       "$(grep -c '"set_by":"t"' "$SK" 2>/dev/null)" "1"

# Tier 3 is above the cap, so no floor can reach it.
subrepo mintierhigh
git checkout -q main
printf '2\n' > .claude/exloom-min-tier
git add -A >/dev/null 2>&1; git commit -qm floor >/dev/null 2>&1
git update-ref refs/remotes/origin/main HEAD
git checkout -qB feat/plan main
mkdir -p db/migrations; printf 'create table t();\n' > db/migrations/V2.sql
git add -A >/dev/null 2>&1; git commit -qm mig >/dev/null 2>&1
ok "a Tier 3 push is still gated"            "$(pushrc)" "2"

# Certified and strict buy rigour; a floor cannot sell it back.
subrepo mintierstrict
git checkout -q main
printf '2\n' > .claude/exloom-min-tier; : > .claude/exloom-strict
git add -A >/dev/null 2>&1; git commit -qm floor >/dev/null 2>&1
git update-ref refs/remotes/origin/main HEAD
git checkout -qB feat/plan main
printf 'a\n' > src/ordinary.txt; git add -A >/dev/null 2>&1; git commit -qm work >/dev/null 2>&1
ok "strict mode ignores the floor and gates" "$(pushrc)" "2"


section "smoke waiver: a skip that names who skipped it"

# The gate cannot prompt, so the waiver is a committed line. It is accepted only
# where the lane allows a skip at all, and only when it says who and at which
# commit — an anonymous waiver is indistinguishable from a forgotten step.
subrepo smokewaiver
WOK="- Smoke test waived: no UI on this change — Mahesh O A at 4f2a1c9"
ok "a waiver naming who and where is read" \
   "$(printf '%s\n' "$WOK" | exloom_smoke_waived; echo $?)" "0"
ok "a bare waiver is not"  "$(printf -- '- Smoke test waived\n' | exloom_smoke_waived; echo $?)" "1"
ok "a reason with no identity is not" \
   "$(printf -- '- Smoke test waived: no UI\n' | exloom_smoke_waived; echo $?)" "1"
ok "an unrelated line is not" "$(printf -- '- Smoke test: ran it\n' | exloom_smoke_waived; echo $?)" "1"

# Certified and strict bought the smoke test; a waiver would be selling it back.
printf 'certified\n' > .claude/exloom-lane
git add -A >/dev/null 2>&1; git commit -qm cert >/dev/null 2>&1
ok "Certified refuses a waiver" "$(printf '%s\n' "$WOK" | exloom_smoke_waived; echo $?)" "1"
git rm -q .claude/exloom-lane >/dev/null 2>&1; : > .claude/exloom-strict
git add -A >/dev/null 2>&1; git commit -qm strict >/dev/null 2>&1
ok "strict mode refuses a waiver"  "$(printf '%s\n' "$WOK" | exloom_smoke_waived; echo $?)" "1"


section "work type: a bug fix is not a feature, and must not be marched through one"

# exloom_next_step routed every non-sprint branch to spec then plan. A bug fix
# has no spec to write — the behaviour was already agreed — and marching it
# through one is what made people run the steps by hand and stop using the gate.
subrepo worktype
WTCL=".claude/reviews/$(git rev-parse --abbrev-ref HEAD).md"
mkdir -p "$(dirname "$WTCL")"
wtset() {   # wtset <work-type-line> [spec] [plan]
  { printf '# review\n\n**Lane:** standard\n'
    [[ -n "${1:-}" ]] && printf '**Work type:** %s\n' "$1"
    [[ -n "${2:-}" ]] && printf '**Spec:** %s\n' "$2"
    [[ -n "${3:-}" ]] && printf '**Plan:** %s\n' "$3"; } > "$WTCL"
  git add -A >/dev/null 2>&1; git commit -qm wt >/dev/null 2>&1
}

wtset '' '' ''
ok "a feature with no spec still asks for one"  "$(exloom_next_step "$(git rev-parse --abbrev-ref HEAD)")" "spec"
wtset 'new feature' '' ''
ok "...and so does an explicit new feature"     "$(exloom_next_step "$(git rev-parse --abbrev-ref HEAD)")" "spec"

wtset 'bug fix' '' ''
ok "a bug fix is never sent to spec"            "$(exloom_next_step "$(git rev-parse --abbrev-ref HEAD)" | grep -c '^spec$')" "0"
ok "a bug fix is never sent to plan"            "$(exloom_next_step "$(git rev-parse --abbrev-ref HEAD)" | grep -c '^plan$')" "0"

# A change note stands in for the spec; a single task needs no plan beside it.
printf 'now: x\nnext: y\n1. it does y\n' > docs/change-note.md
wtset 'change to existing code' '' ''
ok "a change still needs its note"              "$(exloom_next_step "$(git rev-parse --abbrev-ref HEAD)")" "spec"
wtset 'change to existing code' 'docs/change-note.md' 'none'
ok "the note counts as the spec"                "$(exloom_next_step "$(git rev-parse --abbrev-ref HEAD)" | grep -c '^spec$')" "0"
ok "...and 'none' is an acceptable plan"        "$(exloom_next_step "$(git rev-parse --abbrev-ref HEAD)" | grep -c '^plan$')" "0"
wtset 'new feature' 'docs/change-note.md' 'none'
ok "but a feature may not plead 'none'"         "$(exloom_next_step "$(git rev-parse --abbrev-ref HEAD)")" "plan"


section "a reviewer is dispatched, never resumed"

# Resuming a reviewer carries its earlier conclusion and the session's framing
# into the verify pass, which is how a REJECTED finding gets talked into
# ADDRESSED. Verify runs as a fresh dispatch so it leaves its own receipt.
GRM="$HOOKS_ABS/guard-reviewer-message.sh"
subrepo sendmsg
SMV=".claude/reviews/$(git rev-parse --abbrev-ref HEAD).verdicts"
mkdir -p "$SMV"
{ printf '{"agent":"l1-reviewer","key":"final","kind":"review","tool_use_id":"toolu_L1","dispatch_head":"aaa","at":"t"}\n'
  printf '{"map":true,"tool_use_id":"toolu_L1","agent_id":"aREVIEWER1","model":"m"}\n'
  printf '{"agent":"adversarial-reviewer","key":"final","kind":"review","tool_use_id":"toolu_ADV","dispatch_head":"aaa","at":"t"}\n'
  printf '{"map":true,"tool_use_id":"toolu_ADV","agent_id":"aREVIEWER2","model":"m"}\n'
  printf '{"agent":"fixer","key":"fix","kind":"fix","tool_use_id":"toolu_FIX","dispatch_head":"aaa","at":"t"}\n'
  printf '{"map":true,"tool_use_id":"toolu_FIX","agent_id":"aFIXER","model":"m"}\n'; } > "$SMV/dispatches.jsonl"

sm() {   # sm <recipient> -> hook exit code
  python3 -c "
import json,sys
print(json.dumps({'session_id':'s','hook_event_name':'PreToolUse','tool_name':'SendMessage',
 'tool_input':{'to':sys.argv[1],'message':'please re-check'}}))" "$1" \
   | bash "$GRM" >/dev/null 2>&1; echo $?
}

ok "a message to a dispatched L1 reviewer is refused"          "$(sm aREVIEWER1)" "2"
ok "a message to a dispatched adversarial reviewer is refused" "$(sm aREVIEWER2)" "2"
ok "a message to the fixer is allowed"                         "$(sm aFIXER)" "0"
ok "a message to an agent not in the log is allowed"           "$(sm aSOMEONEELSE)" "0"
ok "a message named for a reviewer is refused"                 "$(sm exloom:l1-reviewer)" "2"
ok "a message named for the spec reviewer is refused"          "$(sm exloom:spec-reviewer)" "2"
ok "a message named for the fixer is allowed"                  "$(sm exloom:fixer)" "0"
ok "a recipient named in mixed case is still refused"  "$(sm Exloom:L1-Reviewer)" "2"
ok "...and in upper case"                              "$(sm EXLOOM:SPEC-REVIEWER)" "2"
ok "...with a plugin prefix"                           "$(sm plugin:exloom:adversarial-reviewer)" "2"
ok "the refusal names the fresh dispatch instead" \
   "$(python3 -c "
import json
print(json.dumps({'session_id':'s','hook_event_name':'PreToolUse','tool_name':'SendMessage',
 'tool_input':{'to':'aREVIEWER1','message':'re-check'}}))" | bash "$GRM" 2>&1 | grep -c 'MODE: VERIFY')" "1"

# Another tool is none of its business.
ok "a Bash call is not touched" \
   "$(printf '%s' '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"ls"}}' \
      | bash "$GRM" >/dev/null 2>&1; echo $?)" "0"


section "a reviewer reads a diff, it does not check one out"

# Reviewers were creating a worktree each and removing it inconsistently, which
# is how a repo collects hundreds of megabytes nobody can account for. A
# PreToolUse payload raised inside a subagent carries agent_type, so the refusal
# is scoped to reviewers and cannot catch the fixer, the session, or the proof
# script's own throwaway worktree.
GRS="$HOOKS_ABS/guard-reviewer-shell.sh"
subrepo wtguard
wt() {   # wt <agent_type|-> <command> -> hook exit code
  python3 -c "
import json,sys
d={'session_id':'s','hook_event_name':'PreToolUse','tool_name':'Bash',
   'tool_input':{'command':sys.argv[2]}}
if sys.argv[1] != '-':
    d['agent_id']='aAGENT'; d['agent_type']=sys.argv[1]
print(json.dumps(d))" "$1" "$2" | bash "$GRS" >/dev/null 2>&1; echo $?
}

ok "a reviewer may not add a worktree" \
   "$(wt exloom:l1-reviewer 'git worktree add ../wt-review HEAD')" "2"
ok "...nor the adversarial reviewer" \
   "$(wt exloom:adversarial-reviewer 'git worktree add .worktrees/adv HEAD')" "2"
ok "...nor the security auditor" \
   "$(wt exloom:security-auditor 'git worktree add /tmp/sec HEAD')" "2"
ok "...nor the spec reviewer" \
   "$(wt exloom:spec-reviewer 'git worktree add /tmp/spec HEAD')" "2"

ok "the fixer may"            "$(wt exloom:fixer 'git worktree add /tmp/fix HEAD')" "0"
ok "the session itself may"   "$(wt - 'git worktree add /tmp/mine HEAD')" "0"
ok "a reviewer may still read a diff" \
   "$(wt exloom:l1-reviewer 'git diff abc..def -- src/')" "0"
ok "...and read a file at a commit" \
   "$(wt exloom:l1-reviewer 'git show abc:src/a.go')" "0"
ok "...and remove a worktree it should not have made" \
   "$(wt exloom:l1-reviewer 'git worktree remove /tmp/oops')" "0"

# git takes options before the subcommand, and an option that takes a value
# breaks a pattern that assumes every option is a bare flag.
ok "a reviewer may not add a worktree via -C" \
   "$(wt exloom:l1-reviewer 'git -C /tmp/elsewhere worktree add /tmp/wt HEAD')" "2"
ok "...nor via --git-dir" \
   "$(wt exloom:l1-reviewer 'git --git-dir=/tmp/x/.git worktree add /tmp/wt HEAD')" "2"
ok "...nor with -c config before it" \
   "$(wt exloom:l1-reviewer 'git -c core.quotepath=false worktree add /tmp/wt HEAD')" "2"
ok "...nor with the paths reordered" \
   "$(wt exloom:l1-reviewer 'git worktree --quiet add /tmp/wt HEAD')" "2"
ok "the refusal names what to use instead" \
   "$(python3 -c "
import json
print(json.dumps({'session_id':'s','hook_event_name':'PreToolUse','tool_name':'Bash',
 'agent_id':'a1','agent_type':'exloom:l1-reviewer',
 'tool_input':{'command':'git worktree add /tmp/x HEAD'}}))" | bash "$GRS" 2>&1 | grep -c 'git show')" "1"

# A sed-based JSON read is not a parser: it stops at the first quote, so an
# escaped quote truncates the command and the rest escapes inspection. With no
# parser the decision is made on the raw payload instead, which errs towards
# refusing.
RAWF="$(sed -n '/^_raw_names_reviewer() {/,/^}/p' "$HOOKS_ABS/guard-reviewer-shell.sh"; \
        sed -n '/^_raw_adds_worktree() {/,/^}/p' "$HOOKS_ABS/guard-reviewer-shell.sh")"
raw() {   # raw <payload-json> -> refuse|allow
  bash -c 'set -u; HOOK_INPUT="$1"; '"$RAWF"'
    _raw_names_reviewer && _raw_adds_worktree && echo refuse || echo allow' _ "$1"
}
ESCAPED='{"hook_event_name":"PreToolUse","tool_name":"Bash","agent_type":"exloom:l1-reviewer","tool_input":{"command":"git -C \"a\\\"b\" worktree add /tmp/wt"}}'
ok "an escaped quote cannot hide a worktree add" "$(raw "$ESCAPED")" "refuse"
ok "a reviewer reading a diff is still allowed" \
   "$(raw '{"agent_type":"exloom:l1-reviewer","tool_input":{"command":"git diff a..b"}}')" "allow"
ok "a worktree add by the session is allowed" \
   "$(raw '{"tool_input":{"command":"git worktree add /tmp/x"}}')" "allow"
ok "the fixer is allowed" \
   "$(raw '{"agent_type":"exloom:fixer","tool_input":{"command":"git worktree add /tmp/x"}}')" "allow"
ok "a reviewer removing a worktree is allowed" \
   "$(raw '{"agent_type":"exloom:security-auditor","tool_input":{"command":"git worktree remove /tmp/x"}}')" "allow"


section "reviewers have no file-editing tools"

# Not "read-only": they keep Bash for git, and Bash can write. The honest claim
# is narrower — no editing TOOL — and the README must not overstate it.
for a in l1-reviewer adversarial-reviewer security-auditor spec-reviewer; do
  AF="$HOOKS_ABS/../agents/${a}.md"
  TOOLS="$(sed -n '/^---$/,/^---$/p' "$AF" | sed -n 's/^tools:[[:space:]]*//p' | head -1)"
  ok "$a declares its tools"            "$([[ -n "$TOOLS" ]] && echo yes || echo no)" "yes"
  ok "$a cannot Write"                  "$(printf '%s' "$TOOLS" | grep -cw 'Write')" "0"
  ok "$a cannot Edit"                   "$(printf '%s' "$TOOLS" | grep -cwE 'Edit|MultiEdit|NotebookEdit')" "0"
  ok "$a keeps Read"                    "$(printf '%s' "$TOOLS" | grep -cw 'Read')" "1"
  ok "$a keeps Bash for git"            "$(printf '%s' "$TOOLS" | grep -cw 'Bash')" "1"
done
ok "the fixer keeps its editing tools" \
   "$(sed -n '/^---$/,/^---$/p' "$HOOKS_ABS/../agents/fixer.md" | sed -n 's/^tools:[[:space:]]*//p' | head -1 | grep -cw 'Write')" "0"


section "the spec review is advice, and advice gates nothing"

# A spec reviewer that says NOT READY must change nothing a gate can read.
# Otherwise it is a blocking check wearing an advisory label, and the author
# finds that out at the push.
RRV="$HOOKS_ABS/record-reviewer-verdict.sh"
subrepo specadvice
SAB="$(git rev-parse --abbrev-ref HEAD)"
SACL=".claude/reviews/${SAB}.md"
mkdir -p "$(dirname "$SACL")"
printf '# review\n\n**Lane:** standard\n**Spec:** docs/s.md\n**Plan:** docs/p.md\n' > "$SACL"
mkdir -p docs; printf 'spec\n' > docs/s.md; printf 'plan\n' > docs/p.md
git add -A >/dev/null 2>&1; git commit -qm sa >/dev/null 2>&1

SABEFORE="$(exloom_next_step "$SAB")"
SAROUNDS="$(exloom_round_count "$SACL" HEAD 2>/dev/null || echo 0)"

python3 -c "
import json
print(json.dumps({'session_id':'s','hook_event_name':'SubagentStop',
 'agent_type':'exloom:spec-reviewer','agent_id':'aSPEC',
 'last_assistant_message':'VERDICT: NOT READY (2 items)\n\n## Blocking — cannot be built from as written\n- R3 — no acceptance criterion\n'}))" \
  | bash "$RRV" >/dev/null 2>&1

ok "a NOT READY spec review writes no receipt of its own" \
   "$(ls .claude/reviews/${SAB}.verdicts/spec-reviewer.json 2>/dev/null | wc -l | tr -d ' ')" "0"
ok "...and writes no receipt at all" \
   "$(ls -d .claude/reviews/${SAB}.verdicts 2>/dev/null | wc -l | tr -d ' ')" "0"
ok "...does not move the next step" \
   "$(exloom_next_step "$SAB")" "$SABEFORE"
ok "...and adds no review round" \
   "$(exloom_round_count "$SACL" HEAD 2>/dev/null || echo 0)" "$SAROUNDS"

# The same event from a real reviewer still records, so the test above is not
# passing because the hook simply ignored everything.
python3 -c "
import json
print(json.dumps({'session_id':'s','hook_event_name':'SubagentStop',
 'agent_type':'exloom:l1-reviewer','agent_id':'aL1',
 'last_assistant_message':'VERDICT: APPROVED\n\nROUND NEEDED AFTER FIX: NO\n'}))" \
  | bash "$RRV" >/dev/null 2>&1
ok "an L1 verdict at the same moment does record" \
   "$(grep -c '"verdict":"APPROVED"' .claude/reviews/${SAB}.verdicts/l1-reviewer.json 2>/dev/null)" "1"


section "a tool's scratch folder is not your uncommitted work"

# An untracked .playwright-mcp/ or .gradle/ stopped the branch with "commit your
# work first" on something nobody wants committed. Untracked only: once a path
# is tracked it is the repo's business, whatever it is named.
subrepo scratchdirs
SDCL=".claude/reviews/$(git rev-parse --abbrev-ref HEAD).md"
mkdir -p "$(dirname "$SDCL")"; printf '# review\n\n**Lane:** sprint\n' > "$SDCL"
git add -A >/dev/null 2>&1; git commit -qm cl >/dev/null 2>&1
for d in .playwright-mcp .superpowers node_modules .pytest_cache __pycache__ .ruff_cache .venv \
         dist build .gradle bin obj .dart_tool .angular target coverage; do
  mkdir -p "$d"; printf 'junk\n' > "$d/f"
done
ok "scratch alone does not make the tree dirty" "$(exloom_work_is_dirty && echo dirty || echo clean)" "clean"
ok "...and every one of them is named as skipped" \
   "$(exloom_scratch_skipped | grep -c .)" "16"
ok "...with the branch moving past commit-work" \
   "$(exloom_next_step "$(git rev-parse --abbrev-ref HEAD)" | grep -c '^commit-work$')" "0"

printf 'real\n' > src/real.go
ok "real work still makes it dirty"             "$(exloom_work_is_dirty && echo dirty || echo clean)" "dirty"
ok "...and routes to commit-work"               "$(exloom_next_step "$(git rev-parse --abbrev-ref HEAD)")" "commit-work"
rm -f src/real.go

# Tracked is tracked. A repo that commits its dist/ has decided dist/ matters.
git add -f dist/f >/dev/null 2>&1; git commit -qm dist >/dev/null 2>&1
printf 'changed\n' > dist/f
ok "a TRACKED scratch path still counts as work" "$(exloom_work_is_dirty && echo dirty || echo clean)" "dirty"
ok "...and is not reported as skipped"           "$(exloom_scratch_skipped | grep -c '^dist/$')" "0"


section "line endings survive a fix, and a CRLF install is reported"

# A fixer that rewrites a whole file can flip its line endings, turning a
# one-line fix into a whole-file diff that hides the fix from the reviewer.
FXR="$HOOKS_ABS/../agents/fixer.md"
ok "the fixer is told to preserve line endings" \
   "$(grep -ci 'line ending' "$FXR")" "$(grep -ci 'line ending' "$FXR")"
ok "...and is told so at all" \
   "$([[ "$(grep -ci 'line ending' "$FXR")" -ge 1 ]] && echo yes || echo no)" "yes"
ok "...naming CRLF explicitly" \
   "$([[ "$(grep -c 'CRLF' "$FXR")" -ge 1 ]] && echo yes || echo no)" "yes"

# exloom cannot fix a checkout it does not own, so setup reports it instead.
CRLFD="$(sed -n '/^exloom_hooks_are_crlf() {/,/^}/p' "$LIB_ABS")"
crlfck() { bash -c 'set -u; '"$CRLFD"'
  exloom_hooks_are_crlf "$1" && echo crlf || echo lf' _ "$1"; }
CL="$REG/eol-lf"; CC="$REG/eol-crlf"
rm -rf "$CL" "$CC"; mkdir -p "$CL/hooks" "$CC/hooks"
printf '#!/usr/bin/env bash\nset -u\n' > "$CL/hooks/lib.sh"
printf '#!/usr/bin/env bash\r\nset -u\r\n' > "$CC/hooks/lib.sh"
ok "an LF install is reported as LF"     "$(crlfck "$CL")" "lf"
ok "a CRLF install is reported as CRLF"  "$(crlfck "$CC")" "crlf"
ok "a missing install is not a CRLF one" "$(crlfck "$REG/absent")" "lf"

# The remedy must name both halves: the setting, and the reinstall.
SETUP="$HOOKS_ABS/../commands/exloom-setup.md"
ok "setup names core.autocrlf input" "$(grep -c 'core.autocrlf input' "$SETUP")" "1"
ok "...and says to reinstall"        "$([[ "$(grep -ci 'reinstall' "$SETUP")" -ge 1 ]] && echo yes || echo no)" "yes"

# Setup runs once; /exloom runs constantly. A developer who set exloom up before
# this existed would otherwise meet the CRLF failure as bare shell noise.
XLM="$HOOKS_ABS/../commands/exloom.md"
ok "/exloom checks the installed line endings too" \
   "$(grep -c 'exloom_hooks_are_crlf' "$XLM")" "1"
ok "...and names the remedy where the developer reads it" \
   "$(grep -c 'core.autocrlf input' "$XLM")" "1"
RDM="$HOOKS_ABS/../README.md"
ok "the README answers the error the developer will actually see" \
   "$(grep -c "command not found" "$RDM")" "1"
ok "...with the setting"   "$(grep -c 'core.autocrlf input' "$RDM")" "1"
ok "...and the reinstall"  "$([[ "$(grep -ci 'reinstall' "$RDM")" -ge 1 ]] && echo yes || echo no)" "yes"


section "a narrowed command that does not run must not block the push"

# The adapters build commands for toolchains this repo cannot run, so one of
# them being wrong for a particular project is a question of when. That must
# cost minutes, never a blocked push: a narrowed run that fails is retried with
# the pinned whole-suite command before anything is concluded.
PRVF="$(cd "$(dirname "$LIB_ABS")/../scripts" && pwd)/prove-change-is-tested.sh"
fbrepo() {
  local d="$REG/$1"; rm -rf "$d"; mkdir -p "$d/src" "$d/tests" "$d/.claude"; cd "$d" || return 1
  git init -q -b main . 2>/dev/null; git config user.email t@e.com; git config user.name t
  : > .claude/exloom-gate.enabled
  printf 'bash tests/t.sh\n' > .claude/exloom-test-command
  printf 'calc(){ echo 4; }\n' > src/l.sh
  printf '. ./src/l.sh\n[ "$(calc)" = "4" ]\n' > tests/t.sh
  git add -A >/dev/null 2>&1; git commit -qm b >/dev/null 2>&1
}

fbrepo fb-broken
printf './no-such-runner {tests}\n' > .claude/exloom-test-select
git add -A >/dev/null 2>&1; git commit -qm sel >/dev/null 2>&1
FBB="$(git rev-parse HEAD)"
printf 'calc(){ echo 5; }\n' > src/l.sh
printf '. ./src/l.sh\n[ "$(calc)" = "5" ]\n' > tests/t.sh
git add -A >/dev/null 2>&1; git commit -qm c >/dev/null 2>&1
bash "$PRVF" --base "$FBB" >/dev/null 2>&1; FBRC=$?
FBJ=".claude/reviews/main.verdicts/proof.json"
ok "a broken narrowed command still concludes"  "$FBRC" "0"
ok "...as PROVED, on the pinned suite"          "$(sed -n 's/.*"result":"\([A-Z_]*\)".*/\1/p' "$FBJ" | tail -1)" "PROVED"
ok "...and says it fell back"                   "$(sed -n 's/.*"selection_source":"\([a-z-]*\)".*/\1/p' "$FBJ" | tail -1)" "fallback"

# A base that genuinely fails is still void: the fallback rescues a bad command,
# not a broken repository.
fbrepo fb-reallyvoid
printf './no-such-runner {tests}\n' > .claude/exloom-test-select
printf '. ./missing/dep.sh\n' > tests/t.sh
git add -A >/dev/null 2>&1; git commit -qm sel >/dev/null 2>&1
FBV="$(git rev-parse HEAD)"
printf 'calc(){ echo 5; }\n' > src/l.sh
printf '. ./missing/dep.sh\n. ./src/l.sh\n[ "$(calc)" = "5" ]\n' > tests/t.sh
git add -A >/dev/null 2>&1; git commit -qm c >/dev/null 2>&1
ok "a genuinely broken base is still PROOF VOID" \
   "$(bash "$PRVF" --base "$FBV" >/dev/null 2>&1; echo $?)" "2"

section "re-find disposition: next-line keyword, and legacy checklists"

subrepo disp
LD=".claude/reviews/feat/plan.verdicts"; mkdir -p "$LD"
printf '{"round":1,"agent":"l1-reviewer","severity":"HIGH","scope":"IN-SCOPE","cite":"src/a.go:10","fingerprint":"HIGH|a.go|nullderef","head":"h","at":"t"}\n{"round":2,"agent":"l1-reviewer","severity":"HIGH","scope":"IN-SCOPE","cite":"src/a.go:20","fingerprint":"HIGH|a.go|nullderef","head":"h","at":"t"}\n' > "$LD/l1-reviewer.findings.jsonl"
DCHK=".claude/reviews/feat/plan.md"

printf '# checklist\n' > "$DCHK"
CHECKLIST_CONTENT="$(cat "$DCHK")" exloom_check_refinds "$DCHK" HEAD "test" 2>/dev/null
ok "undisposed re-find -> blocked" "$?" "2"

printf '# checklist\n\n## Re-finds\n- src/a.go:10\n  FIXED THE CLASS: property test over every branch.\n\n## Other\n' > "$DCHK"
CHECKLIST_CONTENT="$(cat "$DCHK")" exloom_check_refinds "$DCHK" HEAD "test" 2>/dev/null
ok "keyword on the NEXT line disposes it" "$?" "0"

printf '# legacy checklist\n\n## L1 code review\n- src/a.go:10 — fixed\n' > "$DCHK"
CHECKLIST_CONTENT="$(cat "$DCHK")" exloom_check_refinds "$DCHK" HEAD "test" 2>/dev/null
ok "legacy checklist (no ## Re-finds) still disposable" "$?" "0"

cd "$WORK" || exit 1

section "round-3 blockers: forgery, binding, writing ABOUT the guarded path"

# Matching command TEXT rather than command TARGETS denies anything that merely
# MENTIONS the guarded path — a commit message about the guard, a note written
# into a heredoc, this test file itself. Content and targets are different
# things, and only the target decides.
GVP=".claude/reviews/feat/x"
GV="${GVP}.verdicts/l1-reviewer.json"
jbash() { python3 -c "
import json,sys
print(json.dumps({'tool_name':'Bash','tool_input':{'command':sys.argv[1]}}))" "$1"; }

ok "a commit message naming the path -> allowed" \
   "$(deny "$(jbash "git commit -m 'fix the ${GV} guard'")")" "0"
ok "a heredoc body naming the path -> allowed" \
   "$(deny "$(jbash "cat > notes.md <<EOF
see ${GV}
EOF")")" "0"
ok "a redirect INTO the path -> still denied" \
   "$(deny "$(jbash "echo {} > ${GV}")")" "2"
ok "a quoted target -> still denied" \
   "$(deny "$(jbash "echo x | tee \"${GV}\"")")" "2"

section "a shell redirection is not a refspec"

# `git push origin 2>&1` must not parse as a push of a branch named `2>&1`. It
# would make the block message tell the author to run /review-init for a branch
# that does not exist — an argument-parsing slip that reads to them as a review
# failure.
pt() { exloom_push_target_branches "$1" | tr '\n' ' ' | sed 's/ $//'; }
ok "git push origin 2>&1 -> no refspec"          "$(pt 'git push origin 2>&1')" ""
ok "git push -u origin 2>&1 -> no refspec"       "$(pt 'git push -u origin 2>&1')" ""
ok "git push origin 1>&2 -> no refspec"          "$(pt 'git push origin 1>&2')" ""
ok "git push origin &>out.txt -> no refspec"     "$(pt 'git push origin &>out.txt')" ""
ok "git push origin >out 2>&1 -> no refspec"     "$(pt 'git push origin >out 2>&1')" ""
ok "git push origin main:feat/z 2>&1 -> main"    "$(pt 'git push origin main:feat/z 2>&1')" "main"
# And the forms that were already right must stay right.
ok "git push origin feat/z 2>&1 -> feat/z"       "$(pt 'git push origin feat/z 2>&1')" "feat/z"
ok "git push origin HEAD -> HEAD"                "$(pt 'git push origin HEAD')" "HEAD"
ok "git push origin other-branch -> other-branch" "$(pt 'git push origin other-branch')" "other-branch"

section "SubagentStop: the verdict is captured at COMPLETION"

# PostToolUse fires at launch and carries no report; SubagentStop fires on
# completion and carries it verbatim. Listening only to the first records every
# dispatch and no verdict, which makes a REJECTED review indistinguishable from
# an approval. The payload shape:
#   {"hook_event_name":"SubagentStop","agent_type":"exloom:l1-reviewer",
#    "agent_id":"...","last_assistant_message":"...VERDICT: REJECTED (1 items)..."}
subrepo substop
SSV=".claude/reviews/feat/plan.verdicts"
ssfeed() {   # ssfeed <report>
  python3 -c "
import json,sys
print(json.dumps({'session_id':'s','hook_event_name':'SubagentStop','agent_id':'a1',
 'agent_type':'exloom:l1-reviewer','last_assistant_message':sys.argv[1]}))" "$1" \
  | bash "$HOOKS_ABS/record-reviewer-verdict.sh" >/dev/null 2>&1
}
rm -rf .claude/reviews
ssfeed '## Critical
- src/one.go:4 — real defect

VERDICT: REJECTED (1 items)

ROUND NEEDED AFTER FIX: YES'
ok "completion records the real verdict" \
   "$(sed -n 's/.*"verdict":"\([A-Z]*\)".*/\1/p' "$SSV/l1-reviewer.json" 2>/dev/null | tail -1)" "REJECTED"
ok "...and round_needed from the same report" \
   "$(sed -n 's/.*"round_needed":"\([A-Z]*\)".*/\1/p' "$SSV/l1-reviewer.json" 2>/dev/null | tail -1)" "YES"
ok "...and the findings" \
   "$(grep -c . "$SSV/l1-reviewer.findings.jsonl" 2>/dev/null | head -1)" "1"

# The decisive case: a dispatch line and a completion line share a commit. If the
# verdict-less dispatch line counted as passing, it would let the REJECTED
# completion beside it through.
SSC=".claude/reviews/feat/plan.md"; printf '# c\n' > "$SSC"
rm -rf .claude/reviews; mkdir -p "$SSV"
printf '%s' '{"session_id":"s","hook_event_name":"PostToolUse","tool_name":"Agent","tool_input":{"subagent_type":"exloom:l1-reviewer"},"tool_response":{"isAsync":true,"status":"async_launched"}}' \
  | bash "$HOOKS_ABS/record-reviewer-verdict.sh" >/dev/null 2>&1
ssfeed 'VERDICT: REJECTED (1 items)'
printf '# c\n' > "$SSC"; git add -A >/dev/null 2>&1; git commit -qm r >/dev/null 2>&1
exloom_check_verdicts "$SSC" 1 HEAD "$(git rev-parse HEAD)" "test" >/dev/null 2>&1
ok "a verdict-less dispatch line does NOT grandfather a REJECTED away" "$?" "2"

# A receipt with no verdict anywhere is a launch, whatever wrote it. An exemption
# for older shapes would also admit reviews whose outcome was never captured.
rm -rf .claude/reviews; mkdir -p "$SSV"
printf '{"agent":"l1-reviewer","head":"%s","at":"n","session":"s"}\n' "$(git rev-parse HEAD)" > "$SSV/l1-reviewer.json"
git add -A >/dev/null 2>&1; git commit -qm legacy >/dev/null 2>&1
LOUT="$(exloom_check_verdicts "$SSC" 1 HEAD "$(git rev-parse HEAD)" "test" 2>&1)"; LRC=$?
ok "a pre-verdict receipt is no longer grandfathered" "$LRC" "2"
ok "...and the block names the fix, not just the refusal" \
   "$(printf '%s' "$LOUT" | grep -c 'without a name')" "1"

section "ASYNC dispatch: PostToolUse fires at LAUNCH, before any report exists"

# The payload of an async launch, verbatim. It carries no report at all, because
# the reviewer has not run yet.
#
# Recording that as UNKNOWN would block every async dispatch with no path
# forward. UNKNOWN must mean "the reviewer stated no verdict" — their omission,
# and blocking. It must not mean "no verdict was observable at this event", which
# is exloom's blindness. So the receipt records only what WAS observed: a
# launch.
subrepo asyncdisp
ADV=".claude/reviews/feat/plan.verdicts"
rm -rf .claude/reviews
printf '%s' '{"session_id":"s","cwd":"/x","hook_event_name":"PostToolUse","tool_name":"Agent","tool_input":{"description":"review","prompt":"review the diff","subagent_type":"exloom:l1-reviewer"},"tool_response":{"isAsync":true,"status":"async_launched","agentId":"a1","description":"review","resolvedModel":"claude-opus-5","outputFile":"/tmp/a1.output","canReadOutputFile":true},"tool_use_id":"t1","duration_ms":4}' \
  | bash "$HOOKS_ABS/record-reviewer-verdict.sh" >/dev/null 2>&1
ok "async launch -> a receipt is still written" \
   "$([[ -f "$ADV/l1-reviewer.json" ]] && echo yes || echo no)" "yes"
ok "async launch -> NO verdict key (not UNKNOWN)" \
   "$(grep -c '"verdict"' "$ADV/l1-reviewer.json" 2>/dev/null | head -1)" "0"
ok "async launch -> the dispatch commit is recorded" \
   "$(grep -c "$(git rev-parse HEAD)" "$ADV/l1-reviewer.json" 2>/dev/null | head -1)" "1"

ok "async launch -> the line is marked as a dispatch, not a conclusion" \
   "$(grep -c '"dispatch":true' "$ADV/l1-reviewer.json" 2>/dev/null | head -1)" "1"

# And the consequence that matters. A launch is not a review: if the reviewer's
# report never reaches exloom, this line is the only one on file, and letting it
# through means an unread review satisfies the gate. The common cause is a
# subagent given a NAME, which reports through the mailbox rather than the tool
# result, so no completion line is ever written and the launch stands alone.
ACL=".claude/reviews/feat/plan.md"; mkdir -p "$(dirname "$ACL")"
printf '# c\n' > "$ACL"; git add -A >/dev/null 2>&1; git commit -qm r >/dev/null 2>&1
ACL_OUT="$(exloom_check_verdicts "$ACL" 1 HEAD "$(git rev-parse HEAD)" "test" 2>&1)"; ACL_RC=$?
ok "...and a dispatch-only receipt BLOCKS - a launch is not a review" "$ACL_RC" "2"
ok "...and the block says the report never arrived" \
   "$(printf '%s' "$ACL_OUT" | grep -c 'never reached exloom' | head -1)" "1"
ok "...and it names the cause a session can act on" \
   "$(printf '%s' "$ACL_OUT" | grep -c 'without a name' | head -1)" "1"

# An older receipt carries no dispatch marker either, and is refused for the same
# reason: the marker says which version wrote the line, not whether a conclusion
# was recorded, and only the second question decides anything.
printf '{"agent":"l1-reviewer","subagent_type":"exloom:l1-reviewer","head":"%s","at":"2026-01-01T00:00:00Z","session":"s"}\n' \
  "$(git rev-parse HEAD)" > "$ADV/l1-reviewer.json"
git add -A >/dev/null 2>&1; git commit -qm pre >/dev/null 2>&1
exloom_check_verdicts "$ACL" 1 HEAD "$(git rev-parse HEAD)" "test" >/dev/null 2>&1
ok "...and an unmarked one is refused the same way" "$?" "2"

# The completion line lands after the launch line. The verdict wins; the marker
# on the earlier line must not poison it.
printf '{"agent":"l1-reviewer","subagent_type":"exloom:l1-reviewer","head":"%s","dispatch":true,"at":"2026-01-01T00:00:00Z","session":"s"}\n{"agent":"l1-reviewer","subagent_type":"exloom:l1-reviewer","head":"%s","verdict":"APPROVED","round_needed":"NO","at":"2026-01-01T00:01:00Z","session":"s"}\n' \
  "$(git rev-parse HEAD)" "$(git rev-parse HEAD)" > "$ADV/l1-reviewer.json"
git add -A >/dev/null 2>&1; git commit -qm done >/dev/null 2>&1
exloom_check_verdicts "$ACL" 1 HEAD "$(git rev-parse HEAD)" "test" >/dev/null 2>&1
ok "...and a completion after the launch clears it" "$?" "0"

# The direction that matters most: a launch line must never rescue a REJECTED one.
printf '{"agent":"l1-reviewer","subagent_type":"exloom:l1-reviewer","head":"%s","verdict":"REJECTED","round_needed":"YES","at":"2026-01-01T00:00:00Z","session":"s"}\n{"agent":"l1-reviewer","subagent_type":"exloom:l1-reviewer","head":"%s","dispatch":true,"at":"2026-01-01T00:01:00Z","session":"s"}\n' \
  "$(git rev-parse HEAD)" "$(git rev-parse HEAD)" > "$ADV/l1-reviewer.json"
git add -A >/dev/null 2>&1; git commit -qm rej >/dev/null 2>&1
exloom_check_verdicts "$ACL" 1 HEAD "$(git rev-parse HEAD)" "test" >/dev/null 2>&1
ok "...and a launch after a REJECTED does not rescue it" "$?" "2"

# A report that IS present but states no verdict is still UNKNOWN, still blocks.
rm -rf .claude/reviews
python3 -c "
import json
print(json.dumps({'tool_name':'Task','session_id':'s',
 'tool_input':{'subagent_type':'exloom:l1-reviewer','prompt':'review'},
 'tool_response':[{'type':'text','text':'I looked at it and it seems fine.'}]}))" \
 | bash "$HOOKS_ABS/record-reviewer-verdict.sh" >/dev/null 2>&1
ok "a real report with no VERDICT line -> still UNKNOWN" \
   "$(sed -n 's/.*"verdict":"\([A-Z]*\)".*/\1/p' "$ADV/l1-reviewer.json" 2>/dev/null | tail -1)" "UNKNOWN"

section "payload shape: the field the harness actually sends"

# The harness delivers a Task result as `tool_response`, a content-block array.
# A fixture feeding `tool_output` as a bare string tests a shape nothing emits,
# so every fixture here uses the real one. These two assert the parser still
# accepts both: the fallback chain is what makes it robust across harness
# versions, and losing it would otherwise be invisible.
subrepo shape; printf '# plan\n- src/one.go\n' > docs/plans/p.md
SVD=".claude/reviews/feat/plan.verdicts"   # subrepo() always checks out feat/plan
shape_verdict() {   # shape_verdict <json-payload>
  rm -rf .claude/reviews
  printf '%s' "$1" | bash "$HOOKS_ABS/record-reviewer-verdict.sh" >/dev/null 2>&1
  sed -n 's/.*"verdict":"\([A-Z]*\)".*/\1/p' "$SVD/l1-reviewer.json" 2>/dev/null | tail -1
}
ok "tool_response block array (what the harness sends) -> verdict read" \
   "$(shape_verdict '{"tool_name":"Task","session_id":"s","tool_input":{"subagent_type":"exloom:l1-reviewer"},"tool_response":[{"type":"text","text":"VERDICT: APPROVED"}]}')" \
   "APPROVED"
ok "tool_output bare string (older shape) -> still read" \
   "$(shape_verdict '{"tool_name":"Task","session_id":"s","tool_input":{"subagent_type":"exloom:l1-reviewer"},"tool_output":"VERDICT: APPROVED"}')" \
   "APPROVED"

section "CONTRACT: every shipped agent's own output block, through the real parser"

# The producer and the consumer are separate files, and nothing else checks that
# they agree. This drives EVERY agent's documented Output-format block through the
# real hook and asserts what comes out. The fixtures are generated FROM
# agents/*.md, so an agent whose format changes without the parser changing fails
# here rather than on somebody's branch.

AGENTS_DIR="$(cd "$(dirname "$LIB_ABS")/../agents" && pwd)"
subrepo contract
printf '# plan\n- src/one.go\n' > docs/plans/p.md
CVD=".claude/reviews/feat/plan.verdicts"

# Extract the first fenced block under "# Output format" in an agent file, then
# instantiate its placeholders into something a parser can actually read.
agent_block() {
  awk '/^# Output format/{f=1} f&&/^```/{c++; if(c==1){inb=1; next} if(c==2){exit}} inb' \
    "$AGENTS_DIR/$1.md" \
  | sed -e 's|<path>:<line>|src/one.go:42|g' \
        -e 's|<file:line[^>]*>|src/one.go:42|g' \
        -e 's|<[^>]*>|src/one.go:42|g'
}

feed() {  # feed <agent-name> <report-text>
  rm -rf .claude/reviews
  python3 -c "
import json,sys
print(json.dumps({'tool_name':'Task','session_id':'s',
 'tool_input':{'subagent_type':'exloom:'+sys.argv[1],'prompt':'review'},
 'tool_response':[{'type':'text','text':sys.argv[2]}]}))" "$1" "$2" | bash "$HOOKS_ABS/record-reviewer-verdict.sh" >/dev/null 2>&1
}
vrd() { sed -n 's/.*"verdict":"\([A-Z]*\)".*/\1/p' "$CVD/$1.json" 2>/dev/null | tail -1; }
fnd() { grep -c . "$CVD/$1.findings.jsonl" 2>/dev/null | head -1; }

# The fixer applies findings and the spec reviewer is advice: neither emits a
# gate verdict, so neither is held to the verdict contract.
for a in $(ls "$HOOKS_ABS/../agents"/*.md | xargs -n1 basename | sed "s/\.md$//" | grep -vE '^(fixer|spec-reviewer)$'); do
  blk="$(agent_block "$a")"
  ok "$a: has an extractable output block" "$([[ -n "$blk" ]] && echo yes || echo no)" "yes"

  # Its own APPROVED form must parse as APPROVED. An agent that emits the verdict
  # line its own file documents, and is scored UNKNOWN for it, is a gate that can
  # never open.
  feed "$a" "$(printf '%s\n\nVERDICT: APPROVED\n' "$blk")"
  ok "$a: own block + APPROVED -> APPROVED" "$(vrd "$a")" "APPROVED"

  # And with a cited finding present, at least one finding must be RECORDED. An
  # agent whose headings carry no severity word records zero, which leaves the
  # blocking re-find gate reading an empty ledger.
  feed "$a" "$(printf '%s\n\nVERDICT: REJECTED (1 items)\n' "$blk")"
  ok "$a: own block + a cite -> at least one finding recorded" \
     "$([[ "$(fnd "$a")" -ge 1 ]] && echo yes || echo no)" "yes"
done


# The spec reviewer sits outside the verdict contract on purpose. Assert the
# property that buys it: its own documented block cannot be read as a verdict,
# whichever way the report reaches the hook.
SRB="$(agent_block spec-reviewer)"
ok "spec-reviewer documents an output block"      "$([[ -n "$SRB" ]] && echo yes || echo no)" "yes"
ok "...which never says APPROVED or REJECTED"     "$(printf '%s' "$SRB" | grep -cE 'VERDICT:[[:space:]]*(APPROVED|REJECTED)')" "0"
feed spec-reviewer "$SRB"
ok "...and feeding it records no verdict"         "$(vrd spec-reviewer)" ""
feed spec-reviewer "$(printf '%s\n\nVERDICT: NOT READY (2 items)\n' "$SRB")"
ok "...nor does its real NOT READY verdict"       "$(vrd spec-reviewer)" ""
ok "...nor any findings file at all" \
   "$([[ -f "$CVD/spec-reviewer.findings.jsonl" ]] && echo yes || echo no)" "no"

# The verdict line each agent literally documents must not be self-defeating.
for a in $(ls "$HOOKS_ABS/../agents"/*.md | xargs -n1 basename | sed "s/\.md$//" | grep -vE '^(fixer|spec-reviewer)$'); do
  vline="$(grep -m1 '^VERDICT: APPROVED' "$AGENTS_DIR/$a.md" || true)"
  ok "$a: documented verdict line is unambiguous (no '|')" \
     "$(printf '%s' "$vline" | grep -c '|')" "0"
done

# Non-blocking must never count as blocking: it is the number that tells an author
# the loop can terminate.
feed adversarial-reviewer '## Blocking (cannot ship until fixed)
- src/one.go:42 — real problem

## Non-blocking (document in checklist, fix or defer)
- src/two.go:17 — cosmetic

VERDICT: REJECTED (1 items)'
ok "adversarial: '## Non-blocking' is not recorded as blocking severity" \
   "$(grep -c '"severity":"HIGH"' "$CVD/adversarial-reviewer.findings.jsonl" 2>/dev/null | head -1)" "1"

section "CONTRACT: every template placeholder is enforced, every alternation is written"

TPL="$(cd "$(dirname "$LIB_ABS")/../../../scripts/fixtures" && pwd)/legacy-review-checklist.md"
PRE="$(sed -n "s/^  placeholder_re='\(.*\)'$/\1/p" "$LIB_ABS")"
ok "placeholder_re extracted from lib.sh" "$([[ -n "$PRE" ]] && echo yes || echo no)" "yes"

# Every <...> token the template ships must be matched, or the section it guards
# is silently optional: the checklist looks complete and the gate never asked.
unmatched=0
while IFS= read -r tok; do
  [[ -n "$tok" ]] || continue
  # Intentional orphans, each for a stated reason:
  #   <branch-name>, <one sentence>, <N>  — substituted by /review-init, cosmetic
  #   <who-attests>                        — filled by /review-complete
  #   <file:line>                          — Re-finds LEGEND, which lives in an HTML
  #     comment above the heading precisely so it is outside the scanned section;
  #     enforcing it would block every branch that legitimately has no re-finds.
  case "$tok" in '<branch-name>'|'<one sentence>'|'<N>'|'<who-attests>'|'<file:line>') continue ;; esac
  printf '%s\n' "$tok" | grep -Eq "$PRE" || { unmatched=$((unmatched+1)); echo "    UNENFORCED: $tok" >&2; }
done < <(grep -oE '<[^>]+>' "$TPL" | sort -u)
ok "every template placeholder is enforced by placeholder_re" "$unmatched" "0"

# And the reverse: an alternation with no writer blocks on text nobody produces.
noWriter=0
for alt in 'expected-result' 'exact steps' 'reviewed-sha' 'ai-assisted' 'model-id' 'directed-by' 'base-sha' 'attested-date'; do
  grep -qF -- "$alt" "$TPL" || { noWriter=$((noWriter+1)); echo "    NO WRITER: $alt" >&2; }
done
ok "every checked alternation has a writer in the template" "$noWriter" "0"

# Paths named in block messages must exist where they are named.
BAD=0
while IFS= read -r ref; do
  [[ -n "$ref" ]] || continue
  [[ -f "$(dirname "$LIB_ABS")/../$ref" ]] || { BAD=$((BAD+1)); echo "    MISSING: $ref" >&2; }
done < <(grep -rhoE 'scripts/[a-z-]+\.sh' "$HOOKS_ABS"/*.sh | sort -u)
ok "every scripts/*.sh named in a hook exists in the plugin" "$BAD" "0"

cd "$WORK" || exit 1

section "prove-change-is-tested (author-side, before review)"

# The three shapes this check exists to catch before review starts: a decorative
# assertion, a write-path test with no read-path test, and a test task that
# reports UP-TO-DATE and never runs.

# A. A test that genuinely notices the change -> PROVED.
proofrepo good 'v=$(bash src/calc.sh); [ "$v" = "4" ]' 'echo 4'; B="$BASESHA"
printf 'echo 5\n' > src/calc.sh
printf 'v=$(bash src/calc.sh); [ "$v" = "5" ]\n' > tests/calc_test.sh
ok "a test that notices the change -> PROVED" "$(prove "$B")" "0"
ok "...and the PROVED receipt is actually written" "$(proofres)" "PROVED"

# B. An assertion too weak to notice anything — a check that the result is
#    non-empty, which is true before and after the change.
proofrepo weak 'v=$(bash src/calc.sh); [ -n "$v" ]' 'echo 4'; B="$BASESHA"
printf 'echo 5\n' > src/calc.sh
printf 'v=$(bash src/calc.sh); [ -n "$v" ]  # still only checks non-empty\n' > tests/calc_test.sh
ok "a decorative assertion -> NOT PROVED" "$(prove "$B")" "1"
ok "...and the receipt says NOT_PROVED, not nothing" "$(proofres)" "NOT_PROVED"

# C. Source changed, no test touched at all.
proofrepo notest 'v=$(bash src/calc.sh); [ "$v" = "4" ]' 'echo 4'; B="$BASESHA"
printf 'echo 5\n' > src/calc.sh
ok "source changed with no test, uncommitted -> commit first, no receipt" "$(prove "$B"; proofres)" "2"
git add -A >/dev/null 2>&1; git commit -qm five >/dev/null 2>&1
ok "source changed with no test and the suite fails -> NOT PROVED" "$(prove "$B")" "1"

# D. Docs-only changes have nothing to prove.
proofrepo docsonly 'v=$(bash src/calc.sh); [ "$v" = "4" ]' 'echo 4'; B="$BASESHA"
printf '# notes\n' > README.md
ok "docs-only change -> nothing to prove" "$(prove "$B")" "2"

# E. The working tree must be untouched — everything runs in a throwaway worktree.
cd "$REG/weak" || exit 1
BEFORE="$(git status --porcelain | sort)"
bash "$PROVE" --base "$(git rev-parse HEAD)" >/dev/null 2>&1
ok "working tree unchanged by the proof run" "$(git status --porcelain | sort)" "$BEFORE"
ok "no worktree left behind" "$(git worktree list | grep -c exloom-proof || true)" "0"

cd "$WORK" || exit 1

section "the loop-termination signal is recorded, not just emitted"

# Every agent emits `ROUND NEEDED AFTER FIX:` as a mandatory closing line. It is
# the signal that lets a loop terminate, so it has to be recorded rather than
# merely emitted — a write-only signal stops nothing.
subrepo roundsig
RSV=".claude/reviews/feat/plan.verdicts"
rn() {   # rn <report-text> -> the recorded round_needed
  rm -rf .claude/reviews
  python3 -c "
import json,sys
print(json.dumps({'tool_name':'Task','session_id':'s',
  'tool_input':{'subagent_type':'exloom:l1-reviewer','prompt':'review'},
  'tool_response':[{'type':'text','text':sys.argv[1]}]}))" "$1" \
    | bash "$HOOKS_ABS/record-reviewer-verdict.sh" >/dev/null 2>&1
  sed -n 's/.*"round_needed":"\([A-Z]*\)".*/\1/p' "$RSV/l1-reviewer.json" 2>/dev/null | tail -1
}
ok "reviewer says NO -> recorded NO (the loop may stop)" \
   "$(rn 'VERDICT: APPROVED

ROUND NEEDED AFTER FIX: NO')" "NO"
ok "reviewer says YES -> recorded YES" \
   "$(rn 'VERDICT: REJECTED (1 items)

ROUND NEEDED AFTER FIX: YES')" "YES"
ok "decorated form still read" \
   "$(rn 'VERDICT: APPROVED

**ROUND NEEDED AFTER FIX:** No')" "NO"
ok "no line at all -> UNKNOWN, never silently NO" \
   "$(rn 'VERDICT: APPROVED')" "UNKNOWN"

section "one dispatch leaves one receipt line, not eighteen"

# SubagentStop fires on EVERY turn a reviewer stops on, not only its last. A
# reviewer that reads eight files stops eight times, and the seven intermediate
# stops hand over a message with no VERDICT line — which scores UNKNOWN and gets
# appended verbatim, so one commit accumulates a long run of UNKNOWN lines around
# the single real verdict. The gate reads that correctly, taking the strongest
# verdict for the commit, so it is legibility rather than a wrong decision — but a
# file that is mostly noise cannot be read by a person, and a reader scanning it
# newest-first would invert the answer.
subrepo dedupe
DSV=".claude/reviews/feat/plan.verdicts"
# Unlike mint()/rn(), this deliberately does NOT clear the receipt first — the
# repetition is the thing under test.
stop() {   # stop <last_assistant_message>
  python3 -c "
import json,sys
print(json.dumps({'hook_event_name':'SubagentStop','session_id':'s',
  'agent_type':'exloom:l1-reviewer','last_assistant_message':sys.argv[1]}))" "$1" \
    | bash "$HOOKS_ABS/record-reviewer-verdict.sh" >/dev/null 2>&1
}
lines() { grep -c . "$DSV/l1-reviewer.json" 2>/dev/null || printf '0'; }

# Seven intermediate stops, then the real report — the field sequence exactly.
for _ in 1 2 3 4 5 6 7; do stop 'Let me read the next file.'; done
ok "seven intermediate stops -> ONE unknown line, not seven" "$(lines)" "1"
ok "...and it blocks, because no verdict was stated" \
   "$(sed -n 's/.*"verdict":"\([A-Z]*\)".*/\1/p' "$DSV/l1-reviewer.json" | tail -1)" "UNKNOWN"

stop 'No findings.

VERDICT: APPROVED

ROUND NEEDED AFTER FIX: NO'
ok "the real report still lands after the UNKNOWNs" "$(lines)" "2"
ok "...and it is the verdict a reader sees last" \
   "$(sed -n 's/.*"verdict":"\([A-Z]*\)".*/\1/p' "$DSV/l1-reviewer.json" | tail -1)" "APPROVED"

# A trailing intermediate stop must not append another UNKNOWN after a stated
# verdict — that is the ordering that would flip a newest-first reader.
stop 'Anything else?'
ok "a LATE intermediate stop adds nothing after a verdict" "$(lines)" "2"

# Repetition of the same conclusion is one fact.
stop 'VERDICT: APPROVED

ROUND NEEDED AFTER FIX: NO'
ok "the same conclusion twice -> still one line" "$(lines)" "2"

# But a changed conclusion is new information and must land.
stop 'VERDICT: APPROVED

ROUND NEEDED AFTER FIX: YES'
ok "a CHANGED round_needed is recorded, not swallowed" "$(lines)" "3"
stop '## Critical
- src/a.go:1 — found it on the second pass

VERDICT: REJECTED (1 items)

ROUND NEEDED AFTER FIX: YES'
ok "a rejection after an approval is recorded" "$(lines)" "4"

# A new commit is a new subject: the suppression is per-commit, never global.
printf 'moved\n' > src/a.go; git add -A >/dev/null 2>&1; git commit -qm move >/dev/null 2>&1
stop 'Let me start reading.'
ok "a new commit gets its own line" "$(lines)" "5"

cd "$WORK" || exit 1

section "lanes: rigour earned by stakes, not imposed by process"

# Tiers scale review DEPTH and are derived from the diff. They do not scale
# CEREMONY, and ceremony is what a small change cannot afford — a single strict
# lane means the same ten steps for a null check and for a subsystem.
subrepo lanes

ok "no marker -> standard, so nothing changes for an existing repo" "$(exloom_repo_lane)" "standard"
printf 'sprint\n' > .claude/exloom-lane
ok "an UNCOMMITTED lane file is ignored" "$(exloom_repo_lane)" "standard"
git add -A >/dev/null 2>&1; git commit -qm lane >/dev/null 2>&1
ok "...and honoured once committed" "$(exloom_repo_lane)" "sprint"
printf 'nonsense\n' > .claude/exloom-lane; git add -A >/dev/null 2>&1; git commit -qm junk >/dev/null 2>&1
ok "junk falls back to standard, never to the weakest lane" "$(exloom_repo_lane)" "standard"
git rm -q --cached .claude/exloom-lane >/dev/null 2>&1; rm -f .claude/exloom-lane
git add -A >/dev/null 2>&1; git commit -qm rmlane >/dev/null 2>&1

ok "checklist declares the lane" \
   "$(printf '**Tier:** 1\n**Lane:** sprint\n' | exloom_declared_lane)" "sprint"
ok "...case-insensitively" \
   "$(printf '**Lane:** Certified\n' | exloom_declared_lane)" "certified"
ok "no Lane line -> empty, so the repo default applies" \
   "$(printf '**Tier:** 1\n' | exloom_declared_lane)" ""
ok "an invented lane is not a lane" \
   "$(printf '**Lane:** yolo\n' | exloom_declared_lane)" ""

# Sprint caps the CEREMONY, never the tier of record — the tier describes the
# diff, and lying about it would corrupt every other check that reads it.
ok "sprint caps ceremony at tier 1"      "$(exloom_effective_tier 2 sprint)" "1"
ok "...and never RAISES a lower tier"    "$(exloom_effective_tier 0 sprint)" "0"
ok "standard leaves the tier alone"      "$(exloom_effective_tier 2 standard)" "2"
ok "certified leaves the tier alone"     "$(exloom_effective_tier 3 certified)" "3"

# The reviewer set follows the effective tier, so a Sprint branch on a 6-file diff
# asks for L1 instead of L1 + adversarial...
ok "tier 2 normally wants two reviewers" \
   "$(exloom_required_reviewers "$(exloom_effective_tier 2 standard)")" "l1-reviewer adversarial-reviewer"
ok "...and one on the Sprint lane" \
   "$(exloom_required_reviewers "$(exloom_effective_tier 2 sprint)")" "l1-reviewer"
# ...but a SAFETY check is not ceremony and no lane turns it off.
ok "the security surface still applies on Sprint" \
   "$(exloom_required_reviewers "$(exloom_effective_tier 2 sprint)" security)" "l1-reviewer security-auditor"

# Sprint is refused at Tier 3. The tier is derived from the diff, so a migration
# cannot be re-labelled a weekend spike — "earned by stakes" has to cut both ways
# or it is a bypass with a nicer name.
LCL=".claude/reviews/feat/plan.md"; mkdir -p "$(dirname "$LCL")"
lchk() { exloom_validate_checklist "$LCL" HEAD 1 "test" >/dev/null 2>&1; echo $?; }
lmsg() { exloom_validate_checklist "$LCL" HEAD 1 "test" 2>&1 >/dev/null; }
printf '**Tier:** 3\n**Lane:** sprint\n' > "$LCL"
ok "Sprint at Tier 3 -> blocked" "$(lchk)" "2"
ok "...and the message says why the lane is refused, not the tier" \
   "$(lmsg | grep -c 'There is no Sprint lane at Tier 3' | head -1)" "1"
printf '**Tier:** 2\n**Lane:** sprint\n' > "$LCL"
ok "Sprint at Tier 2 -> allowed past the lane check" \
   "$(lmsg | grep -c 'no Sprint lane at Tier 3' | head -1)" "0"

# Certified has no escape hatches, and that is checked BEFORE signed provenance —
# otherwise an author with a fixable content problem is shown an environment
# problem they may not be able to fix at all.
printf '**Tier:** 1\n**Lane:** certified\n\n## Escape hatches used\n- Skipped: smoke test — headless box\n' > "$LCL"
ok "an escape hatch on Certified -> blocked" "$(lchk)" "2"
ok "...naming the lane, not the missing signature" \
   "$(lmsg | grep -c 'Certified lane, which has no escape hatches' | head -1)" "1"
ok "...and quoting the skip it found" \
   "$(lmsg | grep -c 'smoke test — headless box' | head -1)" "1"
printf '**Tier:** 1\n**Lane:** certified\n\n## Escape hatches used\n- [x] None (default)\n' > "$LCL"
ok "no escape hatch on Certified -> past that check" \
   "$(lmsg | grep -c 'has no escape hatches' | head -1)" "0"
# A recorded round-cap answer is a decision the user made, not a step skipped.
printf '**Tier:** 1\n**Lane:** certified\n\n## Escape hatches used\n- User approved at round cap — minors only\n' > "$LCL"
ok "a round-cap answer is not an escape hatch on Certified" \
   "$(lmsg | grep -c 'has no escape hatches' | head -1)" "0"

# Standard is unchanged by all of this.
printf '**Tier:** 3\n**Lane:** standard\n\n## Escape hatches used\n- Skipped: smoke test — headless box\n' > "$LCL"
ok "Standard still accepts a documented skip at Tier 3" \
   "$(lmsg | grep -c 'has no escape hatches' | head -1)" "0"

cd "$WORK" || exit 1

section "a javadoc paragraph break is not a pointer dereference"

# A bare `*` line is how every javadoc block separates paragraphs. It strips to
# `*`, which does not match the `'* '*` continuation case (that needs a trailing
# space) and does hit the `'*'*` guard that exists so `*p = x` counts as code.
# Without a case for it, any javadoc edit containing a paragraph break scores
# behavioural — invalidating every reviewer receipt on the branch and mandating
# another round for a comment.
subrepo javadoc noorigin
cat > src/A.java <<'JAVA'
/**
 * A thing.
 */
class A { int x = 1; }
JAVA
git add -A >/dev/null 2>&1; git commit -qm base >/dev/null 2>&1
cat > src/A.java <<'JAVA'
/**
 * A thing.
 *
 * <p>And a second paragraph, which needs a bare star between them.
 */
class A { int x = 1; }
JAVA
git add -A >/dev/null 2>&1; git commit -qm doc >/dev/null 2>&1
ok "a javadoc paragraph break is inert" \
   "$(exloom_diff_is_behavioural HEAD~1 HEAD && echo behavioural || echo inert)" "inert"

# The guard it sits behind still has to work: a dereference is code.
printf 'int f(int *p){\n  return 1;\n}\n' > src/b.c
git add -A >/dev/null 2>&1; git commit -qm cbase >/dev/null 2>&1
printf 'int f(int *p){\n  *p = 3;\n  return 1;\n}\n' > src/b.c
git add -A >/dev/null 2>&1; git commit -qm deref >/dev/null 2>&1
ok "...and a pointer dereference is still code" \
   "$(exloom_diff_is_behavioural HEAD~1 HEAD && echo behavioural || echo inert)" "behavioural"

cd "$WORK" || exit 1

section "a receipt goes to the repo the REVIEW is about, not the session's cwd"

# A reviewer dispatched at a worktree completes while the session's cwd is
# elsewhere. Resolving the repo from cwd alone finds no gate marker there and
# exits in silence — no receipt, no findings, and a gate that reports "never
# dispatched" forever, which re-dispatching cannot clear because every dispatch
# writes to the wrong repo. exloom:isolating-execution recommends a worktree, so
# this path is well travelled.
subrepo receiptrepo noorigin
printf 'x\n' > src/a.java; git add -A >/dev/null 2>&1; git commit -qm base >/dev/null 2>&1
GATED="$PWD"

# A second repo with NO gate marker, standing in for the session's cwd.
mkdir -p "$REG/elsewhere" && cd "$REG/elsewhere"
git init -q -b main . >/dev/null 2>&1
git config user.email t@e.com; git config user.name t
printf 'y\n' > f.txt; git add -A >/dev/null 2>&1; git commit -qm x >/dev/null 2>&1

CITE="$GATED/src/a.java"
python3 -c "
import json, sys
msg = '## Critical\n- ' + sys.argv[1] + ':1 - a real defect\n\nVERDICT: REJECTED (1 items)\n\nROUND NEEDED AFTER FIX: YES'
print(json.dumps({'hook_event_name':'SubagentStop','session_id':'s',
                  'agent_type':'exloom:l1-reviewer','last_assistant_message':msg}))" "$CITE" \
  | bash "$HOOKS_ABS/record-reviewer-verdict.sh" >/dev/null 2>/dev/null

ok "the receipt lands in the gate-enabled repo the report cites" \
   "$([ -f "$GATED/.claude/reviews/feat/plan.verdicts/l1-reviewer.json" ] && echo found || echo missing)" "found"
ok "...carrying the verdict, not just a dispatch line" \
   "$(sed -n 's/.*"verdict":"\([A-Z]*\)".*/\1/p' "$GATED/.claude/reviews/feat/plan.verdicts/l1-reviewer.json" | tail -1)" "REJECTED"
ok "...and nothing was written into the session's own repo" \
   "$([ -d .claude/reviews ] && echo wrote || echo clean)" "clean"

# When no cited path lands in a gated repo, it must SAY SO. A silent exit makes
# the failure undiagnosable: the gate blocks and nothing anywhere explains why.
python3 -c "
import json
msg = '## Critical\n- nowhere/at/all.java:1 - a defect\n\nVERDICT: REJECTED (1 items)'
print(json.dumps({'hook_event_name':'SubagentStop','session_id':'s',
                  'agent_type':'exloom:l1-reviewer','last_assistant_message':msg}))" \
  | bash "$HOOKS_ABS/record-reviewer-verdict.sh" >/dev/null 2>"$REG/quiet.err"
ok "no gated repo anywhere -> says so on stderr, never silent" \
   "$(grep -c 'no receipt was written' "$REG/quiet.err")" "1"
ok "...and names what to do about it" \
   "$(grep -c 'never dispatched' "$REG/quiet.err")" "1"

cd "$WORK" || exit 1

section "the round a finding belongs to is derived, never read from a state file"

# The round has to come from the receipts themselves. Reading it from a state
# file nothing writes lands every finding in round 0, and two things then fail
# quietly: the severity trend collapses to one bucket, and the same defect found
# in three passes counts as three open criticals — so the cap reports "3 critical
# findings" beside a single cite.
subrepo rounds noorigin
printf 'x\n' > src/a.java; git add -A >/dev/null 2>&1; git commit -qm base >/dev/null 2>&1
git update-ref refs/remotes/origin/main HEAD
for i in 1 2 3; do
  printf 'r%s\n' "$i" > src/a.java; git commit -aqm "r$i" >/dev/null 2>&1
  python3 -c "
import json
msg = '## Critical\n- src/a.java:1 - the same defect every time\n\nVERDICT: REJECTED (1 items)'
print(json.dumps({'hook_event_name':'SubagentStop','agent_type':'exloom:l1-reviewer',
                  'session_id':'s','last_assistant_message':msg}))" \
    | bash "$HOOKS_ABS/record-reviewer-verdict.sh" >/dev/null 2>&1
done
git add -A >/dev/null 2>&1; git commit -qm receipts >/dev/null 2>&1
FJ=".claude/reviews/feat/plan.verdicts/l1-reviewer.findings.jsonl"
ok "each pass records its own round, not 0" \
   "$(sed -n 's/.*"round":\([0-9]*\).*/\1/p' "$FJ" | tr '\n' ' ' | sed 's/ *$//')" "1 2 3"
ok "the trend shows three passes, not one bucket" \
   "$(exloom_severity_trend ".claude/reviews/feat/plan.md" HEAD | grep -c '^round ')" "3"
# One defect reported three times is one thing still open.
ok "open criticals counts DEFECTS, not finding lines" \
   "$(exloom_open_criticals ".claude/reviews/feat/plan.md" HEAD)" "1"

cd "$WORK" || exit 1

section "the gate says where it stands at every completion, not only at the end"

# A session that hand-dispatches reviewers gets the same findings as the command,
# so the two feel equivalent, and nothing contradicts that until the push is
# refused. What the command adds — the tier derived from the diff, which receipts
# are missing, which sections are unfilled — is real work with no visible output
# at the moment it matters. So it is printed at that moment.
subrepo gatestatus noorigin
mkdir -p .claude/reviews/feat
printf 'a\n' > src/A.java; git add -A >/dev/null 2>&1; git commit -qm base >/dev/null 2>&1
git update-ref refs/remotes/origin/main HEAD
printf 'b\n' > src/A.java
printf 'class C {}\n' > src/Controller.java
git add -A >/dev/null 2>&1; git commit -qm fix >/dev/null 2>&1

status() {   # status <tier> <lane>
  printf '**Tier:** %s\n**Lane:** %s\n\n- Findings: none\n' "$1" "$2" > .claude/reviews/feat/plan.md
  printf 'x%s\n' "$RANDOM" >> src/A.java
  git add -A >/dev/null 2>&1; git commit -qm bump >/dev/null 2>&1
  python3 -c "
import json
print(json.dumps({'hook_event_name':'SubagentStop','session_id':'s','agent_type':'exloom:l1-reviewer',
 'last_assistant_message':'No findings.\n\nVERDICT: APPROVED\n\nROUND NEEDED AFTER FIX: NO'}))" \
    | bash "$HOOKS_ABS/record-reviewer-verdict.sh" 2>&1 >/dev/null
}

# An under-declared tier is the failure a session cannot see for itself: the
# checklist says Tier 0, the diff has grown, and nothing says so until the push.
ok "an under-declared tier is named at completion, not at push" \
   "$(status 1 standard | grep -c 'derives to 2')" "1"
ok "a required reviewer that never ran is named" \
   "$(status 2 standard | grep -c 'adversarial-reviewer  NOT DISPATCHED')" "1"
# ...and the lane is respected, so Sprint is not nagged about reviewers it does
# not need. A status that over-reports is one people learn to ignore.
ok "the Sprint lane is not told to run reviewers it does not require" \
   "$(status 2 sprint | grep -c 'NOT DISPATCHED')" "0"
# A SATISFIED gate is one line, not a block. Printing the same shape either way
# puts "your branch cannot ship" on the same channel and prefix as "receipt
# recorded", three times a round - which is how a status gets tuned out, and
# would rebuild the problem it was written to fix with more output.
ok "a satisfied gate is one line, not a block" \
   "$(status 2 sprint | grep -c 'gate satisfied')" "1"
ok "...and prints no ACTION NEEDED header" \
   "$(status 2 sprint | grep -c 'ACTION NEEDED')" "0"
ok "an actionable gate is clearly marked as such" \
   "$(status 2 standard | grep -c 'ACTION NEEDED')" "1"
ok "...and still names the lane and the cap" \
   "$(status 2 sprint | grep -c 'sprint lane')" "1"
ok "the status names the command that records it" \
   "$(status 1 standard | grep -c '/review-complete')" "1"
# Never blocks: this is information, and a hook that fails here would stop
# recording receipts, which is the one thing it exists to do.
ok "the status never changes the hook's exit code" \
   "$(status 1 standard >/dev/null 2>&1; echo $?)" "0"

cd "$WORK" || exit 1

section "reading a receipt is not writing one"

# Matching a bare `>` anywhere in the command denies two read-only forms:
#
#   ls -1 .claude/reviews/x.verdicts/ 2>/dev/null    a stderr redirect
#   ls .claude/reviews/<branch>.verdicts/            `<branch>` contains a >
#
# The second is the form /review-complete instructs verbatim, so the command
# would be telling people to run something the gate refuses. Over-blocking is
# what teaches people to reach for EXLOOM_REVIEW_SKIP, which costs more than the
# forgery it prevents.
subrepo pvreads noorigin
mkdir -p .claude/reviews/feat
printf 'x\n' > src/a.txt; git add -A >/dev/null 2>&1; git commit -qm base >/dev/null 2>&1
pv() {
  printf '{"hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":%s}}' \
    "$(python3 -c 'import json,sys;print(json.dumps(sys.argv[1]))' "$1")" \
    | bash "$HOOKS_ABS/protect-verdicts.sh" >/dev/null 2>&1
  echo $?
}
ok "a stderr redirect is not a write"        "$(pv 'ls -1 .claude/reviews/feat/x.verdicts/ 2>/dev/null')" "0"
ok "an unsubstituted <branch> is not a write" "$(pv 'ls .claude/reviews/<branch>.verdicts/')" "0"
ok "plain listing still reads"                "$(pv 'ls .claude/reviews/feat/x.verdicts/')" "0"
ok "cat with a discarded stderr still reads"  "$(pv 'cat .claude/reviews/feat/x.verdicts/l1-reviewer.json 2>/dev/null')" "0"
ok "staging a receipt still works"            "$(pv 'git add .claude/reviews/feat/x.verdicts')" "0"
# And every write form must still be denied - the point of the hook.
ok "truncating a receipt is denied"           "$(pv 'echo forged > .claude/reviews/feat/x.verdicts/l1-reviewer.json')" "2"
ok "appending to a receipt is denied"         "$(pv 'echo forged >> .claude/reviews/feat/x.verdicts/l1-reviewer.json')" "2"
ok "redirecting anything into one is denied"  "$(pv 'cat /dev/null > .claude/reviews/feat/x.verdicts/proof.json')" "2"
ok "tee into a receipt is denied"             "$(pv 'tee .claude/reviews/feat/x.verdicts/l1-reviewer.json < /tmp/f')" "2"
ok "removing a receipt is denied"             "$(pv 'rm .claude/reviews/feat/x.verdicts/l1-reviewer.json')" "2"
ok "destroying the reviews tree is denied"    "$(pv 'rm -rf .claude/reviews')" "2"
ok "touching the gate marker is denied"       "$(pv 'touch .claude/exloom-gate.enabled')" "2"

cd "$WORK" || exit 1

section "the fork point is the NEAREST branch, not the first one named"

# Taking the FIRST candidate that resolves — origin/main, else master, else dev —
# breaks in a repo that keeps main as a RELEASE branch and dev as the integration
# branch: the whole release gap lands in the diff, so every branch derives Tier 3
# off somebody else's migration, and Tier 3 has no escape hatch by design.
#
# `git symbolic-ref refs/remotes/origin/HEAD` does not rescue it: it names the
# branch a clone checks out, which is a different question from the branch work
# merges into.
subrepo forkpoint noorigin
printf 'r1\n' > src/a.txt; git add -A >/dev/null 2>&1; git commit -qm r1 >/dev/null 2>&1
git update-ref refs/remotes/origin/main HEAD          # a release branch, pinned here
for i in 2 3 4 5 6; do
  printf 'r%s\n' "$i" > "src/f$i.java"
  git add -A >/dev/null 2>&1; git commit -qm "dev$i" >/dev/null 2>&1
done
printf 'x\n' > src/migrations_placeholder.txt
mkdir -p db/migrations && printf 'create table t;\n' > db/migrations/001.sql
git add -A >/dev/null 2>&1; git commit -qm "someone elses migration" >/dev/null 2>&1
git update-ref refs/remotes/origin/dev HEAD           # integration branch, far ahead
printf 'class Mine {}\n' > src/Mine.java
git add -A >/dev/null 2>&1; git commit -qm mine >/dev/null 2>&1

ok "the nearest candidate wins, not the first named" \
   "$(exloom_fork_point HEAD)" "$(git rev-parse origin/dev)"
ok "...so the tier describes THIS change, not the release gap" "$(exloom_derive_tier HEAD)" "1"
# What the nearest-candidate rule prevents: with origin/main chosen, the diff
# carries somebody else's migration and the tier is 3 — unescapable, on a
# one-file change.
ok "...where the old rule would have derived 3 off the migration" \
   "$(git diff --name-only "$(git merge-base HEAD origin/main)" HEAD | grep -c 'db/migrations')" "1"
ok "...and the nearest-base diff does not contain it at all" \
   "$(git diff --name-only "$(exloom_fork_point HEAD)" HEAD | grep -c 'db/migrations' || true)" "0"

# A repo whose integration branch is not one of the guessed names. The candidate
# list cannot be made long enough to cover every convention, so a branch may
# record the one it actually forked from - in its own checklist, where a reviewer
# reads it, because a stated base changes what the gate sees.
subrepo forkrecorded noorigin
mkdir -p .claude/reviews/feat
printf 'r1\n' > src/a.txt; git add -A >/dev/null 2>&1; git commit -qm r1 >/dev/null 2>&1
FR_FORK="$(git rev-parse HEAD)"
mkdir -p db/migrations && printf 'create table t;\n' > db/migrations/001.sql
git add -A >/dev/null 2>&1; git commit -qm "someone elses migration" >/dev/null 2>&1
git update-ref refs/remotes/origin/main HEAD
git checkout -q -b dev-deploy "$FR_FORK"
printf 'i\n' > src/i.java; git add -A >/dev/null 2>&1; git commit -qm integ >/dev/null 2>&1
git update-ref refs/remotes/origin/dev-deploy HEAD
git checkout -q -b feat/rec
printf 'class Mine {}\n' > src/Mine.java
printf '**Tier:** 1\n' > .claude/reviews/feat/rec.md
git add -A >/dev/null 2>&1; git commit -qm mine >/dev/null 2>&1

unset _EXLOOM_FP _EXLOOM_FP_TIP
ok "an unguessable integration branch is missed, as before" \
   "$(exloom_fork_point HEAD)" "$FR_FORK"

printf '**Tier:** 1\n**Base branch:** origin/dev-deploy\n' > .claude/reviews/feat/rec.md
git add -A >/dev/null 2>&1; git commit -qm rec >/dev/null 2>&1
unset _EXLOOM_FP _EXLOOM_FP_TIP
ok "a recorded base branch is honoured" \
   "$(exloom_fork_point HEAD)" "$(git rev-parse origin/dev-deploy)"
# The point of honouring it: the foreign commit leaves the diff, so the tier
# stops citing a path this branch never touched.
ok "...so the diff no longer carries the other branch's migration" \
   "$(git diff --name-only "$(exloom_fork_point HEAD)" HEAD | grep -c 'db/migrations' || true)" "0"

# It has to be COMMITTED, like every other thing the gate reads. An uncommitted
# edit that silently changed the derived tier would defeat the reason it lives in
# the checklist rather than in a config file.
printf '**Tier:** 1\n**Base branch:** origin/main\n' > .claude/reviews/feat/rec.md
unset _EXLOOM_FP _EXLOOM_FP_TIP
ok "an uncommitted change to the field is not read" \
   "$(exloom_fork_point HEAD)" "$(git rev-parse origin/dev-deploy)"
git checkout -q -- .claude/reviews/feat/rec.md

# A name that resolves to nothing falls back to the built-in candidates, which
# derive from a FURTHER base and so a HIGHER tier. Safe direction for a typo.
printf '**Tier:** 1\n**Base branch:** origin/does-not-exist\n' > .claude/reviews/feat/rec.md
git add -A >/dev/null 2>&1; git commit -qm bogus >/dev/null 2>&1
unset _EXLOOM_FP _EXLOOM_FP_TIP
ok "an unresolvable recorded base falls back" "$(exloom_fork_point HEAD)" "$FR_FORK"
unset _EXLOOM_FP _EXLOOM_FP_TIP
ok "...and says so rather than failing silently" \
   "$(exloom_fork_point HEAD 2>&1 >/dev/null | grep -c 'not a ref here')" "1"

# The template ships `auto`, meaning "derive it". It is deliberately not a
# <placeholder>: leaving the base unstated is a valid end state, not a gap
# somebody must fill, so it must not read as an unfinished checklist.
printf '**Tier:** 1
**Base branch:** auto
' > .claude/reviews/feat/rec.md
git add -A >/dev/null 2>&1; git commit -qm shipped >/dev/null 2>&1
unset _EXLOOM_FP _EXLOOM_FP_TIP
ok "the shipped auto value derives as before" "$(exloom_fork_point HEAD)" "$FR_FORK"
# A leftover placeholder is ignored too, for a checklist written before the
# field existed and edited by hand afterwards.
printf '**Tier:** 1
**Base branch:** <origin/whatever>
' > .claude/reviews/feat/rec.md
git add -A >/dev/null 2>&1; git commit -qm ph >/dev/null 2>&1
unset _EXLOOM_FP _EXLOOM_FP_TIP
ok "a leftover placeholder is ignored" "$(exloom_fork_point HEAD)" "$FR_FORK"

cd "$WORK" || exit 1

# A repo where main IS the integration branch must be unaffected.
subrepo forkpoint_mainonly noorigin
printf 'a\n' > src/a.txt; git add -A >/dev/null 2>&1; git commit -qm base >/dev/null 2>&1
git update-ref refs/remotes/origin/main HEAD
printf 'b\n' > src/b.txt; git add -A >/dev/null 2>&1; git commit -qm mine >/dev/null 2>&1
ok "main-only repo: unchanged" "$(exloom_fork_point HEAD)" "$(git rev-parse origin/main)"
# A local `main` IS a legitimate candidate, so the no-candidate case needs a repo
# whose only branch is named something else entirely.
ok "no candidate branch at all -> fails rather than guessing a base" \
   "$(cd "$REG" && rm -rf nb && git init -q -b wip nb 2>/dev/null; cd "$REG/nb" && git config user.email t@e.com && git config user.name t && printf 'x\n' > f && git add -A >/dev/null 2>&1 && git commit -qm x >/dev/null 2>&1; exloom_fork_point HEAD >/dev/null 2>&1 && echo found || echo none)" "none"

cd "$WORK" || exit 1

section "criterion coverage is produced by the runner, never by a test's name"

# The criterion-to-test join, done without a per-framework adapter: the ref goes
# in the TEST NAME, and every runner that matters emits JUnit XML. One parser
# instead of one per framework.
#
# A name is hand-written, which is the hole a naive version leaves open: a test
# called "F-012/R-3/AC-2 — …" that asserts nothing still passes, and would report
# the criterion covered — the one number here an author could forge by typing.
# The proof run closes it at no extra cost: a test that passes against the BASE
# source does not notice the change, whatever its name says.
subrepo criteria noorigin
mkdir -p reports
cat > "$REG/criteria/mkreport.sh" <<'MK'
#!/usr/bin/env bash
# Stands in for a test runner. It must PASS at base with the base tests (run 1),
# and fail at base once the new test is staged (run 2) — so it keys off the test
# file's content, exactly as a real suite does.
mkdir -p test-results
new_test=0; grep -q exercises tests/t.txt 2>/dev/null && new_test=1
if [[ $new_test -eq 0 || -f src/feature.txt ]]; then
  cat > test-results/r.xml <<'X'
<testsuite name="s" tests="3">
  <testcase classname="T" name="F-012/R-3/AC-1 — notices the change"/>
  <testcase classname="T" name="F012_R3_AC2 underscore form also notices"/>
  <testcase classname="T" name="F-012/R-9/AC-1 — asserts nothing at all"/>
</testsuite>
X
  exit 0
fi
cat > test-results/r.xml <<'X'
<testsuite name="s" tests="3">
  <testcase classname="T" name="F-012/R-3/AC-1 — notices the change"><failure>no feature</failure></testcase>
  <testcase classname="T" name="F012_R3_AC2 underscore form also notices"><failure>no feature</failure></testcase>
  <testcase classname="T" name="F-012/R-9/AC-1 — asserts nothing at all"/>
</testsuite>
X
exit 1
MK
chmod +x "$REG/criteria/mkreport.sh"
printf 'bash mkreport.sh\n' > .claude/exloom-test-command
mkdir -p tests && printf 'placeholder\n' > tests/t.txt
git add -A >/dev/null 2>&1; git commit -qm base >/dev/null 2>&1
git update-ref refs/remotes/origin/main HEAD
printf 'the feature\n' > src/feature.txt
printf 'exercises it\n' > tests/t.txt
git add -A >/dev/null 2>&1; git commit -qm change >/dev/null 2>&1

PJ=".claude/reviews/feat/plan.verdicts/proof.json"
bash "$PROVE" >/dev/null 2>&1
crit="$(sed -n 's/.*"criteria":"\([^"]*\)".*/\1/p' "$PJ" 2>/dev/null | tail -1)"
ok "a criterion whose test fails at base and passes with the change is PROVED" \
   "$(printf '%s' "$crit" | grep -c 'F-012/R-3/AC-1' | head -1)" "1"
ok "...and the underscore form resolves to the same ref shape" \
   "$(printf '%s' "$crit" | grep -c 'F-012/R-3/AC-2' | head -1)" "1"
# The lie. This test passes either way, so its name is a claim the run refutes.
ok "a test that passes WITHOUT the change claims a criterion it does not cover" \
   "$(printf '%s' "$crit" | grep -c 'F-012/R-9/AC-1' | head -1)" "0"
ok "...and the run says so out loud, rather than dropping it silently" \
   "$(bash "$PROVE" 2>&1 | grep -c 'CLAIMED but not proved' | head -1)" "1"
ok "the receipt records a PROVED result alongside the criteria" \
   "$(sed -n 's/.*"result":"\([A-Z_]*\)".*/\1/p' "$PJ" | tail -1)" "PROVED"

git add -A >/dev/null 2>&1; git commit -qm receipt >/dev/null 2>&1
SPECF="$REG/criteria/F-012-orders.md"
printf 'R-3 · event\nAC-1 · unit\nAC-2 · unit\nAC-3 · unit\nR-9 · event\nAC-1 · unit\n' > "$SPECF"
ok "the spec lists its criteria in ref form" \
   "$(exloom_spec_criteria "$SPECF" | tr '\n' ' ')" "F-012/R-3/AC-1 F-012/R-3/AC-2 F-012/R-3/AC-3 F-012/R-9/AC-1 "
MX="$(exloom_criteria_matrix .claude/reviews/feat/plan.md HEAD "$SPECF")"
ok "matrix: a proved criterion names its test, failing without and passing with" \
   "$(printf '%s\n' "$MX" | grep -c '^| F-012/R-3/AC-1 | T.F-012/R-3/AC-1 — notices the change | yes | yes |$')" "1"
ok "matrix: a criterion whose test passes without the change says so" \
   "$(printf '%s\n' "$MX" | grep -c '^| F-012/R-9/AC-1 | .* | no | yes |$')" "1"
ok "matrix: a criterion with no test is open" \
   "$(printf '%s\n' "$MX" | grep -c '^| F-012/R-3/AC-3 | — | open |')" "1"

section "an additive change is provable by mutation, not by absence"

# The three-run proof is structurally unsatisfiable for a purely additive change:
# every test exercising a new API fails to COMPILE at base. Refusing to call that
# a proof is correct, but it leaves additive work unprovable — and "additive, no
# behaviour change without opt-in" is the shape of most new security controls.
# Mutation asks the same question without needing the code to be absent.
subrepo mutation noorigin
cat > "$REG/mutation/runner.sh" <<'MK'
#!/usr/bin/env bash
# A new API. Passes at base with the base tests; once the new test is staged it
# cannot resolve the symbol, which is a BUILD error rather than an assertion.
new_test=0; grep -q calls tests/t.txt 2>/dev/null && new_test=1
if [[ $new_test -eq 1 && ! -f src/newapi.txt ]]; then
  echo "error: cannot find symbol: newApi" >&2
  exit 1
fi
exit 0
MK
chmod +x "$REG/mutation/runner.sh"
printf 'bash runner.sh\n' > .claude/exloom-test-command
mkdir -p tests && printf 'placeholder\n' > tests/t.txt
git add -A >/dev/null 2>&1; git commit -qm base >/dev/null 2>&1
git update-ref refs/remotes/origin/main HEAD
printf 'brand new api\n' > src/newapi.txt
printf 'calls the new api\n' > tests/t.txt
git add -A >/dev/null 2>&1; git commit -qm add >/dev/null 2>&1

MJ=".claude/reviews/feat/plan.verdicts/proof.json"
out="$(bash "$PROVE" 2>&1)"
ok "with no mutation command -> NOT_APPLICABLE, not NOT_PROVED" \
   "$(sed -n 's/.*"result":"\([A-Z_]*\)".*/\1/p' "$MJ" | tail -1)" "NOT_APPLICABLE"
# The result is only half the record. Without the method a reader cannot tell the
# weakest of the three claims from the strongest.
ok "...and the receipt names the method that produced it" \
   "$(sed -n 's/.*"method":"\([a-z-]*\)".*/\1/p' "$MJ" | tail -1)" "not-applicable"
ok "...and the message names the additive case and the way out" \
   "$(printf '%s' "$out" | grep -c 'PURELY ADDITIVE' | head -1)" "1"

# The repo pins a mutation command. THE CONTRACT IS THE EXIT CODE: every tool has
# its own report format and its own threshold flag, so exloom does not parse and
# does not own the bar.
printf 'bash mutant.sh\n' > .claude/exloom-mutation-command
cat > mutant.sh <<'MK'
#!/usr/bin/env bash
[[ -f .mutants-survive ]] && { echo "2 mutants survived"; exit 1; }
echo "all mutants killed"; exit 0
MK
chmod +x mutant.sh
git add -A >/dev/null 2>&1; git commit -qm mut >/dev/null 2>&1
: > "$MJ"
bash "$PROVE" >/dev/null 2>&1
ok "a pinned mutation command proves an additive change" \
   "$(sed -n 's/.*"result":"\([A-Z_]*\)".*/\1/p' "$MJ" | tail -1)" "PROVED_BY_MUTATION"
# The gate reads receipts from the committed ref, so commit it first.
git add -A >/dev/null 2>&1; git commit -qm receipt >/dev/null 2>&1
ok "...and the gate accepts that result" \
   "$(exloom_check_proof ".claude/reviews/feat/plan.md" HEAD "$(git rev-parse HEAD)" "test" >/dev/null 2>&1; echo $?)" "0"

# An UNCOMMITTED mutation command is ignored, for the same reason the test
# command's hash is recorded: a proof that a file nobody reviewed can switch on
# is not a proof.
subrepo mutation_uncommitted noorigin
cat > runner.sh <<'MK'
#!/usr/bin/env bash
new_test=0; grep -q calls tests/t.txt 2>/dev/null && new_test=1
if [[ $new_test -eq 1 && ! -f src/newapi.txt ]]; then
  echo "error: cannot find symbol: newApi" >&2; exit 1
fi
exit 0
MK
chmod +x runner.sh
printf 'bash runner.sh\n' > .claude/exloom-test-command
mkdir -p tests && printf 'p\n' > tests/t.txt
git add -A >/dev/null 2>&1; git commit -qm base >/dev/null 2>&1
git update-ref refs/remotes/origin/main HEAD
printf 'new\n' > src/newapi.txt; printf 'calls\n' > tests/t.txt
git add -A >/dev/null 2>&1; git commit -qm add >/dev/null 2>&1
printf 'true\n' > .claude/exloom-mutation-command      # never committed
UJ=".claude/reviews/feat/plan.verdicts/proof.json"
bash "$PROVE" >/dev/null 2>&1
# An untracked mutation command is eval'd code that appears in no diff, so it is
# never honoured. What proves it was not honoured is the METHOD: had it run and
# exited 0 this would read PROVED_BY_MUTATION. Falling through to the additive
# case is the correct outcome, and asserting the method is what makes the
# security property observable rather than incidental.
ok "an uncommitted mutation command is ignored" \
   "$(sed -n 's/.*"result":"\([A-Z_]*\)".*/\1/p' "$UJ" | tail -1)" "NOT_APPLICABLE"
ok "...and it is not recorded as a mutation result" \
   "$(sed -n 's/.*"method":"\([a-z-]*\)".*/\1/p' "$UJ" | tail -1)" "not-applicable"

cd "$WORK" || exit 1

section "the spec linter: structural errors block, judgement calls warn"

# The line between ERROR and WARN is the whole design. Errors are structural and
# a machine cannot be wrong about them; warns are judgement and a machine
# probably is. A judgement call that blocks is how a linter gets switched off.
LINT="$(cd "$(dirname "$LIB_ABS")/../scripts" && pwd)/lint-spec.sh"
subrepo speclint
SPEC="s.md"
lint()  { bash "$LINT" "$SPEC" 2>&1; }
lintrc() { bash "$LINT" "$SPEC" >/dev/null 2>&1; echo $?; }

good() {   # a spec that should pass, with $1 spliced into the requirements
  cat > "$SPEC" <<EOF
---
ref: F-001
status: draft
---
# F-001 · thing
## Problem
It is broken.
## Chosen approach
Fix it.
## Rejected approaches
- Other thing — worse.
## Requirements
${1}
## Non-goals
Not doing the other thing.
EOF
}
REQ_OK='R-1 · event
WHEN a thing happens THE SYSTEM SHALL do the other thing.

  AC-1 · unit
  ```gherkin
  Given a thing
  When it happens
  Then the other thing is recorded
  ```'

good "$REQ_OK"
ok "a well-formed spec passes" "$(lintrc)" "0"
ok "...silently" "$(lint | grep -c ERROR | head -1)" "0"

# Gapless refs. An error rather than a warning: a ref is cited by plans, tests
# and checklists, so a gap is a broken link rather than a matter of taste.
good "$(printf '%s' "$REQ_OK" | sed 's/^R-1/R-2/')"
ok "a spec starting at R-2 -> error" "$(lintrc)" "1"
ok "...naming the expected ref" "$(lint | grep -c 'expected R-1, found R-2' | head -1)" "1"

good "${REQ_OK}

R-3 · event
WHEN another thing happens THE SYSTEM SHALL respond.

  AC-1 · unit
  \`\`\`gherkin
  Given x
  When y
  Then z
  \`\`\`"
ok "a gap between requirements -> error" "$(lint | grep -c 'expected R-2, found R-3' | head -1)" "1"

# Criteria are numbered WITHIN their requirement, so the counter resets.
good "${REQ_OK}

R-2 · event
WHEN another thing happens THE SYSTEM SHALL respond.

  AC-1 · unit
  \`\`\`gherkin
  Given x
  When y
  Then z
  \`\`\`"
ok "two requirements each with their own AC-1 -> fine" "$(lintrc)" "0"

# A requirement nothing can check is the one thing a spec may never contain.
good 'R-1 · event
WHEN a thing happens THE SYSTEM SHALL do the other thing.'
ok "a requirement with no criterion -> error" "$(lintrc)" "1"
ok "...saying it is unverifiable" "$(lint | grep -c 'has no acceptance criterion' | head -1)" "1"

good 'R-1 · event
WHEN a thing happens THE SYSTEM SHALL do the other thing.

  AC-1 · unit
  It should work.'
ok "a criterion with no When/Then body -> error" "$(lintrc)" "1"

good "$REQ_OK"
printf 'TODO: decide the rest\n' >> "$SPEC"
ok "a TODO anywhere -> error" "$(lintrc)" "1"

good "$REQ_OK"
python3 -c "
import io,sys
p=sys.argv[1]; s=io.open(p,encoding='utf-8',newline='').read()
io.open(p,'w',encoding='utf-8',newline='').write(s.replace('## Non-goals','## Nongoals'))" "$SPEC"
ok "a missing required section -> error" "$(lintrc)" "1"
ok "...naming which one" "$(lint | grep -c 'missing required section: Non-goals' | head -1)" "1"

# The negative space. A WARN, never an error: whether a spec that says "delete"
# is really about data loss is judgement, and a false block is how a check dies.
good 'R-1 · event
WHEN a refund is issued THE SYSTEM SHALL credit the original payment method.

  AC-1 · unit
  ```gherkin
  Given a paid order
  When a refund is issued
  Then the original method is credited
  ```'
ok "money with no 'unwanted' requirement -> warns" \
   "$(lint | grep -c 'most defects live in the negative space' | head -1)" "1"
ok "...and does NOT block" "$(lintrc)" "0"
good 'R-1 · unwanted
IF a refund exceeds the payment THEN THE SYSTEM SHALL reject it.

  AC-1 · unit
  ```gherkin
  Given a payment of 10
  When a refund of 11 is issued
  Then it is rejected
  ```'
ok "...and stops warning once the negative case is stated" \
   "$(lint | grep -c 'negative space' | head -1)" "0"

# Implementation detail in a requirement is a warn for the same reason.
good 'R-1 · event
WHEN a job is submitted THE SYSTEM SHALL store it in Postgres.

  AC-1 · unit
  ```gherkin
  Given a job
  When it is submitted
  Then it survives a restart
  ```'
ok "naming a database in a requirement -> warns" \
   "$(lint | grep -c 'names an implementation' | head -1)" "1"
ok "...and still passes" "$(lintrc)" "0"

# CRLF. Every anchored match in this script would silently miss without the
# normalisation, and Git Bash on Windows is where exloom actually runs.
good "$REQ_OK"
python3 -c "
import io,sys
p=sys.argv[1]; s=io.open(p,'rb').read().replace(b'\n',b'\r\n')
io.open(p,'wb').write(s)" "$SPEC"
ok "a CRLF spec lints identically" "$(lintrc)" "0"

cd "$WORK" || exit 1

section "the proof binds the COMMAND it proved, not just its own presence"

# The receipt records the hash of the pinned test command, and the gate compares
# it. Without that comparison a repo could prove with a real suite, then point
# .claude/exloom-test-command at `true`, and the receipt would stay valid.
# Asserting the key merely EXISTS tests text; comparing it tests behaviour.
proofrepo bindcmd 'v=$(bash src/calc.sh); [ "$v" = "4" ]' 'echo 4'; B="$BASESHA"
printf 'echo 5\n' > src/calc.sh
printf 'v=$(bash src/calc.sh); [ "$v" = "5" ]\n' > tests/calc_test.sh
git add -A >/dev/null 2>&1; git commit -qm change >/dev/null 2>&1
bash "$PROVE" --base "$B" >/dev/null 2>&1
git add -A >/dev/null 2>&1; git commit -qm receipt >/dev/null 2>&1
BC=".claude/reviews/feat/proof.md"
prf() { exloom_check_proof "$BC" HEAD "$(git rev-parse HEAD)" "test" >/dev/null 2>&1; echo $?; }
ok "proof covering the pinned command -> allowed" "$(prf)" "0"

printf 'true\n' > .claude/exloom-test-command
git add -A >/dev/null 2>&1; git commit -qm swap >/dev/null 2>&1
ok "test command swapped after the proof -> blocked" "$(prf)" "2"

section "security review is triggered by SURFACE, not only by tier"

# Dependency and deserialization changes derive to Tier 1 or 2, so requiring
# security-auditor by tier alone would never reach them — and the skill promises
# a security review for exactly those. The surface has to trigger it directly, or
# the documentation promises a review the code does not require.
subrepo secsurf
git update-ref refs/remotes/origin/main "$(git rev-parse main)" 2>/dev/null
SB="$(git rev-parse main)"
printf '{"dependencies":{"lodash":"4.17.20"}}\n' > package.json
git add -A >/dev/null 2>&1; git commit -qm dep >/dev/null 2>&1
ok "a bumped dependency -> security surface" \
   "$(exloom_security_surface "$SB" HEAD && echo yes || echo no)" "yes"
ok "...and security-auditor joins a Tier 1 reviewer list" \
   "$(exloom_required_reviewers 1 security)" "l1-reviewer security-auditor"

subrepo deser
git update-ref refs/remotes/origin/main "$(git rev-parse main)" 2>/dev/null
SB="$(git rev-parse main)"
printf 'import java.io.*;\nObjectInputStream in = new ObjectInputStream(s);\n' > src/D.java
git add -A >/dev/null 2>&1; git commit -qm deser >/dev/null 2>&1
ok "a deserialization entry point -> security surface" \
   "$(exloom_security_surface "$SB" HEAD && echo yes || echo no)" "yes"

subrepo plainsrc
git update-ref refs/remotes/origin/main "$(git rev-parse main)" 2>/dev/null
SB="$(git rev-parse main)"
printf 'package m\nfunc Add(a, b int) int { return a + b }\n' > src/add.go
git add -A >/dev/null 2>&1; git commit -qm plain >/dev/null 2>&1
ok "ordinary source -> NOT a security surface (no over-block)" \
   "$(exloom_security_surface "$SB" HEAD && echo yes || echo no)" "no"

cd "$WORK" || exit 1

section "test-vs-source classification: a production package named spec/"

# A production package can be named `spec`. If `*/spec/*` matched inside
# src/main, the proof would revert part of a production package and keep the
# rest: the tree would not compile, and the run would fail for a reason that has
# nothing to do with the tests.
ok "src/main spec package -> source" \
   "$(istest 'svc/src/main/java/com/example/orchestration/spec/TopicSpec.java')" "source"
ok "src/main anything -> source" \
   "$(istest 'mod/src/main/java/com/x/test/Helper.java')" "source"
ok "src/test -> test" \
   "$(istest 'svc/src/test/java/com/example/RootKeyShapeTest.java')" "test"
ok "ruby spec/ dir -> test" "$(istest 'spec/models/order_spec.rb')" "test"
ok "js .spec.ts -> test"     "$(istest 'src/order.spec.ts')" "test"
ok "go _test.go -> test"     "$(istest 'internal/order/order_test.go')" "test"
ok "plain source -> source"  "$(istest 'internal/order/order.go')" "source"
for p in scripts/test-all.sh test-gate.sh hooks/gate.bats lib/widgets/card_test.dart \
         src/MyApp.Tests/OrderTests.cs src/MyApp.UnitTests/Order.cs src/MyApp.IntegrationTests/Api.cs \
         src/MyApp.Test/Order.cs src/Orders/OrderServiceTest.cs; do
  ok "$p -> test" "$(istest "$p")" "test"
done
ok "a C# source file -> source" "$(istest 'src/MyApp/OrderService.cs')" "source"
printf 'checks/*.check\n' > .claude/exloom-test-patterns
ok "an uncommitted repo pattern is ignored" "$(istest 'checks/a.check')" "source"
git add .claude/exloom-test-patterns >/dev/null 2>&1; git commit -qm pat >/dev/null 2>&1
ok "a committed repo pattern extends the list" "$(istest 'checks/a.check')" "test"
git rm -q .claude/exloom-test-patterns; git commit -qm unpat >/dev/null 2>&1

section "the shipped template must not block a branch that filled it honestly"

# A placeholder example left in the document BODY blocks every branch: a
# developer who correctly used no escape hatch leaves the line alone, and the
# gate then points at a section they were right not to fill.
#
# The placeholder-coverage test above cannot catch that. It asks whether each
# token is RECOGNISED, not whether an honestly-completed checklist survives the
# scan — which is a different question, and this is where it is asked.
TPL="$HOOKS_ABS/../../../scripts/fixtures/legacy-review-checklist.md"
for tier in 0 1 2 3; do
  filled="$(sed -e 's/<[^>]*>/filled/g' \
                -e 's/- \[ \]/- [x]/g' "$TPL")"
  # Sections a tier drops are irrelevant; what matters is that NOTHING a tier
  # scans still reads as a placeholder once a person has filled it in.
  printf '%s\n' "$filled" | grep -qE '<(paste output|exact command|exact steps|expected-result|step name|one sentence why)' \
    && ok "tier $tier: filled template has no surviving placeholder" "dirty" "clean" \
    || ok "tier $tier: filled template has no surviving placeholder" "clean" "clean"
done
# The specific regression: the example must not sit in the document body.
ok "no placeholder example outside a comment in Escape hatches" \
   "$(awk '/^## Escape hatches used/,/^## Provenance/' "$TPL" | grep -v '^ *<!--' | grep -vE '^ ' | grep -c '<step name>' | head -1)" "0"

section "reviewers are decoupled: only L1 must cover the shipped commit"

# Requiring every reviewer to approve the SAME commit is what stops a loop
# converging: a fix cancels approvals from reviewers that were already satisfied,
# so N reviewers chase a target that moves every time one of them is answered.
subrepo decouple
DC=".claude/reviews/feat/plan.md"; mkdir -p "$(dirname "$DC")"
DCV="$(exloom_verdict_dir "$DC")"; mkdir -p "$DCV"
printf 'a\n' > src/one.go; git add -A >/dev/null 2>&1; git commit -qm one >/dev/null 2>&1
A="$(git rev-parse HEAD)"
printf '{"agent":"adversarial-reviewer","head":"%s","verdict":"APPROVED"}\n' "$A" > "$DCV/adversarial-reviewer.json"
printf '{"agent":"l1-reviewer","head":"%s","verdict":"APPROVED"}\n' "$A" > "$DCV/l1-reviewer.json"
git add -A >/dev/null 2>&1; git commit -qm receipts >/dev/null 2>&1
dchk() { exloom_check_verdicts "$DC" 2 HEAD "$(git rev-parse HEAD)" "test" >/dev/null 2>&1; echo $?; }
ok "both approved at the tip -> allowed" "$(dchk)" "0"

# Fix a finding. Under the old rule this cancelled BOTH approvals.
printf 'b\n' > src/one.go; git add -A >/dev/null 2>&1; git commit -qm fix >/dev/null 2>&1
B="$(git rev-parse HEAD)"
ok "after a fix, stale L1 -> still blocked" "$(dchk)" "2"
printf '{"agent":"l1-reviewer","head":"%s","verdict":"APPROVED"}\n' "$B" >> "$DCV/l1-reviewer.json"
git add -A >/dev/null 2>&1; git commit -qm l1again >/dev/null 2>&1
ok "re-running ONLY L1 unblocks it" "$(dchk)" "0"
ok "...and the adversarial receipt never had to be refreshed" \
   "$(grep -c "$A" "$DCV/adversarial-reviewer.json" | head -1)" "1"

# The gap decoupling creates is disclosed, never blocked on: a fact for whoever
# reads the PR. Silence would let a reviewer's week-old approval look current.
ok "a behind reviewer is reported, not blocked" \
   "$(exloom_check_verdicts "$DC" 2 HEAD "$(git rev-parse HEAD)" "test" 2>&1 >/dev/null | grep -c 'commit(s) have landed since' | head -1)" "1"
ok "...and it names the agent that is behind" \
   "$(exloom_check_verdicts "$DC" 2 HEAD "$(git rev-parse HEAD)" "test" 2>&1 >/dev/null | grep -c 'adversarial-reviewer approved' | head -1)" "1"
ok "...while L1, which covers the tip, is NOT reported behind" \
   "$(exloom_check_verdicts "$DC" 2 HEAD "$(git rev-parse HEAD)" "test" 2>&1 >/dev/null | grep -c 'l1-reviewer approved' | head -1)" "0"

section "the round cap: three rounds, then a person decides"

subrepo roundcap
RC=".claude/reviews/feat/plan.md"; mkdir -p "$(dirname "$RC")"
RCV="$(exloom_verdict_dir "$RC")"; mkdir -p "$RCV"
cp "$WORK/../$(basename "$WORK")/.claude/reviews/feat/x.md" "$RC" 2>/dev/null || printf '# checklist\n\n## Escape hatches used\n- [ ] None (default)\n' > "$RC"
rounds_at() {   # rounds_at <n> — n distinct reviewed commits, each REJECTED
  : > "$RCV/l1-reviewer.json"
  local i
  for i in $(seq 1 "$1"); do
    printf 'r%s\n' "$i" > src/one.go; git add -A >/dev/null 2>&1; git commit -qm "r$i" >/dev/null 2>&1
    printf '{"agent":"l1-reviewer","head":"%s","verdict":"REJECTED"}\n' "$(git rev-parse HEAD)" >> "$RCV/l1-reviewer.json"
  done
  git add -A >/dev/null 2>&1; git commit -qm receipts >/dev/null 2>&1
}
rchk() { exloom_check_verdicts "$RC" 1 HEAD "$(git rev-parse HEAD)" "test" >/dev/null 2>&1; echo $?; }

rounds_at 2
ok "round count is distinct reviewed commits" "$(exloom_round_count "$RC" HEAD)" "2"
# `grep -c .` prints 0 AND exits 1 on no match, so a `|| printf 0` fallback fires
# too and the answer becomes a two-line string. Every arithmetic test on it then
# fails with a syntax error, at every push before the first review.
ok "no receipts at all -> exactly one zero, not two" \
   "$(exloom_round_count ".claude/reviews/no-such-branch.md" HEAD)" "0"
ok "...and it survives an arithmetic test without erroring" \
   "$(r="$(exloom_round_count ".claude/reviews/no-such-branch.md" HEAD)"; if [[ "$r" -ge 3 ]] 2>/dev/null; then echo cap; else echo nocap; fi)" "nocap"
ok "under the cap -> ordinary block, not the cap" "$(rchk)" "2"
ok "...and the message is NOT the cap message" \
   "$(exloom_check_verdicts "$RC" 1 HEAD "$(git rev-parse HEAD)" "test" 2>&1 | grep -c 'Round cap reached' | head -1)" "0"

# Counting only the COMMITTED ref answers 0 whenever receipts are still on disk —
# which is most of the time, since nothing commits them until /review-complete
# says so. The cap then never fires, and it fails OPEN in the one mechanism whose
# only job is to notice accumulation.
printf 'uncommitted\n' > src/one.go; git add -A >/dev/null 2>&1; git commit -qm r3 >/dev/null 2>&1
printf '{"agent":"l1-reviewer","head":"%s","verdict":"APPROVED"}\n' "$(git rev-parse HEAD)" >> "$RCV/l1-reviewer.json"
ok "an UNCOMMITTED receipt still counts" "$(exloom_round_count "$RC" HEAD)" "3"
git add -A >/dev/null 2>&1; git commit -qm r3receipt >/dev/null 2>&1
ok "...and is not double-counted once committed" "$(exloom_round_count "$RC" HEAD)" "3"

# At the cap the gate BLOCKS and hands the session a question to put to the user.
#
# Printing an "ask" decision instead would render as approve/cancel on the push
# itself, and cancel there is a tool refusal rather than an answer: the push dies,
# the session has nothing to act on, and the person retypes what they wanted. A
# cap is a decision point, so it has to yield a DECISION — which means named
# options, which only AskUserQuestion can render, and that is a session tool
# rather than a hook capability.
rounds_at 3
ok "at the cap -> blocks (2), it does not prompt on the push" "$(rchk)" "2"
capmsg() { exloom_check_verdicts "$RC" 1 HEAD "$(git rev-parse HEAD)" "test" 2>&1 >/dev/null; }
ok "...and the report reaches the session" \
   "$(capmsg | grep -c 'Findings by pass' | head -1)" "1"
ok "...as an instruction to ask, naming the tool" \
   "$(capmsg | grep -c 'Use AskUserQuestion' | head -1)" "1"
ok "...with all three options" \
   "$(capmsg | grep -cE '^  - (Fix|Accept the open items|Show me the findings)' | head -1)" "3"
ok "...and nothing is printed to stdout (that would be a decision)" \
   "$(exloom_check_verdicts "$RC" 1 HEAD "$(git rev-parse HEAD)" "test" 2>/dev/null | wc -c | tr -d ' ')" "0"

# The recommendation comes from OPEN criticals, not from the round number — and
# the fix option names the DEFECTS. "2 open criticals" is a score; a cite is
# something a person can decide about.
RCH="$(sed -n 's/.*"head":"\([0-9a-f]*\)".*/\1/p' "$RCV/l1-reviewer.json" | tail -1)"
printf '{"round":3,"agent":"l1-reviewer","severity":"HIGH","scope":"IN-SCOPE","cite":"src/one.go:1","fingerprint":"c1","head":"%s","at":"n"}\n' \
  "$RCH" > "$RCV/l1-reviewer.findings.jsonl"
git add -A >/dev/null 2>&1; git commit -qm crit >/dev/null 2>&1
ok "an open critical -> recommend fixing, not another pass" \
   "$(capmsg | grep -c 'RECOMMENDATION: FIX, THEN RE-REVIEW' | head -1)" "1"
ok "...and the fix option names the cite, not a count" \
   "$(capmsg | grep -c 'Fix src/one.go:1, then re-review' | head -1)" "1"
ok "...and the cites come from exloom_open_critical_cites" \
   "$(exloom_open_critical_cites "$RC" HEAD)" "src/one.go:1"
printf '{"round":3,"agent":"l1-reviewer","severity":"LOW","scope":"IN-SCOPE","cite":"src/one.go:1","fingerprint":"m1","head":"%s","at":"n"}\n' \
  "$RCH" > "$RCV/l1-reviewer.findings.jsonl"
git add -A >/dev/null 2>&1; git commit -qm minor >/dev/null 2>&1
ok "only minors open -> recommend merge" \
   "$(capmsg | grep -c 'RECOMMENDATION: MERGE' | head -1)" "1"

# A PASS IS NOT A FIX. Re-reviewing a tip nobody changed returns the previous
# pass's findings and spends a round doing it. This is the mechanism behind
# "every feature gets bigger and never completes": the counter counted reviews,
# when the thing that has to happen between rounds is a fix.
ok "code moved between the last two passes -> not a no-op" \
   "$(exloom_last_pass_was_noop "$RC" HEAD && echo noop || echo moved)" "moved"
printf '// just a comment\n' >> src/one.go
git add -A >/dev/null 2>&1; git commit -qm 'comment only' >/dev/null 2>&1
printf '{"agent":"l1-reviewer","head":"%s","verdict":"REJECTED"}\n' "$(git rev-parse HEAD)" >> "$RCV/l1-reviewer.json"
git add -A >/dev/null 2>&1; git commit -qm rereview >/dev/null 2>&1
ok "a pass over unchanged code IS a no-op" \
   "$(exloom_last_pass_was_noop "$RC" HEAD && echo noop || echo moved)" "noop"
ok "...and the cap report says so, rather than counting it" \
   "$(capmsg | grep -c 'ran against the same code as the pass before it' | head -1)" "1"

# A recorded user answer stops the asking about ROUNDS, and only that. The last
# receipt here is REJECTED, and "we have reviewed enough times" is not an answer
# to "did anyone approve this".
printf '\n## Escape hatches used\n- User approved at round cap — approved after 3 passes\n' >> "$RC"
git add -A >/dev/null 2>&1; git commit -qm userok >/dev/null 2>&1
ok "the answer does not waive a REJECTED review with no rulings" "$(rchk)" "2"
ok "...and says which question it actually answered" \
   "$(capmsg | grep -c 'does not answer' | head -1)" "1"
REJ="$(sed -n 's/.*"head":"\([0-9a-f]*\)","verdict":"REJECTED".*/\1/p' "$RCV/l1-reviewer.json" | tail -1)"
printf '{"round":4,"agent":"l1-reviewer","severity":"MED","scope":"IN-SCOPE","cite":"src/one.go:1","fingerprint":"i9","head":"%s","at":"n"}\n' \
  "$REJ" >> "$RCV/l1-reviewer.findings.jsonl"
printf '\n## Rulings\n- src/one.go:1 — PARKED: the retry covers it\n' >> "$RC"
git add -A >/dev/null 2>&1; git commit -qm ruled >/dev/null 2>&1
ok "...but with a ruling on each open finding the gate passes" "$(rchk)" "0"
python3 -c "
import sys,re
p=sys.argv[1]; s=open(p,encoding='utf-8').read()
s=s.replace('\n## Rulings\n- src/one.go:1 — PARKED: the retry covers it\n','\n')
open(p,'w',encoding='utf-8',newline='').write(s)" "$RC"
git add -A >/dev/null 2>&1; git commit -qm unruled >/dev/null 2>&1

# With the reviewer satisfied, the same recorded answer ships the branch: the cap
# is a counter a person answers, and their answer stands.
printf '{"agent":"l1-reviewer","head":"%s","verdict":"APPROVED","round_needed":"NO"}\n' "$(git rev-parse HEAD)" >> "$RCV/l1-reviewer.json"
git add -A >/dev/null 2>&1; git commit -qm approved >/dev/null 2>&1
ok "the user's recorded answer -> no further prompt" "$(rchk)" "0"
python3 -c "
import sys,re
p=sys.argv[1]; s=open(p,encoding='utf-8').read()
s=re.sub(r'- User approved at round cap.*\n','',s)
open(p,'w',encoding='utf-8',newline='').write(s)" "$RC"
git add -A >/dev/null 2>&1; git commit -qm rmok >/dev/null 2>&1

# And the cap fires on the COUNT, even when every reviewer is satisfied.
: > "$RCV/l1-reviewer.json"
for i in 1 2 3 4; do
  printf 'ok%s\n' "$i" > src/one.go; git add -A >/dev/null 2>&1; git commit -qm "ok$i" >/dev/null 2>&1
  printf '{"agent":"l1-reviewer","head":"%s","verdict":"APPROVED"}\n' "$(git rev-parse HEAD)" >> "$RCV/l1-reviewer.json"
done
git add -A >/dev/null 2>&1; git commit -qm approved >/dev/null 2>&1
ok "4 rounds all APPROVED -> still asks (a counter only goes up)" "$(rchk)" "2"
ok "...and the report says every reviewer is satisfied" \
   "$(capmsg | grep -c 'every required reviewer is satisfied' | head -1)" "1"

section "the cap is configurable, but only from a COMMITTED file"

ok "default cap" "$(exloom_max_rounds)" "3"
printf '5\n' > .claude/exloom-max-rounds
ok "uncommitted config is ignored" "$(exloom_max_rounds)" "3"
git add -A >/dev/null 2>&1; git commit -qm cap >/dev/null 2>&1
ok "committed config is honoured" "$(exloom_max_rounds)" "5"

section "a pipeline that records nothing is not a clean branch"

# When receipt capture degrades, every line records a launch and no conclusion,
# and every mechanism downstream reads blank and renders blank as fine: the cap
# report says no findings exist and every reviewer is satisfied. A person then
# answers the cap question against that.
subrepo blindpipe
BCL=".claude/reviews/feat/plan.md"; BVD=".claude/reviews/feat/plan.verdicts"
mkdir -p "$BVD"; printf '**Tier:** 1\n' > "$BCL"
printf 'x\n' >> src/base.txt; git add -A >/dev/null 2>&1; git commit -qm c1 >/dev/null 2>&1
for i in 1 2 3 4; do
  printf 'l%s\n' "$i" >> src/base.txt
  git add -A >/dev/null 2>&1; git commit -qm "c$i" >/dev/null 2>&1
  printf '{"agent":"l1-reviewer","subagent_type":"exloom:l1-reviewer","head":"%s","at":"2026-01-0%sT00:00:00Z","session":"s"}\n' \
    "$(git rev-parse HEAD)" "$i" >> "$BVD/l1-reviewer.json"
done
git add -A >/dev/null 2>&1; git commit -qm receipts >/dev/null 2>&1

ok "blindness is detected"            "$(exloom_evidence_blind "$BCL" HEAD)" "4"
ok "...and the note says what to do"  "$(exloom_evidence_blind_note "$BCL" HEAD | grep -c 'without a name')" "1"

# An exemption for verdict-less receipts is meant to protect reviews that really
# happened under an older version. It cannot distinguish those from reviews whose
# outcome was never captured, so it is widest exactly where the evidence is
# weakest.
BOUT="$(exloom_check_verdicts "$BCL" 1 HEAD "$(git rev-parse HEAD)" "push" 2>&1)"; BRC=$?
ok "a branch with no verdict anywhere does NOT ship" "$BRC" "2"
ok "...and is reported as launched, not approved" \
   "$(printf '%s' "$BOUT" | grep -c 'never reached exloom')" "1"
ok "...with the pipeline warning attached" \
   "$(printf '%s' "$BOUT" | grep -c 'EVIDENCE PIPELINE IS NOT RECORDING')" "1"

# One real verdict is enough to clear the blindness warning: the pipeline is
# demonstrably recording, and the remaining verdict-less lines are launches
# rather than an absence of evidence about the branch as a whole.
printf '{"agent":"l1-reviewer","subagent_type":"exloom:l1-reviewer","head":"%s","verdict":"APPROVED","round_needed":"NO","at":"2026-01-09T00:00:00Z","session":"s"}\n' \
  "$(git rev-parse HEAD)" >> "$BVD/l1-reviewer.json"
git add -A >/dev/null 2>&1; git commit -qm real >/dev/null 2>&1
ok "one real verdict clears the blindness" \
   "$(exloom_evidence_blind "$BCL" HEAD >/dev/null 2>&1 && echo blind || echo ok)" "ok"

section "the cap override answers the round question, and only that"

# Checked below the receipt evaluation, not above it. Returning early would let a
# recorded 'merge as-is' waive the requirement that reviewers ran at all — which
# is a different question, and one the person was never asked.
subrepo capscope
CCL=".claude/reviews/feat/plan.md"; CVD=".claude/reviews/feat/plan.verdicts"
mkdir -p "$CVD"
printf '**Tier:** 1\n\n## Escape hatches used\n- User approved at round cap — the open items are acceptable\n' > "$CCL"
for i in 1 2 3 4; do
  printf 'c%s\n' "$i" >> src/base.txt
  git add -A >/dev/null 2>&1; git commit -qm "c$i" >/dev/null 2>&1
  printf '{"agent":"l1-reviewer","subagent_type":"exloom:l1-reviewer","head":"%s","dispatch":true,"at":"2026-01-0%sT00:00:00Z","session":"s"}\n' \
    "$(git rev-parse HEAD)" "$i" >> "$CVD/l1-reviewer.json"
done
git add -A >/dev/null 2>&1; git commit -qm r >/dev/null 2>&1
COUT="$(exloom_check_verdicts "$CCL" 1 HEAD "$(git rev-parse HEAD)" "push" 2>&1)"; CRC=$?
ok "a cap decision does not waive a missing review" "$CRC" "2"
ok "...and says which question it actually answered" \
   "$(printf '%s' "$COUT" | grep -c 'does not answer')" "1"

# With the reviewers genuinely satisfied, the same decision ships the branch —
# the cap is a counter a person answers, and their answer stands.
printf '{"agent":"l1-reviewer","subagent_type":"exloom:l1-reviewer","head":"%s","verdict":"APPROVED","round_needed":"NO","at":"2026-01-09T00:00:00Z","session":"s"}\n' \
  "$(git rev-parse HEAD)" >> "$CVD/l1-reviewer.json"
git add -A >/dev/null 2>&1; git commit -qm ok >/dev/null 2>&1
exloom_check_verdicts "$CCL" 1 HEAD "$(git rev-parse HEAD)" "push" >/dev/null 2>&1
ok "...but ships once the reviewers are real" "$?" "0"

section "the status line stops driving the loop at the cap"

# exloom_gate_status runs after every reviewer completes, and a fix commit always
# leaves the L1 receipt behind the tip — so an unconditional "covers an earlier
# commit - re-run it" asks for another round on every pass, indefinitely. That
# makes the status a motor for the loop the cap exists to stop.
subrepo capstatus
SCL=".claude/reviews/feat/plan.md"; SVD=".claude/reviews/feat/plan.verdicts"
mkdir -p "$SVD"; printf '**Tier:** 1\n' > "$SCL"
for i in 1 2 3 4; do
  printf 's%s\n' "$i" >> src/base.txt
  git add -A >/dev/null 2>&1; git commit -qm "s$i" >/dev/null 2>&1
  printf '{"agent":"l1-reviewer","subagent_type":"exloom:l1-reviewer","head":"%s","verdict":"APPROVED","round_needed":"YES","at":"2026-01-0%sT00:00:00Z","session":"s"}\n' \
    "$(git rev-parse HEAD)" "$i" >> "$SVD/l1-reviewer.json"
done
git add -A >/dev/null 2>&1; git commit -qm r >/dev/null 2>&1
SOUT="$(exloom_gate_status "feat/plan" "$(git rev-parse HEAD)" 2>&1)"
ok "past the cap the status says STOP"        "$(printf '%s' "$SOUT" | grep -c 'STOP -')" "1"
ok "...and does not ask for another reviewer" "$(printf '%s' "$SOUT" | grep -c 're-run it')" "0"
ok "...naming the pass count and the cap"     "$(printf '%s' "$SOUT" | grep -c '4 review passes (cap 3)')" "1"
ok "...and hands over the three options"      "$(printf '%s' "$SOUT" | grep -c 'Accept the open items')" "1"

# A REJECTED receipt at the cap is the one case where "do not dispatch" deadlocks
# the gate against itself. A rejection has no escape hatch, the push gate says to
# clear it, and clearing it needs the dispatch this message used to forbid - so
# the only way out was a person overriding what the gate itself demanded.
#
# Stale is deliberately NOT in this set: a fix commit always leaves the L1 receipt
# behind the tip, so treating that as clearable rebuilds the endless loop the cap
# exists to stop. The test above pins that half; this one pins the other.
subrepo capreject
RCL=".claude/reviews/feat/plan.md"; RVD=".claude/reviews/feat/plan.verdicts"
mkdir -p "$RVD"; printf '**Tier:** 1
' > "$RCL"
for i in 1 2 3 4; do
  printf 'j%s
' "$i" >> src/base.txt
  git add -A >/dev/null 2>&1; git commit -qm "j$i" >/dev/null 2>&1
  printf '{"agent":"l1-reviewer","subagent_type":"exloom:l1-reviewer","head":"%s","verdict":"REJECTED","round_needed":"YES","at":"2026-01-0%sT00:00:00Z","session":"s"}
'     "$(git rev-parse HEAD)" "$i" >> "$RVD/l1-reviewer.json"
done
git add -A >/dev/null 2>&1; git commit -qm r >/dev/null 2>&1
ROUT="$(exloom_gate_status "feat/plan" "$(git rev-parse HEAD)" 2>&1)"
ok "a rejected receipt at the cap is still clearable"    "$(printf '%s' "$ROUT" | grep -c 'not another round')" "1"
ok "...and does not forbid the dispatch that clears it"    "$(printf '%s' "$ROUT" | grep -c 'Do not dispatch another reviewer')" "0"
ok "...while still naming the cap it is at"    "$(printf '%s' "$ROUT" | grep -c 'at the round cap')" "1"

# The same shape for a receipt that recorded a launch and never a verdict - the
# named-subagent case. It never reported, so it has not had its round.
subrepo caplaunch
NCL=".claude/reviews/feat/plan.md"; NVD=".claude/reviews/feat/plan.verdicts"
mkdir -p "$NVD"; printf '**Tier:** 1
' > "$NCL"
for i in 1 2 3 4; do
  printf 'n%s
' "$i" >> src/base.txt
  git add -A >/dev/null 2>&1; git commit -qm "n$i" >/dev/null 2>&1
  printf '{"agent":"l1-reviewer","subagent_type":"exloom:l1-reviewer","head":"%s","dispatch":true,"at":"2026-01-0%sT00:00:00Z","session":"s"}
'     "$(git rev-parse HEAD)" "$i" >> "$NVD/l1-reviewer.json"
done
git add -A >/dev/null 2>&1; git commit -qm r >/dev/null 2>&1
NOUT="$(exloom_gate_status "feat/plan" "$(git rev-parse HEAD)" 2>&1)"
ok "a launch-only receipt at the cap is clearable too"    "$(printf '%s' "$NOUT" | grep -c 'not another round')" "1"

# Under the cap it must still do its ordinary job, or the fix would just be a
# mute button.
subrepo undercap
UCL=".claude/reviews/feat/plan.md"; UVD=".claude/reviews/feat/plan.verdicts"
mkdir -p "$UVD"; printf '**Tier:** 1\n' > "$UCL"
printf 'u1\n' >> src/base.txt; git add -A >/dev/null 2>&1; git commit -qm u1 >/dev/null 2>&1
printf '{"agent":"l1-reviewer","subagent_type":"exloom:l1-reviewer","head":"%s","verdict":"APPROVED","round_needed":"NO","at":"2026-01-01T00:00:00Z","session":"s"}\n' \
  "$(git rev-parse HEAD)" > "$UVD/l1-reviewer.json"
printf 'u2\n' >> src/base.txt; git add -A >/dev/null 2>&1; git commit -qm u2 >/dev/null 2>&1
UOUT="$(exloom_gate_status "feat/plan" "$(git rev-parse HEAD)" 2>&1)"
ok "under the cap it still reports a stale receipt" \
   "$(printf '%s' "$UOUT" | grep -c 'covers an earlier commit')" "1"
ok "...and does not say STOP" "$(printf '%s' "$UOUT" | grep -c 'STOP -')" "0"

section "rulings close a REJECTED review, one finding at a time"

subrepo rulings
RUC=".claude/reviews/feat/plan.md"; RUV=".claude/reviews/feat/plan.verdicts"; mkdir -p "$RUV"
printf '# checklist\n\n## Rulings\n' > "$RUC"
printf 'r1\n' > src/one.go; git add -A >/dev/null 2>&1; git commit -qm r1 >/dev/null 2>&1
RUH="$(git rev-parse HEAD)"
printf '{"agent":"l1-reviewer","head":"%s","verdict":"REJECTED","round_needed":"YES"}\n' "$RUH" > "$RUV/l1-reviewer.json"
{ printf '{"round":1,"agent":"l1-reviewer","severity":"HIGH","scope":"IN-SCOPE","cite":"src/one.go:1","fingerprint":"c1","head":"%s","at":"n"}\n' "$RUH"
  printf '{"round":1,"agent":"l1-reviewer","severity":"MED","scope":"IN-SCOPE","cite":"src/one.go:2","fingerprint":"i1","head":"%s","at":"n"}\n' "$RUH"
  printf '{"round":1,"agent":"l1-reviewer","severity":"MED","scope":"PRE-EXISTING","cite":"src/old.go:9","fingerprint":"p1","head":"%s","at":"n"}\n' "$RUH"
} > "$RUV/l1-reviewer.findings.jsonl"
git add -A >/dev/null 2>&1; git commit -qm receipts >/dev/null 2>&1
ruchk() { exloom_check_verdicts "$RUC" "${1:-1}" HEAD "$(git rev-parse HEAD)" "test" "${2:-standard}" >/dev/null 2>&1; echo $?; }
rule() { printf '%s\n' "$1" >> "$RUC"; git add -A >/dev/null 2>&1; git commit -qm rule >/dev/null 2>&1; }
unrule() { python3 -c "
import sys
p=sys.argv[1]; s=open(p,encoding='utf-8').read()
open(p,'w',encoding='utf-8',newline='').write(s.split('## Rulings\n')[0]+'## Rulings\n')" "$RUC"
  git add -A >/dev/null 2>&1; git commit -qm unrule >/dev/null 2>&1; }

ok "no rulings -> REJECTED blocks" "$(ruchk)" "2"
ok "...and the block names each unruled cite" \
   "$(exloom_check_verdicts "$RUC" 1 HEAD "$(git rev-parse HEAD)" test 2>&1 | grep -cE 'src/one.go:(1|2)' | head -1)" "2"
rule '- src/one.go:1 — PARKED: the null check is upstream'
ok "one of two findings ruled -> still blocks" "$(ruchk)" "2"
rule '- src/one.go:2 — DEFERRED: later'
ok "DEFERRED with no ticket is not a ruling" "$(ruchk)" "2"
rule '- src/one.go:2 — DEFERRED ABC-123: the retry path is rewritten there'
ok "every in-scope finding ruled -> passes; pre-existing needs none" "$(ruchk)" "0"
ok "...and the gate prints the rulings" \
   "$(exloom_check_verdicts "$RUC" 1 HEAD "$(git rev-parse HEAD)" test 2>&1 | grep -c 'ABC-123' | head -1)" "1"
ok "Certified lane: a Critical ruled without the user's words -> blocks" "$(ruchk 1 certified)" "2"
rule '- src/one.go:1 — PARKED: user said "ship it, the flag is off in prod"'
ok "...with their words quoted -> passes" "$(ruchk 1 certified)" "0"

unrule
rule '- src/one.go:10 — PARKED: a different line'
rule '- src/one.go:2 — PARKED: fine'
ok "a ruling on src/one.go:10 does not rule src/one.go:1" "$(ruchk)" "2"
unrule
rule '- src/one.go:1 — not FIXED yet'
rule '- src/one.go:2 — PARKED: fine'
ok "the disposition must follow the cite, not appear anywhere" "$(ruchk)" "2"
unrule
rule '    - src/one.go:1 — PARKED: an indented example'
rule '    - src/one.go:2 — PARKED: an indented example'
ok "an indented example line is not a ruling" "$(ruchk)" "2"

unrule
rule '- src/one.go:1 — PARKED: x'
rule '- src/one.go:2 — PARKED: x'
printf '{"agent":"l1-reviewer","head":"%s","verdict":"UNKNOWN","round_needed":"UNKNOWN"}\n' "$RUH" >> "$RUV/l1-reviewer.json"
git add -A >/dev/null 2>&1; git commit -qm unknown >/dev/null 2>&1
ok "an UNKNOWN verdict cannot be ruled away" "$(ruchk)" "2"

printf 'r2\n' > src/one.go; git add -A >/dev/null 2>&1; git commit -qm r2 >/dev/null 2>&1
printf '{"agent":"l1-reviewer","head":"%s","verdict":"REJECTED","round_needed":"YES"}\n' "$(git rev-parse HEAD)" >> "$RUV/l1-reviewer.json"
git add -A >/dev/null 2>&1; git commit -qm blind >/dev/null 2>&1
ok "a REJECTED review with no findings recorded cannot be ruled away" "$(ruchk)" "2"

section "verify mode: a re-review covers only the fix range"

subrepo verify
VC=".claude/reviews/feat/plan.md"; VV=".claude/reviews/feat/plan.verdicts"; mkdir -p "$VV"
printf '# checklist\n\n## Rulings\n' > "$VC"
printf 'l1\nl2\nl3\nl4\nl5\n' > src/a.go; git add -A >/dev/null 2>&1; git commit -qm a >/dev/null 2>&1
VA="$(git rev-parse HEAD)"
vfeed() {   # vfeed <report>
  python3 -c "
import json,sys
print(json.dumps({'session_id':'s','hook_event_name':'SubagentStop','agent_id':'a1',
 'agent_type':'exloom:l1-reviewer','last_assistant_message':sys.argv[1]}))" "$1" \
  | bash "$HOOKS_ABS/record-reviewer-verdict.sh" >/dev/null 2>&1
}
vfeed 'VERDICT: REJECTED (1 items)
## Critical (must fix before merge)
- src/a.go:2 — IN-SCOPE — null dereference
ROUND NEEDED AFTER FIX: YES'
ok "a full review records mode full" "$(grep -c '"mode":"full"' "$VV/l1-reviewer.json")" "1"
git add -A >/dev/null 2>&1; git commit -qm r1 >/dev/null 2>&1
printf 'l1\nl2 fixed\nl3\nl4\nl5\nl6\n' > src/a.go; git add -A >/dev/null 2>&1; git commit -qm fix >/dev/null 2>&1
VB="$(git rev-parse HEAD)"
vfeed "VERDICT: REJECTED (2 items)
MODE: VERIFY ${VA}..${VB}
## Previous findings
- src/a.go:2 — ADDRESSED
## Critical (must fix before merge)
- src/a.go:4 — IN-SCOPE — a line the fix did not touch
- src/a.go:6 — IN-SCOPE — a line the fix added
ROUND NEEDED AFTER FIX: YES"
ok "a verify review records its mode and range" \
   "$(tail -1 "$VV/l1-reviewer.json" | grep -c "\"mode\":\"verify\",\"range\":\"${VA}..${VB}\"")" "1"
ok "a finding outside the fix range is recorded out of scope" \
   "$(grep "\"head\":\"${VB}\"" "$VV/l1-reviewer.findings.jsonl" | grep 'src/a.go:4' | grep -c 'OUT-OF-SCOPE')" "1"
ok "a finding inside the fix range stays in scope" \
   "$(grep "\"head\":\"${VB}\"" "$VV/l1-reviewer.findings.jsonl" | grep 'src/a.go:6' | grep -c '"scope":"IN-SCOPE"')" "1"
ok "an ADDRESSED finding is recorded closed, not open" \
   "$(grep "\"head\":\"${VB}\"" "$VV/l1-reviewer.findings.jsonl" | grep 'src/a.go:2' | grep -vc '"scope":"ADDRESSED"')" "0"
git add -A >/dev/null 2>&1; git commit -qm r2 >/dev/null 2>&1
vchk() { exloom_check_verdicts "$VC" 1 HEAD "$(git rev-parse HEAD)" test 2>&1 >/dev/null; }
ok "the in-range finding blocks" "$(vchk | grep -c 'src/a.go:6')" "1"
ok "...and the out-of-range one is not asked for a ruling" "$(vchk | grep -c 'src/a.go:4')" "0"
printf -- '- src/a.go:6 — DEFERRED ABC-7: the added line is reworked there\n' >> "$VC"
git add -A >/dev/null 2>&1; git commit -qm rule >/dev/null 2>&1
ok "ruling the in-range finding passes; the out-of-range one cannot reject" \
   "$(exloom_check_verdicts "$VC" 1 HEAD "$(git rev-parse HEAD)" test >/dev/null 2>&1; echo $?)" "0"

vfeed "VERDICT: REJECTED (1 items)
MODE: VERIFY ${VB}..$(git rev-parse HEAD)
## Previous findings
- src/a.go:2 — NOT ADDRESSED: still dereferences null
ROUND NEEDED AFTER FIX: YES"
ok "a NOT ADDRESSED finding is recorded in scope with its earlier severity" \
   "$(grep "\"head\":\"$(git rev-parse HEAD)\"" "$VV/l1-reviewer.findings.jsonl" | grep 'src/a.go:2' | grep '"scope":"IN-SCOPE"' | grep -c '"severity":"HIGH"')" "1"
printf 'l7\n' >> src/a.go; git add -A >/dev/null 2>&1; git commit -qm more >/dev/null 2>&1
vfeed "VERDICT: REJECTED (1 items)
MODE: VERIFY $(git rev-parse HEAD)..$(git rev-parse HEAD)
## Critical (must fix before merge)
- src/a.go:1 — IN-SCOPE — empty range
ROUND NEEDED AFTER FIX: YES"
ok "a verify range that does not start at the last reviewed head is not verify mode" \
   "$(grep 'src/a.go:1' "$VV/l1-reviewer.findings.jsonl" | tail -1 | grep -c '"scope":"IN-SCOPE"')" "1"


printf 'l7\nl8\n' >> src/a.go; git add -A >/dev/null 2>&1; git commit -qm more2 >/dev/null 2>&1
VL="$(sed -n 's/.*"head":"\([0-9a-f]*\)","verdict".*/\1/p' "$VV/l1-reviewer.json" | tail -1)"
vfeed "VERDICT: REJECTED (1 items)
MODE: VERIFY ${VL}..$(git rev-parse HEAD)
## Critical (must fix before merge)
- a.go:8 — IN-SCOPE — cited by its file name only
ROUND NEEDED AFTER FIX: YES"
ok "a cite by file name alone still counts as in the fix range" \
   "$(grep 'a.go:8' "$VV/l1-reviewer.findings.jsonl" | tail -1 | grep -c '"scope":"IN-SCOPE"')" "1"

subrepo verify2
V2V=".claude/reviews/feat/plan.verdicts"; mkdir -p "$V2V"
printf 'l1\nl2\nl3\n' > src/a.go; git add -A >/dev/null 2>&1; git commit -qm a >/dev/null 2>&1
V2A="$(git rev-parse HEAD)"
vfeed 'VERDICT: REJECTED (2 items)
## Critical (must fix before merge)
- src/a.go:1 — IN-SCOPE — first defect
- src/a.go:3 — IN-SCOPE — second defect
## Pre-existing (backlog, not this branch)
- src/a.go:2 — PRE-EXISTING — old leak
ROUND NEEDED AFTER FIX: YES'
git add -A >/dev/null 2>&1; git commit -qm r1 >/dev/null 2>&1
printf 'l1 fixed\nl2\nl3\n' > src/a.go; git add -A >/dev/null 2>&1; git commit -qm fix >/dev/null 2>&1
vfeed "VERDICT: APPROVED
MODE: VERIFY ${V2A}..$(git rev-parse HEAD)
## Previous findings
- src/a.go:1 — ADDRESSED
- src/a.go:2 — NOT ADDRESSED: still leaks
ROUND NEEDED AFTER FIX: NO"
V2B="$(git rev-parse HEAD)"
ok "a blocking finding left out of the verify prompt is carried forward" \
   "$(grep "\"head\":\"${V2B}\"" "$V2V/l1-reviewer.findings.jsonl" | grep 'src/a.go:3' | grep -c '"scope":"IN-SCOPE"')" "1"
ok "...and the verify pass cannot approve over it" \
   "$(tail -1 "$V2V/l1-reviewer.json" | grep -c '"verdict":"REJECTED"')" "1"
ok "a pre-existing finding not addressed stays pre-existing" \
   "$(grep "\"head\":\"${V2B}\"" "$V2V/l1-reviewer.findings.jsonl" | grep 'src/a.go:2' | grep -c '"scope":"PRE-EXISTING"')" "1"

subrepo verify3
V3V=".claude/reviews/feat/plan.verdicts"; mkdir -p "$V3V"
printf 'guard\nwork\nmore\n' > src/a.go; git add -A >/dev/null 2>&1; git commit -qm a >/dev/null 2>&1
V3A="$(git rev-parse HEAD)"
vfeed 'VERDICT: REJECTED (1 items)
## Critical (must fix before merge)
- src/a.go:3 — IN-SCOPE — first defect
ROUND NEEDED AFTER FIX: YES'
git add -A >/dev/null 2>&1; git commit -qm r1 >/dev/null 2>&1
printf 'work\nmore\n' > src/a.go; git add -A >/dev/null 2>&1; git commit -qm 'delete the guard' >/dev/null 2>&1
vfeed "VERDICT: REJECTED (2 items)
MODE: VERIFY ${V3A}..$(git rev-parse HEAD)
## Previous findings
- src/a.go:3 — PARTIALLY ADDRESSED: still reachable
## Critical (must fix before merge)
- src/a.go:1 — IN-SCOPE — the deleted guard leaves this unchecked
ROUND NEEDED AFTER FIX: YES"
V3B="$(git rev-parse HEAD)"
ok "a finding at a deletion the fix made is in the fix range" \
   "$(grep "\"head\":\"${V3B}\"" "$V3V/l1-reviewer.findings.jsonl" | grep 'src/a.go:1' | grep -c '"scope":"IN-SCOPE"')" "1"
ok "PARTIALLY ADDRESSED counts as not addressed" \
   "$(grep "\"head\":\"${V3B}\"" "$V3V/l1-reviewer.findings.jsonl" | grep 'src/a.go:3' | grep -c '"scope":"IN-SCOPE"')" "1"

section "the ledger: minor findings never enter the fix loop"

subrepo ledger
LC=".claude/reviews/feat/plan.md"; LV=".claude/reviews/feat/plan.verdicts"; LL=".claude/reviews/feat/plan.ledger.md"
mkdir -p "$LV"; printf '# checklist\n\n## Rulings\n' > "$LC"
printf 'a\nb\n' > src/a.go; git add -A >/dev/null 2>&1; git commit -qm a >/dev/null 2>&1
lfeed() {
  python3 -c "
import json,sys
print(json.dumps({'session_id':'s','hook_event_name':'SubagentStop','agent_id':'a1',
 'agent_type':'exloom:l1-reviewer','last_assistant_message':sys.argv[1]}))" "$1" \
  | bash "$HOOKS_ABS/record-reviewer-verdict.sh" >/dev/null 2>&1
}
MINOR_ONLY='VERDICT: REJECTED (1 items)
## Minor (may defer with a reason in the checklist)
- src/a.go:1 — IN-SCOPE — the name says count, it holds a total
## Pre-existing (backlog, not this branch)
- src/a.go:2 — PRE-EXISTING — an old unchecked return
ROUND NEEDED AFTER FIX: YES'
lfeed "$MINOR_ONLY"
ok "a minor finding goes to the ledger" "$(grep -c 'src/a.go:1' "$LL" 2>/dev/null)" "1"
ok "...and so does a pre-existing one" "$(grep -c 'src/a.go:2' "$LL" 2>/dev/null)" "1"
ok "a minor-only report does not ask for another round" \
   "$(tail -1 "$LV/l1-reviewer.json" | grep -c '"round_needed":"NO"')" "1"
lfeed "$MINOR_ONLY"
ok "the same report twice adds nothing to the ledger" "$(grep -c 'src/a.go:1' "$LL")" "1"
git add -A >/dev/null 2>&1; git commit -qm receipts >/dev/null 2>&1
ok "a minor-only REJECTED needs no ruling" \
   "$(exloom_check_verdicts "$LC" 1 HEAD "$(git rev-parse HEAD)" test >/dev/null 2>&1; echo $?)" "0"

printf 'c\n' >> src/a.go; git add -A >/dev/null 2>&1; git commit -qm more >/dev/null 2>&1
lfeed 'VERDICT: REJECTED (2 items)
## Critical (must fix before merge)
- the whole retry path leaks connections
## Minor (may defer with a reason in the checklist)
- src/a.go:3 — IN-SCOPE — a name
ROUND NEEDED AFTER FIX: YES'
ok "a Critical the parser could not cite keeps the round open" \
   "$(tail -1 "$LV/l1-reviewer.json" | grep -c '"round_needed":"YES"')" "1"
git add -A >/dev/null 2>&1; git commit -qm mixed >/dev/null 2>&1
ok "...and the gate does not pass it on the minor alone" \
   "$(exloom_check_verdicts "$LC" 1 HEAD "$(git rev-parse HEAD)" test >/dev/null 2>&1; echo $?)" "2"

section "per-task review: a spec verdict, kept apart from the branch's rounds"

subrepo tasks
TV=".claude/reviews/feat/plan.verdicts"; mkdir -p "$TV"
printf 'a\n' > src/a.go; git add -A >/dev/null 2>&1; git commit -qm task3 >/dev/null 2>&1
tfeed() {
  python3 -c "
import json,sys
print(json.dumps({'session_id':'s','hook_event_name':'SubagentStop','agent_id':'a1',
 'agent_type':'exloom:l1-reviewer','last_assistant_message':sys.argv[1]}))" "$1" \
  | bash "$HOOKS_ABS/record-reviewer-verdict.sh" >/dev/null 2>&1
}
tfeed 'VERDICT: REJECTED (1 items)
MODE: TASK 3
SPEC: EXTRA
## Spec
- src/a.go:1 — EXTRA — a retry helper the task does not ask for
ROUND NEEDED AFTER FIX: YES'
ok "a task review is recorded in the task receipt" \
   "$(grep -c '"task":"3","spec":"EXTRA"' "$TV/l1-reviewer.tasks.json" 2>/dev/null)" "1"
ok "...and not in the branch receipt, so it is not a branch round" \
   "$( [[ -f "$TV/l1-reviewer.json" ]] && echo present || echo absent)" "absent"
ok "code beyond the task's text is recorded as a blocking spec finding" \
   "$(grep 'src/a.go:1' "$TV/l1-reviewer.findings.jsonl" | grep '"severity":"MED"' | grep -c '"scope":"IN-SCOPE"')" "1"

section "the dispatch budget is enforced at dispatch, and a receipt is bound to it"

subrepo budget
BC=".claude/reviews/feat/plan.md"; BV=".claude/reviews/feat/plan.verdicts"; mkdir -p "$BV"
printf '# checklist\n\n## Rulings\n' > "$BC"
printf 'a\n' > src/a.go; git add -A >/dev/null 2>&1; git commit -qm a >/dev/null 2>&1
disp() {   # disp <tool_use_id> <prompt> [agent] [nolaunch] -> exit code of the guard
  local rc
  python3 -c "
import json,sys
print(json.dumps({'session_id':'s','hook_event_name':'PreToolUse','tool_name':'Agent','tool_use_id':sys.argv[1],
 'tool_input':{'subagent_type':'exloom:'+sys.argv[3],'prompt':sys.argv[2]}}))" "$1" "$2" "${3:-l1-reviewer}" \
  | bash "$HOOKS_ABS/guard-reviewer-dispatch.sh" >/dev/null 2>&1; rc=$?
  if [[ $rc -eq 0 && -z "${4:-}" ]]; then
    python3 -c "
import json,sys
print(json.dumps({'session_id':'s','hook_event_name':'PostToolUse','tool_name':'Agent','tool_use_id':sys.argv[1],
 'tool_input':{'subagent_type':'exloom:'+sys.argv[3],'prompt':sys.argv[2]},
 'tool_response':{'isAsync':True,'status':'async_launched','agentId':'ag-'+sys.argv[1]}}))" "$1" "$2" "${3:-l1-reviewer}" \
      | bash "$HOOKS_ABS/record-reviewer-verdict.sh" >/dev/null 2>&1
  fi
  echo $rc
}
ok "a task's first review is allowed" "$(disp t1 'Review task 3 of p.md. Diff: git diff a..b')" "0"
ok "...a second full review of the same task is refused" "$(disp t2 'Review task 3 of p.md. Diff: git diff a..b')" "2"
ok "fix round 1 is allowed" "$(disp t3 'Verify fixes for task 3 on branch feat/plan. Fix range: a..b')" "0"
ok "fix round 2 is allowed" "$(disp t4 'Verify fixes for task 3 on branch feat/plan. Fix range: a..b')" "0"
ok "fix round 3 is allowed" "$(disp t5 'Verify fixes for task 3 on branch feat/plan. Fix range: a..b')" "0"
ok "a fourth fix round is refused" "$(disp t6 'Verify fixes for task 3 on branch feat/plan. Fix range: a..b')" "2"
printf -- '- Extra round — sure\n' >> "$BC"
ok "an extra-round line without the user's quoted words grants nothing" \
   "$(disp t6b 'Verify fixes for task 3 on branch feat/plan. Fix range: a..b')" "2"
printf -- '- Extra round — "one more, then we ship"\n' >> "$BC"
ok "an uncommitted grant grants nothing" "$(disp t6c 'Verify fixes for task 3 on branch feat/plan. Fix range: a..b')" "2"
git add -A >/dev/null 2>&1; git commit -qm grant >/dev/null 2>&1
ok "...a committed grant allows one more round" "$(disp t7 'Verify fixes for task 3 on branch feat/plan. Fix range: a..b')" "0"
ok "...and the grant is used once" "$(disp t8 'Verify fixes for task 3 on branch feat/plan. Fix range: a..b')" "2"
printf -- '- Extra round — "after this fix only"\n' >> "$BC"; git add -A >/dev/null 2>&1; git commit -qm grant2 >/dev/null 2>&1
printf 'more\n' >> src/a.go; git add -A >/dev/null 2>&1; git commit -qm 'new code' >/dev/null 2>&1
ok "a grant written before a code change expires with it" "$(disp t9 'Review task 3 of p.md. Diff: git diff a..b')" "2"
ok "the last fix always gets one verify, whatever the budget" "$(disp t10 'Verify fixes for task 3 on branch feat/plan. Fix range: a..b')" "0"
ok "...but a second verify of the same code is refused" "$(disp t11 'Verify fixes for task 3 on branch feat/plan. Fix range: a..b')" "2"
ok "the final review runs once" "$(disp f1 'Review branch feat/plan at x. Diff: git diff m...x' adversarial-reviewer)" "0"
ok "...a second final review is refused" "$(disp f2 'Review branch feat/plan at x. Diff: git diff m...x' adversarial-reviewer)" "2"
ok "...one scoped re-review is allowed" "$(disp f3 'Verify fixes on branch feat/plan. Fix range: a..b' adversarial-reviewer)" "0"
ok "...a second fix wave is refused" "$(disp f4 'Verify fixes on branch feat/plan. Fix range: a..b' adversarial-reviewer)" "2"
ok "each dispatch records the commit and a prompt hash" \
   "$(grep '"tool_use_id":"t1"' "$BV/dispatches.jsonl" | grep -cE '"dispatch_head":"[0-9a-f]{40}","prompt_hash":"[0-9a-f]{40}"')" "1"

ok "a dispatch that never launched does not spend the budget" \
   "$(disp n1 'Review branch feat/plan at x.' security-auditor nolaunch; disp n2 'Review branch feat/plan at x.' security-auditor)" "0
0"
seq 1 150 > src/big.go; git add -A >/dev/null 2>&1; git commit -qm grow >/dev/null 2>&1
ok "planned work does not count as growth: a new task is still reviewed" \
   "$(disp g0 'Review task 9 of p.md. Diff: git diff a..b')" "0"
ok "growth since the final review started refuses the next fix round" \
   "$(disp g1 'Verify fixes on branch feat/plan. Fix range: a..b' security-auditor)" "2"

subrepo binding
BC=".claude/reviews/feat/plan.md"; BV=".claude/reviews/feat/plan.verdicts"; mkdir -p "$BV"
printf '# checklist\n' > "$BC"
printf 'a\n' > src/a.go; git add -A >/dev/null 2>&1; git commit -qm a >/dev/null 2>&1
H1="$(git rev-parse HEAD)"
post() {   # post <tool_use_id> <agent_id> <response-json>
  python3 -c "
import json,sys
print(json.dumps({'session_id':'s','hook_event_name':'PostToolUse','tool_name':'Agent','tool_use_id':sys.argv[1],
 'tool_input':{'subagent_type':'exloom:l1-reviewer','prompt':'Review branch feat/plan'},
 'tool_response':dict(json.loads(sys.argv[3]),agentId=sys.argv[2],resolvedModel='claude-opus-5-5')}))" "$1" "$2" "$3" \
  | bash "$HOOKS_ABS/record-reviewer-verdict.sh" >/dev/null 2>&1
}
stop() {   # stop <agent_id> <report>
  python3 -c "
import json,sys
print(json.dumps({'session_id':'s','hook_event_name':'SubagentStop','agent_id':sys.argv[1],
 'agent_type':'exloom:l1-reviewer','last_assistant_message':sys.argv[2]}))" "$1" "$2" \
  | bash "$HOOKS_ABS/record-reviewer-verdict.sh" >/dev/null 2>&1
}
disp b1 'Review branch feat/plan at x. Diff: git diff m...x' l1-reviewer nolaunch >/dev/null
post b1 ag1 '{"isAsync":true,"status":"async_launched"}'
printf 'b\n' >> src/a.go; git add -A >/dev/null 2>&1; git commit -qm during >/dev/null 2>&1
stop ag1 'VERDICT: APPROVED
ROUND NEEDED AFTER FIX: NO'
ok "an async review's receipt names the commit it was dispatched at" \
   "$(tail -1 "$BV/l1-reviewer.json" | grep -c "\"head\":\"${H1}\",\"verdict\":\"APPROVED\"")" "1"
ok "...and records the model that ran" "$(tail -1 "$BV/l1-reviewer.json" | grep -c '"model":"claude-opus-5-5"')" "1"
git add -A >/dev/null 2>&1; git commit -qm receipts >/dev/null 2>&1
ok "a commit made during the review cannot inherit its approval" \
   "$(exloom_check_verdicts "$BC" 1 HEAD "$(git rev-parse HEAD)" test >/dev/null 2>&1; echo $?)" "2"
ok "committing receipts does not raise the round count" "$(exloom_round_count "$BC" HEAD)" "1"

printf -- '- Extra round — "check the fix"\n' >> "$BC"; git add "$BC" >/dev/null 2>&1; git commit -qm grant >/dev/null 2>&1
H2="$(git rev-parse HEAD)"
disp b2 'Review branch feat/plan at y. Diff: git diff m...y' l1-reviewer nolaunch >/dev/null
stop ag2 'VERDICT: APPROVED
ROUND NEEDED AFTER FIX: NO'
ok "a foreground result is held until PostToolUse maps it" \
   "$(grep -c "\"head\":\"${H2}\"" "$BV/l1-reviewer.json"; [[ -f "$BV/held/ag2.json" ]] && echo held)" "0
held"
post b2 ag2 '{"content":[{"type":"text","text":"VERDICT: APPROVED"}]}'
ok "...then recorded against the dispatch commit" \
   "$(grep -c "\"head\":\"${H2}\",\"verdict\":\"APPROVED\"" "$BV/l1-reviewer.json")" "1"

T1="$(git rev-parse HEAD)"
disp k1 'Review task 4 of p.md. Diff: git diff a..b' >/dev/null
stop ag-k1 'VERDICT: REJECTED (1 items)
MODE: TASK 4
SPEC: MATCHES
## Critical (must fix before merge)
- src/a.go:1 — IN-SCOPE — bad
ROUND NEEDED AFTER FIX: YES'
printf 'fixed\n' > src/a.go; git add -A >/dev/null 2>&1; git commit -qm taskfix >/dev/null 2>&1
disp k2 'Verify fixes for task 4 on branch feat/plan. Fix range: a..b' >/dev/null
stop ag-k2 "VERDICT: APPROVED
MODE: VERIFY ${T1}..$(git rev-parse HEAD)
## Previous findings
- src/a.go:1 — ADDRESSED
ROUND NEEDED AFTER FIX: NO"
ok "a task's verify pass goes to the task receipt, with its range" \
   "$(tail -1 "$BV/l1-reviewer.tasks.json" | grep -c "\"mode\":\"verify\",\"range\":\"${T1}\.\..*\"task\":\"4\"")" "1"
ok "...and is not a branch round" "$(grep -c '"verify"' "$BV/l1-reviewer.json")" "0"

section "the latest verdict counts, and a same-commit re-run cannot overturn a rejection"

subrepo reroll
RR=".claude/reviews/feat/plan.md"; RRV=".claude/reviews/feat/plan.verdicts"; mkdir -p "$RRV"
printf '# checklist\n\n## Rulings\n' > "$RR"
printf 'a\n' > src/a.go; git add -A >/dev/null 2>&1; git commit -qm a >/dev/null 2>&1
RRH="$(git rev-parse HEAD)"
rline() { printf '{"agent":"l1-reviewer","head":"%s","verdict":"%s","round_needed":"NO"}\n' "$RRH" "$1"; }
rrchk() { git add -A >/dev/null 2>&1; git commit -qm r >/dev/null 2>&1
  exloom_check_verdicts "$RR" 1 HEAD "$(git rev-parse HEAD)" test >/dev/null 2>&1; echo $?; }
{ rline APPROVED; rline REJECTED; } > "$RRV/l1-reviewer.json"
ok "APPROVED then REJECTED at the same commit -> blocks" "$(rrchk)" "2"
{ rline REJECTED; rline APPROVED; } > "$RRV/l1-reviewer.json"
ok "REJECTED then a re-run APPROVED at the same commit -> still blocks" "$(rrchk)" "2"
{ rline UNKNOWN; rline APPROVED; } > "$RRV/l1-reviewer.json"
ok "UNKNOWN then APPROVED at the same commit -> passes" "$(rrchk)" "0"
{ rline APPROVED; printf '{"agent":"l1-reviewer","head":"%s","dispatch":true}\n' "$RRH"; } > "$RRV/l1-reviewer.json"
ok "a launch line after an approval does not change the verdict" "$(rrchk)" "0"

section "only exloom's own reviewers write receipts"

subrepo names
NV=".claude/reviews/feat/plan.verdicts"; NC=".claude/reviews/feat/plan.md"; mkdir -p "$NV"
printf '# checklist\n' > "$NC"
printf 'a\n' > src/a.go; git add -A >/dev/null 2>&1; git commit -qm a >/dev/null 2>&1
python3 -c "
import json
print(json.dumps({'session_id':'s','hook_event_name':'SubagentStop','agent_id':'x',
 'agent_type':'myplugin:l1-reviewer','last_assistant_message':'VERDICT: APPROVED'}))" \
  | bash "$HOOKS_ABS/record-reviewer-verdict.sh" >/dev/null 2>&1
ok "an agent merely named *l1-reviewer writes no receipt" "$([[ -f "$NV/l1-reviewer.json" ]] && echo yes || echo no)" "no"
printf '{"agent":"l1-reviewer","subagent_type":"myplugin:l1-reviewer","head":"%s","verdict":"APPROVED"}\n' "$(git rev-parse HEAD)" > "$NV/l1-reviewer.json"
git add -A >/dev/null 2>&1; git commit -qm forged >/dev/null 2>&1
ok "the gate ignores a receipt line from another agent" \
   "$(exloom_check_verdicts "$NC" 1 HEAD "$(git rev-parse HEAD)" test >/dev/null 2>&1; echo $?)" "2"

section "no base branch blocks; an empty diff passes"

subrepo nobase noorigin
git branch -m main production >/dev/null 2>&1
printf 'a\n' > src/a.go; git add -A >/dev/null 2>&1; git commit -qm a >/dev/null 2>&1
exloom_derive_tier HEAD >/dev/null 2>&1; ok "no base branch -> derive returns 1" "$?" "1"
NBC=".claude/reviews/feat/plan.md"; mkdir -p "$(dirname "$NBC")"
printf '**Tier:** 1\n**Base branch:** auto\n\n## Final verdict\n- [x] All required gates passed for declared tier\n- [x] Checklist committed\n- [x] Ready to ship\n\nReviewed code commit: %s\n' "$(git rev-parse HEAD)" > "$NBC"
git add -A >/dev/null 2>&1; git commit -qm cl >/dev/null 2>&1
ok "...and the gate blocks, asking for the base branch" \
   "$(exloom_validate_checklist "$NBC" HEAD 1 test 2>&1 >/dev/null | grep -c 'Base branch:' | head -1)" "1"
sed -i 's/^\*\*Base branch:\*\* auto/**Base branch:** production/' "$NBC"
git add -A >/dev/null 2>&1; git commit -qm base >/dev/null 2>&1
ok "a recorded base clears that block" \
   "$(exloom_validate_checklist "$NBC" HEAD 1 test 2>&1 >/dev/null | grep -c 'cannot find the branch' | head -1)" "0"
git branch main production; git checkout -q -b feat/empty main
exloom_derive_tier HEAD >/dev/null 2>&1; ok "an empty diff -> derive returns 2" "$?" "2"
git checkout -q feat/plan

section "security paths derive Tier 3 whatever their case"

subrepo secpaths
for p in src/OAuth2Config.java src/security/Filter.java src/PasswordEncoder.java src/EncryptionService.java \
         app/SECRETS.py src/rbac/Roles.go src/HTTPSecurity.java src/IAMPolicy.go src/sso/x.go src/acl.go; do
  ok "$p -> Tier 3" "$(sp "$p")" "3"
done
for p in src/authoring/x.go src/Author.java src/diameter.go src/oracle.go src/decipherable.go; do
  ok "$p -> not Tier 3" "$(sp "$p")" "1"
done

section "docs-only means Markdown, READMEs and top-level docs/"

subrepo docsonly
for p in requirements.txt src/docs/Handler.java; do
  ok "$p -> not docs-only" "$(sp "$p")" "1"
done
for p in docs/guide.txt README notes/x.md; do
  ok "$p -> docs-only" "$(sp "$p")" "0"
done

section "the base comes from origin, not from a local branch near HEAD"

subrepo localbase
mkdir -p src/auth; printf 'x\n' > src/auth/login.go; git add -A >/dev/null 2>&1; git commit -qm auth >/dev/null 2>&1
git branch -f main HEAD
printf 'y\n' > src/one.go; git add -A >/dev/null 2>&1; git commit -qm one >/dev/null 2>&1
ok "a local main moved up to HEAD does not shrink the diff" "$(exloom_derive_tier HEAD 2>/dev/null)" "3"
subrepo localonly noorigin
printf 'y\n' > src/one.go; git add -A >/dev/null 2>&1; git commit -qm one >/dev/null 2>&1
ok "with no origin, a local base is used" "$(exloom_derive_tier HEAD 2>/dev/null)" "1"
ok "...with a warning" "$(exloom_derive_tier HEAD 2>&1 >/dev/null | grep -c 'no origin/' | head -1)" "1"

section "a comment line is a comment only when nothing follows it"

subrepo comments
printf 'int a = 1;\n' > src/c.java; git add -A >/dev/null 2>&1; git commit -qm c >/dev/null 2>&1
cbeh() {   # cbeh <added line> -> behavioural|inert
  local b; b="$(git rev-parse HEAD)"
  printf 'int a = 1;\n%s\n' "$1" > src/c.java; git add -A >/dev/null 2>&1; git commit -qm x >/dev/null 2>&1
  if exloom_diff_is_behavioural "$b" HEAD; then echo behavioural; else echo inert; fi
  git reset -q --hard "$b"
}
ok "/**/ code(); -> behavioural" "$(cbeh '/**/ code();')" "behavioural"
ok "*/ code(); -> behavioural" "$(cbeh '*/ code();')" "behavioural"
ok "/* note */ -> inert" "$(cbeh '/* note */')" "inert"
ok "/** opening a javadoc -> inert" "$(cbeh '/**')" "inert"
ok "*/ closing it -> inert" "$(cbeh ' */')" "inert"
ok "// line comment -> inert" "$(cbeh '// note')" "inert"

section "hand-written receipts: cd, node -e and git apply"

subrepo handwrite
bashj() { python3 -c "import json,sys; print(json.dumps({'tool_name':'Bash','tool_input':{'command':sys.argv[1]}}))" "$1"; }
ok "cd into the verdicts folder, then a relative redirect -> denied" \
   "$(deny "$(bashj 'cd .claude/reviews/feat/plan.verdicts && echo {} > l1-reviewer.json')")" "2"
ok "...but cd there to list it -> allowed" \
   "$(deny "$(bashj 'cd .claude/reviews/feat/plan.verdicts && ls -la')")" "0"
ok "node -e writing a receipt -> denied" \
   "$(deny "$(bashj "node -e \"require('fs').writeFileSync('.claude/reviews/feat/plan.verdicts/l1-reviewer.json','{}')\"")")" "2"
printf -- '--- a/.claude/reviews/feat/plan.verdicts/l1-reviewer.json\n+++ b/.claude/reviews/feat/plan.verdicts/l1-reviewer.json\n@@ -0,0 +1 @@\n+{}\n' > fix.patch
ok "git apply of a patch that writes a receipt -> denied" "$(deny "$(bashj 'git apply fix.patch')")" "2"
printf -- '--- a/src/a.go\n+++ b/src/a.go\n@@ -0,0 +1 @@\n+x\n' > ok.patch
ok "git apply of an ordinary patch -> allowed" "$(deny "$(bashj 'git apply ok.patch')")" "0"

section "a tier's placeholder scan skips the sections that tier does not need"

subrepo tiersections
TSC=".claude/reviews/feat/plan.md"; mkdir -p "$(dirname "$TSC")"
for tier in 1 2; do
  awk '/^## What a revert will not undo/{keep=1} /^## /&&!/^## What a revert will not undo/{keep=0} {print keep?$0:"@@"$0}' \
      "$HOOKS_ABS/../../../scripts/fixtures/legacy-review-checklist.md" \
    | sed -e '/^@@/s/<[^>]*>/filled/g' -e 's/^@@//' -e 's/- \[ \]/- [x]/g' \
          -e "s/^\*\*Tier:\*\* .*/**Tier:** ${tier}/" > "$TSC"
  ok "tier ${tier}: the Tier 3 section's placeholders do not block" \
     "$(exloom_validate_checklist "$TSC" HEAD 1 test 2>&1 >/dev/null | grep -c 'runbook' | head -1)" "0"
done

section "the proof applies the branch's deletions"

proofrepo replaced 'v=$(bash src/calc.sh); [ "$v" = "4" ]' 'echo 4'; B="$BASESHA"
printf 'for t in tests/*_test.sh; do bash "$t" || exit 1; done\n' > .claude/exloom-test-command
git rm -q tests/calc_test.sh; mkdir -p tests
printf 'v=$(bash src/calc.sh); [ "$v" = "5" ]\n' > tests/new_test.sh
printf 'echo 5\n' > src/calc.sh
git add -A >/dev/null 2>&1; git commit -qm replace >/dev/null 2>&1
ok "a replaced test is removed before the runs, so the change proves" "$(prove "$B")" "0"
ok "...and the receipt says PROVED" "$(proofres)" "PROVED"

section "a git-ignored .claude/ is named, file by file"

subrepo ignored
ok "nothing ignored -> nothing listed" "$(exloom_ignored_settings feat/plan | grep -c .)" "0"
printf '.claude/\n' > .gitignore
ok "an ignored .claude/ lists the receipts and every committed-only setting" \
   "$(exloom_ignored_settings feat/plan | grep -cE 'reviews/feat/plan.md|verdicts|exloom-test-command|exloom-max-rounds|exloom-proof.disabled|exloom-lane|exloom-mutation-command|exloom-protected-branches|exloom-skip-branches|exloom-test-patterns|exloom-not-testable-patterns|exloom-docs|exloom-doc-patterns')" "13"
printf '.claude/*\n!.claude/reviews/\n!.claude/exloom-*\n' > .gitignore
ok "ignoring only local files -> nothing listed" "$(exloom_ignored_settings feat/plan | grep -c .)" "0"

section "a deletion with no new behaviour proves NO_NEW_BEHAVIOUR"

proofrepo deletion 'v=$(bash src/calc.sh); [ "$v" = "4" ]' 'echo 4
unused() { echo dead; }'; B="$BASESHA"
printf 'echo 4\n' > src/calc.sh; git add -A >/dev/null 2>&1; git commit -qm 'drop dead code' >/dev/null 2>&1
ok "a pure deletion whose suite passes -> NO_NEW_BEHAVIOUR" "$(prove "$B"; proofres)" "0
NO_NEW_BEHAVIOUR"
proofrepo deletionbroken 'v=$(bash src/calc.sh); [ "$v" = "4" ]' 'echo 4'; B="$BASESHA"
: > src/calc.sh; git add -A >/dev/null 2>&1; git commit -qm 'delete too much' >/dev/null 2>&1
ok "a deletion that breaks the suite -> NOT_PROVED" "$(prove "$B"; proofres)" "1
NOT_PROVED"
proofrepo addition 'v=$(bash src/calc.sh); [ "$v" = "4" ]' 'echo 4'; B="$BASESHA"
printf 'echo 4\nrm -rf /tmp/x\n' > src/calc.sh; git add -A >/dev/null 2>&1; git commit -qm add >/dev/null 2>&1
ok "an added behavioural line with no test and a passing suite -> NO_TEST_CHANGED" "$(prove "$B"; proofres)" "0
NO_TEST_CHANGED"

NC=".claude/reviews/feat/proof.md"; NV=".claude/reviews/feat/proof.verdicts"; mkdir -p "$NV"
printf '# checklist\n' > "$NC"
printf '{"check":"change-is-tested","result":"NO_NEW_BEHAVIOUR","head":"%s"}\n' "$(git rev-parse HEAD)" > "$NV/proof.json"
git add -A >/dev/null 2>&1; git commit -qm nnb >/dev/null 2>&1
nnb() { exloom_check_proof "$NC" HEAD "$(git rev-parse HEAD)" test "$1" >/dev/null 2>&1; echo $?; }
ok "NO_NEW_BEHAVIOUR passes at Tier 1" "$(nnb 1)" "0"
ok "...not at Tier 2 without a ruling" "$(nnb 2)" "2"
printf -- '- Proof: deletion only — the helper had no callers\n' >> "$NC"
git add -A >/dev/null 2>&1; git commit -qm ruling >/dev/null 2>&1
ok "...and at Tier 2 with one" "$(nnb 2)" "0"

section "the proof detects .NET and Flutter test commands"

detect() {   # detect <name> <files...> -> the command the proof chose, or its refusal
  local d="$REG/detect-$1"; shift; rm -rf "$d"; mkdir -p "$d/.claude" "$d/src"; cd "$d" || return 1
  git init -q -b main . 2>/dev/null; git config user.email t@e.com; git config user.name t
  : > .claude/exloom-gate.enabled; local f; for f in "$@"; do mkdir -p "$(dirname "$f")"; : > "$f"; done
  git add -A >/dev/null 2>&1; git commit -qm base >/dev/null 2>&1; git checkout -q -b feat/x
  printf 'x\n' > src/a.cs; mkdir -p t; printf 'x\n' > t/ATests.cs; git add -A >/dev/null 2>&1; git commit -qm c >/dev/null 2>&1
  bash "$PROVE" --base main 2>&1 | grep -E '^command:|no test command|more than one' | head -1
}
ok "pubspec.yaml -> flutter test" "$(detect flutter pubspec.yaml)" "command: flutter test"
ok "one .sln at the root -> dotnet test <sln>" "$(detect onesln App.sln)" "command: dotnet test App.sln"
ok "several .sln files -> a pinned command is required" \
   "$(detect twosln A.sln B.sln | grep -c 'more than one .NET')" "1"
ok "a .sln plus a loose .csproj -> a pinned command is required" \
   "$(detect slnproj App.sln Tool.csproj | grep -c 'more than one .NET')" "1"
cd "$WORK" || exit 1

section "Flutter integration tests and package files"

ok "integration_test/ -> test" "$(istest 'integration_test/app_test.dart')" "test"
ok "a nested integration_test/ -> test" "$(istest 'packages/app/integration_test/login.dart')" "test"
subrepo flutterdeps
for p in pubspec.yaml pubspec.lock Directory.Packages.props; do
  git checkout -q -B "d/$RANDOM" main; printf 'x\n' > "$p"; git add -A >/dev/null 2>&1; git commit -qm d >/dev/null 2>&1
  ok "$p is a dependency surface" \
     "$(exloom_security_surface "$(git rev-parse main)" HEAD && echo yes || echo no)" "yes"
done

section "a block is one line and a next action, unless asked for more"

short="$(EXLOOM_VERBOSE=0 _exloom_block "push" "proof missing for this commit
more detail that should not show" 2>&1)"
ok "the default block is one line" "$(printf '%s\n' "$short" | grep -c .)" "1"
ok "...naming the reason and /exloom" "$(printf '%s' "$short" | grep -c 'blocked — proof missing for this commit → run /exloom')" "1"
ok "the user's verbose setting shows everything" \
   "$(EXLOOM_VERBOSE=0 CLAUDE_PLUGIN_OPTION_VERBOSE=true _exloom_block push "a
b" 2>&1 | grep -c 'Only the user can choose the emergency bypass')" "1"

section "strict mode is a committed repo setting"

subrepo strict
SC=".claude/reviews/feat/plan.md"; mkdir -p "$(dirname "$SC")"
printf '**Tier:** 1\n**Lane:** standard\n\n## Escape hatches used\n- Skipped: smoke test — headless box\n' > "$SC"
smsg() { exloom_validate_checklist "$SC" HEAD 1 test 2>&1 >/dev/null | grep -c 'Certified lane, which has no escape hatches' | head -1; }
ok "no strict file -> the standard lane accepts the skip" "$(smsg)" "0"
: > .claude/exloom-strict
ok "an uncommitted strict file changes nothing" "$(smsg)" "0"
git add .claude/exloom-strict >/dev/null 2>&1; git commit -qm strict >/dev/null 2>&1
ok "a committed strict file makes every branch Certified" "$(smsg)" "1"
ok "...and the ignore check lists it" \
   "$(printf '.claude/\n' > .gitignore; exloom_ignored_settings feat/plan | grep -c 'exloom-strict')" "1"

section "the evidence report is generated; people write only rulings"

subrepo report
RPC=".claude/reviews/feat/plan.md"; RPV=".claude/reviews/feat/plan.verdicts"; mkdir -p "$RPV"
printf 'a\n' > src/a.go; git add -A >/dev/null 2>&1; git commit -qm a >/dev/null 2>&1
RH="$(git rev-parse HEAD)"
printf '{"agent":"l1-reviewer","subagent_type":"exloom:l1-reviewer","head":"%s","verdict":"APPROVED","round_needed":"NO","mode":"full","model":"claude-opus-5-5"}\n' "$RH" > "$RPV/l1-reviewer.json"
printf '{"check":"change-is-tested","result":"PROVED","method":"three-run","head":"%s","matrix":""}\n' "$RH" > "$RPV/proof.json"
printf '{"check":"smoke","method":"agent-run","head":"%s","cmd":"x","exit":0,"output":"smoke.out","at":"n"}\n' "$RH" > "$RPV/smoke.json"
exloom_render_report feat/plan >/dev/null 2>&1
ok "a first render writes the skeleton and the evidence block" \
   "$(grep -cE '^## Rulings$|^<!-- exloom:report|^<!-- /exloom:report -->$' "$RPC")" "3"
ok "...with the derived tier, not a declared one" \
   "$(grep -c '^\*\*Derived tier:\*\* 1$' "$RPC"; grep -c '^\*\*Tier:\*\*' "$RPC")" "1
0"
ok "...the reviewed commit" "$(grep -c "^Reviewed code commit: ${RH}$" "$RPC")" "1"
ok "...each required reviewer's latest verdict and model" \
   "$(grep -c "^| l1-reviewer | APPROVED | ${RH:0:12} | full | claude-opus-5-5 |$" "$RPC")" "1"
ok "...and the provenance lines the gate reads" "$(grep -cE '^- (AI-assisted|Model\(s\)|Directed by|Base commit):' "$RPC")" "4"
sed -i 's/^none$/- src\/a.go:1 — PARKED: kept on purpose/' "$RPC"
exloom_render_report feat/plan >/dev/null 2>&1
ok "a re-render keeps the rulings and replaces only the block" \
   "$(grep -c 'PARKED: kept on purpose' "$RPC"; grep -c '^<!-- exloom:report' "$RPC")" "1
1"
git add -A >/dev/null 2>&1; git commit -qm report >/dev/null 2>&1
ok "the gate accepts a generated report with its receipts" \
   "$(exloom_validate_checklist "$RPC" HEAD 1 test >/dev/null 2>&1; echo $?)" "0"
git checkout -q -b feat/deep
mkdir -p src/auth; printf 'x\n' > src/auth/login.go; git add -A >/dev/null 2>&1; git commit -qm auth >/dev/null 2>&1
mkdir -p .claude/reviews/feat; cp "$RPC" .claude/reviews/feat/deep.md; cp -r "$RPV" .claude/reviews/feat/deep.verdicts
exloom_render_report feat/deep >/dev/null 2>&1; git add -A >/dev/null 2>&1; git commit -qm deep >/dev/null 2>&1
ok "a report for a Tier 3 diff is held to Tier 3 without a declared tier" \
   "$(exloom_validate_checklist .claude/reviews/feat/deep.md HEAD 1 test 2>&1 >/dev/null | grep -c 'Tier 3 requires a verdict receipt' | head -1)" "1"

section "/exloom knows the next step"

subrepo nextstep
NSV=".claude/reviews/feat/plan.verdicts"; NSC=".claude/reviews/feat/plan.md"
ok "no checklist -> init" "$(exloom_next_step feat/plan)" "init"
ok "the summary of a branch with no checklist is quiet" \
   "$(exloom_branch_summary feat/plan 2>&1 | grep -c 'No such file')" "0"
exloom_render_report feat/plan >/dev/null 2>&1
ok "an uncommitted checklist -> commit" "$(exloom_next_step feat/plan)" "commit"
ok "provenance names the git user, not the email" "$(grep -c '^- Directed by: t$' "$NSC")" "1"
git add -A >/dev/null 2>&1; git commit -qm init >/dev/null 2>&1
printf 'w\n' > src/w.go
ok "uncommitted work outside .claude/reviews -> commit-work" "$(exloom_next_step feat/plan)" "commit-work"
rm -f src/w.go
ok "standard lane, no spec -> spec" "$(exloom_next_step feat/plan)" "spec"
mkdir -p docs/specs; printf '# F-001\n' > docs/specs/F-001-x.md
sed -i 's/^\*\*Spec:\*\* none$/**Spec:** docs\/specs\/F-001-x.md/' "$NSC"
git add -A >/dev/null 2>&1; git commit -qm spec >/dev/null 2>&1
ok "spec but no plan -> plan" "$(exloom_next_step feat/plan)" "plan"
printf '### Task 1 — a\n### Task 2 — b\n' > docs/plans/p.md
sed -i 's/^\*\*Plan:\*\* none$/**Plan:** docs\/plans\/p.md/' "$NSC"
git add -A >/dev/null 2>&1; git commit -qm plan >/dev/null 2>&1
ok "spec and plan committed are not code -> build" "$(exloom_next_step feat/plan)" "build"
printf 'a\n' > src/a.go; git add -A >/dev/null 2>&1; git commit -qm a >/dev/null 2>&1
ok "code committed, no task approved -> build" "$(exloom_next_step feat/plan)" "build"
mkdir -p "$NSV"
printf '{"agent":"l1-reviewer","head":"%s","verdict":"APPROVED","mode":"task","task":"1"}\n' "$(git rev-parse HEAD)" > "$NSV/l1-reviewer.tasks.json"
git add -A >/dev/null 2>&1; git commit -qm t1 >/dev/null 2>&1
ok "one of two tasks approved -> build" "$(exloom_next_step feat/plan)" "build"
printf '{"agent":"l1-reviewer","head":"%s","verdict":"APPROVED","mode":"task","task":"2"}\n' "$(git rev-parse HEAD)" >> "$NSV/l1-reviewer.tasks.json"
exloom_render_report feat/plan >/dev/null 2>&1; git add -A >/dev/null 2>&1; git commit -qm t2 >/dev/null 2>&1
ok "every task approved, no reviewer has run -> review" "$(exloom_next_step feat/plan)" "review"
git checkout -q -b feat/sprint
sed -i -e 's/^\*\*Lane:\*\* standard$/**Lane:** sprint/' -e 's/^\*\*Spec:\*\* .*$/**Spec:** none/' -e 's/^\*\*Plan:\*\* .*$/**Plan:** none/' "$NSC"
exloom_render_report feat/plan >/dev/null 2>&1; git add -A >/dev/null 2>&1; git commit -qm sprint >/dev/null 2>&1
ok "the sprint lane needs no spec or plan -> review" "$(exloom_next_step feat/plan)" "review"
git checkout -q feat/plan
NSH="$(git rev-parse HEAD)"
mkdir -p "$NSV"
printf '{"agent":"l1-reviewer","subagent_type":"exloom:l1-reviewer","head":"%s","verdict":"REJECTED","round_needed":"YES"}\n' "$NSH" > "$NSV/l1-reviewer.json"
printf '{"round":1,"agent":"l1-reviewer","severity":"HIGH","scope":"IN-SCOPE","cite":"src/a.go:1","fingerprint":"f","head":"%s","at":"n"}\n' "$NSH" > "$NSV/l1-reviewer.findings.jsonl"
exloom_render_report feat/plan >/dev/null 2>&1; git add -A >/dev/null 2>&1; git commit -qm rej >/dev/null 2>&1
ok "a rejection with open findings -> fix" "$(exloom_next_step feat/plan)" "fix"
printf '{"agent":"l1-reviewer","subagent_type":"exloom:l1-reviewer","head":"%s","verdict":"APPROVED","round_needed":"NO"}\n' "$NSH" > "$NSV/l1-reviewer.json"
exloom_render_report feat/plan >/dev/null 2>&1; git add -A >/dev/null 2>&1; git commit -qm ok >/dev/null 2>&1
ok "reviewed but no proof -> proof" "$(exloom_next_step feat/plan)" "proof"
printf '{"check":"change-is-tested","result":"PROVED","head":"%s"}\n' "$NSH" > "$NSV/proof.json"
exloom_render_report feat/plan >/dev/null 2>&1; git add -A >/dev/null 2>&1; git commit -qm proof >/dev/null 2>&1
ok "proved but no smoke test -> smoke" "$(exloom_next_step feat/plan)" "smoke"
printf '{"check":"smoke","method":"agent-run","head":"%s","cmd":"x","exit":0,"output":"smoke.out","at":"n"}\n' "$NSH" > "$NSV/smoke.json"
exloom_render_report feat/plan >/dev/null 2>&1; git add -A >/dev/null 2>&1; git commit -qm smoke >/dev/null 2>&1
ok "everything in place -> push" "$(exloom_next_step feat/plan)" "push"
ok "the status is one line" "$(exloom_status_line feat/plan | grep -c .)" "1"
ok "...naming tier, proof and the next step" \
   "$(exloom_status_line feat/plan | grep -cE '^Tier 1 · task 2/2 · round [0-9]+/3 · proof ✓ · 0 rulings · next: push$')" "1"
mkdir -p docs/plans; printf '### Task 1 — a\n### Task 2 — b\n### Task 3 — c\n' > docs/plans/p.md
printf '{"agent":"l1-reviewer","head":"%s","verdict":"APPROVED","mode":"task","task":"1"}\n' "$NSH" > "$NSV/l1-reviewer.tasks.json"
sed -i 's/^\*\*Lane:\*\* standard$/**Lane:** standard\n**Plan:** docs\/plans\/p.md/' .claude/reviews/feat/plan.md
ok "with a plan, the status shows tasks reviewed and approved" \
   "$(exloom_status_line feat/plan | grep -cE '^Tier 1 · task 1/3 · round ')" "1"
printf '{"agent":"l1-reviewer","key":"final","kind":"review","tool_use_id":"t","dispatch_head":"%s","prompt_hash":"x","extra":false,"at":"2026-01-01T10:00:00Z"}\n' "$NSH" > "$NSV/dispatches.jsonl"
sed -i 's/^none$/- src\/a.go:1 — PARKED: fine/' .claude/reviews/feat/plan.md
ok "the branch summary line has duration, rounds, criteria and rulings" \
   "$(exloom_branch_summary feat/plan "2026-01-01T10:42:00Z" | grep -cE '^42 min · [0-9]+ review rounds? · [0-9]+(/[0-9]+)? criteria proved · 1 ruling$')" "1"
git checkout -q -- .claude/reviews/feat/plan.md
rm -f .claude/exloom-gate.enabled
ok "gate off -> setup" "$(exloom_next_step feat/plan)" "setup"

section "the reviewer model is a committed per-repo setting, Opus by default"

subrepo revmodel
ok "no setting -> opus" "$(exloom_reviewer_model l1-reviewer)" "opus"
printf 'l1-reviewer: sonnet\n' > .claude/exloom-reviewer-model
ok "an uncommitted setting is ignored" "$(exloom_reviewer_model l1-reviewer)" "opus"
git add .claude/exloom-reviewer-model >/dev/null 2>&1; git commit -qm model >/dev/null 2>&1
ok "a committed setting names the reviewer's model" "$(exloom_reviewer_model l1-reviewer)" "sonnet"
ok "...and leaves the others on opus" "$(exloom_reviewer_model security-auditor)" "opus"
ok "the ignore check lists it" \
   "$(printf '.claude/\n' > .gitignore; exloom_ignored_settings feat/plan | grep -c 'exloom-reviewer-model')" "1"

section "during the fix loop only the fixer commits code"

subrepo fixloop
FLC=".claude/reviews/feat/plan.md"; FLV=".claude/reviews/feat/plan.verdicts"; mkdir -p "$FLV"
printf '# r\n\n## Rulings\n\nnone\n' > "$FLC"
printf 'a\n' > src/a.go; git add -A >/dev/null 2>&1; git commit -qm a >/dev/null 2>&1
FLH="$(git rev-parse HEAD)"
printf '{"agent":"l1-reviewer","subagent_type":"exloom:l1-reviewer","head":"%s","verdict":"REJECTED","round_needed":"YES","at":"2026-01-01T10:00:00Z"}\n' "$FLH" > "$FLV/l1-reviewer.json"
printf '{"round":1,"agent":"l1-reviewer","severity":"HIGH","scope":"IN-SCOPE","cite":"src/a.go:1","fingerprint":"f","head":"%s","at":"n"}\n' "$FLH" > "$FLV/l1-reviewer.findings.jsonl"
git add -A >/dev/null 2>&1; git commit -qm rej >/dev/null 2>&1
fl() {   # fl <command> [agent_id] -> exit code of the hook
  python3 -c "
import json,sys
d={'session_id':'s','hook_event_name':'PreToolUse','tool_name':'Bash','tool_input':{'command':sys.argv[1]}}
if sys.argv[2]: d.update(agent_id=sys.argv[2], agent_type='exloom:fixer')
print(json.dumps(d))" "$1" "${2:-}" | bash "$HOOKS_ABS/guard-fix-loop.sh" >/dev/null 2>&1; echo $?
}
printf 'b\n' > src/a.go; git add src/a.go
ok "the main session committing code with an open rejection -> refused" "$(fl 'git commit -m fix')" "2"
ok "...the fixer subagent committing it -> allowed" "$(fl 'git commit -m fix' agent-1)" "0"
git reset -q src/a.go
printf 'x\n' > .claude/reviews/feat/note.md; git add .claude/reviews/feat/note.md
ok "committing only review files -> allowed" "$(fl 'git commit -m review')" "0"
git commit -qm note >/dev/null 2>&1
sed -i 's/^none$/- src\/a.go:1 — PARKED: kept/' "$FLC"; git add -A >/dev/null 2>&1; git commit -qm ruled >/dev/null 2>&1
printf 'c\n' > src/b.go; git add src/b.go
ok "once every finding is ruled, the session commits again" "$(fl 'git commit -m next')" "0"
ok "an ordinary command is not judged" "$(fl 'git status')" "0"

section "smoke evidence: agent-run for CLI and API at Tier 0-2, pasted for UI and Tier 3"

subrepo smoke
SMC=".claude/reviews/feat/plan.md"; SMV=".claude/reviews/feat/plan.verdicts"; mkdir -p "$SMV"
SMOKE="$(cd "$(dirname "$LIB_ABS")/../scripts" && pwd)/record-smoke.sh"
printf 'echo 4\n' > src/calc.sh; git add -A >/dev/null 2>&1; git commit -qm calc >/dev/null 2>&1
SMH="$(git rev-parse HEAD)"
printf '{"agent":"l1-reviewer","subagent_type":"exloom:l1-reviewer","head":"%s","verdict":"APPROVED","round_needed":"NO"}\n' "$SMH" > "$SMV/l1-reviewer.json"
printf '{"check":"change-is-tested","result":"PROVED","head":"%s"}\n' "$SMH" > "$SMV/proof.json"
smchk() { exloom_render_report feat/plan >/dev/null 2>&1; git add -A >/dev/null 2>&1; git commit -qm r >/dev/null 2>&1
  exloom_validate_checklist "$SMC" HEAD 1 test 2>&1 >/dev/null; }
ok "no smoke evidence -> blocked" "$(smchk | grep -c 'smoke test' | head -1)" "1"
bash "$SMOKE" -- bash src/calc.sh >/dev/null 2>&1
ok "the script records the command, exit code and commit" \
   "$(tail -1 "$SMV/smoke.json" | grep -cE "\"head\":\"$(git rev-parse HEAD)\".*\"exit\":0")" "1"
ok "...and the output it printed" "$(grep -c '^4$' "$SMV/smoke.out")" "1"
ok "an agent-run receipt satisfies a Tier 1 CLI change" "$(smchk | grep -c 'smoke test' | head -1)" "0"
bash "$SMOKE" -- false >/dev/null 2>&1
ok "a failing command does not" "$(smchk | grep -c 'smoke test' | head -1)" "1"
mkdir -p web; printf '<p/>\n' > web/page.html; git add -A >/dev/null 2>&1; git commit -qm ui >/dev/null 2>&1
SMH="$(git rev-parse HEAD)"
printf '{"agent":"l1-reviewer","subagent_type":"exloom:l1-reviewer","head":"%s","verdict":"APPROVED","round_needed":"NO"}\n' "$SMH" >> "$SMV/l1-reviewer.json"
printf '{"check":"change-is-tested","result":"PROVED","head":"%s"}\n' "$SMH" >> "$SMV/proof.json"
bash "$SMOKE" -- true >/dev/null 2>&1
ok "a UI change needs a pasted result, not an agent receipt" "$(smchk | grep -c 'pasted' | head -1)" "1"
sed -i 's/^## Rulings$/## Smoke test\n\nOpened \/page.html; the paragraph rendered.\n\n## Rulings/' "$SMC"
ok "...and the pasted section satisfies it" "$(smchk | grep -c 'smoke test' | head -1)" "0"

section "after a fix the reviewer verifies; the user rules only on what is still open"

subrepo rulingflow
RFC=".claude/reviews/feat/plan.md"; RFV=".claude/reviews/feat/plan.verdicts"
exloom_render_report feat/plan >/dev/null 2>&1; sed -i 's/^\*\*Lane:\*\* standard$/**Lane:** sprint/' "$RFC"
git add -A >/dev/null 2>&1; git commit -qm init >/dev/null 2>&1
printf 'l1\nl2\n' > src/a.go; git add -A >/dev/null 2>&1; git commit -qm a >/dev/null 2>&1
RFA="$(git rev-parse HEAD)"
rffeed() {
  python3 -c "
import json,sys
print(json.dumps({'session_id':'s','hook_event_name':'SubagentStop','agent_id':'a1',
 'agent_type':'exloom:l1-reviewer','last_assistant_message':sys.argv[1]}))" "$1" \
  | bash "$HOOKS_ABS/record-reviewer-verdict.sh" >/dev/null 2>&1
  exloom_render_report feat/plan >/dev/null 2>&1; git add -A >/dev/null 2>&1; git commit -qm receipt >/dev/null 2>&1
}
rfrule() { sed -i "/^## Rulings/a $1" "$RFC"; exloom_render_report feat/plan >/dev/null 2>&1; git add -A >/dev/null 2>&1; git commit -qm rule >/dev/null 2>&1; }
rfcheck() { exloom_check_verdicts "$RFC" 1 HEAD "$(git rev-parse HEAD)" test; }
rffeed 'VERDICT: REJECTED (2 items)
## Critical (must fix before merge)
- src/a.go:1 — IN-SCOPE — null dereference
## Important (must fix or justify deferral)
- src/a.go:2 — IN-SCOPE — leaks the handle
ROUND NEEDED AFTER FIX: YES'
ok "a first rejection is fixed, not ruled on" "$(exloom_next_step feat/plan)" "fix"
printf 'l1 fixed\nl2 tried\n' > src/a.go; git add -A >/dev/null 2>&1; git commit -qm fix >/dev/null 2>&1
RFB="$(git rev-parse HEAD)"
rffeed "VERDICT: REJECTED (1 items)
MODE: VERIFY ${RFA}..${RFB}
## Previous findings
- src/a.go:1 — ADDRESSED
- src/a.go:2 — NOT ADDRESSED: still leaks the handle on the error path
ROUND NEEDED AFTER FIX: YES"
ok "an ADDRESSED finding is recorded closed" \
   "$(grep "\"head\":\"${RFB}\"" "$RFV/l1-reviewer.findings.jsonl" | grep 'src/a.go:1' | grep -c '"scope":"ADDRESSED"')" "1"
ok "after a verify, what is still open goes to the user" "$(exloom_next_step feat/plan)" "rulings"
RFMSG="$(EXLOOM_VERBOSE=1 rfcheck 2>&1 >/dev/null)"
ok "...naming the still-open finding with the reviewer's reason" \
   "$(printf '%s\n' "$RFMSG" | grep -c 'src/a.go:2.*still leaks the handle on the error path')" "1"
ok "...not the addressed one" "$(printf '%s\n' "$RFMSG" | grep -c 'src/a.go:1')" "0"
ok "...offering the three options in plain words" \
   "$(printf '%s\n' "$RFMSG" | grep -cF -e '"Fix again"' -e '"Not a real problem, ignore (PARKED)"' -e '"Fix later, with a ticket (DEFERRED)"')" "3"
rfrule '- src/a.go:2 — FIXED: done'
ok "FIXED is no longer a ruling" "$(rfcheck >/dev/null 2>&1; echo $?)" "2"
rfrule '- src/a.go:2 — PARKED: the error path is unreachable here'
ok "PARKED closes it" "$(rfcheck >/dev/null 2>&1; echo $?)" "0"

section "a change that is not code needs no proof"

pcommit() { git add -A >/dev/null 2>&1; git commit -qm "$1" >/dev/null 2>&1; }
pgate() {   # pgate [tier] -> exit code of the proof gate after committing the receipt
  pcommit receipt
  exloom_check_proof .claude/reviews/feat/proof.md HEAD "$(git rev-parse HEAD)" test "${1:-1}" >/dev/null 2>&1; echo $?
}
proofrepo noncode 'true' 'echo 4'; B="$BASESHA"
mkdir -p web img; printf 'a{}\n' > web/site.css; printf 'b{}\n' > web/x.scss; printf 'PNG\n' > img/logo.png
printf '{"name":"x"}\n' > package.json; printf 'k: v\n' > deploy.yml; printf '{"a":1}\n' > web/settings.json
pcommit noncode
ok "styles, assets, a manifest and config only -> NOT_TESTABLE" "$(prove "$B"; proofres)" "0
NOT_TESTABLE"
ok "...which passes at every tier" "$(pgate 3)" "0"
ok "a dependency change still needs the security auditor" "$(exloom_security_surface "$B" HEAD; echo $?)" "0"
proofrepo noncodemixed 'true' 'echo 4'; B="$BASESHA"
mkdir -p web; printf 'a{}\n' > web/site.css; printf 'echo 4\nx=1\n' > src/calc.sh; pcommit mixed
ok "a style change next to a source change is not NOT_TESTABLE" "$(prove "$B" >/dev/null; proofres)" "NO_TEST_CHANGED"
proofrepo noncodeext 'true' 'echo 4'; B="$BASESHA"
mkdir -p infra; printf 'resource {}\n' > infra/main.tf; pcommit tf
printf '*.tf\n' > .claude/exloom-not-testable-patterns
ok "an uncommitted pattern file extends nothing" "$(prove "$B" >/dev/null; proofres)" "NO_TEST_CHANGED"
pcommit patterns
ok "a committed pattern file extends the list" "$(prove "$B"; proofres)" "0
NOT_TESTABLE"
subrepo noncodenocmd
printf 'a{}\n' > src/site.css; pcommit css
ok "no test command is needed for a change with nothing to test" \
   "$(bash "$PROVE" --base main >/dev/null 2>&1; echo $?; sed -n 's/.*"result":"\([A-Z_]*\)".*/\1/p' .claude/reviews/feat/plan.verdicts/proof.json 2>/dev/null)" "0
NOT_TESTABLE"

section "a tests-only branch passes the proof"

pcommit() { git add -A >/dev/null 2>&1; git commit -qm "$1" >/dev/null 2>&1; }
proofrepo testsonly 'true' 'echo 4'; B="$BASESHA"
printf 'true\ntrue\n' > tests/calc_test.sh; pcommit tests
ok "only tests changed -> a passing TESTS_ONLY receipt" "$(prove "$B"; proofres)" "0
TESTS_ONLY"
pcommit receipt
ok "...which the gate accepts at every tier" \
   "$(exloom_check_proof .claude/reviews/feat/proof.md HEAD "$(git rev-parse HEAD)" test 3 >/dev/null 2>&1; echo $?)" "0"

section "a refactor passes on the user's ruling when the suite passes"

pcommit() { git add -A >/dev/null 2>&1; git commit -qm "$1" >/dev/null 2>&1; }
rgate() { exloom_check_proof .claude/reviews/feat/proof.md HEAD "$(git rev-parse HEAD)" test "${1:-1}" 2>&1 >/dev/null; echo "rc=$?"; }
proofrepo refactor 'v=$(bash src/calc.sh); [ "$v" = "4" ]' 'echo 4'; B="$BASESHA"
printf '# checklist\n\n## Rulings\n\n' > .claude/reviews/feat/proof.md
printf 'x=4\necho "$x"\n' > src/calc.sh; pcommit refactor
ok "no test changed and the suite passes -> NO_TEST_CHANGED" "$(prove "$B"; proofres)" "0
NO_TEST_CHANGED"
pcommit receipt
ok "...which blocks without a ruling" "$(rgate | tail -1)" "rc=2"
ok "...and asks for the refactor ruling" "$(EXLOOM_VERBOSE=1 rgate | grep -c 'Proof: refactor')" "1"
printf -- '- Proof: refactor — renamed a variable, same output\n' >> .claude/reviews/feat/proof.md
ok "an uncommitted refactor ruling does not count" "$(rgate | tail -1)" "rc=2"
pcommit ruling
ok "a committed refactor ruling passes at every tier" "$(rgate 3 | tail -1)" "rc=0"
proofrepo refactorbroken 'v=$(bash src/calc.sh); [ "$v" = "4" ]' 'echo 4'; B="$BASESHA"
printf 'echo 5\n' > src/calc.sh; pcommit broken
ok "no test changed and the suite fails -> NOT_PROVED" "$(prove "$B"; proofres)" "1
NOT_PROVED"

section "the NOT_PROVED message suggests only what works"

pcommit() { git add -A >/dev/null 2>&1; git commit -qm "$1" >/dev/null 2>&1; }
proofrepo vacuous 'true' 'echo 4'; B="$BASESHA"
printf 'echo 5\n' > src/calc.sh; printf 'true\n# touched\n' > tests/calc_test.sh; pcommit vacuous
VOUT="$(bash "$PROVE" --base "$B" 2>&1)"
ok "the script's NOT PROVED does not say 'say so'" "$(printf '%s\n' "$VOUT" | grep -ci 'say so')" "0"
ok "...and names the mutation command" "$(printf '%s\n' "$VOUT" | grep -c 'exloom-mutation-command')" "1"
pcommit receipt
VMSG="$(EXLOOM_VERBOSE=1 exloom_check_proof .claude/reviews/feat/proof.md HEAD "$(git rev-parse HEAD)" test 1 2>&1 >/dev/null)"
ok "the gate's NOT_PROVED does not say 'say so in the checklist'" "$(printf '%s\n' "$VMSG" | grep -ci 'say so')" "0"
ok "...and names the mutation command" "$(printf '%s\n' "$VMSG" | grep -c 'exloom-mutation-command')" "1"

section "a push of an existing tag is a tag, not a branch"

subrepo tagpush
git tag v1.0.0
pt() { exloom_push_target_branches "$1" | tr '\n' ' ' | sed 's/ $//'; }
ok "git push origin v1.0.0 -> a tag" "$(pt 'git push origin v1.0.0')" "__DELETE__"
ok "git push origin --tags -> tags only" "$(pt 'git push origin --tags')" "__DELETE__"
ok "git push origin feat/plan -> still a branch" "$(pt 'git push origin feat/plan')" "feat/plan"
git branch v2 >/dev/null 2>&1; git tag v2 >/dev/null 2>&1
ok "a name that is both a tag and a branch is checked as the branch" "$(pt 'git push origin v2')" "v2"

section "merging main into a reviewed branch"

subrepo mergemain
MMC=".claude/reviews/feat/plan.md"; MMV=".claude/reviews/feat/plan.verdicts"; mkdir -p "$MMV"
printf '# checklist\n\n## Rulings\n\n' > "$MMC"
mmcommit() { git add -A >/dev/null 2>&1; git commit -qm "$1" >/dev/null 2>&1; }
mmguard() {   # mmguard <tool_use_id> <prompt> -> guard exit code; a launch is mapped when allowed
  local rc
  python3 -c "
import json,sys
print(json.dumps({'session_id':'s','hook_event_name':'PreToolUse','tool_name':'Agent','tool_use_id':sys.argv[1],
 'tool_input':{'subagent_type':'exloom:l1-reviewer','prompt':sys.argv[2]}}))" "$1" "$2" \
    | bash "$HOOKS_ABS/guard-reviewer-dispatch.sh" >/dev/null 2>&1; rc=$?
  if [[ $rc -eq 0 ]]; then
    python3 -c "
import json,sys
print(json.dumps({'session_id':'s','hook_event_name':'PostToolUse','tool_name':'Agent','tool_use_id':sys.argv[1],
 'tool_input':{'subagent_type':'exloom:l1-reviewer','prompt':sys.argv[2]},
 'tool_response':{'isAsync':True,'status':'async_launched','agentId':'ag-'+sys.argv[1]}}))" "$1" "$2" \
      | bash "$HOOKS_ABS/record-reviewer-verdict.sh" >/dev/null 2>&1
  fi
  echo $rc
}
mmstop() {   # mmstop <tool_use_id> <report>
  python3 -c "
import json,sys
print(json.dumps({'session_id':'s','hook_event_name':'SubagentStop','agent_id':'ag-'+sys.argv[1],
 'agent_type':'exloom:l1-reviewer','last_assistant_message':sys.argv[2]}))" "$1" "$2" \
    | bash "$HOOKS_ABS/record-reviewer-verdict.sh" >/dev/null 2>&1
}
mmmain() {   # mmmain <file> -> commits <file> on main and merges main into the branch
  git checkout -q main; seq 1 150 > "$1"; mmcommit "main: $1"
  git update-ref refs/remotes/origin/main HEAD; git checkout -q feat/plan
  git merge -q --no-edit main >/dev/null 2>&1
}
printf 'a1\na2\na3\n' > src/a.go; mmcommit a
MMA="$(git rev-parse HEAD)"
mmguard m1 'Review branch feat/plan at x. Diff: git diff m...x' >/dev/null
mmstop m1 'VERDICT: REJECTED (1 items)
## Critical (must fix before merge)
- src/a.go:2 — IN-SCOPE — null dereference
ROUND NEEDED AFTER FIX: YES'
mmcommit receipts
mmmain src/main.go
printf 'a1\na2 fixed\na3\n' > src/a.go; mmcommit fix
MMB="$(git rev-parse HEAD)"
ok "main's lines do not count as growth: the verify after a merge is allowed" \
   "$(mmguard m2 "Verify fixes on branch feat/plan. Fix range: ${MMA}..${MMB}")" "0"
mmstop m2 "VERDICT: REJECTED (1 items)
MODE: VERIFY ${MMA}..${MMB}
## Previous findings
- src/a.go:2 — ADDRESSED
## Critical (must fix before merge)
- src/main.go:5 — IN-SCOPE — a line main brought in
- src/a.go:2 — IN-SCOPE — a line the fix changed
ROUND NEEDED AFTER FIX: YES"
ok "a finding on a line main brought in is out of the verify range" \
   "$(grep "\"head\":\"${MMB}\"" "$MMV/l1-reviewer.findings.jsonl" | grep 'src/main.go:5' | grep -c '"scope":"OUT-OF-SCOPE"')" "1"
ok "...and one on the branch's own fix stays in range" \
   "$(grep "\"head\":\"${MMB}\"" "$MMV/l1-reviewer.findings.jsonl" | grep 'src/a.go:2' | grep -c '"scope":"IN-SCOPE"')" "1"

subrepo mergeonly
MMC=".claude/reviews/feat/plan.md"
printf '# checklist\n\n## Rulings\n\n' > "$MMC"
printf 'a1\n' > src/a.go; mmcommit a
mmguard o1 'Review branch feat/plan at x. Diff: git diff m...x' >/dev/null
mmstop o1 'VERDICT: APPROVED
ROUND NEEDED AFTER FIX: NO'
MMV=".claude/reviews/feat/plan.verdicts"
printf '{"check":"change-is-tested","result":"PROVED","head":"%s"}\n' "$(git rev-parse HEAD)" > "$MMV/proof.json"
printf '{"check":"smoke","method":"agent-run","head":"%s","cmd":"x","exit":0,"output":"smoke.out","at":"n"}\n' "$(git rev-parse HEAD)" > "$MMV/smoke.json"
mmcommit receipts
mmmain src/main.go
ok "a merge of main alone keeps the approval: nothing to re-review, no round spent" \
   "$(exloom_check_verdicts "$MMC" 1 HEAD "$(git rev-parse HEAD)" test >/dev/null 2>&1; echo $?)" "0"
ok "...and keeps the proof" "$(exloom_check_proof "$MMC" HEAD "$(git rev-parse HEAD)" test 1 >/dev/null 2>&1; echo $?)" "0"
ok "...and the smoke receipt" "$(exloom_check_smoke "$MMC" HEAD "$(git rev-parse HEAD)" test 1 >/dev/null 2>&1; echo $?)" "0"
printf 'a1\na2\n' > src/a.go; mmcommit own
ok "...but the branch's own change after it still needs review" \
   "$(exloom_check_verdicts "$MMC" 1 HEAD "$(git rev-parse HEAD)" test >/dev/null 2>&1; echo $?)" "2"

subrepo mergeconflict
MMC=".claude/reviews/feat/plan.md"; MMV=".claude/reviews/feat/plan.verdicts"; mkdir -p "$MMV"
printf '# checklist\n\n## Rulings\n\n' > "$MMC"
printf 'branch\n' > src/base.txt; mmcommit own
printf '{"check":"change-is-tested","result":"PROVED","head":"%s"}\n' "$(git rev-parse HEAD)" > "$MMV/proof.json"
printf '{"check":"smoke","method":"agent-run","head":"%s","cmd":"x","exit":0,"output":"smoke.out","at":"n"}\n' "$(git rev-parse HEAD)" > "$MMV/smoke.json"
mmcommit receipts
git checkout -q main; printf 'main\n' > src/base.txt; mmcommit main; git update-ref refs/remotes/origin/main HEAD
git checkout -q feat/plan; git merge -q --no-edit main >/dev/null 2>&1
printf 'branch and main\n' > src/base.txt; git add -A >/dev/null 2>&1; git commit -q --no-edit >/dev/null 2>&1
ok "a conflicted merge makes the proof stale" "$(exloom_check_proof "$MMC" HEAD "$(git rev-parse HEAD)" test 1 >/dev/null 2>&1; echo $?)" "2"
ok "...and the smoke receipt" "$(exloom_check_smoke "$MMC" HEAD "$(git rev-parse HEAD)" test 1 >/dev/null 2>&1; echo $?)" "2"

section "reference docs: a code change without its doc warns, never blocks"

rdcommit() { git add -A >/dev/null 2>&1; git commit -qm "$1" >/dev/null 2>&1; }
rdrepo() {   # rdrepo <name> <doc-file-on-main>... -> a fresh feat/plan off a main that has those docs
  subrepo "$1"; shift
  git checkout -q main
  local f; for f in "$@"; do mkdir -p "$(dirname "$f")"; printf '# doc\n' > "$f"; done
  rdcommit docs; git update-ref refs/remotes/origin/main HEAD
  git checkout -q -B feat/plan main
}
dw() { exloom_doc_warnings .claude/reviews/feat/plan.md HEAD 2>/dev/null; }

rdrepo refdocsnone
mkdir -p db/migrations; printf 'create table t();\n' > db/migrations/V2.sql; rdcommit mig
ok "with no docs, a migration change is silent" "$(dw | grep -c .)" "0"

rdrepo refdocs docs/db/schema.md
mkdir -p db/migrations src/controllers; printf 'create table t();\n' > db/migrations/V2.sql
printf 'x\n' > src/controllers/orders.go; rdcommit code
ok "a migration change without docs/db warns" "$(dw | grep -c 'docs/db')" "1"
ok "...and an API change with no API docs stays silent" "$(dw | grep -c 'docs/api')" "0"
ok "...and the warning never blocks the gate's checks" "$(exloom_doc_warnings .claude/reviews/feat/plan.md HEAD >/dev/null 2>&1; echo $?)" "0"
printf '# doc\n\n## t\n' > docs/db/schema.md; rdcommit doc
ok "updating docs/db in the branch clears it" "$(dw | grep -c .)" "0"

rdrepo refdocsimpact docs/db/schema.md
mkdir -p db/migrations; printf 'create index i;\n' > db/migrations/V2.sql; rdcommit mig
mkdir -p .claude/reviews/feat; printf '# c\n\n## Rulings\n\n- Doc impact: none — an index only\n' > .claude/reviews/feat/plan.md
ok "an uncommitted Doc impact line does not count" "$(dw | grep -c 'docs/db')" "1"
rdcommit impact
ok "a committed Doc impact: none line clears it" "$(dw | grep -c .)" "0"

rdrepo refdocsmap documentation/schema/tables.md docs/db/schema.md
mkdir -p sql; printf 'create table t();\n' > sql/tables.sql; rdcommit sql
printf 'documentation/schema: sql/*\n' > .claude/exloom-docs
ok "an uncommitted mapping is ignored: the defaults apply" "$(dw | grep -c 'documentation/schema')" "0"
rdcommit map
ok "a committed mapping names the repo's own doc" "$(dw | grep -c 'documentation/schema')" "1"
ok "...and replaces the defaults" "$(dw | grep -c 'docs/db')" "0"

rdrepo refdocspush docs/db/schema.md
printf 'feat/*\n' > .claude/exloom-skip-branches; rdcommit skip
mkdir -p db/migrations; printf 'create table t();\n' > db/migrations/V2.sql; rdcommit mig
RDOUT="$(printf '%s' '{"session_id":"s","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"git push"}}' \
  | bash "$HOOKS_ABS/block-unverified-push.sh" 2>/dev/null; echo "rc=$?")"
ok "the push is allowed" "$(printf '%s\n' "$RDOUT" | tail -1)" "rc=0"
ok "...and the warning reaches the user" "$(printf '%s\n' "$RDOUT" | grep -c '"systemMessage".*docs/db')" "1"

subrepo refdocsreview
mkdir -p docs/db; printf '# doc\n' > docs/db/schema.md; printf 'a\n' > src/a.go; rdcommit a
printf '# c\n\n## Rulings\n\n' > .claude/reviews/feat/plan.md
python3 -c "
import json
print(json.dumps({'session_id':'s','hook_event_name':'SubagentStop','agent_id':'a1','agent_type':'exloom:l1-reviewer',
 'last_assistant_message':'VERDICT: APPROVED\nROUND NEEDED AFTER FIX: NO'}))" \
  | bash "$HOOKS_ABS/record-reviewer-verdict.sh" >/dev/null 2>&1
rdcommit receipt
printf '# doc\n\nupdated after the review\n' > docs/db/schema.md; rdcommit doc
ok "a doc-only commit after the review keeps the L1 approval" \
   "$(exloom_check_verdicts .claude/reviews/feat/plan.md 1 HEAD "$(git rev-parse HEAD)" test >/dev/null 2>&1; echo $?)" "0"
RDOK="$(git rev-parse HEAD)"
mkdir -p src/docs/db; printf 'code\n' > src/docs/db/x.go; rdcommit nested
ok "...but code under a nested docs/db path is still code" \
   "$(exloom_check_verdicts .claude/reviews/feat/plan.md 1 HEAD "$(git rev-parse HEAD)" test >/dev/null 2>&1; echo $?)" "2"
git reset -q --hard "$RDOK"
printf 'src: *.go\n' > .claude/exloom-docs; rdcommit map
printf 'b\n' > src/a.go; rdcommit code
ok "...and a doc mapping committed after the review cannot exempt code" \
   "$(exloom_check_verdicts .claude/reviews/feat/plan.md 1 HEAD "$(git rev-parse HEAD)" test >/dev/null 2>&1; echo $?)" "2"
for rdf in docs/api/openapi.yaml docs/db/seed.sql docs/architecture/run.sh; do
  git reset -q --hard "$RDOK"; mkdir -p "$(dirname "$rdf")"; printf 'x: 1\n' > "$rdf"; rdcommit nonprose
  ok "a non-prose file in a doc folder still needs review: $rdf" \
     "$(exloom_check_verdicts .claude/reviews/feat/plan.md 1 HEAD "$(git rev-parse HEAD)" test >/dev/null 2>&1; echo $?)" "2"
done
for rdf in docs/db/schema.mmd docs/api/Guide.DOCX docs/data-model/fields.xlsx docs/architecture/overview.pdf; do
  git reset -q --hard "$RDOK"; mkdir -p "$(dirname "$rdf")"; printf 'doc\n' > "$rdf"; rdcommit doc
  ok "a document in a doc folder does not: $rdf" \
     "$(exloom_check_verdicts .claude/reviews/feat/plan.md 1 HEAD "$(git rev-parse HEAD)" test >/dev/null 2>&1; echo $?)" "0"
done

section "a team adds its own document types"

subrepo refdocpatterns
rpcommit() { git add -A >/dev/null 2>&1; git commit -qm "$1" >/dev/null 2>&1; }
rpapprove() {
  python3 -c "
import json
print(json.dumps({'session_id':'s','hook_event_name':'SubagentStop','agent_id':'a1','agent_type':'exloom:l1-reviewer',
 'last_assistant_message':'VERDICT: APPROVED\nROUND NEEDED AFTER FIX: NO'}))" \
    | bash "$HOOKS_ABS/record-reviewer-verdict.sh" >/dev/null 2>&1
  rpcommit receipt
}
rpchk() { exloom_check_verdicts .claude/reviews/feat/plan.md 1 HEAD "$(git rev-parse HEAD)" test >/dev/null 2>&1; echo $?; }
mkdir -p docs/architecture .claude/reviews/feat; printf '# a\n' > docs/architecture/overview.md
printf 'a\n' > src/a.go; printf '# c\n\n## Rulings\n\n' > .claude/reviews/feat/plan.md; rpcommit a
rpapprove
RPOK="$(git rev-parse HEAD)"
printf '@startuml\n' > docs/architecture/flow.puml; rpcommit puml
ok "an unlisted document type in a doc folder needs review" "$(rpchk)" "2"
git reset -q --hard "$RPOK"
printf '*.puml\n' > .claude/exloom-doc-patterns; rpcommit patterns
printf '@startuml\n' > docs/architecture/flow.puml; rpcommit puml
ok "a patterns file committed after the review exempts nothing" "$(rpchk)" "2"
git reset -q --hard "$RPOK"
printf '*.puml\n' > .claude/exloom-doc-patterns; rpcommit patterns
rpapprove
printf '@startuml\n' > docs/architecture/flow.puml; rpcommit puml
ok "a committed patterns file in place at review adds the type" "$(rpchk)" "0"
printf 'x: 1\n' > docs/architecture/deploy.yaml; rpcommit yaml
ok "...and nothing else" "$(rpchk)" "2"

section "open criticals come from each reviewer's latest pass; commentary is not a finding"

subrepo opencrit
OCC=".claude/reviews/feat/plan.md"; OCF=".claude/reviews/feat/plan.verdicts/l1-reviewer.findings.jsonl"
mkdir -p .claude/reviews/feat; printf '# c\n\n## Rulings\n' > "$OCC"
printf 'l1\nl2\nl3\n' > src/a.go; git add -A >/dev/null 2>&1; git commit -qm a >/dev/null 2>&1
ocfeed() {
  python3 -c "
import json,sys
print(json.dumps({'session_id':'s','hook_event_name':'SubagentStop','agent_id':'a1',
 'agent_type':'exloom:l1-reviewer','last_assistant_message':sys.argv[1]}))" "$1" \
  | bash "$HOOKS_ABS/record-reviewer-verdict.sh" >/dev/null 2>&1
  git add -A >/dev/null 2>&1; git commit -qm receipt >/dev/null 2>&1
}
ocfix() { printf '%s\n' "$1" >> src/a.go; git add -A >/dev/null 2>&1; git commit -qm fix >/dev/null 2>&1; git rev-parse HEAD; }
OC0="$(git rev-parse HEAD)"
ocfeed 'VERDICT: REJECTED (1 items)
## Critical (must fix before merge)
- src/a.go:1 — IN-SCOPE — null dereference
The caller in src/a.go:3 was read for context and is fine.
ROUND NEEDED AFTER FIX: YES'
ok "a sentence under a severity heading is not a finding" "$(grep -c 'src/a.go:3' "$OCF")" "0"
OC1="$(ocfix f1)"
ocfeed "VERDICT: REJECTED (1 items)
MODE: VERIFY ${OC0}..${OC1}
## Previous findings
- src/a.go:1 — NOT ADDRESSED: still dereferences null
ROUND NEEDED AFTER FIX: YES"
OC2="$(ocfix f2)"
ocfeed "VERDICT: REJECTED (1 items)
MODE: VERIFY ${OC1}..${OC2}
## Previous findings
- src/a.go:1 — NOT ADDRESSED: the null path is still reachable
- see src/a.go:3, a critical-looking call that is fine
The critical branch at src/a.go:2 is now guarded by the check the fix added.
ROUND NEEDED AFTER FIX: YES"
ok "round 3: an explanatory sentence is not a finding" \
   "$(grep "\"head\":\"${OC2}\"" "$OCF" | grep -c 'src/a.go:2')" "0"
ok "round 3: in verify mode a previous-findings line without NOT ADDRESSED is not a finding" \
   "$(grep "\"head\":\"${OC2}\"" "$OCF" | grep -c 'src/a.go:3')" "0"
ok "round 3: the NOT ADDRESSED critical is the one open" "$(exloom_open_criticals "$OCC" HEAD)" "1"
OC3="$(ocfix f3)"
ocfeed 'VERDICT: APPROVED
ROUND NEEDED AFTER FIX: NO'
ok "then an approval with no findings leaves nothing open" "$(exloom_open_criticals "$OCC" HEAD)" "0"
ok "...and no open cites" "$(exloom_open_critical_cites "$OCC" HEAD)" ""

subrepo opencrit2
OCC=".claude/reviews/feat/plan.md"; mkdir -p .claude/reviews/feat; printf '# c\n\n## Rulings\n' > "$OCC"
printf 'l1\nl2\n' > src/a.go; git add -A >/dev/null 2>&1; git commit -qm a >/dev/null 2>&1
OC0="$(git rev-parse HEAD)"
ocfeed 'VERDICT: REJECTED (1 items)
## Critical (must fix before merge)
- src/a.go:1 — IN-SCOPE — null dereference
ROUND NEEDED AFTER FIX: YES'
OC1="$(ocfix f1)"
ocfeed "VERDICT: APPROVED
MODE: VERIFY ${OC0}..${OC1}
## Previous findings
- src/a.go:1 — ADDRESSED
ROUND NEEDED AFTER FIX: NO"
ok "a critical the latest pass marked ADDRESSED is not open" "$(exloom_open_criticals "$OCC" HEAD)" "0"

section "the bypass leaves a trace"

# EXLOOM_REVIEW_SKIP turns the gate off unconditionally, and should. But an
# announcement on stderr scrolls past, so without a committed trace nothing can
# afterwards say which changes shipped around the gate — not a person reading the
# repo, and not CI.
subrepo bypassreceipt
printf 'x\n' > f.txt
git add -A >/dev/null 2>&1; git commit -qm f >/dev/null 2>&1
BP=".claude/reviews/$(git rev-parse --abbrev-ref HEAD).bypass.json"

PUSH_JSON='{"session_id":"s","hook_event_name":"PreToolUse","tool_name":"Bash","tool_input":{"command":"git push"}}'
printf '%s' "$PUSH_JSON" | EXLOOM_REVIEW_SKIP=1 bash "$HOOKS_ABS/block-unverified-push.sh" >/dev/null 2>&1
ok "the bypass still allows the push" "$?" "0"
ok "...and writes a receipt" "$([[ -f "$BP" ]] && echo yes || echo no)" "yes"
ok "...naming the commit it let through" \
   "$(grep -c "$(git rev-parse HEAD)" "$BP" 2>/dev/null | head -1)" "1"
ok "...and the action, not just that something happened" \
   "$(grep -c '"action":"push:Bash"' "$BP" 2>/dev/null | head -1)" "1"
ok "...and who did it" \
   "$(grep -c '"by":"[^"]' "$BP" 2>/dev/null | head -1)" "1"
ok "...by git user name, not email" "$(grep -c '"by":"t"' "$BP" 2>/dev/null | head -1)" "1"

# One line per bypass. Two skips on one branch is two facts, and collapsing them
# would hide the second.
printf '%s' "$PUSH_JSON" | EXLOOM_REVIEW_SKIP=1 bash "$HOOKS_ABS/block-unverified-push.sh" >/dev/null 2>&1
ok "...appended, so a second bypass is not hidden by the first" \
   "$(wc -l < "$BP" | tr -d ' ')" "2"

# The verdict-write protection is the bypass most worth recording: it lifts the
# one control that makes a receipt evidence rather than an author-written file.
VJ='{"session_id":"s","hook_event_name":"PreToolUse","tool_name":"Write","tool_input":{"file_path":".claude/reviews/x.verdicts/l1-reviewer.json","content":"{}"}}'
printf '%s' "$VJ" | EXLOOM_REVIEW_SKIP=1 bash "$HOOKS_ABS/protect-verdicts.sh" >/dev/null 2>&1
ok "a bypassed verdict write is recorded too" \
   "$(grep -c '"action":"verdict-write' "$BP" 2>/dev/null | head -1)" "1"

# A repo that never opted in must stay untouched — exloom writes nothing into a
# repo that did not ask for the gate, bypass or no bypass.
rm -f .claude/exloom-gate.enabled "$BP"
printf '%s' "$PUSH_JSON" | EXLOOM_REVIEW_SKIP=1 bash "$HOOKS_ABS/block-unverified-push.sh" >/dev/null 2>&1
ok "no receipt in a repo with the gate off" "$([[ -f "$BP" ]] && echo yes || echo no)" "no"

section "the status line judges coverage the way the GATE does"

# A status line stricter than the check it reports on sends people to re-run a
# reviewer the gate is content with. Once its demands are known to be inflated,
# the ones that are real stop being read too.
subrepo statusline
SVD=".claude/reviews/feat/s.verdicts"; SCL=".claude/reviews/feat/s.md"
mkdir -p "$SVD"
printf 'Tier: 1\n' > "$SCL"
printf 'x\n' > code.txt
git add -A >/dev/null 2>&1; git commit -qm code >/dev/null 2>&1
REVIEWED="$(git rev-parse HEAD)"
printf '{"agent":"l1-reviewer","subagent_type":"exloom:l1-reviewer","head":"%s","verdict":"APPROVED","round_needed":"NO","at":"2026-01-01T00:00:00Z","session":"s"}\n' \
  "$REVIEWED" > "$SVD/l1-reviewer.json"
git add -A >/dev/null 2>&1; git commit -qm receipt >/dev/null 2>&1

# The checklist commit moves the tip. Nothing the reviewer saw has changed, so an
# exact-tip match reports a re-run the gate does not want.
ok "an approval survives a checklist-only commit on top of it" \
   "$(exloom_gate_status "feat/s" "$(git rev-parse HEAD)" 2>&1 | grep -c 'covers an earlier commit')" "0"

printf 'y\n' >> code.txt
git add -A >/dev/null 2>&1; git commit -qm more >/dev/null 2>&1
ok "...but real code landing after it does report stale" \
   "$(exloom_gate_status "feat/s" "$(git rev-parse HEAD)" 2>&1 | grep -c 'covers an earlier commit')" "1"

printf '{"agent":"l1-reviewer","subagent_type":"exloom:l1-reviewer","head":"%s","dispatch":true,"at":"2026-01-01T00:00:00Z","session":"s"}\n' \
  "$(git rev-parse HEAD)" > "$SVD/l1-reviewer.json"
git add -A >/dev/null 2>&1; git commit -qm launch >/dev/null 2>&1
ok "a launch is reported as a launch, not as coverage" \
   "$(exloom_gate_status "feat/s" "$(git rev-parse HEAD)" 2>&1 | grep -c 'never reached exloom')" "1"

printf '{"agent":"l1-reviewer","subagent_type":"exloom:l1-reviewer","head":"%s","verdict":"REJECTED","round_needed":"YES","at":"2026-01-01T00:00:00Z","session":"s"}\n' \
  "$(git rev-parse HEAD)" > "$SVD/l1-reviewer.json"
git add -A >/dev/null 2>&1; git commit -qm rej >/dev/null 2>&1
ok "a rejection is reported as a rejection, not as a stale receipt" \
   "$(exloom_gate_status "feat/s" "$(git rev-parse HEAD)" 2>&1 | grep -c 'did NOT approve')" "1"

section "the early exit lets through every input a hook must judge"

. "$HOOKS_ABS/prefilter.sh"
pf() { if "$1" "$2"; then echo pass; else echo exit; fi; }
bashp() { printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$1"; }

ok "receipts: a cd into the verdicts folder, then a relative redirect" \
   "$(pf exloom_may_touch_receipts "$(bashp 'cd .claude/reviews/feat/x.verdicts && echo {} > l1-reviewer.json')")" "pass"
ok "receipts: node -e writing a receipt" \
   "$(pf exloom_may_touch_receipts "$(bashp "node -e \\\"require('fs').writeFileSync('.claude/reviews/x.verdicts/l1-reviewer.json','{}')\\\"")")" "pass"
ok "receipts: git apply of a patch that names no path" \
   "$(pf exloom_may_touch_receipts "$(bashp 'git apply fix.patch')")" "pass"
ok "receipts: git clean -fdx" "$(pf exloom_may_touch_receipts "$(bashp 'git clean -fdx')")" "pass"
ok "receipts: a Windows path to a receipt" \
   "$(pf exloom_may_touch_receipts '{"tool_name":"Write","tool_input":{"file_path":"C:\\r\\.claude\\reviews\\x.verdicts\\l1-reviewer.json"}}')" "pass"
ok "receipts: deleting the gate marker" \
   "$(pf exloom_may_touch_receipts "$(bashp 'rm .claude/exloom-gate.enabled')")" "pass"
ok "receipts: an ordinary command exits early" \
   "$(pf exloom_may_touch_receipts "$(bashp 'ls -la && git status')")" "exit"

ok "push: git -C dir push" "$(pf exloom_may_publish "$(bashp 'git -C ../x push origin HEAD')")" "pass"
ok "push: gh pr create" "$(pf exloom_may_publish "$(bashp 'gh pr create --fill')")" "pass"
for t in mcp__github__push_files mcp__github__create_pull_request mcp__github__merge_pull_request mcp__github__delete_file mcp__github__create_or_update_file; do
  ok "push: $t" "$(pf exloom_may_publish "{\"tool_name\":\"$t\",\"tool_input\":{}}")" "pass"
done
ok "push: an ordinary command exits early" "$(pf exloom_may_publish "$(bashp 'ls -la && git status')")" "exit"

ok "receipt hook: a SubagentStop from a reviewer" \
   "$(pf exloom_may_be_reviewer '{"hook_event_name":"SubagentStop","agent_type":"exloom:security-auditor"}')" "pass"
ok "receipt hook: a Task dispatch of a reviewer" \
   "$(pf exloom_may_be_reviewer '{"tool_name":"Agent","tool_input":{"subagent_type":"exloom:adversarial-reviewer"}}')" "pass"
ok "receipt hook: any other agent exits early" \
   "$(pf exloom_may_be_reviewer '{"hook_event_name":"SubagentStop","agent_type":"Explore"}')" "exit"

section "exloom runs only its own installed files, never a copy found by search"

# Claude Code substitutes ${CLAUDE_PLUGIN_ROOT} into command and SKILL.md bodies.
# Each block is run three ways: substituted, left literal (an older Claude Code),
# and substituted to a folder without the file.
EXLOOM_DIR="$(cd "$HOOKS_ABS/.." && pwd)"
OWN="$REG/own"; EMPTY="$REG/empty-root"; DHOME="$REG/decoy-home"; MARKS="$REG/marks"; RUNIN="$REG/runin"
DECOY="$DHOME/.claude/plugins/cache/zz-other/exloom/99.9.9"
LITERAL_DIR="$RUNIN/"'${CLAUDE_PLUGIN_ROOT}'
mkdir -p "$OWN/hooks" "$OWN/scripts" "$EMPTY" "$MARKS" "$RUNIN"
for d in "$DECOY" "$LITERAL_DIR"; do mkdir -p "$d/hooks" "$d/scripts"; done
for f in hooks/lib.sh scripts/prove-change-is-tested.sh scripts/record-smoke.sh scripts/lint-spec.sh; do
  printf 'touch "%s/own"; command_not_found_handle() { return 0; }\n' "$MARKS" > "$OWN/$f"
  printf 'touch "%s/decoy"\n' "$MARKS" > "$DECOY/$f"
  printf 'touch "%s/decoy"\n' "$MARKS" > "$LITERAL_DIR/$f"
done
(cd "$RUNIN" && git init -q -b feat/x . && git config user.email t@e.com && git config user.name t \
  && git commit -q --allow-empty -m base) >/dev/null 2>&1
blocks() {   # blocks <file> -> each ```bash block naming CLAUDE_PLUGIN_ROOT, NUL-terminated
  tr -d '\r' < "$1" | awk '/^[[:space:]]*```bash/{on=1;b="";next}
    on&&/^[[:space:]]*```/{on=0; if(b~/CLAUDE_PLUGIN_ROOT/) printf "%s%c",b,0; next} on{b=b $0 "\n"}'
}
CPR_LIT='${CLAUDE_PLUGIN_ROOT}'
runblk() {   # runblk <block> <root|RAW> -> "rc own decoy said"
  local b="$1" rc
  [[ "$2" == RAW ]] || b="${b//"$CPR_LIT"/$2}"
  b="$(printf '%s' "$b" | sed 's/<[^>]*>/x/g')"
  rm -f "$MARKS/own" "$MARKS/decoy"
  (cd "$RUNIN" && HOME="$DHOME" CLAUDE_PLUGIN_ROOT="$DECOY" bash -c "$b" >"$REG/blk.out" 2>&1); rc=$?
  [[ $rc -eq 0 ]] || rc=1
  echo "$rc $([[ -f $MARKS/own ]] && echo own || echo -) $([[ -f $MARKS/decoy ]] && echo decoy || echo -) $(grep -q 'exloom:.*missing' "$REG/blk.out" && echo said || echo -)"
}
NBLK=0; BAD=""
for f in "$EXLOOM_DIR"/commands/*.md "$EXLOOM_DIR"/agents/*.md "$EXLOOM_DIR"/skills/*/SKILL.md; do
  while IFS= read -r -d '' blk; do
    NBLK=$((NBLK + 1)); n="${f#"$EXLOOM_DIR"/}#$NBLK"
    r="$(runblk "$blk" "$OWN")";   [[ "$r" == "0 own - -" ]]  || BAD+=" $n:own=[$r]"
    r="$(runblk "$blk" RAW)";      [[ "$r" == "1 - - said" ]] || BAD+=" $n:literal=[$r]"
    r="$(runblk "$blk" "$EMPTY")"; [[ "$r" == "1 - - said" ]] || BAD+=" $n:missing=[$r]"
  done < <(blocks "$f")
done
ok "every block that runs an exloom file names it through \${CLAUDE_PLUGIN_ROOT}" "$NBLK" "10"
ok "...uses exloom's own file while a decoy that sorts higher sits in the plugins folder, and stops with a message when the path is literal or the file is missing" "$BAD" ""

REPO_ROOT="$(cd "$EXLOOM_DIR/../.." && pwd)"
SEARCH_RE='find[[:space:]][^|]*\.claude/plugins|sort -V|find it like the library'
printf '%s\n' "LIB=\"\$(find ~/.claude/plugins -path '*exloom*/hooks/lib.sh' | sort -V | tail -1)\"" > "$REG/search-probe.md"
ok "the search guard matches the old lookup" "$(grep -lE "$SEARCH_RE" "$REG/search-probe.md" | wc -l | tr -d ' ')" "1"
ok "no file in the repository searches the plugins folder for a copy" \
   "$(grep -rlE --exclude-dir=.git "$SEARCH_RE" "$REPO_ROOT" | grep -v 'scripts/test-exloom-gate\.sh$' | tr '\n' ' ')" ""
ok "supporting files are not substituted, so only commands, agents and SKILL.md assign \${CLAUDE_PLUGIN_ROOT}" \
   "$(grep -rlF "'$CPR_LIT'" "$EXLOOM_DIR" | grep -vE '/(commands|agents)/[^/]*\.md$|/skills/[^/]*/SKILL\.md$' | tr '\n' ' ')" ""

section "the push gate covers git, PR creation and the GitHub server's tools, nothing else"

PJ="$(cd "$HOOKS_ABS/../.claude-plugin" && pwd)/plugin.json"
PM="$(python3 -c "import json,sys
for e in json.load(open(sys.argv[1]))['hooks']['PreToolUse']:
    if any('block-unverified-push.sh' in h['command'] for h in e['hooks']): print(e['matcher'])" "$PJ" | tr -d '\r')"
# Claude Code compares a matcher of letters, digits, _, -, spaces, | and , as a list of exact names.
ok "the push matcher is a list of exact tool names, not a pattern" \
   "$([[ "$PM" =~ ^[A-Za-z0-9_|,\ -]+$ ]] && echo exact || echo pattern)" "exact"
fires() { local n x; IFS='|,' read -ra n <<< "$PM"; for x in "${n[@]}"; do x="${x// /}"; [[ "$x" == "$1" ]] && { echo yes; return; }; done; echo no; }
ok "Bash is gated" "$(fires Bash)" "yes"
for p in mcp__github__ mcp__plugin_github_github__; do
  for t in push_files create_or_update_file delete_file create_pull_request merge_pull_request; do
    ok "$p$t is gated" "$(fires "$p$t")" "yes"
  done
done
for t in mcp__notes__delete_file mcp__drive__create_or_update_file mcp__gitlab__push_files mcp__x__create_pull_request; do
  ok "$t is not gated" "$(fires "$t")" "no"
done
subrepo mcpgate
printf 'x\n' > src/a.go; git add -A >/dev/null 2>&1; git commit -qm a >/dev/null 2>&1
pushrc() { printf '%s' "$1" | bash "$HOOKS_ABS/block-unverified-push.sh" >/dev/null 2>&1; echo $?; }
ok "git push is still blocked" "$(pushrc '{"tool_name":"Bash","tool_input":{"command":"git push origin feat/plan"}}')" "2"
ok "the GitHub server's push is still blocked" "$(pushrc '{"tool_name":"mcp__github__push_files","tool_input":{}}')" "2"
ok "the GitHub plugin's PR tool is still blocked" "$(pushrc '{"tool_name":"mcp__plugin_github_github__create_pull_request","tool_input":{}}')" "2"
ok "another connector's delete_file passes, even when its content says git push" \
   "$(pushrc '{"tool_name":"mcp__notes__delete_file","tool_input":{"note":"then git push origin main"}}')" "0"

section "a block tells the user about the bypass; it never tells Claude to switch the gate off"

subrepo blockmsg
printf 'x\n' > src/a.go; git add -A >/dev/null 2>&1; git commit -qm a >/dev/null 2>&1
PUSHMSG="$(printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git push"}}' | EXLOOM_VERBOSE=1 bash "$HOOKS_ABS/block-unverified-push.sh" 2>&1 >/dev/null)"
VERMSG="$(printf '%s' '{"tool_name":"Write","tool_input":{"file_path":".claude/reviews/feat/plan.verdicts/l1-reviewer.json","content":"{}"}}' | bash "$HOOKS_ABS/protect-verdicts.sh" 2>&1 >/dev/null)"
for m in PUSHMSG VERMSG; do
  ok "$m: says no setting may be changed to get past it" "$(grep -c 'Do not change any setting' <<< "${!m}")" "1"
  ok "$m: says only the user can choose the bypass" "$(grep -c 'Only the user can choose' <<< "${!m}")" "1"
  ok "$m: does not tell Claude to set the bypass" "$(grep -ciE 'set EXLOOM_REVIEW_SKIP=1 in your|"env"\), then retry' <<< "${!m}")" "0"
done
ok "no command or skill tells Claude to set the bypass itself" \
   "$(grep -rnE 'EXLOOM_REVIEW_SKIP.*settings\.json|settings\.json.*EXLOOM_REVIEW_SKIP' "$HOOKS_ABS/../commands" "$HOOKS_ABS/../skills" "$HOOKS_ABS/../agents" | grep -vc 'never set it yourself')" "0"

section "the reviewer report held while it waits is never committed"

subrepo heldreport
HV=".claude/reviews/feat/plan.verdicts"; mkdir -p "$HV"; printf '# c\n' > .claude/reviews/feat/plan.md; : > .claude/reviews/feat/plan.ledger.md
printf 'x\n' > src/a.go; git add -A >/dev/null 2>&1; git commit -qm a >/dev/null 2>&1
python3 -c "import json
print(json.dumps({'session_id':'s','hook_event_name':'PreToolUse','tool_name':'Agent','tool_use_id':'h1',
 'tool_input':{'subagent_type':'exloom:l1-reviewer','prompt':'Review branch feat/plan at x. Diff: git diff m...x'}}))" \
  | bash "$HOOKS_ABS/guard-reviewer-dispatch.sh" >/dev/null 2>&1
python3 -c "import json
print(json.dumps({'session_id':'s','hook_event_name':'SubagentStop','agent_id':'hag','agent_type':'exloom:l1-reviewer',
 'last_assistant_message':'VERDICT: APPROVED\nROUND NEEDED AFTER FIX: NO'}))" | bash "$HOOKS_ABS/record-reviewer-verdict.sh" >/dev/null 2>&1
ok "the report is held while the dispatch is unmapped" "$([[ -f "$HV/held/hag.json" ]] && echo held)" "held"
RCADD="$(tr -d '\r' < "$HOOKS_ABS/../commands/review-complete.md" | grep -m1 '^git add .claude/reviews/<branch>.md' | sed 's#<branch>#feat/plan#g')"
ok "/review-complete has a git add line to run" "$([[ -n "$RCADD" ]] && echo yes)" "yes"
printf 'y\n' >> .claude/reviews/feat/plan.md
bash -c "$RCADD" >/dev/null 2>&1
ok "/review-complete's git add stages the checklist" "$(git diff --cached --name-only | grep -c 'feat/plan.md$')" "1"
ok "/review-complete's git add leaves it out" "$(git diff --cached --name-only | grep -c '/held/')" "0"
git add .claude/reviews >/dev/null 2>&1
ok "/exloom's commit of .claude/reviews leaves it out" "$(git diff --cached --name-only | grep -c '/held/')" "0"
git reset -q
python3 -c "import json
print(json.dumps({'session_id':'s','hook_event_name':'PostToolUse','tool_name':'Agent','tool_use_id':'h1',
 'tool_input':{'subagent_type':'exloom:l1-reviewer','prompt':'Review branch feat/plan'},
 'tool_response':{'content':[{'type':'text','text':'VERDICT: APPROVED'}],'agentId':'hag'}}))" | bash "$HOOKS_ABS/record-reviewer-verdict.sh" >/dev/null 2>&1
ok "once the receipt is written the held folder is gone" "$([[ -e "$HV/held" ]] && echo left || echo gone)" "gone"
ok "...and the receipt is there" "$(grep -c '"verdict":"APPROVED"' "$HV/l1-reviewer.json")" "1"

section "the session-start note appears only where exloom is set up"

ss() { (cd "$1" && bash "$HOOKS_ABS/session-start.sh" </dev/null 2>/dev/null); }
mkdir -p "$REG/nogit"
ok "outside a git repository: nothing" "$(ss "$REG/nogit")" ""
subrepo ssoff; rm -f .claude/exloom-gate.enabled
ok "a repository without the gate: nothing" "$(ss "$PWD")" ""
: > .claude/exloom-gate.enabled
ok "a repository with the gate on: the note" "$(ss "$PWD" | grep -c 'exloom')" "1"

section "capturing-learnings asks first and opens no PR to exloom"

CLD="$HOOKS_ABS/../skills/capturing-learnings"
ok "it starts only when the user asks to record a lesson" \
   "$(sed -n 's/^description: //p' "$CLD/SKILL.md" | grep -ciE '^Use when the user asks to record')" "1"
ok "...and never automatically" "$(sed -n 's/^description: //p' "$CLD/SKILL.md" | grep -ci 'automatic')" "0"
ok "it shows the CLAUDE.md change and waits for approval" "$(grep -c 'approves' "$CLD/SKILL.md" | awk '{print ($1>0)?"yes":"no"}')" "yes"
ok "it no longer edits CLAUDE.md directly" "$(grep -ci 'directly' "$CLD/SKILL.md")" "0"
ok "nothing proposes changes to exloom's own repository" \
   "$(grep -rlE 'plugins/exloom|PRs to the exloom|plugin maintainer' "$CLD" | wc -l | tr -d ' ')" "0"
ok "a PR goes only to a repository the user names" "$(grep -c 'repository the user names' "$CLD/SKILL.md")" "1"

cd "$WORK" || exit 1

echo
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]] || exit 1
echo "All exloom review-gate tests passed."
