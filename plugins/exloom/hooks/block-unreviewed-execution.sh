#!/usr/bin/env bash
# exloom — PreToolUse hook (plan-execution gate).
#
# OPT-IN: does nothing unless the repo created `.claude/exloom-gate.enabled`.
#
# WHY THIS EXISTS. exloom enforced review on CODE and merely recommended it on
# the PLAN. `reviewing-plans` opens with "Plan author and executor are different
# people. No exceptions." — and then ships no agent and no receipt, so it
# degrades to self-review by default. A session writes a plan, reviews its own
# plan, and executes it. Every defect the plan carries is then reproduced by
# every regeneration of the code, which is precisely what breaks the premise
# that the spec is durable and the code is throwaway: you cannot throw code away
# and rebuild it from a plan nobody independently read.
#
# So this hook blocks the FIRST source edit on a branch that carries a plan for
# which no `plan-reviewer` receipt covers the plan-or-spec's current
# content. Receipts are written by hooks/record-reviewer-verdict.sh on a real
# subagent dispatch and cannot be written by hand (hooks/protect-verdicts.sh).
#
# BOUND TO CONTENT, NOT TO TIME. The receipt names the artifact's git blob hash.
# Editing the plan after it was reviewed changes the hash, the receipt stops
# covering it, and execution blocks until it is reviewed again. That is the
# FREEZE rule expressed as a mechanism instead of a paragraph.
#
# READ FROM THE WORKING TREE, not from a ref, because execution begins before
# anything is committed. Forgery is not a concern here: protect-verdicts.sh
# denies writing into the verdicts directory.
#
# Exit codes:
#   0  — allow (gate off, no plan in play, artifact is itself a plan/doc/review,
#              receipt covers the plan, or ANY infrastructure failure)
#   2  — block with a stderr message
#
# Bypass (audited): EXLOOM_REVIEW_SKIP=1

set -u
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
# shellcheck source=/dev/null
. "$SCRIPT_DIR/lib.sh"

# ---------- bypass ----------
if [[ "${EXLOOM_REVIEW_SKIP:-0}" == "1" ]]; then
  echo "exloom: plan-execution bypass via EXLOOM_REVIEW_SKIP=1 (audit)" >&2
  exit 0
fi

# ---------- read hook input ----------
HOOK_INPUT=""
if [[ -p /dev/stdin || ! -t 0 ]]; then
  HOOK_INPUT="$(cat 2>/dev/null || true)"
fi
[[ -n "$HOOK_INPUT" ]] || exit 0

TOOL="$(exloom_json_field "$HOOK_INPUT" tool_name)"

# Nested tool_input fields; exloom_json_field only reads top-level keys.
_tool_input() {
  printf '%s' "$HOOK_INPUT" \
    | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -1
}

