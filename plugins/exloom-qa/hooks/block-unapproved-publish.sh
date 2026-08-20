#!/usr/bin/env bash
# exloom-qa — PreToolUse hook (publish gate).
#
# Intercepts Bash commands that write to Azure DevOps and blocks anything that
# is not a create/update of an APPROVED test case. Every tracker write is a
# shell command (the plugin uses the az CLI, not an MCP server), so there is
# exactly one door to gate.
#
# Exit codes:
#   0  — allow (not a tracker write, or a verified approved case)
#   2  — block with a stderr explanation
#
# Fails CLOSED: a command recognised as a tracker write that cannot be
# positively attributed to an approved TC id is denied. See lib.sh.
#
# Bypass: EXLOOM_QA_SKIP=1

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=/dev/null
. "$SCRIPT_DIR/lib.sh"

if [[ "${EXLOOM_QA_SKIP:-0}" == "1" ]]; then
  echo "exloom-qa: publish gate bypassed via EXLOOM_QA_SKIP=1 (audit)" >&2
  exit 0
fi

HOOK_INPUT=""
if [[ -p /dev/stdin || ! -t 0 ]]; then
  HOOK_INPUT="$(cat 2>/dev/null || true)"
fi
[[ -n "$HOOK_INPUT" ]] || exit 0

CMD="$(exloomqa_command "$HOOK_INPUT")"
[[ -n "$CMD" ]] || exit 0

# Quote-stripped, whitespace-collapsed copy. Matching `--type "Test Plan"` is
# unreadable once shell quoting is layered on, so type checks run against this.
CMD_NORM="$(printf '%s' "$CMD" | tr -d '"'"'"'' | tr -s '[:space:]' ' ')"

# ---------- is this an Azure DevOps write at all? ----------
# az boards ... | az devops invoke | a non-GET curl at an ADO host.
IS_ADO=0
printf '%s' "$CMD" | grep -Eq '(^|[^[:alnum:]_])az[[:space:]]+(boards|devops)([^[:alnum:]_]|$)' && IS_ADO=1
if printf '%s' "$CMD" | grep -Eq 'dev\.azure\.com|\.visualstudio\.com'; then
  if printf '%s' "$CMD" | grep -Eq '(^|[^[:alnum:]_])curl([^[:alnum:]_]|$)' \
     && printf '%s' "$CMD" | grep -Eq -- '-X[[:space:]]*(POST|PATCH|PUT|DELETE)|--request[[:space:]]+(POST|PATCH|PUT|DELETE)'; then
    IS_ADO=1
  fi
fi
[[ "$IS_ADO" -eq 1 ]] || exit 0

# ---------- read-only operations pass straight through ----------
# Reading the story is required BEFORE approval exists, so these must never block.
if printf '%s' "$CMD" | grep -Eq 'az[[:space:]]+boards[[:space:]]+(work-item[[:space:]]+show|query|iteration|area)|az[[:space:]]+boards[[:space:]]+work-item[[:space:]]+relation[[:space:]]+list-type|az[[:space:]]+devops[[:space:]]+(project|user)[[:space:]]+(list|show)'; then
  exit 0
fi

# ---------- unconditional denials ----------
if printf '%s' "$CMD" | grep -Eq 'az[[:space:]]+boards[[:space:]]+work-item[[:space:]]+delete|_apis/test/testcases/[0-9]+|-X[[:space:]]*DELETE|--request[[:space:]]+DELETE'; then
  exloomqa_deny \
    "This command deletes work items. exloom-qa never deletes anything on the board." \
    "If a published test case is genuinely wrong, remove it by hand in Azure DevOps."
fi

if printf '%s' "$CMD_NORM" | grep -Eqi -- '--type[[:space:]]+Test[[:space:]_-]+(Plan|Suite)|_apis/testplan|testplan|test[-_]suite|az[[:space:]]+boards[[:space:]]+.*[[:space:]]suite'; then
  exloomqa_deny \
    "This command touches Test Plans or Test Suites, which are out of scope for exloom-qa." \
    "Test Plans and Suites are managed manually by the QA team."
fi

# ---------- work-item writes ----------
IS_WRITE=0
printf '%s' "$CMD" | grep -Eq 'az[[:space:]]+boards[[:space:]]+work-item[[:space:]]+(create|update)' && IS_WRITE=1
printf '%s' "$CMD" | grep -Eq 'az[[:space:]]+boards[[:space:]]+work-item[[:space:]]+relation[[:space:]]+(add|remove)' && IS_WRITE=1
printf '%s' "$CMD" | grep -Eq '_apis/wit/workitems' && IS_WRITE=1
[[ "$IS_WRITE" -eq 1 ]] || exit 0

# A create of something other than a Test Case is not this gate's business —
# exloom-qa only ever creates Test Cases, so another type is someone else's work.
if printf '%s' "$CMD" | grep -Eq 'az[[:space:]]+boards[[:space:]]+work-item[[:space:]]+create' \
   && ! printf '%s' "$CMD" | grep -Eqi -- '--type[[:space:]]+["'"'"']?Test[[:space:]]+Case'; then
  exit 0
fi

# ---------- from here on, verification is required ----------
TAG_PARTS="$(exloomqa_extract_tag "$CMD" || true)"
if [[ -z "$TAG_PARTS" ]]; then
  exloomqa_deny \
    "This writes a Test Case with no exloom-qa provenance tag, so it cannot be matched to an approved case." \
    "Publish through /qa-test-publish, which tags every case as
  exloom-qa:<story-id>; exloom-qa:<story-id>:TC-<nnn>"
fi

STORY_ID="${TAG_PARTS%% *}"
TC_ID="${TAG_PARTS##* }"
ARTIFACT="$(exloomqa_qa_dir)/${STORY_ID}.md"

if [[ ! -f "$ARTIFACT" ]]; then
  exloomqa_deny \
    "No exloom-qa artifact found for story ${STORY_ID} (expected ${ARTIFACT})." \
    "Run /qa-test-init ${STORY_ID}, then /qa-test-review to generate and approve cases."
fi

if ! awk '/^## Approval Record/{f=1;next} /^## /{f=0} f' "$ARTIFACT" | grep -qiE '^[[:space:]]*Approved:'; then
  exloomqa_deny \
    "${ARTIFACT} has no approval record — no test case for story ${STORY_ID} has been approved." \
    "Run /qa-test-review and approve the cases you want published."
fi

if ! exloomqa_is_approved "$ARTIFACT" "$TC_ID"; then
  exloomqa_deny \
    "${TC_ID} is not in the approved list for story ${STORY_ID}." \
    "Only cases named in the Approval Record of ${ARTIFACT} may be published.
Re-run /qa-test-review to approve ${TC_ID} if it should ship."
fi

exit 0
