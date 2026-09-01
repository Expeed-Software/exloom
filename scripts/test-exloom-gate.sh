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

LIB="plugins/exloom/hooks/lib.sh"
HOOKS="plugins/exloom/hooks"

if [[ ! -f "$LIB" ]]; then
  echo "FAIL: run this from the repository root (no $LIB)"
  exit 1
fi

LIB_ABS="$(cd "$(dirname "$LIB")" && pwd)/$(basename "$LIB")"
HOOKS_ABS="$(cd "$HOOKS" && pwd)"
WORK="${TMPDIR:-/tmp}/exloom-gate-fixture.$$"
# Scratch root for the per-section throwaway repos. Previously declared inside
# the plan-gate section; that section is gone, and every later section that
# builds a fixture repo needs it, so it lives here now.
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

cleanup() { cd / 2>/dev/null; rm -rf "$WORK"; }
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

echo "== tier derivation (declared tier cannot go below this) =="

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

# `auth` must match as a WORD, not a substring. A bare `auth` matched
# `authoring-claude-md`, so three markdown docs forced Tier 3 — and tier has no
# escape hatch, making the gate unsatisfiable. Found by running exloom's own
# /review-init against this branch.
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

echo "== verdict receipts (dispatch is recorded, not claimed) =="

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
printf '{"agent":"l1-reviewer","head":"%s","at":"now","session":"s"}\n' "$REVIEWED" > "$VD/l1-reviewer.json"
git add -A; git commit -qm receipt
exloom_check_verdicts "$CHECK" 1 HEAD "$REVIEWED" "test" 2>/dev/null
ok "receipt covering the reviewed commit -> allowed" "$?" "0"

exloom_check_verdicts "$CHECK" 2 HEAD "$REVIEWED" "test" 2>/dev/null
ok "tier 2 with only the L1 receipt -> blocked" "$?" "2"

# A checklist-only commit must not invalidate a real review...
printf 'note\n' >> "$CHECK"; git add -A; git commit -qm checklist-only
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

echo "== staleness by change class (a typo fix must not demand another round) =="

# The gate invalidated a review on ANY code change. Combined with fixing findings
# that guarantees another round after every round — no terminating state. One real
# branch reached round 9 with nothing outstanding but stale comments and test
# parameter names, and the gate would still have demanded a codepoint sweep.
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

# ...but only where indentation is not syntax. The blank-line fixture above was
# the ONLY case exercising the -w rule, so it pinned "any change `git diff -w`
# cannot see" as the spec. In Python a de-indent moves a statement out of an `if`
# branch; in YAML it re-parents a key. Both are behavioural, both are invisible
# to -w, and both would have left a stale receipt valid over changed behaviour.
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

echo "== code-reviewer verdicts (a REJECTED review does not satisfy the gate) =="

# Same rule as the plan gate, applied to the push/done gate. The migration risk
# here is real: receipts written before verdicts existed have no "verdict" key,
# and refusing those would block every in-flight branch the moment this version
# lands. Legacy receipts are therefore grandfathered, and that is tested.
git checkout -q -b feat/verd main
CV=".claude/reviews/feat/verd.md"; mkdir -p "$(dirname "$CV")"
CVD="$(exloom_verdict_dir "$CV")"; mkdir -p "$CVD"
printf 'a\n' > src/v.go; git add -A; git commit -qm v
RV="$(git rev-parse HEAD)"
# Receipts reach the consumer the way they reach it in production: minted by the
# PRODUCER from a reviewer report. Hand-writing them here meant
# exloom_check_verdicts was only ever shown receipts record-reviewer-verdict.sh
# does not write, so receipt-shape drift between the two was invisible — and the
# suite performed the exact forgery this branch exists to prevent.
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
# Only for receipts the CURRENT producer cannot write: the 2.0.0 shape, which is
# the whole point of the grandfather clause. Anything the producer can emit must
# go through mint().
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

