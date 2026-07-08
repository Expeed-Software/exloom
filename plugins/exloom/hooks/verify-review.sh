#!/usr/bin/env bash
# exloom — Stop hook (review gate)
#
# OPT-IN: this gate does nothing unless the repo turned it on by creating
# `.claude/exloom-gate.enabled`. Default is off — exloom never blocks a repo
# that didn't ask for the gate. (You create that marker yourself — see the README; the gate stays off until you do.)
#
# When enabled: fires on a stop. If the last assistant message asserts done /
# complete / ready / approved, verify `.claude/reviews/<branch>.md` exists and
# has the tier-required sections filled with real evidence. Exit 2 blocks.
#
# Exit codes:
#   0  — allow (gate off, checklist complete, not a done-claim, protected branch,
#              or any infrastructure parse failure — we never block on infra)
#   2  — block with stderr message
#
# Bypass (when enabled):
#   EXLOOM_REVIEW_SKIP=1  — logged to stderr, allow anyway (for emergencies)

set -u

# ---------- bypass ----------
if [[ "${EXLOOM_REVIEW_SKIP:-0}" == "1" ]]; then
  echo "exloom: review gate bypass via EXLOOM_REVIEW_SKIP=1 (audit)" >&2
  exit 0
fi

# ---------- read hook input ----------
HOOK_INPUT=""
if [[ -p /dev/stdin || ! -t 0 ]]; then
  HOOK_INPUT="$(cat 2>/dev/null || true)"
fi

# ---------- extract transcript_path ----------
TRANSCRIPT_PATH=""
if command -v jq >/dev/null 2>&1; then
  TRANSCRIPT_PATH="$(printf '%s' "$HOOK_INPUT" | jq -r '.transcript_path // empty' 2>/dev/null || true)"
fi
if [[ -z "$TRANSCRIPT_PATH" ]] && command -v python3 >/dev/null 2>&1; then
  TRANSCRIPT_PATH="$(printf '%s' "$HOOK_INPUT" | python3 -c 'import json,sys
try:
    d=json.load(sys.stdin)
    print(d.get("transcript_path",""))
except Exception:
    pass' 2>/dev/null || true)"
fi
if [[ -z "$TRANSCRIPT_PATH" ]]; then
  # Fallback when neither jq nor python3 is on PATH: best-effort sed extraction.
  # Resolves POSIX-style transcript paths (Linux/macOS). Windows paths arrive with
  # escaped backslashes and won't resolve here, so on Windows install jq or python3
  # for the Stop hook — the push hook is the primary gate (it matches the common
  # push/PR forms even without jq/python3, though obfuscated commands can evade text-matching).
  TRANSCRIPT_PATH="$(printf '%s' "$HOOK_INPUT" | sed -n 's/.*"transcript_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
fi

if [[ -z "$TRANSCRIPT_PATH" ]] || [[ ! -f "$TRANSCRIPT_PATH" ]]; then
  exit 0
fi