TARGET=""
IS_SHELL=0
case "$TOOL" in
  Write|Edit|MultiEdit|NotebookEdit)
    TARGET="$(_tool_input file_path)"
    # NotebookEdit carries notebook_path, not file_path. Without this fallback
    # every notebook edit is ungated — and in an ML repo the notebook IS source.
    [[ -z "$TARGET" ]] && TARGET="$(_tool_input notebook_path)"
    [[ -n "$TARGET" ]] || exit 0
    ;;
  Bash)
    # Shell writes are how a session edits source when a formatter, codegen step
    # or `sed -i` is the natural tool. Leaving Bash ungated left the gate off the
    # path the work actually takes. There is no single target path to resolve
    # here, so any WRITE-shaped command is gated when a plan is uncovered;
    # reads, greps, builds and git inspection stay free.
    CMD="$(_tool_input command)"
    [[ -n "$CMD" ]] || exit 0
    CMD="${CMD//$'\n'/ }"; CMD="${CMD//$'\t'/ }"
    # Redirections to /dev/null, &1 and &2 are NOT writes. `>>?` matched
    # `2>/dev/null` and `2>&1`, so `grep -rn foo src/ 2>/dev/null`, `./gradlew test`,
    # `npm run test` and `go build ./...` were all gated — and under a review freeze
    # that locks out the reviewers just dispatched and the smoke test the gate
    # itself requires. Strip those forms before shape-matching.
    SHAPE="$(printf '%s' "$CMD" | sed -e 's/[0-9]*>&[0-9]*//g' -e 's/[0-9]*>>\{0,1\}[[:space:]]*\/dev\/null//g')"
    printf '%s' "$SHAPE" | grep -Eq '>>?|(^|[^[:alnum:]_])(rm|mv|cp|tee|truncate|install|dd|patch|touch|chmod|ln|npx|protoc|gofmt|goimports|black|ruff|isort|prettier|eslint|rustfmt|clang-format)([^[:alnum:]_]|$)|sed[[:space:]]+[^|;]*-i|awk[[:space:]]+[^|;]*-i[[:space:]]*inplace|(npm|yarn|pnpm)[[:space:]]+install|(go|cargo|dotnet)[[:space:]]+(generate|fmt)|(python[0-9.]*|perl|node|ruby|php|deno|bun)[[:space:]]+-[a-zA-Z]*[ce]|git[[:space:]]+(apply|checkout|switch|clean|merge|rebase|reset|cherry-pick|restore|stash|revert|am)|git[[:space:]]+branch[[:space:]]+-[mMdD]|git[[:space:]]+worktree[[:space:]]+(add|remove|prune)' || exit 0
    # Narrowed to the LITERAL files the block messages tell a session to create.
    # The previous rule exempted any command merely MENTIONING `.claude/` unless it
    # also named src|lib|app|test|tests|pkg|cmd — so
    #   `cat .claude/exloom-gate.enabled; sed -i s/a/b/ internal/server/handler.go`
    # bypassed everything, and it silently ungated every Go (internal/), Java
    # (main/java/), .NET and plugin-shaped repo whose source is not under those six
    # names. It also sat above the freeze check, so it lifted the freeze too.
    if printf '%s' "$CMD" | grep -Eq '(^|[;&|(][[:space:]]*)(touch|:[[:space:]]*>|printf|echo)[^;&|]*[.]claude/exloom-(no-plan|plan-dirs|test-command)([[:space:]]|$)'; then
      exit 0
    fi
    IS_SHELL=1
    TARGET="$CMD"
    ;;
  *) exit 0 ;;
esac
# Windows paths arrive escaped and/or backslashed; normalise for matching only.
# BOTH lines are required and neither touches forward slashes (verified byte-exact):
#   line 1: pattern `\\\\` matches a DOUBLED backslash (JSON-escaped) -> `/`
#   line 2: pattern `\\`   matches a SINGLE backslash               -> `/`
# `E:\p\docs\x.md` needs the second; `E:\\p\\docs\\x.md` needs the first.
TARGET="${TARGET//\\\\//}"
TARGET="${TARGET//\\//}"

# ---------- repo + opt-in ----------
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
[[ -n "$REPO_ROOT" ]] || exit 0
cd "$REPO_ROOT" || exit 0
[[ -f ".claude/exloom-gate.enabled" ]] || exit 0

BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)" || exit 0
[[ -n "$BRANCH" && "$BRANCH" != "HEAD" ]] || exit 0
exloom_is_protected_branch "$BRANCH" && exit 0
exloom_is_skip_branch "$BRANCH" && exit 0

# ---------- is the edit itself exempt? ----------
# Editing a plan, a spec, or the review artifacts is never "executing the plan" —
# and blocking a plan edit would make a rejected plan unfixable.
#
# Matched REPO-RELATIVE, deliberately. Matching the raw path meant a repo checked
# out beneath any directory named `docs` was permanently exempt for reasons
# nobody could guess. A blanket `*.md` was worse: this plugin's entire product is
# markdown, so exloom could not gate its own execution.
if [[ $IS_SHELL -eq 0 ]]; then
  REL="$TARGET"
  case "$REL" in
    "$REPO_ROOT"/*) REL="${REL#"$REPO_ROOT"/}" ;;
    ./*)            REL="${REL#./}" ;;
  esac
  case "$REL" in
    docs/*|.claude/*) exit 0 ;;
  esac
fi

# ---------- is this branch frozen for review? ----------
# A review examines a FINISHED artifact. Editing source while reviewers are
# running turns review into a development loop that cannot converge: every fix
# invalidates the artifact, so the next round reviews something that did not exist
# when the last round started, and what finally ships has never been reviewed —
# only its predecessor has.
STATE_FILE=".claude/reviews/${BRANCH}.state"
if [[ -f "$STATE_FILE" ]]; then
  ST="$(sed -n 's/.*"state":"\([A-Z]*\)".*/\1/p' "$STATE_FILE" | tail -1)"
  RND="$(sed -n 's/.*"round":\([0-9]*\).*/\1/p' "$STATE_FILE" | tail -1)"
  if [[ "$ST" == "REVIEW" ]]; then
    cat >&2 <<EOF