# Byte-for-byte the shape exloom 2.0.0 actually wrote — every key, in order,
# copied from a live receipt in apptor-cms. A simplified stand-in would pass
# while the real thing failed on a key the parser did not expect.
put_legacy "{\"agent\":\"l1-reviewer\",\"subagent_type\":\"exloom:l1-reviewer\",\"head\":\"$RV\",\"at\":\"2026-08-28T18:24:11Z\",\"session\":\"7bc2e35f-7c0f-4f69-b7f2-bbea28ffe7a5\"}"
ok "legacy 2.0.0 receipt (real shape, no verdict key) -> still allowed" "$(chk)" "0"

# An APPROVED receipt from an EARLIER commit must not vouch for a REJECTED
# review of the current one. Verdict and commit are read from the same line.
OLD="$RV"
printf 'b\n' > src/v.go; git add -A; git commit -qm v2
NEW="$(git rev-parse HEAD)"
printf '{"agent":"l1-reviewer","head":"%s","verdict":"APPROVED"}\n{"agent":"l1-reviewer","head":"%s","verdict":"REJECTED"}\n' "$OLD" "$NEW" > "$CVD/l1-reviewer.json"
git add -A; git commit -qm r2
ok "old APPROVED does not vouch for a new REJECTED" "$(chk)" "2"
git checkout -q feat/x

echo "== proof receipt (the tested-ness check cannot be skipped by forgetting) =="

git checkout -q -b feat/proof main
CP=".claude/reviews/feat/proof.md"; mkdir -p "$(dirname "$CP")"
CPD="$(exloom_verdict_dir "$CP")"; mkdir -p "$CPD"
printf 'a\n' > src/p.go; git add -A; git commit -qm p
RP="$(git rev-parse HEAD)"
pchk() { exloom_check_proof "$CP" HEAD "$(git rev-parse HEAD)" "test" 2>/dev/null; echo $?; }

ok "no proof receipt -> blocked" "$(pchk)" "2"

printf '{"check":"change-is-tested","result":"NOT_PROVED","head":"%s"}\n' "$RP" > "$CPD/proof.json"
git add -A; git commit -qm p2
ok "NOT_PROVED receipt -> blocked" "$(pchk)" "2"

printf '{"check":"change-is-tested","result":"PROVED","head":"%s"}\n' "$RP" > "$CPD/proof.json"
git add -A; git commit -qm p3
ok "PROVED receipt covering the commit -> allowed" "$(pchk)" "0"

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

echo "== protect-verdicts hook (a receipt cannot be written by hand) =="

deny() { printf '%s' "$1" | bash "$HOOKS_ABS/protect-verdicts.sh" >/dev/null 2>&1; echo $?; }

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

echo "== protection: state file and wholesale deletion =="

# The freeze was liftable by writing one JSON file: `.claude/*` was exempt in the
# execution gate and protect-verdicts matched only `.verdicts/`. And `rm -rf
# .claude/reviews` / `git clean -fdx` name neither, so both destroyed every
# receipt, the round counter and the findings ledger unopposed.
ok "writing the review STATE file -> denied"   "$(deny '{"tool_name":"Write","tool_input":{"file_path":".claude/reviews/feat/x.state"}}')" "2"
ok "editing the CHECKLIST is still allowed"   "$(deny '{"tool_name":"Edit","tool_input":{"file_path":".claude/reviews/feat/x.md"}}')" "0"
ok "rm -rf of the reviews tree -> denied"   "$(deny '{"tool_name":"Bash","tool_input":{"command":"rm -rf .claude/reviews"}}')" "2"
ok "git clean -fdx -> denied"   "$(deny '{"tool_name":"Bash","tool_input":{"command":"git clean -fdx"}}')" "2"
ok "reading the state file -> allowed"   "$(deny '{"tool_name":"Bash","tool_input":{"command":"cat .claude/reviews/feat/x.state"}}')" "0"

echo "== remediation commands in block messages must actually run =="

