#!/usr/bin/env bash
# test-qa-gate.sh — behavioural tests for the exloom-qa publish gate.
# Usage: bash scripts/test-qa-gate.sh
# Exits 0 if every case behaves as specified, 1 otherwise.
#
# The gate decides whether unapproved Test Cases can reach a live board, and
# published Test Cases cannot be cleanly deleted. It is tested by running it,
# never by reading it.

set -u

HOOK="plugins/exloom-qa/hooks/block-unapproved-publish.sh"
FIX="$(mktemp -d)"
trap 'rm -rf "$FIX"' EXIT
mkdir -p "$FIX/.claude/qa"

PASS=0
FAIL=0

# run <expected:allow|deny> <name> <command>
run() {
  local expect="$1" name="$2" cmd="$3" rc
  local json
  json="$(CMD_ENV="$cmd" python3 -c '
import json, os
print(json.dumps({"tool_name": "Bash", "tool_input": {"command": os.environ["CMD_ENV"]}}))')"
  set +e
  printf '%s' "$json" | CLAUDE_PROJECT_DIR="$FIX" EXLOOM_QA_SKIP=0 bash "$HOOK" >/dev/null 2>&1
  rc=$?
  set -e
  local got="allow"; [[ "$rc" -eq 2 ]] && got="deny"
  if [[ "$got" == "$expect" ]]; then
    echo "  PASS  [$expect] $name"
    PASS=$((PASS + 1))
  else
    echo "  FAIL  [expected $expect, got $got] $name"
    FAIL=$((FAIL + 1))
  fi
}

TC_CREATE='az boards work-item create --type "Test Case" --title "Save is rejected without a close date" --org https://dev.azure.com/acme --project proj --fields "System.Tags=exloom-qa:24501; exloom-qa:24501:TC-007; Negative"'

echo "== exloom-qa publish gate =="

echo ""
echo "-- no artifact --"
run deny "create Test Case with no artifact present" "$TC_CREATE"

echo ""
echo "-- artifact, no approval record --"
cat > "$FIX/.claude/qa/24501.md" <<'EOF'
# QA Test Cases — 24501

## Test Cases
### TC-007 — Save is rejected without a close date
EOF
run deny "create Test Case, artifact has no approval record" "$TC_CREATE"

echo ""
echo "-- approval record, TC not approved --"
cat >> "$FIX/.claude/qa/24501.md" <<'EOF'

## Approval Record
Approved by: Priya
Date: 2026-08-20
Approved: TC-001..TC-005, TC-009
EOF
run deny "create Test Case not in the approved list" "$TC_CREATE"

echo ""
echo "-- approval record, TC approved --"
cat > "$FIX/.claude/qa/24501.md" <<'EOF'
# QA Test Cases — 24501

## Approval Record
Approved by: Priya
Date: 2026-08-20
Approved: TC-001..TC-012, TC-015
EOF
run allow "create Test Case that is approved (range)" "$TC_CREATE"

cat > "$FIX/.claude/qa/24501.md" <<'EOF'
## Approval Record
Approved: TC-002, TC-007, TC-011
EOF
run allow "create Test Case that is approved (explicit list)" "$TC_CREATE"

cat > "$FIX/.claude/qa/24501.md" <<'EOF'
## Approval Record
Approved: TC-001 to TC-006
EOF
run deny "TC-007 against range TC-001 to TC-006" "$TC_CREATE"

echo ""
echo "-- provenance tag --"
cat > "$FIX/.claude/qa/24501.md" <<'EOF'
## Approval Record
Approved: TC-001..TC-050
EOF
run deny "create Test Case with no provenance tag" \
  'az boards work-item create --type "Test Case" --title "Untagged case" --org https://dev.azure.com/acme --project proj'
run deny "create Test Case with a malformed provenance tag" \
  'az boards work-item create --type "Test Case" --title "Bad tag" --fields "System.Tags=exloom-qa-24501-TC-007"'

echo ""
echo "-- scope denials --"
run deny "delete a work item" 'az boards work-item delete --id 24132 --org https://dev.azure.com/acme --yes'
run deny "delete via Test Management API" \
  'curl -s -X DELETE -H "Authorization: Bearer $T" https://dev.azure.com/acme/proj/_apis/test/testcases/24132?api-version=7.1-preview.1'