exloom review gate: BLOCKED — this branch is frozen for review (round ${RND:-?}).

You are editing source while a review of that source is in flight. The verdict
would then describe code that no longer exists, and the code that ships would
never have been reviewed at all.

If you are acting on findings, leave review deliberately — it is recorded, and the
round counter is what tells you whether review is converging:

    bash "$SCRIPT_DIR/../scripts/exit-review.sh" "acting on round ${RND:-?} findings"

Before you do: a PRE-EXISTING finding is a backlog entry, not work for this branch.

Emergency bypass (audited): set EXLOOM_REVIEW_SKIP=1 in your session env.
EOF
    exit 2
  fi
fi

# ---------- which plans are in play on this branch? ----------
# Enumerated from the FILESYSTEM, not from git.
#
# An earlier version discovered plans through `git status` + a merge-base diff,
# and each of those had a silent hole that reproduced in a scratch repo:
#   - `git mv docs/plans/a.md b.md` -> porcelain emits "R  a.md -> b.md"; the
#     arrow was parsed as a path, the file did not exist, the plan vanished.
#   - `.claude/` in .gitignore -> porcelain lists nothing, plan vanished.
#   - no origin/{main,master,dev,develop} ref -> merge-base empty, the whole
#     committed-plan arm was skipped, plan vanished.
# All three failed OPEN, which for a gate is the worst possible direction: it
# looks installed and enforces nothing. `find` sees every plan on disk however it
# got there, and cannot be disarmed by a rename, an ignore rule, or a remote name.
PLAN_DIRS=()
for d in docs/plans docs/exloom/plans .claude/plans docs/specs docs/exloom/specs; do
  [[ -d "$d" ]] && PLAN_DIRS+=( "$d" )
