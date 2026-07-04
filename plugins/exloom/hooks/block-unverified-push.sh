#!/usr/bin/env bash
# exloom — PreToolUse(Bash) hook (review gate)
#
# OPT-IN: does nothing unless the repo created `.claude/exloom-gate.enabled`.
# Default off. When enabled, intercepts `git push` and `gh pr create`; if the
# review checklist for the current branch is missing or incomplete, exit 2 blocks.
#
# Exit codes:
#   0  — allow (gate off, not a push/PR command, checklist complete, protected
#              branch, or any infrastructure parse failure)
#   2  — block with stderr message
#
# Bypass (when enabled):
#   EXLOOM_REVIEW_SKIP=1

set -u

# ---------- bypass ----------
if [[ "${EXLOOM_REVIEW_SKIP:-0}" == "1" ]]; then
  echo "exloom: push bypass via EXLOOM_REVIEW_SKIP=1 (audit)" >&2
  exit 0
fi

# ---------- read hook input & extract command ----------
HOOK_INPUT=""
if [[ -p /dev/stdin || ! -t 0 ]]; then
  HOOK_INPUT="$(cat 2>/dev/null || true)"
fi

CMD=""
if command -v jq >/dev/null 2>&1; then
  CMD="$(printf '%s' "$HOOK_INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
elif command -v python3 >/dev/null 2>&1; then
  CMD="$(printf '%s' "$HOOK_INPUT" | python3 -c 'import json,sys
try:
    d=json.load(sys.stdin)
    print((d.get("tool_input") or {}).get("command",""))
except Exception:
    pass' 2>/dev/null || true)"
fi

if [[ -z "$CMD" ]]; then exit 0; fi

# ---------- match only push / PR create ----------
if ! printf '%s' "$CMD" | grep -Eq '(^|[^[:alnum:]_])git[[:space:]]+push([[:space:]]|$)|(^|[^[:alnum:]_])gh[[:space:]]+pr[[:space:]]+create([[:space:]]|$)'; then
  exit 0
fi

# ---------- branch check ----------
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
if [[ -z "$REPO_ROOT" ]]; then
  exit 0
fi
cd "$REPO_ROOT" || exit 0

# ---------- opt-in: gate enforces only if this repo enabled it ----------
if [[ ! -f ".claude/exloom-gate.enabled" ]]; then
  exit 0
fi

BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
case "$BRANCH" in
  main|master|dev|develop|HEAD|"")
    exit 0
    ;;
esac

CHECKLIST=".claude/reviews/${BRANCH}.md"

if [[ ! -f "$CHECKLIST" ]]; then
  cat >&2 <<EOF
exloom review gate: push BLOCKED

Branch '$BRANCH' has no review checklist at:
  $CHECKLIST

The review gate has not run. You cannot push / open a PR until a
tier-appropriate checklist exists and is marked complete.

Next steps:
  1. Run /review-init to bootstrap the checklist.
  2. Run /smoke-test to capture smoke-test evidence.
  3. Run /review-complete to mark the final verdict.
  4. Retry the push.

Emergency bypass (audited): set EXLOOM_REVIEW_SKIP=1 in your Claude Code
  session env (settings.json "env"), then retry. An inline
  "EXLOOM_REVIEW_SKIP=1 <cmd>" will NOT work — this hook reads its own
  environment, not the command's.
EOF
  exit 2
fi

# Check Final Verdict is signed.
if ! grep -q '^\- \[x\] All required gates passed for declared tier' "$CHECKLIST" \
   || ! grep -q '^\- \[x\] Checklist committed' "$CHECKLIST" \
   || ! grep -q '^\- \[x\] Ready to ship' "$CHECKLIST"; then
  cat >&2 <<EOF
exloom review gate: push BLOCKED

Checklist at $CHECKLIST is not marked complete.

Next step:
  Run /review-complete. It will verify each tier-required section and tell
  you exactly what is missing before the final verdict can be signed.

Emergency bypass (audited): set EXLOOM_REVIEW_SKIP=1 in your Claude Code
  session env (settings.json "env"), then retry. An inline
  "EXLOOM_REVIEW_SKIP=1 <cmd>" will NOT work — this hook reads its own
  environment, not the command's.
EOF
  exit 2
fi

# Placeholder text detection.
PLACEHOLDER_RE='<(paste output / screenshot link|exact command|exact steps|description|Claude-session-or-human-reviewer|path to committed runbook\.md|log excerpt or link|paste|file:line — problem[^>]*|category \+ file:line[^>]*|list[^>]*|N files changed[^>]*|Critical / Important / Minor[^>]*)>'
if grep -Eq "$PLACEHOLDER_RE" "$CHECKLIST" || grep -qE '^Date:[[:space:]]*YYYY-MM-DD[[:space:]]*$' "$CHECKLIST"; then
  cat >&2 <<EOF
exloom review gate: push BLOCKED

Checklist at $CHECKLIST is marked complete but contains template placeholder
text (e.g. <paste output / screenshot link>, unfilled date). The final verdict
cannot stand on placeholders. Fill in the real evidence or revert the
final-verdict ticks.
EOF
  exit 2
fi

# The "Checklist committed" box is self-attested — verify it against git so a
# ticked box cannot stand in for an actually-committed file. Block if the
# checklist is untracked or differs from HEAD. Fail open on genuine git errors.
if git rev-parse --verify HEAD >/dev/null 2>&1; then
  if ! git ls-files --error-unmatch "$CHECKLIST" >/dev/null 2>&1 \
     || ! git diff --quiet HEAD -- "$CHECKLIST" 2>/dev/null; then
    cat >&2 <<EOF
exloom review gate: push BLOCKED

The checklist is marked "Checklist committed", but git shows otherwise:
  $CHECKLIST is untracked or has uncommitted changes.

The review evidence must ship with the code it reviews. Commit it, then retry:
  git add "$CHECKLIST" && git commit -m "chore(review): commit review checklist"
EOF
    exit 2
  fi
fi

exit 0