# ${CLAUDE_PLUGIN_ROOT} is interpolated into plugin.json by the harness and is NOT
# set in the Bash environment, so every sanctioned escape printed to a blocked
# session failed with "No such file or directory" — leaving EXLOOM_REVIEW_SKIP,
# which the same message advertises, as the only reachable option.
# Scoped to EVERY hook and command, not just the files already fixed — the first
# version of this test grepped only the two files the fix touched, so it could
# never have caught a third. That is the same "fix the instance" defect the whole
# branch is about, committed inside the regression test for it.
ok "no shipped file tells a session to run \${CLAUDE_PLUGIN_ROOT}"   "$(grep -rlE '(bash|sh|cat|find|cp) [^
]*\\$\{CLAUDE_PLUGIN_ROOT\}' "$HOOKS_ABS" "$HOOKS_ABS/../commands" "$HOOKS_ABS/../scripts" 2>/dev/null | wc -l | tr -d ' ')" "0"
ok "prove-change-is-tested.sh exists where the message points"   "$([[ -f "$HOOKS_ABS/../scripts/prove-change-is-tested.sh" ]] && echo yes || echo no)" "yes"

echo "== record-reviewer-verdict hook (a real dispatch writes one) =="

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
ok "unprefixed reviewer name also matches" "$([[ -f "$RVD/l1-reviewer.json" ]] && echo yes || echo no)" "yes"

record '{"tool_name":"Read","tool_input":{"file_path":"x"}}'
ok "non-Task tool ignored" "$(ls "$RVD" | wc -l | tr -d ' ')" "2"

# The whole gate is opt-in; with the marker gone, neither hook does anything.
mv .claude/exloom-gate.enabled .claude/gate-off
rm -rf "$RVD"
record '{"tool_name":"Task","session_id":"s","tool_input":{"subagent_type":"exloom:l1-reviewer"}}'
ok "gate off -> no receipt written" "$([[ -d "$RVD" ]] && echo yes || echo no)" "no"
ok "gate off -> receipt writes allowed" \
  "$(deny '{"tool_name":"Write","tool_input":{"file_path":".claude/reviews/feat/x.verdicts/l1-reviewer.json"}}')" "0"
mv .claude/gate-off .claude/exloom-gate.enabled

echo "== verdicts (a dispatch is not a review) =="

# The receipt used to record only that a reviewer RAN. A REJECTED report opened
# the gate exactly like an approval, so the mechanism enforced attendance.
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

echo "== classifier: real code the old version called non-behavioural =="

# Every case below was reproduced by review as a FALSE non-behavioural, which
# kept a stale reviewer receipt "covering" a changed commit.
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

echo "== reviewer output parsed as the shipped agents actually print it =="

# Fixtures copied from agents/l1-reviewer.md's own "Output format — strict" block.
# The previous fixtures put severity and cite on ONE line — a shape no agent emits —
# so the parser passed its tests while recording nothing from a real report.
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

echo "== round-2 regressions (every one was a defect a FIX introduced) =="

# Each case reproduces something that broke while closing round 1. On this branch a
# fix has been worse than the bug more than once, so these are permanent guards.

git checkout -q -b feat/r2 main
mkdir -p r2
r2beh() { git add -A >/dev/null 2>&1; git commit -qm "$1" >/dev/null 2>&1
          exloom_diff_is_behavioural "$2" HEAD && echo yes || echo no; }

# Pointer dereference was classified as a javadoc continuation — a sibling of the
# `#define` hole, in the same function, introduced by the fix for it.
printf 'int f(int *o){ *o = 1; return 0; }\n' > r2/d.c
git add -A >/dev/null 2>&1; git commit -qm dbase >/dev/null 2>&1; RB="$(git rev-parse HEAD)"
printf 'int f(int *o){ *o = 999; return 0; }\n' > r2/d.c
ok "pointer deref -> behavioural" "$(r2beh deref "$RB")" "yes"

printf '/**\n * explains f\n */\nint f(void){ return 1; }\n' > r2/j.java
git add -A >/dev/null 2>&1; git commit -qm jbase >/dev/null 2>&1; RB="$(git rev-parse HEAD)"
printf '/**\n * explains f much better\n */\nint f(void){ return 1; }\n' > r2/j.java
ok "javadoc continuation -> NOT behavioural" "$(r2beh javadoc "$RB")" "no"