done
# A repo may name additional plan roots (one path per line, committed).
if [[ -f ".claude/exloom-plan-dirs" ]]; then
  while IFS= read -r d; do
    d="${d%%#*}"; d="${d#"${d%%[![:space:]]*}"}"; d="${d%"${d##*[![:space:]]}"}"
    [[ -n "$d" && -d "$d" ]] && PLAN_DIRS+=( "$d" )
  done < ".claude/exloom-plan-dirs"
fi

# No plan anywhere the gate can see. Previously this exited 0 — so a session that
# kept its plan in the conversation, in PLAN.md, in docs/design/ or in a ticket was
# never gated at all, and nothing said so. The gate silently did not apply, which
# is the failure mode it exists to prevent.
if [[ ${#PLAN_DIRS[@]} -eq 0 ]] && [[ ! -f ".claude/exloom-no-plan" ]]; then
  cat >&2 <<EOF
exloom review gate: BLOCKED — the gate is enabled but no plan is visible to it.

Looked in: docs/plans, docs/exloom/plans, .claude/plans, docs/specs, docs/exloom/specs

A plan held in the conversation, in a ticket, or in a directory this gate does not
know about means the plan gate and the scope gate both silently do nothing. That is
worse than no gate, because the checklist still says the branch was gated.

Pick one:
  1. Put the plan somewhere above, or name its directory in a committed
     .claude/exloom-plan-dirs (one path per line).
  2. This branch genuinely has no plan (a one-line fix, a revert):
       touch .claude/exloom-no-plan
     Commit it. It is a recorded decision, visible in review, not a silent skip.

Emergency bypass (audited): set EXLOOM_REVIEW_SKIP=1 in your session env.
EOF
  exit 2
fi
[[ ${#PLAN_DIRS[@]} -gt 0 ]] || exit 0

# A branch may NAME its plan in the checklist, which ends the guessing entirely:
#
#     **Plan:** docs/plans/2026-08-30-my-feature-plan.md
#
# Turning the gate on in this repo listed ELEVEN plans as this branch's unreviewed
# work — untracked historical planning documents from April and June that the branch
# never touched. "Not present at the fork point" is not the same as "this branch
# wrote it", and for an untracked file git cannot tell the difference. A named plan
# is unambiguous; the directory scan stays as the fallback for branches that do not
# name one.
CHECKLIST=".claude/reviews/${BRANCH}.md"
NAMED_PLAN=""
if [[ -f "$CHECKLIST" ]]; then
  # First line only, first whitespace-delimited token only. Taking the whole value
  # swallowed a multi-line justification and tried to open it as a path.
  NAMED_PLAN="$(sed -n 's/^\*\*Plan:\*\*[[:space:]]*//p' "$CHECKLIST" | head -1                 | tr -d '`' | awk '{print $1}')"
fi
# "none" is a first-class answer, recorded where a reviewer reads it rather than in
# an untracked marker file. A branch that genuinely has no plan says so in the
# checklist, and that statement ships with the PR.
case "$(printf '%s' "$NAMED_PLAN" | tr '[:upper:]' '[:lower:]')" in
  none|n/a|-) 
    echo "exloom: checklist declares no plan for '$BRANCH' — plan and scope gates do not apply (audit)" >&2
    NAMED_PLAN="__NONE__" ;;
esac

if [[ "$NAMED_PLAN" == "__NONE__" ]]; then
  exit 0
elif [[ -n "$NAMED_PLAN" ]]; then
  if [[ -f "$NAMED_PLAN" ]]; then
    PLANS="$NAMED_PLAN"
  else
    cat >&2 <<EOF
exloom review gate: BLOCKED — the checklist names a plan that does not exist.

  named: ${NAMED_PLAN}

Fix the **Plan:** line in ${CHECKLIST}, or remove it to fall back to scanning the
plan directories.
EOF
    exit 2
  fi
else

ALL_PLANS="$(find "${PLAN_DIRS[@]}" -type f -name '*.md' 2>/dev/null | sed 's|^\./||' | sort -u)"
# An EMPTY plan directory must take the same branch as no plan directory. Otherwise
# `mkdir -p docs/plans` is a one-command, permanent, silent disarm of both the plan
# gate and the scope gate — "looks installed and enforces nothing", which is the
# worst direction a gate can fail in.
if [[ -z "$ALL_PLANS" ]] && [[ ! -f ".claude/exloom-no-plan" ]]; then
  cat >&2 <<EOF
exloom review gate: BLOCKED — a plan directory exists but contains no plan.

Found: ${PLAN_DIRS[*]}

An empty plan directory is treated exactly like no plan at all. Otherwise creating
one would silently disable both the plan gate and the scope gate, and the checklist
would still claim the branch was gated.

Pick one:
  1. Write the plan, and have it reviewed:  Agent(subagent_type: "exloom:plan-reviewer", ...)
  2. This branch genuinely has no plan:     touch .claude/exloom-no-plan   (commit it)

Emergency bypass (audited): set EXLOOM_REVIEW_SKIP=1 in your session env.
EOF
  exit 2
fi
[[ -n "$ALL_PLANS" ]] || exit 0

# "In play" = this branch's work. A plan tracked and byte-identical to the fork
# point belongs to earlier work and must not gate every future branch forever.
# When the fork point cannot be resolved, EVERY plan is in play — failing open on
# *detection* is not the same decision as failing open on infrastructure error,
# and this is the detection step.
BASE="$(git merge-base HEAD origin/main 2>/dev/null \
     || git merge-base HEAD origin/master 2>/dev/null \
     || git merge-base HEAD origin/dev 2>/dev/null \
     || git merge-base HEAD origin/develop 2>/dev/null \
     || git merge-base HEAD "$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null)" 2>/dev/null \
     || true)"

PLANS=""
while IFS= read -r p; do
  [[ -z "$p" ]] && continue
  # MSYS_NO_PATHCONV: Git Bash on Windows mangles a `ref:path` argument (colon -> ';',
  # '/' -> '\'), so BOTH lookups failed and EVERY plan on disk was treated as in play
  # on every branch, forever. Turning the gate on in this repo listed eleven plans from
  # April and June as unreviewed work for a branch that never touched them — which is a
  # block a session cannot satisfy, and therefore a straight path to EXLOOM_REVIEW_SKIP.
  # Every other `ref:path` call in lib.sh already carries this guard.
  if [[ -n "$BASE" ]] && MSYS_NO_PATHCONV=1 git cat-file -e "${BASE}:${p}" 2>/dev/null; then
    # Present at the fork point — in play only if its content has changed since.
    if [[ "$(MSYS_NO_PATHCONV=1 git rev-parse "${BASE}:${p}" 2>/dev/null)" == "$(git hash-object "$p" 2>/dev/null)" ]]; then
      continue
    fi
  fi
  PLANS+="${p}"$'\n'
done <<< "$ALL_PLANS"

PLANS="$(printf '%s' "$PLANS" | sed '/^$/d' | sort -u)"

fi

[[ -n "$PLANS" ]] || exit 0

# ---------- does a receipt cover each plan's CURRENT content? ----------
VDIR="$(exloom_verdict_dir ".claude/reviews/${BRANCH}.md")"
UNCOVERED=""
while IFS= read -r plan; do
  [[ -z "$plan" ]] && continue
  [[ -f "$plan" ]] || continue          # deleted plan gates nothing
  hash="$(git hash-object "$plan" 2>/dev/null || true)"
  [[ -n "$hash" ]] || continue          # cannot hash -> fail open on this plan
  covered=0
  seen_verdict=""
  for agent in plan-reviewer; do
    f="${VDIR}/${agent}.json"
    [[ -f "$f" ]] || continue
    # A receipt covers this plan only if it names this artifact, this exact
    # content hash, AND carries an APPROVED verdict.
    #
    # The verdict requirement is the difference between "a reviewer ran" and
    # "the work was reviewed". Without it a REJECTED report opened the gate
    # identically to an approval, so the mechanism enforced attendance rather
    # than review. UNKNOWN (no parsable verdict line) is NOT approval — a gate
    # may not guess in the permissive direction.
    while IFS= read -r rline || [[ -n "$rline" ]]; do
      [[ "$rline" == *"\"artifact\":\"${plan}\""* ]] || continue
      [[ "$rline" == *"\"artifact_hash\":\"${hash}\""* ]] || continue
      if [[ "$rline" == *'"verdict":"APPROVED"'* ]]; then
        covered=1; break
      fi
      # Remember the most recent non-approving verdict so the block message can
      # say "your reviewer rejected this" rather than "no review found", which
      # are different problems with different next actions.
      case "$rline" in
        *'"verdict":"REJECTED"'*) seen_verdict="REJECTED" ;;
        *'"verdict":"UNKNOWN"'*)  seen_verdict="UNKNOWN" ;;
      esac
    done < "$f"
    [[ $covered -eq 1 ]] && break
  done
  if [[ $covered -ne 1 ]]; then
    case "$seen_verdict" in
      REJECTED) UNCOVERED+="  - ${plan}  [reviewed, verdict REJECTED — fix the findings]"$'\n' ;;
      UNKNOWN)  UNCOVERED+="  - ${plan}  [reviewed, but no 'VERDICT: APPROVED' line was found in the report]"$'\n' ;;
      *)        UNCOVERED+="  - ${plan}  [no review]"$'\n' ;;
    esac
  fi
