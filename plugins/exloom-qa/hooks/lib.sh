#!/usr/bin/env bash
# exloom-qa — shared hook library. SOURCED by block-unapproved-publish.sh;
# never executed directly.
#
# Design note — this library FAILS CLOSED, which is the opposite of exloom's
# review gate. exloom blocks a `git push`, which is reversible. This gate blocks
# the creation of Azure DevOps Test Cases, which are NOT: the work-item API
# refuses to delete them, and the Test Management API destroys them permanently
# with no recycle bin. A false denial costs one clarifying message; a false
# allow puts unapproved work items on a live board that cannot be swept back.
#
# No git. The working folder may be an ordinary directory. Artifacts are keyed
# by story ID, never by branch, and nothing here shells out to git.

# ---------- resolve a usable Python ----------
# Do not assume the name `python3`. Windows installs from winget and python.org
# provide `python` but NOT `python3`, and Windows ships a `python3` App
# Execution Alias stub that prints "Python was not found…" instead of running
# anything. A `command -v python3` check therefore succeeds on a machine with no
# usable Python, and fails on a machine that has one.
#
# So the name is never trusted: each candidate is asked to execute something and
# is accepted only if the right answer comes back. Echoes the working command,
# or returns non-zero when there is none.
EXLOOMQA_PY=""
exloomqa_python() {
  if [[ -n "$EXLOOMQA_PY" ]]; then printf '%s' "$EXLOOMQA_PY"; return 0; fi
  local candidate
  for candidate in python3 python; do
    command -v "$candidate" >/dev/null 2>&1 || continue
    if [[ "$("$candidate" -c 'print(1)' 2>/dev/null)" == "1" ]]; then
      EXLOOMQA_PY="$candidate"
      printf '%s' "$candidate"
      return 0
    fi
  done
  return 1
}

# ---------- JSON field extraction (jq -> python -> sed) ----------
exloomqa_json_field() {
  local json="$1" field="$2" out=""
  if command -v jq >/dev/null 2>&1; then
    out="$(printf '%s' "$json" | jq -r --arg f "$field" '.[$f] // empty' 2>/dev/null || true)"
  fi
  local py
  py="$(exloomqa_python || true)"
  if [[ -z "$out" && -n "$py" ]]; then
    out="$(printf '%s' "$json" | FIELD="$field" "$py" -c 'import json,os,sys
try:
    print(json.load(sys.stdin).get(os.environ["FIELD"],""))
except Exception:
    pass' 2>/dev/null || true)"
  fi
  if [[ -z "$out" ]]; then
    out="$(printf '%s' "$json" | sed -n "s/.*\"$field\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -1)"
  fi
  printf '%s' "$out"
}

# Extract tool_input.command. A shell command contains quotes, so the sed
# fallback used above is unsafe here — fall back to the RAW input instead, which
# only ever makes the matching MORE eager (fail closed).
exloomqa_command() {
  local json="$1" cmd=""
  if command -v jq >/dev/null 2>&1; then
    cmd="$(printf '%s' "$json" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
  fi
  local py
  py="$(exloomqa_python || true)"
  if [[ -z "$cmd" && -n "$py" ]]; then
    cmd="$(printf '%s' "$json" | "$py" -c 'import json,sys
try:
    d=json.load(sys.stdin)
    print((d.get("tool_input") or {}).get("command",""))
except Exception:
    pass' 2>/dev/null || true)"
  fi
  [[ -z "$cmd" ]] && cmd="$json"
  printf '%s' "$cmd"
}