# A shell script emitting markdown from a heredoc: the `#` marker treated heredoc
# BODY lines as comments, so exloom mis-classified its own hooks.
printf 'cat <<EOF\n# heading one\nEOF\n' > r2/e.sh
git add -A >/dev/null 2>&1; git commit -qm ebase >/dev/null 2>&1; RB="$(git rev-parse HEAD)"
printf 'cat <<EOF\n# heading TWO CHANGED\nEOF\n' > r2/e.sh
ok "heredoc body in .sh -> behavioural" "$(r2beh heredoc "$RB")" "yes"
git checkout -q feat/x

echo "== verdict decoration: every form an LLM actually emits =="

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

# A heading containing "clean" cleared severity and dropped every finding under it.
rm -rf .claude/reviews
python3 -c "
import json
print(json.dumps({'tool_name':'Task','session_id':'s',
 'tool_input':{'subagent_type':'exloom:l1-reviewer','prompt':'review'},
 'tool_response':[{'type':'text','text':'## Critical (cleanup of stale handlers)\n- src/one.go:4 — real defect\n\nVERDICT: REJECTED (1 items)'}]}))" \
 | bash "$HOOKS_ABS/record-reviewer-verdict.sh" >/dev/null 2>&1
ok "'Critical (cleanup...)' still records findings" \
   "$(grep -c . "$VVD/l1-reviewer.findings.jsonl" 2>/dev/null | head -1)" "1"

echo "== proof: the three-run protocol, which shipped with no fixtures =="

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

echo "== re-find disposition: next-line keyword, and legacy checklists =="

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

echo "== round-3 blockers: forgery, binding, writing ABOUT the guarded path =="

# 1. protect-verdicts matched command TEXT, so a command merely MENTIONING the
#    guarded path was denied. It blocked a comment being written into the hook's own
#    source, then blocked the commit message documenting that block, then blocked
#    this very test three times. Content is now distinguished from targets.
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

# 2. Plan approval was bound to the DISPATCH PROMPT — text written by the party being
#    gated — so "Per <a> and <b>, check the heading style" approved BOTH plans off one
#    cosmetic review. The reviewer's own REVIEWED: line is now authoritative.
subrepo bind
printf '# plan a\n- src/one.go\n' > docs/plans/a.md
printf '# plan b\n- src/two.go\n' > docs/plans/b.md
BVD=".claude/reviews/feat/plan.verdicts"
echo "== a shell redirection is not a refspec =="

# Reported from a real session, hit twice: `git push origin 2>&1` was read as a
# push of a branch named `2>&1`, and the block message told the author to run
# /review-init for a branch that does not exist — an argument-parsing slip that
# reads as a review failure.
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

echo "== SubagentStop: the verdict is captured at COMPLETION =="

# The cause behind the async compensation. PostToolUse fires at launch and has no
# report; SubagentStop fires on completion and carries it verbatim. Payload shape
# below is captured from a real dispatch, not invented:
#   {"hook_event_name":"SubagentStop","agent_type":"exloom:l1-reviewer",
#    "agent_id":"...","last_assistant_message":"...VERDICT: REJECTED (1 items)..."}
# Without this, a REJECTED review was indistinguishable from an approval on a
# live branch — reported from apptor-agents.
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

# The decisive one: a dispatch line and a completion line share a commit. The
# dispatch line has no verdict and used to be grandfathered as passing, which
# would let a REJECTED review through.
SSC=".claude/reviews/feat/plan.md"; printf '# c\n' > "$SSC"
rm -rf .claude/reviews; mkdir -p "$SSV"
printf '%s' '{"session_id":"s","hook_event_name":"PostToolUse","tool_name":"Agent","tool_input":{"subagent_type":"exloom:l1-reviewer"},"tool_response":{"isAsync":true,"status":"async_launched"}}' \
  | bash "$HOOKS_ABS/record-reviewer-verdict.sh" >/dev/null 2>&1
ssfeed 'VERDICT: REJECTED (1 items)'
printf '# c\n' > "$SSC"; git add -A >/dev/null 2>&1; git commit -qm r >/dev/null 2>&1
exloom_check_verdicts "$SSC" 1 HEAD "$(git rev-parse HEAD)" "test" >/dev/null 2>&1
ok "a verdict-less dispatch line does NOT grandfather a REJECTED away" "$?" "2"

