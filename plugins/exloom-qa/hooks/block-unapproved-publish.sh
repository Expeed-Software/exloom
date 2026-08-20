#!/usr/bin/env bash
# exloom-qa — PreToolUse hook (publish gate).
#
# Intercepts Bash commands that write to Azure DevOps and blocks anything that
# is not a create/update of an APPROVED test case. Every tracker write is a
# shell command (the plugin uses the az CLI, not an MCP server), so there is
# exactly one door to gate.
#
# The command is split into segments on ; && || | and newlines, and each is
# classified independently. A compound command that reads a story AND creates a
# case is judged on the create, not on the whole blob — scanning the blob made
# read-only queries collide with write patterns elsewhere in the same line.
#
# Exit codes:
#   0  — allow (no segment is a gated tracker write)
#   2  — block with a stderr explanation
#
# Fails CLOSED on the segments it gates: a Test Case write that cannot be
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

# ---------- classify one segment ----------
# Returns 0 always; denies (exit 2) from inside exloomqa_deny when warranted.
classify_segment() {
  local seg="$1"
  # Quote-stripped, whitespace-collapsed copy for --type matching.
  local norm
  norm="$(printf '%s' "$seg" | tr -d '"'"'"'' | tr -s '[:space:]' ' ')"

  # Is this segment an Azure DevOps command at all?
  #
  # The command must START the segment (after optional VAR=value assignments).
  # Merely CONTAINING "az boards ..." is not enough: prose mentions it — commit
  # messages, documentation, this comment. An unanchored match blocked a commit
  # whose message described the gate, which is a false positive with no upside.
  local prefix='^[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*(sudo[[:space:]]+)?'
  local is_ado=0
  printf '%s' "$seg" | grep -Eq "${prefix}az[[:space:]]+(boards|devops)([^[:alnum:]_]|$)" && is_ado=1
  if printf '%s' "$seg" | grep -Eq "${prefix}curl([^[:alnum:]_]|$)" \
     && printf '%s' "$seg" | grep -Eq 'dev\.azure\.com|\.visualstudio\.com'; then
    is_ado=1
  fi
  [[ "$is_ado" -eq 1 ]] || return 0

  # Does this segment use a mutating HTTP method?
  local mutating=0
  printf '%s' "$seg" | grep -Eq -- '-X[[:space:]]*(POST|PATCH|PUT|DELETE)|--request[[:space:]]+(POST|PATCH|PUT|DELETE)' && mutating=1

  # ---- unconditional denials ----
  if printf '%s' "$seg" | grep -Eq 'az[[:space:]]+boards[[:space:]]+work-item[[:space:]]+delete'; then
    exloomqa_deny \
      "This command deletes work items. exloom-qa never deletes anything on the board." \
      "If a published test case is genuinely wrong, remove it by hand in Azure DevOps."
  fi
  if printf '%s' "$seg" | grep -Eq -- '-X[[:space:]]*DELETE|--request[[:space:]]+DELETE|_apis/test/testcases/[0-9]+'; then
    exloomqa_deny \
      "This command deletes board artifacts. exloom-qa never deletes anything." \
      "Test Case deletion is permanent with no recycle bin — do it by hand if it is truly intended."
  fi
  if printf '%s' "$seg" | grep -Eq 'az[[:space:]]+boards[[:space:]]+work-item[[:space:]]+relation[[:space:]]+remove'; then
    exloomqa_deny "This command removes a work-item link. exloom-qa never removes links."
  fi
  if printf '%s' "$norm" | grep -Eqi -- '--type[[:space:]]+Test[[:space:]_-]+(Plan|Suite)|_apis/testplan|testplan|test[-_]suite|az[[:space:]]+boards[[:space:]]+.*[[:space:]]suite'; then
    exloomqa_deny \
      "This command touches Test Plans or Test Suites, which are out of scope for exloom-qa." \
      "Test Plans and Suites are managed manually by the QA team."
  fi

  # ---- linking is allowed ----
  # `relation add` carries no TC tag and creates no case. The irreversible act
  # is creating the Test Case, which was already gated at creation; a link is
  # reversible. Gating this would block exloom-qa's own publish step.
  if printf '%s' "$seg" | grep -Eq 'az[[:space:]]+boards[[:space:]]+work-item[[:space:]]+relation[[:space:]]+add'; then
    return 0
  fi

  # ---- which segments require verification ----
  local needs_check=0

  # Creating a Test Case via the CLI.
  if printf '%s' "$norm" | grep -Eq 'az[[:space:]]+boards[[:space:]]+work-item[[:space:]]+create' \
     && printf '%s' "$norm" | grep -Eqi -- '--type[[:space:]]+Test[[:space:]]+Case'; then
    needs_check=1
  fi

  # Updating a work item that carries an exloom-qa tag.
  if printf '%s' "$seg" | grep -Eq 'az[[:space:]]+boards[[:space:]]+work-item[[:space:]]+update' \
     && printf '%s' "$seg" | grep -q 'exloom-qa:'; then
    needs_check=1
  fi

  # A mutating REST call against the work-item endpoint. `_apis/wit/wiql` is a
  # POST but a READ, so it is deliberately excluded.
  if [[ "$mutating" -eq 1 ]] && printf '%s' "$seg" | grep -Eq '_apis/wit/workitems'; then
    needs_check=1
  fi

  [[ "$needs_check" -eq 1 ]] || return 0

  # ---- verification ----
  local tag_parts
  tag_parts="$(exloomqa_extract_tag "$seg" || true)"
  if [[ -z "$tag_parts" ]]; then
    exloomqa_deny \
      "This writes a Test Case with no exloom-qa provenance tag, so it cannot be matched to an approved case." \
      "Publish through /qa-test-publish, which tags every case as
  exloom-qa:<story-id>; exloom-qa:<story-id>:TC-<nnn>"
  fi

  local story_id tc_id artifact
  story_id="${tag_parts%% *}"
  tc_id="${tag_parts##* }"
  artifact="$(exloomqa_qa_dir)/${story_id}.md"

  if [[ ! -f "$artifact" ]]; then
    exloomqa_deny \
      "No exloom-qa artifact found for story ${story_id} (expected ${artifact})." \
      "Run /qa-test-init ${story_id}, then /qa-test-review to generate and approve cases."
  fi
  if ! awk '/^## Approval Record/{f=1;next} /^## /{f=0} f' "$artifact" | grep -qiE '^[[:space:]]*Approved:'; then
    exloomqa_deny \
      "${artifact} has no approval record — no test case for story ${story_id} has been approved." \
      "Run /qa-test-review and approve the cases you want published."
  fi
  if ! exloomqa_is_approved "$artifact" "$tc_id"; then
    exloomqa_deny \
      "${tc_id} is not in the approved list for story ${story_id}." \
      "Only cases named in the Approval Record of ${artifact} may be published.
Re-run /qa-test-review to approve ${tc_id} if it should ship."
  fi
  return 0
}

# ---------- split into segments and classify each ----------
while IFS= read -r seg; do
  [[ -n "${seg// /}" ]] || continue
  classify_segment "$seg"
done < <(exloomqa_segments "$CMD")

exit 0