# ---------- extract last assistant message text from JSONL ----------
LAST_MSG=""
if command -v jq >/dev/null 2>&1; then
  LAST_MSG="$(tail -n 200 "$TRANSCRIPT_PATH" 2>/dev/null \
    | jq -rs '
        [ .[] | select((.type // .role // "") == "assistant") ] | last // empty
        | (.message.content // .content // [])
        | if type=="string" then .
          elif type=="array" then (map(select(.type=="text") | .text) | join(" "))
          else "" end
      ' 2>/dev/null || true)"
elif command -v python3 >/dev/null 2>&1; then
  LAST_MSG="$(tail -n 200 "$TRANSCRIPT_PATH" 2>/dev/null | python3 -c '
import json, sys
last = None
for line in sys.stdin:
    line=line.strip()
    if not line: continue
    try: d=json.loads(line)
    except Exception: continue
    if (d.get("type") or d.get("role") or "") == "assistant":
        last = d
if not last:
    sys.exit(0)
msg = last.get("message", last)
content = msg.get("content") if isinstance(msg, dict) else None
if isinstance(content, str):
    print(content)
elif isinstance(content, list):
    parts=[b.get("text","") for b in content if isinstance(b,dict) and b.get("type")=="text"]
    print(" ".join(parts))
' 2>/dev/null || true)"
fi

if [[ -z "$LAST_MSG" ]]; then exit 0; fi

# ---------- done-claim detection ----------
DONE_PHRASES='\b(all done|work is (now )?(complete|done|ready)|feature is (ready|complete|shipped)|implementation is complete|ready to merge|ready to ship|ready to push|safe to merge|safe to ship|good to merge|good to ship|marking (this|it) (done|complete)|task complete|phase complete|plan complete|APPROVED for merge|ready to deploy)\b'
if ! printf '%s' "$LAST_MSG" | grep -Eiq "$DONE_PHRASES"; then
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

# ---------- checklist verification ----------
CHECKLIST=".claude/reviews/${BRANCH}.md"

if [[ ! -f "$CHECKLIST" ]]; then
  cat >&2 <<EOF
exloom review gate: BLOCKED

Branch '$BRANCH' has no review checklist at:
  $CHECKLIST

You asserted the work is complete. The review gate requires a tier-appropriate
checklist before that claim can stand.

Next step:
  Run /review-init to create the checklist, then /smoke-test, then /review-complete.

Bypass (emergency only, audited):
  EXLOOM_REVIEW_SKIP=1
EOF
  exit 2
fi

# Parse tier.
TIER="$(grep -E '^\*\*Tier:\*\*' "$CHECKLIST" | head -1 | sed -E 's/.*Tier:\*\*[[:space:]]*([0-9]).*/\1/')"
if [[ ! "$TIER" =~ ^[0123]$ ]]; then
  cat >&2 <<EOF
exloom review gate: BLOCKED

Checklist at $CHECKLIST does not declare a tier (Tier: 0, 1, 2, or 3).
Open the file and set the tier, or re-run /review-init.
EOF
  exit 2
fi

# Check Final Verdict is signed.
if ! grep -q '^\- \[x\] All required gates passed for declared tier' "$CHECKLIST" \
   || ! grep -q '^\- \[x\] Checklist committed' "$CHECKLIST" \
   || ! grep -q '^\- \[x\] Ready to ship' "$CHECKLIST"; then
  cat >&2 <<EOF
exloom review gate: BLOCKED

Checklist at $CHECKLIST is not marked complete. The Final Verdict section
has unticked boxes or is missing.

Next step:
  Run /review-complete. It will verify each tier-required section and tell you
  exactly what is missing.

Bypass (emergency only, audited):
  EXLOOM_REVIEW_SKIP=1
EOF
  exit 2
fi

# Placeholder detection — scoped to the sections that apply to the declared tier,
# so unfilled higher-tier sections on a lower-tier change are not falsely flagged,
# and matched only against distinctive template tokens (not substrings of pasted
# evidence like an XML <description> element).
PLACEHOLDER_RE='<(paste output / screenshot link|exact command|exact steps|expected-result|Claude-session-or-human-reviewer|path to committed runbook\.md|log excerpt or link|paste|list[^>]*|file:line — problem[^>]*|category \+ file:line[^>]*|N files changed[^>]*|Critical / Important / Minor[^>]*|reviewed-sha|ai-assisted|model-id|directed-by|base-sha|attested-date)>'
P_TIER="$(grep -E '^\*\*Tier:\*\*' "$CHECKLIST" | head -1 | sed -E 's/.*Tier:\*\*[[:space:]]*([0-9]).*/\1/')"
[[ "$P_TIER" =~ ^[0-3]$ ]] || P_TIER=3
# An unsubstituted template tier (`[0 | 1 | 2 | 3]`) parses as its first digit (0);
# treat that placeholder as the strictest tier so nothing gets under-scanned.
if grep -qE '^\*\*Tier:\*\*.*\|' "$CHECKLIST"; then P_TIER=3; fi
P_DROP=''
if   [[ "$P_TIER" -lt 1 ]]; then P_DROP='^## (Smoke test|Cross-layer|Adversarial|Security review|Runbook)'
elif [[ "$P_TIER" -lt 2 ]]; then P_DROP='^## (Cross-layer|Adversarial|Security review|Runbook)'
elif [[ "$P_TIER" -lt 3 ]]; then P_DROP='^## (Security review|Runbook)'
fi
P_SCAN="$(awk -v drop="$P_DROP" '/^## /{skip=(drop!="" && $0 ~ drop)?1:0} !skip{print}' "$CHECKLIST")"
if printf '%s' "$P_SCAN" | grep -Eq "$PLACEHOLDER_RE" || printf '%s' "$P_SCAN" | grep -qE '^Date:[[:space:]]*YYYY-MM-DD[[:space:]]*$'; then
  cat >&2 <<EOF
exloom review gate: BLOCKED

A required section of $CHECKLIST still contains template placeholder text. Fill in
the real evidence for the declared tier (e.g. run /smoke-test), then /review-complete.

Bypass (emergency only, audited):
  EXLOOM_REVIEW_SKIP=1
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
exloom review gate: BLOCKED

The checklist is marked "Checklist committed", but git shows otherwise:
  $CHECKLIST is untracked or has uncommitted changes.

The review evidence must ship with the code it reviews. Commit it, then retry.
EOF
    exit 2
  fi
fi

# Staleness + migration: a complete checklist must record a valid reviewed code
# commit, and no non-checklist file may have changed since it. Only enforced when
# HEAD is resolvable — fail open on genuine git/infra failure, never on content.
if git rev-parse --verify HEAD >/dev/null 2>&1; then
  REVIEWED_SHA="$(grep -E '^Reviewed code commit:' "$CHECKLIST" | head -1 | sed -E 's/^Reviewed code commit:[[:space:]]*//' | tr -d '[:space:]')"
  if [[ -z "$REVIEWED_SHA" ]] || ! [[ "$REVIEWED_SHA" =~ ^[0-9a-f]{7,40}$ ]] || ! git rev-parse --verify "${REVIEWED_SHA}^{commit}" >/dev/null 2>&1; then
    cat >&2 <<EOF
exloom review gate: BLOCKED

The checklist is marked complete but records no valid 'Reviewed code commit:',
so the review cannot be bound to the current code. A checklist created before
this field existed needs migrating.

Re-run /review-complete to record the reviewed tip before claiming done.
EOF
    exit 2
  fi
  STALE="$(git diff --name-only "$REVIEWED_SHA" HEAD -- . ':(exclude).claude/reviews' 2>/dev/null)"
  if [[ -n "$STALE" ]]; then
    cat >&2 <<EOF
exloom review gate: BLOCKED

The review is stale. These files changed after the reviewed commit
(${REVIEWED_SHA}) and are not covered by the committed review:
${STALE}

Re-run /review-complete to review the current tip before claiming done.
EOF
    exit 2
  fi

  # ---------- provenance attestation ----------
  # Who/what produced the change must be recorded; it is bound to the reviewed
  # code by the Reviewed-commit + staleness checks above.
  if ! grep -q '^- AI-assisted:' "$CHECKLIST" || ! grep -q '^- Model(s):' "$CHECKLIST" \
     || ! grep -q '^- Directed by:' "$CHECKLIST" || ! grep -q '^- Base commit:' "$CHECKLIST"; then
    cat >&2 <<EOF
exloom review gate: BLOCKED

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
exloom review gate: BLOCKED

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