# A genuinely old receipt — no verdict anywhere — must still be grandfathered.
rm -rf .claude/reviews; mkdir -p "$SSV"
printf '{"agent":"l1-reviewer","head":"%s","at":"n","session":"s"}\n' "$(git rev-parse HEAD)" > "$SSV/l1-reviewer.json"
git add -A >/dev/null 2>&1; git commit -qm legacy >/dev/null 2>&1
exloom_check_verdicts "$SSC" 1 HEAD "$(git rev-parse HEAD)" "test" >/dev/null 2>&1
ok "a pre-verdict receipt is still grandfathered" "$?" "0"

echo "== ASYNC dispatch: PostToolUse fires at LAUNCH, before any report exists =="

# Captured from a real dispatch, verbatim. On an async launch the payload carries
# no report at all — the reviewer has not run. v4.0.0/v4.0.1 recorded UNKNOWN
# here, which the gate treats as "not approved", so every real dispatch in every
# gate-enabled repo blocked with no path forward.
#
# UNKNOWN must mean "the reviewer stated no verdict" (their omission, blocking).
# It must NOT mean "exloom could not observe one at this event" (our blindness).
# The receipt records what WAS observed: a dispatch. The gate grandfathers that.
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

# And the consequence that matters: it must not block.
ACL=".claude/reviews/feat/plan.md"; mkdir -p "$(dirname "$ACL")"
printf '# c\n' > "$ACL"; git add -A >/dev/null 2>&1; git commit -qm r >/dev/null 2>&1
exloom_check_verdicts "$ACL" 1 HEAD "$(git rev-parse HEAD)" "test" >/dev/null 2>&1
ok "...and a dispatch-only receipt does NOT block the gate" "$?" "0"

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

echo "== payload shape: the field the harness actually sends =="

# The harness delivers a Task result as `tool_response`, a content-block array.
# Every fixture in this suite used to feed `tool_output` as a bare string — a
# shape nothing emits — so the parser was verified against a payload it never
# receives. The fixtures now use the real shape; these two assert the parser
# still accepts both, because the fallback chain is what makes it robust across
# harness versions, and silently losing it would be invisible otherwise.
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

echo "== CONTRACT: every shipped agent's own output block, through the real parser =="

# The class, not the instances. Four rounds of findings were all one shape: the
# producer and the consumer were edited separately and nothing checked they agree.
# This drives EVERY agent's documented Output-format block through the real hook and
# asserts what comes out. It is generated FROM agents/*.md, so an agent whose format
# changes without the parser changing fails here rather than in round 5.

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

