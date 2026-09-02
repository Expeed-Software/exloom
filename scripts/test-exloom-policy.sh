#!/usr/bin/env bash
# exloom — .exloom.yml repository policy tests.
#
# Split from test-exloom-gate.sh because the glob matcher has to be provable on
# its own. A policy language that looks correct and matches nothing is the worst
# outcome available here: the author writes a Tier 3 rule for their identity
# module, the rule never fires, and nothing anywhere says so.

set -u
unset EXLOOM_REVIEW_SKIP

HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
HOOKS_ABS="$(cd "$HERE/../plugins/exloom/hooks" && pwd)"
WORK="$(pwd)"
REG="$(mktemp -d 2>/dev/null || echo "${TMPDIR:-/tmp}/exloom-policy-$$")"
mkdir -p "$REG"
trap 'cd "$WORK"; rm -rf "$REG"' EXIT

PASS=0; FAIL=0
ok() {   # ok <name> <got> <want>
  if [[ "$2" == "$3" ]]; then PASS=$((PASS+1)); echo "  PASS  $1"
  else FAIL=$((FAIL+1)); echo "  FAIL  $1 — got '$2', want '$3'"; fi
}

# shellcheck source=/dev/null
. "$HOOKS_ABS/policy.sh"

echo "== glob semantics are deterministic, and do not come from the shell =="

m() {   # m <glob> <path> -> match|no
  if exloom_policy_match "$1" "$2"; then printf 'match'; else printf 'no'; fi
}

# The separator rule is the whole game. A `*` that quietly spans `/` turns a
# narrow rule into a broad one and nothing in the output would say so.
ok "**/identity/** matches a nested path"      "$(m '**/identity/**' 'src/identity/TokenService.java')" "match"
ok "**/identity/** matches the directory too"  "$(m '**/identity/**' 'identity/Token.java')"            "match"
ok "**/identity/** matches the bare segment"   "$(m '**/identity/**' 'identity')"                       "match"
ok "identity/** matches at the root"           "$(m 'identity/**' 'identity/Auth.java')"                "match"
ok "identity/** does NOT match nested"         "$(m 'identity/**' 'src/identity/Auth.java')"            "no"
ok "**/auth/** matches a module path"          "$(m '**/auth/**' 'modules/auth/service.java')"          "match"
ok "**/*Secret* matches an infix"              "$(m '**/*Secret*' 'src/FooSecretStore.java')"           "match"
ok "**/*.sql matches an extension"             "$(m '**/*.sql' 'db/migration/V1.sql')"                  "match"
ok "src/*/auth/** matches one segment"         "$(m 'src/*/auth/**' 'src/main/auth/X.java')"            "match"
ok "src/*/auth/** does NOT span separators"    "$(m 'src/*/auth/**' 'src/a/b/auth/X.java')"             "no"

# Case sensitivity is a correctness property: git paths are case-sensitive and
# Windows filesystems often are not, so a case-insensitive matcher would derive
# different tiers for the same repository on different machines.
ok "**/IAM/** does NOT match src/iam (case-sensitive)" "$(m '**/IAM/**' 'src/iam/Auth.java')" "no"
ok "**/iam/** does match src/iam"                      "$(m '**/iam/**' 'src/iam/Auth.java')" "match"

# A dot is a literal, not "any character" — otherwise `**/*.sql` also matches
# `V1xsql`, and a migration rule starts firing on unrelated files.
ok "a dot in the glob is literal" "$(m '**/*.sql' 'db/V1xsql')" "no"
ok "? matches exactly one non-separator" "$(m 'src/?.java' 'src/A.java')" "match"
ok "? does not match a separator"        "$(m 'src/?.java' 'src//.java')" "no"

# A rule that matches nothing is legal and must stay silent rather than error —
# but it must also never match by accident.
ok "an unrelated path does not match" "$(m '**/identity/**' 'src/orders/Order.java')" "no"
ok "a prefix is not a match"          "$(m '**/auth/**' 'src/authoring/Doc.java')"    "no"

echo "== the parser accepts the schema and rejects everything else =="

polrepo() {   # polrepo <yaml-content>
  local d="$REG/r$RANDOM"; rm -rf "$d"; mkdir -p "$d"; cd "$d" || return 1
  git init -q -b main . 2>/dev/null
  git config user.email t@e.com; git config user.name t
  mkdir -p .claude src
  : > .claude/exloom-gate.enabled
  printf 'x\n' > src/base.txt
  [[ -n "${1:-}" ]] && printf '%s\n' "$1" > .exloom.yml
  git add -A >/dev/null 2>&1; git commit -qm base >/dev/null 2>&1
  # A feature branch with a real fork point, because standing on the default
  # branch makes the fork point HEAD itself and every diff empty.
  git update-ref refs/remotes/origin/main HEAD
  git checkout -q -b feat/x
  unset _EXLOOM_POL_LOADED _EXLOOM_POL_HEAD
}

err_of() {  # err_of -> the first line of the failure detail, or ''
  exloom_policy_load >/dev/null 2>&1
  exloom_policy_error | sed -n '3p' | sed 's/^  //'
}

