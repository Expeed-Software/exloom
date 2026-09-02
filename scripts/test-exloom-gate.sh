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

echo "== staleness by change class (a typo fix must not demand another round) =="

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

echo "== code-reviewer verdicts (a REJECTED review does not satisfy the gate) =="

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

# Guarding `.verdicts/` alone is not enough: `rm -rf .claude/reviews` and
# `git clean -fdx` name neither the directory nor the state file, and either one
# destroys every receipt, the round counter and the findings ledger.
ok "writing the review STATE file -> denied"   "$(deny '{"tool_name":"Write","tool_input":{"file_path":".claude/reviews/feat/x.state"}}')" "2"
ok "editing the CHECKLIST is still allowed"   "$(deny '{"tool_name":"Edit","tool_input":{"file_path":".claude/reviews/feat/x.md"}}')" "0"
ok "rm -rf of the reviews tree -> denied"   "$(deny '{"tool_name":"Bash","tool_input":{"command":"rm -rf .claude/reviews"}}')" "2"
ok "git clean -fdx -> denied"   "$(deny '{"tool_name":"Bash","tool_input":{"command":"git clean -fdx"}}')" "2"
ok "reading the state file -> allowed"   "$(deny '{"tool_name":"Bash","tool_input":{"command":"cat .claude/reviews/feat/x.state"}}')" "0"

echo "== remediation commands in block messages must actually run =="

# ${CLAUDE_PLUGIN_ROOT} is interpolated into plugin.json by the harness and is
# NOT set in the Bash environment. A remediation command built from it fails with
# "No such file or directory", which leaves EXLOOM_REVIEW_SKIP — advertised in
# the same message — as the only reachable option.
#
# Scoped to the WHOLE plugin, not to hooks/commands/scripts: skills and templates
# carry runnable snippets too, and a guard that covers only the directories a
# past fix happened to touch cannot catch the next one.
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

# .claude-plugin/plugin.json is excluded, and only it: that manifest is the one
# place the harness DOES interpolate the variable, so its hook commands are
# correct exactly as written.
ok "no shipped file tells a session to run \${CLAUDE_PLUGIN_ROOT}" \
   "$(grep -rlE "$CPR_RE" "$PLUGIN_ROOT_DIR" 2>/dev/null \
      | grep -v '\.claude-plugin/plugin\.json$' | wc -l | tr -d ' ')" "0"
ok "...while the manifest, where it IS interpolated, still uses it" \
   "$(grep -cE '\$\{CLAUDE_PLUGIN_ROOT\}' "$PLUGIN_ROOT_DIR/.claude-plugin/plugin.json" | head -1)" "5"
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

echo "== classifier: real code the old version called non-behavioural =="

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

echo "== reviewer output parsed as the shipped agents actually print it =="

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

echo "== classifier: near-misses of the comment-marker rules =="

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

echo "== proof: the three-run protocol =="

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

echo "== a shell redirection is not a refspec =="

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

echo "== SubagentStop: the verdict is captured at COMPLETION =="

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

echo "== ASYNC dispatch: PostToolUse fires at LAUNCH, before any report exists =="

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

echo "== payload shape: the field the harness actually sends =="

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

echo "== CONTRACT: every shipped agent's own output block, through the real parser =="

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

for a in $(ls "$HOOKS_ABS/../agents"/*.md | xargs -n1 basename | sed "s/\.md$//"); do
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

echo "== prove-change-is-tested (author-side, before review) =="

# The three shapes this check exists to catch before review starts: a decorative
# assertion, a write-path test with no read-path test, and a test task that
# reports UP-TO-DATE and never runs.
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

echo "== one dispatch leaves one receipt line, not eighteen =="

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

echo "== lanes: rigour earned by stakes, not imposed by process =="

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

echo "== a javadoc paragraph break is not a pointer dereference =="

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

echo "== a receipt goes to the repo the REVIEW is about, not the session's cwd =="

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

echo "== the round a finding belongs to is derived, never read from a state file =="

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

echo "== the gate says where it stands at every completion, not only at the end =="

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

echo "== reading a receipt is not writing one =="

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

echo "== the fork point is the NEAREST branch, not the first one named =="

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

echo "== criterion coverage is produced by the runner, never by a test's name =="

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

echo "== an additive change is provable by mutation, not by absence =="

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
ok "with no mutation command -> still NOT PROVED, as before" \
   "$(sed -n 's/.*"result":"\([A-Z_]*\)".*/\1/p' "$MJ" | tail -1)" "NOT_PROVED"
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
ok "an uncommitted mutation command is ignored" \
   "$(sed -n 's/.*"result":"\([A-Z_]*\)".*/\1/p' "$UJ" | tail -1)" "NOT_PROVED"

cd "$WORK" || exit 1

echo "== the spec linter: structural errors block, judgement calls warn =="

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

echo "== the proof binds the COMMAND it proved, not just its own presence =="

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

echo "== security review is triggered by SURFACE, not only by tier =="

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

echo "== test-vs-source classification: a production package named spec/ =="

# A production package can be named `spec`. If `*/spec/*` matched inside
# src/main, the proof would revert part of a production package and keep the
# rest: the tree would not compile, and the run would fail for a reason that has
# nothing to do with the tests.
PRVS="$(cd "$(dirname "$LIB_ABS")/../scripts" && pwd)/prove-change-is-tested.sh"
istest() {   # istest <path> -> test|source, using the script's own function
  bash -c 'set -u; '"$(sed -n '/^is_test() {/,/^}/p' "$PRVS")"'
    is_test "$1" && echo test || echo source' _ "$1"
}
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

echo "== the shipped template must not block a branch that filled it honestly =="

# A placeholder example left in the document BODY blocks every branch: a
# developer who correctly used no escape hatch leaves the line alone, and the
# gate then points at a section they were right not to fill.
#
# The placeholder-coverage test above cannot catch that. It asks whether each
# token is RECOGNISED, not whether an honestly-completed checklist survives the
# scan — which is a different question, and this is where it is asked.
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

# A recorded user answer stops the asking about ROUNDS, and only that. The last
# receipt here is REJECTED, and "we have reviewed enough times" is not an answer
# to "did anyone approve this".
printf '\n## Escape hatches used\n- User approved at round cap — approved after 3 passes\n' >> "$RC"
git add -A >/dev/null 2>&1; git commit -qm userok >/dev/null 2>&1
ok "the answer does not waive a reviewer that REJECTED the code" "$(rchk)" "2"
ok "...and says which question it actually answered" \
   "$(capmsg | grep -c 'does not answer' | head -1)" "1"

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

echo "== the cap is configurable, but only from a COMMITTED file =="

ok "default cap" "$(exloom_max_rounds)" "3"
printf '5\n' > .claude/exloom-max-rounds
ok "uncommitted config is ignored" "$(exloom_max_rounds)" "3"
git add -A >/dev/null 2>&1; git commit -qm cap >/dev/null 2>&1
ok "committed config is honoured" "$(exloom_max_rounds)" "5"

echo "== a pipeline that records nothing is not a clean branch =="

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

echo "== the cap override answers the round question, and only that =="

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

echo "== the status line stops driving the loop at the cap =="

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
ok "...and hands over the three options"      "$(printf '%s' "$SOUT" | grep -c 'Merge as-is')" "1"

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

echo "== the bypass leaves a trace =="

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

echo "== the status line judges coverage the way the GATE does =="

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

cd "$WORK" || exit 1

echo
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]] || exit 1
echo "All exloom review-gate tests passed."