done <<< "$PLANS"

if [[ -z "$UNCOVERED" ]]; then
  # ---------- scope: is this file in the approved plan? ----------
  # Every plan in play is approved, so the plan now defines the branch's scope.
  # A file the plan never names is scope creep, and scope creep is the single
  # largest round multiplier measured in real transcripts: four of nine rounds on
  # one branch reviewed a detector the author invented mid-review, and the branch
  # finished "roughly three features larger than the bug it was opened to fix".
  #
  # The author's own diagnosis of how it happens: "I never asked 'is this in the
  # scope of the branch'. I asked 'is this worth doing', which is always yes, and
  # that question has no stopping condition."
  #
  # Shell writes cannot be resolved to a single path, so they are not scope-checked
  # here — the review freeze above already covers the dangerous window.
  [[ $IS_SHELL -eq 0 ]] || exit 0

  REL="$TARGET"
  case "$REL" in
    "$REPO_ROOT"/*) REL="${REL#"$REPO_ROOT"/}" ;;
    ./*)            REL="${REL#./}" ;;
  esac

  # Any path-shaped token anywhere in an in-play plan counts as naming the file:
  # deliberately permissive, because the target is the file the plan never mentions
  # at all, not a table-formatting quibble.
  in_scope=0
  while IFS= read -r plan; do
    [[ -n "$plan" && -f "$plan" ]] || continue
    # Anchored, not a bare substring. `grep -F "main.go"` matched INSIDE
    # `cmd/x/main.go`, so a plan naming a nested file authorised the root one — and
    # a plan naming `src/api/user.ts` authorised `src/api/user.ts.bak`. The path
    # must be followed by end-of-line or a character that cannot continue a path.
    rel_re="$(printf '%s' "$REL" | sed 's/[^A-Za-z0-9_/-]/[&]/g')"
    if grep -qE -- "(^|[^A-Za-z0-9_./-])${rel_re}([^A-Za-z0-9_./-]|$)" "$plan" 2>/dev/null; then in_scope=1; break; fi
    # Basename fallback ONLY when that basename is unique in the repo. Otherwise a
    # plan naming src/app.ts authorised tools/scratch/app.ts, and any plan
    # mentioning package.json / index.ts / __init__.py / main.go opened every
    # same-named file there is.
    base="$(basename "$REL")"
    # Anchored `(^|/)` so a repo-ROOT file is counted — `/${base}$` never matched
    # one, so the uniqueness rule never fired for root files and a plan naming
    # cmd/x/main.go still authorised editing ./main.go. `$base` is also escaped
    # before entering the ERE; unescaped, `.` in `app.ts` matched any character.
    base_re="$(printf '%s' "$base" | sed 's/[^A-Za-z0-9_-]/[&]/g')"
    if [[ "$(git ls-files | grep -cE "(^|/)${base_re}$")" -le 1 ]] && grep -qF -- "$base" "$plan" 2>/dev/null; then in_scope=1; break; fi
  done <<< "$PLANS"

  [[ $in_scope -eq 1 ]] && exit 0
  # A file that already exists and is untouched on this branch is being read-modified
  # for the first time; that is exactly the case worth stopping.
  cat >&2 <<EOF
exloom review gate: BLOCKED — '${REL}' is not named in this branch's approved plan.

Plans in play:
$(printf '%s\n' "$PLANS" | sed 's/^/  - /')

This is the decision point that otherwise never happens. Pick one:

  1. IN SCOPE — add the file to the plan's "Files to Touch" and say why. That
     invalidates the plan's approval, so it gets re-reviewed. That is the cost,
     and it is the point.
  2. NOT IN SCOPE — put it in the backlog and leave it alone. A defect someone
     found in passing is a ticket, not work for this branch.

Measured on real branches, editing files the plan never named is the largest
single cause of long review loops: the branch grows, the diff grows, per-pass
review coverage drops, and the extra rounds are spent on code that should not
have been there.

Emergency bypass (audited): set EXLOOM_REVIEW_SKIP=1 in your session env.
EOF
  exit 2
fi

cat >&2 <<EOF
exloom review gate: BLOCKED — cannot edit source while an unreviewed plan is in play.

This branch carries a plan with no independent review covering its current content:
${UNCOVERED}
Executing a plan you reviewed yourself is the failure this gate exists to stop:
every defect in the plan is reproduced by every regeneration of the code, so the
code is not throwaway and the plan is not a spec — it is an unreviewed draft with
tasks in it.

Fix: dispatch the reviewer, then re-run.

    Agent(subagent_type: "exloom:plan-reviewer",
          prompt: "Review <plan path> for handoff-readiness ...")

exloom records the receipt when the subagent actually completes — it cannot be
written by hand. Editing the plan after review invalidates the receipt by design;
review it again.

Emergency bypass (audited): set EXLOOM_REVIEW_SKIP=1 in your Claude Code session
env (settings.json "env"), then retry.
EOF
exit 2
