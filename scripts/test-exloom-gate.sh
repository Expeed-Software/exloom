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

LIB="plugins/exloom/hooks/lib.sh"
HOOKS="plugins/exloom/hooks"

if [[ ! -f "$LIB" ]]; then
  echo "FAIL: run this from the repository root (no $LIB)"
  exit 1
fi

LIB_ABS="$(cd "$(dirname "$LIB")" && pwd)/$(basename "$LIB")"
HOOKS_ABS="$(cd "$HOOKS" && pwd)"
WORK="${TMPDIR:-/tmp}/exloom-gate-fixture.$$"

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

echo "== verdict receipts (dispatch is recorded, not claimed) =="

CHECK=".claude/reviews/feat/x.md"
mkdir -p "$(dirname "$CHECK")"
VD="$(exloom_verdict_dir "$CHECK")"
ok "receipt dir derived from checklist path" "$VD" ".claude/reviews/feat/x.verdicts"
ok "tier 2 reviewer set" "$(exloom_required_reviewers 2)" \
   "l1-reviewer cross-layer-auditor adversarial-reviewer"

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

echo "== record-reviewer-verdict hook (a real dispatch writes one) =="

git checkout -q -b feat/rec main
RVD=".claude/reviews/feat/rec.verdicts"
rm -rf "$RVD"
record() { printf '%s' "$1" | bash "$HOOKS_ABS/record-reviewer-verdict.sh" >/dev/null 2>&1; }

record '{"tool_name":"Task","session_id":"s1","tool_input":{"subagent_type":"exloom:adversarial-reviewer"}}'
ok "reviewer dispatch -> receipt written" "$([[ -f "$RVD/adversarial-reviewer.json" ]] && echo yes || echo no)" "yes"
ok "receipt names the dispatched-at commit" \
   "$(grep -c "$(git rev-parse HEAD)" "$RVD/adversarial-reviewer.json" 2>/dev/null || echo 0)" "1"

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

echo
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]] || exit 1
echo "All exloom review-gate tests passed."