run deny "create a test plan" 'az boards work-item create --type "Test Plan" --title "Regression plan"'
run deny "test suite REST call" \
  'curl -s -X POST -H "Authorization: Bearer $T" https://dev.azure.com/acme/proj/_apis/testplan/Plans/1/suites?api-version=7.1'

echo ""
echo "-- reads and unrelated commands pass through --"
run allow "read a work item" 'az boards work-item show --id 24501 --org https://dev.azure.com/acme'
run allow "WIQL query (GET-shaped read)" \
  'curl -s -H "Authorization: Bearer $T" "https://dev.azure.com/acme/proj/_apis/wit/workitems/24501?api-version=7.1"'
run allow "list relation types" 'az boards work-item relation list-type --org https://dev.azure.com/acme'
run allow "unrelated shell command" 'ls -la && git status'
run allow "az login" 'az login --tenant example.com'
run allow "create a non-Test-Case work item" \
  'az boards work-item create --type "User Story" --title "Some story" --org https://dev.azure.com/acme'

echo ""
echo "-- reads must never be blocked (regression: live false positive 2026-08-20) --"
run allow "WIQL POST is a read despite the POST method" \
  'curl -s -X POST -H "Authorization: Bearer $T" -H "Content-Type: application/json" -d "{\"query\":\"SELECT [System.Id] FROM WorkItems\"}" https://dev.azure.com/acme/proj/_apis/wit/wiql?api-version=7.1'
run allow "GET on the workitems endpoint" \
  'curl -s -H "Authorization: Bearer $T" "https://dev.azure.com/acme/proj/_apis/wit/workitems?ids=1,2&api-version=7.1"'
run allow "compound: WIQL POST then GET workitems in one command" \
  'curl -s -X POST -d "{}" https://dev.azure.com/acme/proj/_apis/wit/wiql?api-version=7.1 -o /tmp/a.json; curl -s "https://dev.azure.com/acme/proj/_apis/wit/workitems?ids=1&api-version=7.1"'
run deny "compound: a read followed by an unapproved Test Case create" \
  'az boards work-item show --id 1 --org https://dev.azure.com/acme && az boards work-item create --type "Test Case" --title "x" --fields "System.Tags=exloom-qa:24501:TC-099"'

echo ""
echo "-- linking must not be blocked (it is how publishing links cases) --"
run allow "relation add (tests link)" \
  'az boards work-item relation add --id 24132 --relation-type "tests" --target-id 24501 --org https://dev.azure.com/acme'
run deny "relation remove" \
  'az boards work-item relation remove --id 24132 --relation-type "tests" --target-id 24501 --org https://dev.azure.com/acme --yes'

echo ""
echo "-- prose is not a command (regression: a commit message was blocked) --"
run allow "commit message describing the gate" \
  'git commit -m "fix: az boards work-item relation add carries no exloom-qa:24501:TC-007 tag, so the gate denied it"'
run allow "documentation mentioning a create command" \
  'echo "- run: az boards work-item create --type \"Test Case\" --fields System.Tags=exloom-qa:1:TC-1" >> NOTES.md'
run allow "grep for the command in source" \
  'grep -rn "az boards work-item create" plugins/'
run deny "a real create still denied when prefixed by an env assignment" \
  'ORG=https://dev.azure.com/acme az boards work-item create --type "Test Case" --title "x" --fields "System.Tags=exloom-qa:24501:TC-099"'

echo ""
echo "-- bypass --"
set +e
printf '%s' "$(CMD_ENV="$TC_CREATE" python3 -c '
import json, os
print(json.dumps({"tool_name":"Bash","tool_input":{"command":os.environ["CMD_ENV"]}}))')" \
  | CLAUDE_PROJECT_DIR="$(mktemp -d)" EXLOOM_QA_SKIP=1 bash "$HOOK" >/dev/null 2>&1
rc=$?
set -e
if [[ "$rc" -eq 0 ]]; then
  echo "  PASS  [allow] EXLOOM_QA_SKIP=1 bypasses the gate"
  PASS=$((PASS + 1))
else
  echo "  FAIL  [expected allow, got deny] EXLOOM_QA_SKIP=1 bypass"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "== $PASS passed, $FAIL failed =="
[[ "$FAIL" -eq 0 ]] || exit 1