polrepo 'version: 1

risk:
  tier3:
    paths:
      - "**/identity/**"
      - "**/iam/**"
  tier2:
    paths:
      - "**/integration/**"

reviewers:
  require:
    security-auditor:
      paths:
        - "**/identity/**"'
exloom_policy_load >/dev/null 2>&1
ok "a well-formed policy loads"        "$?" "0"
ok "...with no error"                  "$(exloom_policy_error)" ""
ok "...and a fingerprint"              "$([[ -n "$(exloom_policy_fingerprint)" ]] && echo yes || echo no)" "yes"

ok "tier3 rule fires"   "$(exloom_policy_tier $'src/identity/T.java\n')" "3"
ok "tier2 rule fires"   "$(exloom_policy_tier $'src/integration/A.java\n')" "2"
ok "no rule, no tier"   "$(exloom_policy_tier $'src/orders/O.java\n')" ""
ok "the highest match wins" \
   "$(exloom_policy_tier $'src/integration/A.java\nsrc/iam/B.java\n')" "3"
ok "the reason names the file, the rule and the source" \
   "$(exloom_policy_tier $'src/identity/T.java\n' >/dev/null; exloom_policy_reasons | head -1)" \
   "$(printf 'src/identity/T.java\t**/identity/**\t.exloom.yml:risk.tier3')"
ok "a repo-required reviewer is reported" \
   "$(exloom_policy_reviewers $'src/identity/T.java\n')" "security-auditor"
ok "...only for files it matches" \
   "$(exloom_policy_reviewers $'src/orders/O.java\n')" ""

# No policy at all is not an error — the built-in rules simply stand alone.
polrepo ''
exloom_policy_load >/dev/null 2>&1
ok "an absent policy is not an error" "$?" "0"
ok "...and contributes no tier"       "$(exloom_policy_tier $'src/identity/T.java\n')" ""

echo "== an unknown key is an error, never a silently ignored line =="

# The failure this exists to stop: the author believes a security rule is in
# force, and a typo meant it never ran.
polrepo 'version: 1
risk:
  teir3:
    paths:
      - "**/identity/**"'
ok "a misspelled key fails"     "$(err_of | grep -c 'unknown configuration key')" "1"
ok "...and suggests the fix"    "$(err_of | grep -c 'did you mean')" "1"

polrepo 'version: 1
reviewers:
  require:
    securty-auditor:
      paths:
        - "**/identity/**"'
ok "an unknown reviewer fails"  "$(err_of | grep -c 'unknown reviewer')" "1"
ok "...and lists the real ones" "$(err_of >/dev/null; exloom_policy_error | grep -c 'Available reviewers')" "1"

polrepo 'risk:
  tier3:
    paths:
      - "**/identity/**"'
ok "a missing version fails" "$(err_of >/dev/null; exloom_policy_error | grep -c 'no .version:')" "1"

polrepo 'version: 2
risk:
  tier3:
    paths:
      - "**/x/**"'
ok "an unsupported version fails" "$(err_of | grep -c 'unsupported policy version')" "1"

echo "== the format stays small: unsupported YAML is rejected, not accommodated =="

polrepo 'version: 1
risk:
  tier3:
    paths: ["**/identity/**"]'
ok "inline arrays rejected" "$(err_of | grep -c 'inline arrays')" "1"

