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

# Which tool fired? A shell `git push`/`gh pr create` and a GitHub MCP write/PR
# tool are both "publish" actions the gate must cover.
TOOL=""
if command -v jq >/dev/null 2>&1; then
  TOOL="$(printf '%s' "$HOOK_INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)"
fi
if [[ -z "$TOOL" ]] && command -v python3 >/dev/null 2>&1; then
  TOOL="$(printf '%s' "$HOOK_INPUT" | python3 -c 'import json,sys
try:
    print(json.load(sys.stdin).get("tool_name",""))
except Exception:
    pass' 2>/dev/null || true)"
fi
if [[ -z "$TOOL" ]]; then
  TOOL="$(printf '%s' "$HOOK_INPUT" | sed -n 's/.*"tool_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
fi

IS_PUBLISH=0
case "$TOOL" in
  # GitHub MCP write/PR tools (any server-name prefix). The tool call itself is
  # the publish, so there is no shell command to parse — go straight to the gate.
  *push_files|*create_or_update_file|*create_pull_request|*merge_pull_request|*delete_file)
    IS_PUBLISH=1 ;;
esac

if [[ "$IS_PUBLISH" -eq 0 ]]; then
  # Not an MCP publish tool — treat as a Bash command and match git push / gh pr create.
  CMD=""
  if command -v jq >/dev/null 2>&1; then
    CMD="$(printf '%s' "$HOOK_INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
  fi
  if [[ -z "$CMD" ]] && command -v python3 >/dev/null 2>&1; then
    CMD="$(printf '%s' "$HOOK_INPUT" | python3 -c 'import json,sys
try:
    d=json.load(sys.stdin)
    print((d.get("tool_input") or {}).get("command",""))
except Exception:
    pass' 2>/dev/null || true)"
  fi
  if [[ -z "$CMD" ]]; then
    # Fallback when neither jq nor python3 is on PATH (e.g. stock Windows Git Bash).
    # Best-effort sed extraction of tool_input.command — covers ordinary commands
    # like `git push origin main`.
    CMD="$(printf '%s' "$HOOK_INPUT" | sed -n 's/.*"command"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
  fi
  if printf '%s' "$CMD" | grep -Eq '(^|[^[:alnum:]_])git[[:space:]]+push([[:space:]]|$)|(^|[^[:alnum:]_])gh[[:space:]]+pr[[:space:]]+create([[:space:]]|$)'; then
    IS_PUBLISH=1
  fi
fi

if [[ "$IS_PUBLISH" -eq 0 ]]; then exit 0; fi

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
PLACEHOLDER_RE='<(paste output / screenshot link|exact command|exact steps|description|Claude-session-or-human-reviewer|path to committed runbook\.md|log excerpt or link|paste|file:line — problem[^>]*|category \+ file:line[^>]*|list[^>]*|N files changed[^>]*|Critical / Important / Minor[^>]*|reviewed-sha|ai-assisted|model-id|directed-by|base-sha|attested-date)>'
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

# Staleness + migration: a complete checklist must record a valid reviewed code
# commit, and no non-checklist file may have changed since it. Only enforced when
# HEAD is resolvable — fail open on genuine git/infra failure, never on content.
if git rev-parse --verify HEAD >/dev/null 2>&1; then
  REVIEWED_SHA="$(grep -E '^Reviewed code commit:' "$CHECKLIST" | head -1 | sed -E 's/^Reviewed code commit:[[:space:]]*//' | tr -d '[:space:]')"
  if [[ -z "$REVIEWED_SHA" ]] || ! git rev-parse --verify "${REVIEWED_SHA}^{commit}" >/dev/null 2>&1; then
    cat >&2 <<EOF
exloom review gate: push BLOCKED

The checklist is marked complete but records no valid 'Reviewed code commit:',
so the review cannot be bound to the code being pushed. A checklist created
before this field existed needs migrating.

Re-run /review-complete to record the reviewed tip, then retry the push.
EOF
    exit 2
  fi
  STALE="$(git diff --name-only "$REVIEWED_SHA" HEAD -- . ':(exclude).claude/reviews' 2>/dev/null)"
  if [[ -n "$STALE" ]]; then
    cat >&2 <<EOF
exloom review gate: push BLOCKED

The review is stale. These files changed after the reviewed commit
(${REVIEWED_SHA}) and are not covered by the committed review:
${STALE}

Re-run /review-complete to review the current tip, then retry the push.
EOF
    exit 2
  fi

  # ---------- provenance attestation ----------
  # Who/what produced the change must be recorded; it is bound to the reviewed
  # code by the Reviewed-commit + staleness checks above.
  if ! grep -q '^- AI-assisted:' "$CHECKLIST" || ! grep -q '^- Model(s):' "$CHECKLIST" \
     || ! grep -q '^- Directed by:' "$CHECKLIST" || ! grep -q '^- Base commit:' "$CHECKLIST"; then
    cat >&2 <<EOF
exloom review gate: push BLOCKED

Provenance is missing from $CHECKLIST (AI-assisted / Model / Directed by / Base
commit). Run /review-complete to record who and what produced this change.
EOF
    exit 2
  fi
  # v2 (opt-in): the attestation commit must be a verified signed commit.
  if [[ -f ".claude/exloom-provenance-signed.enabled" ]]; then
    P_COMMIT="$(git log -1 --format=%H -- "$CHECKLIST" 2>/dev/null)"
    if [[ -z "$P_COMMIT" ]] || ! git verify-commit "$P_COMMIT" >/dev/null 2>&1; then
      cat >&2 <<EOF
exloom review gate: push BLOCKED

Signed provenance is required here (.claude/exloom-provenance-signed.enabled) but
the commit that recorded the checklist is not a verified signed commit. Configure
git commit signing and re-run /review-complete (it commits with -S), or remove the
marker to use v1 (unsigned) provenance.
EOF
      exit 2
    fi
  fi
fi

exit 0