# Split a shell command into segments on newline, ; && || and |, IGNORING those
# characters when they appear inside quotes. Quote-awareness is not optional:
# a Test Case tag value is "exloom-qa:10420; exloom-qa:10420:TC-007; Negative",
# so a naive split on ';' severs the tag from its own command and the gate then
# denies a properly tagged, approved case.
# Without a usable Python, emit the command unsplit — coarser, and fail-closed.
exloomqa_segments() {
  local cmd="$1" py
  py="$(exloomqa_python || true)"
  if [[ -n "$py" ]]; then
    CMD_ENV="$cmd" "$py" -c '
import os
s = os.environ.get("CMD_ENV", "")
DQ, SQ = chr(34), chr(39)
out, cur, q, i = [], [], None, 0
while i < len(s):
    c = s[i]
    if q:
        cur.append(c)
        if c == q:
            q = None
        i += 1
        continue
    if c in (DQ, SQ):
        q = c; cur.append(c); i += 1; continue
    if s[i:i+2] in ("&&", "||"):
        out.append("".join(cur)); cur = []; i += 2; continue
    if c in (chr(10), ";", "|"):
        out.append("".join(cur)); cur = []; i += 1; continue
    cur.append(c); i += 1
out.append("".join(cur))
for seg in out:
    seg = seg.strip()
    if seg:
        print(seg)
' 2>/dev/null
  else
    printf '%s\n' "$cmd"
  fi
}

# ---------- artifact location ----------
exloomqa_qa_dir() {
  printf '%s' "${CLAUDE_PROJECT_DIR:-$PWD}/.claude/qa"
}

# ---------- provenance tag ----------
# Echo "<story-id> <tc-id>" from the first exloom-qa:<story>:TC-<nnn> tag in the
# command. Echoes nothing when absent — callers treat that as a denial.
exloomqa_extract_tag() {
  local cmd="$1" tag
  tag="$(printf '%s' "$cmd" | grep -oE 'exloom-qa:[A-Za-z0-9_-]+:TC-[0-9]+' | head -1)"
  [[ -z "$tag" ]] && return 1
  local story tc
  story="$(printf '%s' "$tag" | cut -d: -f2)"
  tc="$(printf '%s' "$tag" | cut -d: -f3)"
  printf '%s %s' "$story" "$tc"
}

# ---------- approval record ----------
# Is <tc-id> listed in the artifact's Approval Record? Understands comma lists
# and "TC-001..TC-012" / "TC-001 to TC-012" ranges. Any parse failure returns
# non-zero (deny), never a permissive default.
exloomqa_is_approved() {
  local artifact="$1" tc="$2"
  [[ -f "$artifact" ]] || return 1
  local line
  line="$(awk '/^## Approval Record/{f=1;next} /^## /{f=0} f' "$artifact" \
          | grep -iE '^[[:space:]]*Approved:' | head -1)"
  [[ -n "$line" ]] || return 1
  local py
  if ! py="$(exloomqa_python)"; then
    echo "exloom-qa: no usable Python found (tried python3, python) — cannot read the approval record, so the write is denied. Install Python, or run the publish by hand." >&2
    return 1
  fi
  ARTIFACT_APPROVED_LINE="$line" TC="$tc" "$py" -c '
import os, re, sys
line = os.environ["ARTIFACT_APPROVED_LINE"]
want = int(re.sub(r"\D", "", os.environ["TC"]) or -1)
if want < 0:
    sys.exit(1)
line = re.sub(r"(?i)^\s*approved:\s*", "", line)
ok = False
for part in line.split(","):
    part = part.strip()
    if not part:
        continue
    m = re.match(r"(?i)TC-0*(\d+)\s*(?:\.\.|to|-)\s*TC-0*(\d+)$", part)
    if m:
        lo, hi = int(m.group(1)), int(m.group(2))
        if lo <= want <= hi:
            ok = True
    else:
        m = re.match(r"(?i)TC-0*(\d+)$", part)
        if m and int(m.group(1)) == want:
            ok = True
sys.exit(0 if ok else 1)
' 2>/dev/null
}

# ---------- denial ----------
exloomqa_deny() {
  local reason="$1" fix="${2:-}"
  cat >&2 <<EOF
exloom-qa publish gate: BLOCKED.

${reason}
EOF
  [[ -n "$fix" ]] && printf '\n%s\n' "$fix" >&2
  cat >&2 <<'EOF'

Azure DevOps Test Cases cannot be deleted through the work-item API, and the
Test Management API destroys them permanently with no recycle bin. This gate
denies anything it cannot positively verify, by design.

Bypass (audited): set EXLOOM_QA_SKIP=1 in your Claude Code session env
(settings.json "env"), then retry. An inline "EXLOOM_QA_SKIP=1 <cmd>" will NOT
work — the hook reads its own environment, not the command's.
EOF
  exit 2
}