for a in $(ls "$HOOKS_ABS/../agents"/*.md | xargs -n1 basename | sed "s/\.md$//"); do
  blk="$(agent_block "$a")"
  ok "$a: has an extractable output block" "$([[ -n "$blk" ]] && echo yes || echo no)" "yes"

  # Its own APPROVED form must parse as APPROVED. An agent that copies its own
  # documented verdict line and gets UNKNOWN is a gate that can never open —
  # which is exactly what plan-reviewer.md did.
  feed "$a" "$(printf '%s\n\nVERDICT: APPROVED\n' "$blk")"
  ok "$a: own block + APPROVED -> APPROVED" "$(vrd "$a")" "APPROVED"

  # And with a cited finding present, at least one finding must be RECORDED.
  # cross-layer-auditor and security-auditor recorded zero because their headings
  # carry no severity word — a blocking re-find gate, structurally inert.
  feed "$a" "$(printf '%s\n\nVERDICT: REJECTED (1 items)\n' "$blk")"
  ok "$a: own block + a cite -> at least one finding recorded" \
     "$([[ "$(fnd "$a")" -ge 1 ]] && echo yes || echo no)" "yes"
done

# The verdict line each agent literally documents must not be self-defeating.
for a in $(ls "$HOOKS_ABS/../agents"/*.md | xargs -n1 basename | sed "s/\.md$//"); do
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

echo "== CONTRACT: every template placeholder is enforced, every alternation is written =="

TPL="$(cd "$(dirname "$LIB_ABS")/../templates" && pwd)/review-checklist.md"
PRE="$(sed -n "s/^  placeholder_re='\(.*\)'$/\1/p" "$LIB_ABS")"
ok "placeholder_re extracted from lib.sh" "$([[ -n "$PRE" ]] && echo yes || echo no)" "yes"

# Every <...> token the template ships must be matched, or the section it guards is
# unenforced — the Tier 3 security Findings field and the all-tiers L1 Resolution
# field were both silently optional.
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

echo "== prove-change-is-tested (author-side, before review) =="

# Modelled directly on real review transcripts: rounds 2..7 were spent on defects
# this check catches before the first commit — a decorative assertion, a missing
# read-path test, and a test task that reported UP-TO-DATE and never ran.
PROVE="$(cd "$(dirname "$LIB_ABS")/../scripts" && pwd)/prove-change-is-tested.sh"

proofrepo() {   # proofrepo <name> <base-test-body> <base-src-body>
  local d="$REG/$1"; rm -rf "$d"; mkdir -p "$d/src" "$d/tests" "$d/.claude"; cd "$d" || return 1
  git init -q -b main . 2>/dev/null
  git config user.email t@e.com; git config user.name t
  # The gate marker and a feature branch are REQUIRED, not decoration:
  # prove-change-is-tested.sh returns before writing a receipt when either is
  # missing. Without them these fixtures asserted exit codes on a path where the
  # receipt-minting branch was dead code — including the forged-PROVED defect
  # that lives precisely there. A fixture that does not reach the code it names
  # is worse than no fixture, because it reports green.
  : > .claude/exloom-gate.enabled
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

# A. A test that genuinely notices the change -> PROVED.
proofrepo good 'v=$(bash src/calc.sh); [ "$v" = "4" ]' 'echo 4'; B="$BASESHA"
printf 'echo 5\n' > src/calc.sh
printf 'v=$(bash src/calc.sh); [ "$v" = "5" ]\n' > tests/calc_test.sh
ok "a test that notices the change -> PROVED" "$(prove "$B")" "0"
ok "...and the PROVED receipt is actually written" "$(proofres)" "PROVED"

# B. The transcript's own failure: an assertion too weak to notice anything.
#    (`hasMessageContaining("a")` on an object named `a`, in miniature.)
proofrepo weak 'v=$(bash src/calc.sh); [ -n "$v" ]' 'echo 4'; B="$BASESHA"
printf 'echo 5\n' > src/calc.sh
printf 'v=$(bash src/calc.sh); [ -n "$v" ]  # still only checks non-empty\n' > tests/calc_test.sh
ok "a decorative assertion -> NOT PROVED" "$(prove "$B")" "1"
ok "...and the receipt says NOT_PROVED, not nothing" "$(proofres)" "NOT_PROVED"

# C. Source changed, no test touched at all.
proofrepo notest 'v=$(bash src/calc.sh); [ "$v" = "4" ]' 'echo 4'; B="$BASESHA"
printf 'echo 5\n' > src/calc.sh
ok "source changed with no test -> NOT PROVED" "$(prove "$B")" "1"

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

echo "== the loop-termination signal is recorded, not just emitted =="

# All five agents emit `ROUND NEEDED AFTER FIX:` as a mandatory closing line and
# nothing read it. The presenting complaint is review loops that do not stop;
# this is the signal that stops them, and it was write-only.
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

echo "== one dispatch leaves one receipt line, not eighteen =="

# SubagentStop fires on EVERY turn a reviewer stops on, not only its last. A
# reviewer that reads eight files stops eight times, and the seven intermediate
# stops hand over a message with no VERDICT line — which scored UNKNOWN and was
# appended verbatim. Observed in the field: 18 lines for one commit, 17 UNKNOWN
# and one REJECTED. The gate read that correctly (it takes the strongest verdict
# for the commit), so this is legibility, not a wrong decision — but a file that
# is 90% noise cannot be read by a person, and a reader scanning it newest-first
# would invert the answer.
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

echo "== lanes: rigour earned by stakes, not imposed by process =="

# exloom shipped one lane and it was the strictest one — the same ten steps for a
# null check and a subsystem. Tiers scale review DEPTH, derived from the diff;
# they never scaled CEREMONY, which is what a small change cannot afford.
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

echo "== the spec linter: structural errors block, judgement calls warn =="

# `reviewing-plans` asks nine questions in prose, and prose checks do not run.
# The line between ERROR and WARN is the whole design: errors are structural and
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

# Gapless refs. Keel made this an error rather than a warning because the people
# who wrote the rule had already broken it in their own hand-written specs.
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

echo "== the proof binds the COMMAND it proved, not just its own presence =="

# cmd_hash was written by prove-change-is-tested.sh and read by nothing. The only
# assertion on it was `grep -c cmd_hash == 1` — the key exists. So a repo could
# prove with a real suite and then point .claude/exloom-test-command at `true`,
# and the receipt stayed valid. Presence is text; binding is behaviour.
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

echo "== security review is triggered by SURFACE, not only by tier =="

# The review-gate skill promised security review for dependency and
# deserialization changes; lib.sh required security-auditor only at Tier 3, so
# both derived to Tier 1/2 and got none. The doc promised a review the code did
# not require.
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

echo "== test-vs-source classification: a production package named spec/ =="

# Found in a real repo running v4.0.0. `*/spec/*` matched
# src/main/java/.../orchestration/spec/SpeakerSelectionSpec.java, so the proof
# reverted part of a production package and kept the rest — the tree would not
# compile, and the run failed for a reason unrelated to the tests.
PRVS="$(cd "$(dirname "$LIB_ABS")/../scripts" && pwd)/prove-change-is-tested.sh"
istest() {   # istest <path> -> test|source, using the script's own function
  bash -c 'set -u; '"$(sed -n '/^is_test() {/,/^}/p' "$PRVS")"'
    is_test "$1" && echo test || echo source' _ "$1"
}
ok "src/main spec package -> source" \
   "$(istest 'apptor-agents/src/main/java/ai/apptor/agents/orchestration/spec/TopicSpec.java')" "source"
ok "src/main anything -> source" \
   "$(istest 'mod/src/main/java/com/x/test/Helper.java')" "source"
ok "src/test -> test" \
   "$(istest 'apptor-agents/src/test/java/ai/apptor/agents/RootKeyShapeTest.java')" "test"
ok "ruby spec/ dir -> test" "$(istest 'spec/models/order_spec.rb')" "test"
ok "js .spec.ts -> test"     "$(istest 'src/order.spec.ts')" "test"
ok "go _test.go -> test"     "$(istest 'internal/order/order_test.go')" "test"
ok "plain source -> source"  "$(istest 'internal/order/order.go')" "source"

echo "== the shipped template must not block a branch that filled it honestly =="

# Found by an end-to-end run, not by this suite: the template carried
# `- <step name> — <one sentence why>` under Escape hatches, and both phrases are
# in placeholder_re. A developer who correctly used NO escape hatch left the line
# alone and the gate blocked, pointing at a section they were right not to fill.
# Every branch would have hit it. The placeholder-coverage test above passes
# either way, because it only asks whether each token is RECOGNISED — not whether
# an honestly-completed checklist survives the scan.
TPL="$HOOKS_ABS/../templates/review-checklist.md"
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

echo "== reviewers are decoupled: only L1 must cover the shipped commit =="

# Requiring every reviewer to approve the SAME commit is what produced the loop:
# a fix cancels approvals from reviewers that were already satisfied, so N
# reviewers chase a target that moves each time one is answered.
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

echo "== the round cap: three rounds, then a person decides =="

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
ok "under the cap -> ordinary block, not the cap" "$(rchk)" "2"
ok "...and the message is NOT the cap message" \
   "$(exloom_check_verdicts "$RC" 1 HEAD "$(git rev-parse HEAD)" "test" 2>&1 | grep -c 'Round cap reached' | head -1)" "0"

# Reported from a real branch: four dispatches on disk, the cap did not fire, the
# push went through with no prompt. Cause — the count read only the COMMITTED
# ref, and nothing commits receipts until /review-complete says so. It answered 0
# rather than erroring: fail-open in the mechanism whose only job is to notice
# accumulation.
printf 'uncommitted\n' > src/one.go; git add -A >/dev/null 2>&1; git commit -qm r3 >/dev/null 2>&1
printf '{"agent":"l1-reviewer","head":"%s","verdict":"APPROVED"}\n' "$(git rev-parse HEAD)" >> "$RCV/l1-reviewer.json"
ok "an UNCOMMITTED receipt still counts" "$(exloom_round_count "$RC" HEAD)" "3"
git add -A >/dev/null 2>&1; git commit -qm r3receipt >/dev/null 2>&1
ok "...and is not double-counted once committed" "$(exloom_round_count "$RC" HEAD)" "3"

# At the cap the gate BLOCKS and hands the session a question to put to the user.
#
# It used to print an "ask" decision instead, which the harness renders as
# approve/cancel on the push itself. Cancel there is a tool refusal, not an
# answer: the push died, the session had nothing to act on, and the person had to
# retype what they wanted. A cap is a decision point, so it has to yield a
# DECISION — which means named options, which only AskUserQuestion can render,
# which is a session tool and not a hook capability.
rounds_at 3
ok "at the cap -> blocks (2), it does not prompt on the push" "$(rchk)" "2"
capmsg() { exloom_check_verdicts "$RC" 1 HEAD "$(git rev-parse HEAD)" "test" 2>&1 >/dev/null; }
ok "...and the report reaches the session" \
   "$(capmsg | grep -c 'Findings by pass' | head -1)" "1"
ok "...as an instruction to ask, naming the tool" \
   "$(capmsg | grep -c 'Use AskUserQuestion' | head -1)" "1"
ok "...with all three options" \
   "$(capmsg | grep -cE '^  - (Fix|Merge as-is|Show me the findings)' | head -1)" "3"
ok "...and nothing is printed to stdout (that would be a decision)" \
   "$(exloom_check_verdicts "$RC" 1 HEAD "$(git rev-parse HEAD)" "test" 2>/dev/null | wc -c | tr -d ' ')" "0"

# The recommendation comes from OPEN criticals, not from the round number — and
# the fix option names the DEFECTS. "2 open criticals" is a score; a cite is
# something a person can decide about.
printf '{"round":3,"agent":"l1-reviewer","severity":"HIGH","scope":"IN-SCOPE","cite":"src/one.go:1","fingerprint":"c1","head":"%s","at":"n"}\n' \
  "$(git rev-parse HEAD)" > "$RCV/l1-reviewer.findings.jsonl"
git add -A >/dev/null 2>&1; git commit -qm crit >/dev/null 2>&1
ok "an open critical -> recommend fixing, not another pass" \
   "$(capmsg | grep -c 'RECOMMENDATION: FIX, THEN RE-REVIEW' | head -1)" "1"
ok "...and the fix option names the cite, not a count" \
   "$(capmsg | grep -c 'Fix src/one.go:1, then re-review' | head -1)" "1"
ok "...and the cites come from exloom_open_critical_cites" \
   "$(exloom_open_critical_cites "$RC" HEAD)" "src/one.go:1"
printf '{"round":3,"agent":"l1-reviewer","severity":"LOW","scope":"IN-SCOPE","cite":"src/one.go:1","fingerprint":"m1","head":"%s","at":"n"}\n' \
  "$(git rev-parse HEAD)" > "$RCV/l1-reviewer.findings.jsonl"
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

# A recorded user answer stops the asking.
printf '\n## Escape hatches used\n- User approved at round cap — approved after 3 passes\n' >> "$RC"
git add -A >/dev/null 2>&1; git commit -qm userok >/dev/null 2>&1
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

echo "== the cap is configurable, but only from a COMMITTED file =="

ok "default cap" "$(exloom_max_rounds)" "3"
printf '5\n' > .claude/exloom-max-rounds
ok "uncommitted config is ignored" "$(exloom_max_rounds)" "3"
git add -A >/dev/null 2>&1; git commit -qm cap >/dev/null 2>&1
ok "committed config is honoured" "$(exloom_max_rounds)" "5"

cd "$WORK" || exit 1

echo
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]] || exit 1
echo "All exloom review-gate tests passed."