polrepo 'version: 1
risk:
  tier3:
    paths:
      - **/identity/**'
ok "unquoted globs rejected" "$(err_of | grep -c 'must be double-quoted')" "1"

polrepo 'version: 1
risk: &base
  tier3:
    paths:
      - "**/x/**"'
ok "anchors rejected" "$(err_of | grep -c 'anchors')" "1"

polrepo 'version: 1
risk:
  tier3:
    paths:
      - "**/x/**"   # the identity module'
ok "trailing comments rejected" "$(err_of | grep -c 'whole-line comment')" "1"

polrepo 'version: 1
risk:
   tier3:
     paths:
       - "**/x/**"'
ok "three-space indent rejected" "$(err_of | grep -c 'two spaces per level')" "1"

polrepo 'version: 1
risk:
  tier3:
    paths:
      - "$(rm -rf /)"'
ok "a value outside the glob charset is rejected" "$(err_of | grep -c 'is not a glob')" "1"

polrepo 'version: 1
# the identity module carries our tenancy checks
risk:
  tier3:
    paths:
      - "**/identity/**"'
exloom_policy_load >/dev/null 2>&1
ok "a whole-line comment is fine" "$?" "0"

echo "== repository policy may only escalate =="

# Someone writing a tier1 rule over a path the built-ins call tier3 must not
# lower it. The evaluator reports what it matched; the caller takes the maximum,
# and there is no key that subtracts.
polrepo 'version: 1
risk:
  tier1:
    paths:
      - "**/migrations/**"'
ok "a tier1 rule reports only tier1" \
   "$(exloom_policy_tier $'db/migrations/V1.sql\n')" "1"
mkdir -p db/migrations; printf 'x\n' > db/migrations/V1.sql
git add -A >/dev/null 2>&1; git commit -qm m >/dev/null 2>&1
ok "...and the built-in derivation still says 3" \
   "$(. "$HOOKS_ABS/lib.sh" >/dev/null 2>&1; exloom_derive_tier HEAD)" "3"
ok "...so the effective tier is the higher of the two" \
   "$(. "$HOOKS_ABS/lib.sh" >/dev/null 2>&1; exloom_derive_tier HEAD)" "3"

echo "== the repo's vocabulary reaches the derived tier =="

# The reason this feature exists. `identity` is not a word the built-in rules
# know, so without policy this change derives Tier 1 and ships with an L1 review
# and nothing else.
polrepo 'version: 1
risk:
  tier3:
    paths:
      - "**/identity/**"'
mkdir -p src/identity; printf 'x\n' > src/identity/TokenService.java
git add -A >/dev/null 2>&1; git commit -qm id >/dev/null 2>&1
# shellcheck source=/dev/null
. "$HOOKS_ABS/lib.sh" >/dev/null 2>&1
unset _EXLOOM_POL_LOADED _EXLOOM_POL_HEAD _EXLOOM_FP _EXLOOM_FP_TIP
ok "a repo rule raises the tier the built-ins would have given" \
   "$(exloom_derive_tier HEAD)" "3"
ok "...and says which file and which rule did it" \
   "$(exloom_derive_tier HEAD >/dev/null; exloom_tier_reasons | head -1)" \
   "$(printf 'src/identity/TokenService.java\t**/identity/**\t.exloom.yml:risk.tier3')"

# Same repo, same rule, a markdown file. A path glob does not turn documentation
# into code, and Tier 0 is checked before anything else for that reason.
polrepo 'version: 1
risk:
  tier3:
    paths:
      - "**/identity/**"'
mkdir -p src/identity; printf 'x\n' > src/identity/README.md
git add -A >/dev/null 2>&1; git commit -qm doc >/dev/null 2>&1
unset _EXLOOM_POL_LOADED _EXLOOM_POL_HEAD _EXLOOM_FP _EXLOOM_FP_TIP
ok "a docs-only change is still Tier 0 under a matching rule" \
   "$(exloom_derive_tier HEAD)" "0"

# The escalation rule, stated as a test rather than a comment: a repo rule that
# names a lower tier than the built-ins cannot lower anything.
polrepo 'version: 1
risk:
  tier1:
    paths:
      - "**/migrations/**"'
mkdir -p db/migrations; printf 'x\n' > db/migrations/V1.sql
git add -A >/dev/null 2>&1; git commit -qm m >/dev/null 2>&1
unset _EXLOOM_POL_LOADED _EXLOOM_POL_HEAD _EXLOOM_FP _EXLOOM_FP_TIP
ok "a tier1 rule cannot lower a built-in tier3" "$(exloom_derive_tier HEAD)" "3"

echo "== repository reviewers are additive =="

polrepo 'version: 1
reviewers:
  require:
    security-auditor:
      paths:
        - "**/identity/**"'
mkdir -p src/identity; printf 'x\n' > src/identity/T.java
git add -A >/dev/null 2>&1; git commit -qm id >/dev/null 2>&1
unset _EXLOOM_POL_LOADED _EXLOOM_POL_HEAD _EXLOOM_FP _EXLOOM_FP_TIP
EXTRA="$(exloom_policy_required_reviewers "$(exloom_fork_point HEAD)" HEAD)"
ok "the repo adds a reviewer the tier did not ask for" "$EXTRA" "security-auditor"
ok "...and it joins the required set" \
   "$(exloom_required_reviewers 1 '' "$EXTRA")" "l1-reviewer security-auditor"
ok "...without duplicating one already required" \
   "$(exloom_required_reviewers 3 '' "$EXTRA")" "l1-reviewer adversarial-reviewer security-auditor"
ok "no repo rule, no addition" "$(exloom_required_reviewers 1 '' '')" "l1-reviewer"

echo "== an invalid policy blocks, and never falls back to the built-ins =="

polrepo 'version: 1
risk:
  teir3:
    paths:
      - "**/identity/**"'
mkdir -p .claude/reviews/feat; printf '**Tier:** 1\n' > .claude/reviews/feat/x.md
git add -A >/dev/null 2>&1; git commit -qm cl >/dev/null 2>&1
unset _EXLOOM_POL_LOADED _EXLOOM_POL_HEAD
OUT="$(exloom_validate_checklist ".claude/reviews/feat/x.md" HEAD 0 "push" 2>&1)"; RC=$?
ok "the gate refuses to run"        "$RC" "2"
ok "...naming the offending key"    "$(printf '%s' "$OUT" | grep -c 'unknown configuration key')" "1"
ok "...and saying it will not guess" \
   "$(printf '%s' "$OUT" | grep -c 'does not fall back')" "1"

cd "$WORK" || exit 1
echo
echo "PASS=$PASS FAIL=$FAIL"
[[ $FAIL -eq 0 ]] || exit 1
echo "All exloom policy tests passed."
