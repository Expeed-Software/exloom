#!/usr/bin/env bash
# exloom — shared hook library. SOURCED by block-unverified-push.sh and
# protect-verdicts.sh; never executed directly. Keeping the checklist
# validation, branch classification, and JSON extraction in one place means the
# Stop hook and the push gate can never silently disagree about what "complete"
# means (they used to duplicate ~150 lines).
#
# All functions assume the caller has already cd'd to the repo root when they
# touch git. Every git failure fails OPEN (return/exit 0 at the call site) —
# exloom blocks on missing evidence, never on an infrastructure hiccup.

# Resolved once so block messages can print a command that actually runs.
# `${CLAUDE_PLUGIN_ROOT}` is interpolated by the harness into plugin.json only;
# it is NOT set in the Bash tool environment, so every remediation command that
# used it failed with "No such file or directory" and left the bypass as the
# only reachable option.
EXLOOM_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

# ---------- JSON field extraction (jq -> python3 -> sed) ----------
# Extract a top-level string field from hook input. Args: <json> <field>.
# The sed fallback truncates at the first quote, so callers that need a value
# which may contain quotes (a shell command) must NOT rely on it — see the raw
# fallback in block-unverified-push.sh.
exloom_json_field() {
  local json="$1" field="$2" out=""
  if command -v jq >/dev/null 2>&1; then
    out="$(printf '%s' "$json" | jq -r --arg f "$field" '.[$f] // empty' 2>/dev/null || true)"
  fi
  if [[ -z "$out" ]] && command -v python3 >/dev/null 2>&1; then
    out="$(printf '%s' "$json" | FIELD="$field" python3 -c 'import json,os,sys
try:
    print(json.load(sys.stdin).get(os.environ["FIELD"],""))
except Exception:
    pass' 2>/dev/null || true)"
  fi
  if [[ -z "$out" ]]; then
    out="$(printf '%s' "$json" | _exloom_sed_str "$field")"
  fi
  out="${out//$'\r'$'\n'/$'\n'}"   # see exloom_tool_input: jq on Windows emits CRLF
  printf '%s' "$out"
}

# Read a JSON string value with sed, when neither jq nor python3 is available.
#
# Do not "simplify" to `s/.*"key" *: *"\([^"]*\)".*/\1/`. `[^"]*` stops at the
# first quote byte, truncating any value containing an escaped quote; the leading
# `.*` is greedy, so it matches the LAST occurrence of the key. Both fail OPEN.
# `\\.` consumes an escaped pair before `[^"\\]` can stop on it; `head -1` takes
# the first occurrence. The value stays JSON-escaped, which is correct for
# shape-matching — `\"` is not a quote character in the command.
_exloom_sed_str() {
  grep -o "\"$1\"[[:space:]]*:[[:space:]]*\"\(\\\\.\|[^\"\\\\]\)*\"" 2>/dev/null \
    | head -1 | sed -e "s/^\"$1\"[[:space:]]*:[[:space:]]*\"//" -e 's/"$//'
}

# Remove heredoc BODIES and here-string operands, keeping everything else, so a
# scanner sees write targets and not prose. Commands AFTER the terminator must
# still be scanned — truncating at the first `<<` lets `cat <<< '' ; rm <target>`
# through.
#
# Bash string ops, not awk: the caller flattens newlines first, and an awk
# program nested three quoting layers deep behaved differently in situ than
# standalone. This is unit-testable on its own.
exloom_strip_heredocs() {
  local s="$1" pre rest tag
  # A here-string carries a word, not a body.
  s="$(printf '%s' "$s" | sed -E "s/<<<[[:space:]]*(\"[^\"]*\"|'[^']*'|[^[:space:];&|]*)/ /g")"
  while [[ "$s" == *"<<"* ]]; do
    pre="${s%%<<*}"
    rest="${s#*<<}"
    rest="${rest#-}"                       # <<- strips leading tabs in the body
    rest="${rest#"${rest%%[![:space:]]*}"}" # skip space between << and the tag
    tag="${rest%%[[:space:]]*}"
    tag="${tag//\'/}"; tag="${tag//\"/}"
    if [[ -z "$tag" ]]; then s="$pre"; break; fi
    rest="${rest#*"$tag"}"
    # Keep whatever follows the terminator: commands after a heredoc are
    # ordinary commands and must still be scanned.
    if [[ "$rest" == *" $tag "* ]]; then
      s="$pre ${rest#*" $tag "}"
    else
      s="$pre"   # unterminated body: nothing after it can be a target
    fi
  done
  printf '%s' "$s"
}

# Read a key from the NESTED tool_input object. Same ladder, same reasons.
# Every hook that gates a tool call must use this rather than scanning the raw
# payload: a hook that cannot parse its input must not conclude "allow".
exloom_tool_input() {
  local json="$1" key="$2" out=""
  if command -v jq >/dev/null 2>&1; then
    out="$(printf '%s' "$json" | jq -r --arg k "$key" '.tool_input[$k] // empty' 2>/dev/null || true)"
  fi
  if [[ -z "$out" ]] && command -v python3 >/dev/null 2>&1; then
    out="$(printf '%s' "$json" | KEY="$key" python3 -c 'import json,os,sys
try:
    v = (json.load(sys.stdin).get("tool_input") or {}).get(os.environ["KEY"], "")
    print(v if isinstance(v, str) else "")
except Exception:
    pass' 2>/dev/null || true)"
  fi
  if [[ -z "$out" ]]; then
    out="$(printf '%s' "$json" | _exloom_sed_str "$key")"
  fi
  # jq built for Windows writes CRLF, so a multi-line command comes back as
  # `cmd\r\nnext` and every downstream word/line match sees `next\r` instead of
  # `next`. This silently defeated the heredoc-terminator match in
  # exloom_strip_heredocs — the guard fell through to "unterminated" and dropped
  # the real write target. On Git Bash, which is the whole environment here, a
  # scanner that does not normalise line endings is a scanner that fails open.
  # Normalise CRLF only; a lone CR is left alone.
  out="${out//$'\r'$'\n'/$'\n'}"
  printf '%s' "$out"
}

# ---------- branch classification ----------
# A protected branch is one the gate deliberately skips (work committed straight
# to an integration branch is out of scope). Defaults: main|master|dev|develop
# plus empty/HEAD. A repo may ADD its own integration branches (e.g. pre-dev) via
# a COMMITTED .claude/exloom-protected-branches (one bash-glob per line, # comments).
# Additive, never subtractive — main/master/dev/develop stay protected.
exloom_is_protected_branch() {
  local br="$1" pat
  [[ -z "$br" || "$br" == "HEAD" ]] && return 0
  case "$br" in main|master|dev|develop) return 0 ;; esac
  local pfile=".claude/exloom-protected-branches"
  if [[ -f "$pfile" ]] && git ls-files --error-unmatch "$pfile" >/dev/null 2>&1; then
    while IFS= read -r pat || [[ -n "$pat" ]]; do
      pat="${pat%%#*}"; pat="$(printf '%s' "$pat" | tr -d '[:space:]')"
      [[ -z "$pat" ]] && continue
      # shellcheck disable=SC2254
      case "$br" in $pat) return 0 ;; esac
    done < "$pfile"
  fi
  return 1
}

# Should the gate skip branch $1 entirely via .claude/exloom-skip-branches?
# This is a deliberate widening of an enforcement boundary, so it is honored ONLY
# when the file is COMMITTED (an uncommitted skip-list would be an invisible
# personal bypass), and every match is logged to stderr so a skip is never silent.
# Intended for branches that never reach a protected branch (spike/*, tmp/*,
# experiment/*) — NOT for integration/merge branches (a botched merge is new,
# unreviewed code). See the review-gate skill.
exloom_is_skip_branch() {
  local br="$1" pat sfile=".claude/exloom-skip-branches"
  [[ -f "$sfile" ]] || return 1
  git ls-files --error-unmatch "$sfile" >/dev/null 2>&1 || return 1
  while IFS= read -r pat || [[ -n "$pat" ]]; do
    pat="${pat%%#*}"; pat="$(printf '%s' "$pat" | tr -d '[:space:]')"
    [[ -z "$pat" ]] && continue
    # shellcheck disable=SC2254
    case "$br" in $pat)
      echo "exloom: branch '$br' matches skip pattern '$pat' in $sfile — gate skipped (audit)" >&2
      return 0 ;;
    esac
  done < "$sfile"
  return 1
}

# ---------- push target parsing ----------
# Given a git push command line, echo the newline-separated list of SOURCE branch
# names whose code the push ships — i.e. the branch each refspec's LEFT side names,
# because the review checklist is keyed to the code being pushed, not the remote
# destination. `git push origin foo` -> foo; `git push origin HEAD:foo` -> HEAD
# (caller maps HEAD to the current branch); `git push origin mybranch:foo` ->
# mybranch. Echo nothing => "the current branch" (bare `git push`,
# `git push origin`). A `__DELETE__` line marks a deletion refspec (`:branch`,
# `--delete`) which ships no code. `--all`/`--mirror` echo nothing (can't scope;
# caller falls back to the current branch). This closes the hole where
# `git push origin other-branch` from a reviewed branch shipped an unreviewed one.
exloom_push_target_branches() {
  local cmd="$1" i t pushidx=-1 skip_next=0 deletion=0 allrefs=0
  local -a toks=() positionals=() refspecs=()
  read -r -a toks <<< "$cmd"
  for i in "${!toks[@]}"; do
    if [[ "${toks[$i]}" == "push" ]]; then pushidx=$i; break; fi
  done
  [[ $pushidx -lt 0 ]] && return 0
  for ((i=pushidx+1; i<${#toks[@]}; i++)); do
    t="${toks[$i]}"
    case "$t" in ';'|'&&'|'||'|'|'|'&') break ;; esac
    if [[ $skip_next -eq 1 ]]; then skip_next=0; continue; fi
    # A shell redirection is not a refspec. `git push origin 2>&1` was read as a
    # push of a branch named `2>&1`, and the block message then told the author
    # to run /review-init for a branch that does not exist — an argument-parsing
    # slip that reads as a review failure. Only bites when no branch is named;
    # `git push origin HEAD 2>&1` was always correct.
    case "$t" in
      [0-9]*'>&'[0-9]*|'&>'*|'>'*|'>>'*|[0-9]*'>'*|'<'*) continue ;;
    esac
    case "$t" in
      --all|--mirror) allrefs=1; continue ;;
      --delete|-d) deletion=1; continue ;;
      --repo|-o|--push-option|--exec|--receive-pack) skip_next=1; continue ;;
      --repo=*|--push-option=*|--exec=*|--receive-pack=*) continue ;;
      -*) continue ;;
    esac
    positionals+=( "$t" )
  done
  [[ $allrefs -eq 1 ]] && return 0
  # positionals[0] is the remote; the rest are refspecs.
  if [[ ${#positionals[@]} -ge 2 ]]; then refspecs=( "${positionals[@]:1}" ); fi
  if [[ $deletion -eq 1 ]]; then echo "__DELETE__"; return 0; fi
  [[ ${#refspecs[@]} -eq 0 ]] && return 0
  local r src skipnext=0
  for r in "${refspecs[@]}"; do
    if [[ $skipnext -eq 1 ]]; then skipnext=0; continue; fi
    r="${r#\"}"; r="${r%\"}"; r="${r#\'}"; r="${r%\'}"   # strip surrounding quotes
    # `git push origin tag <name>` ships a tag, not branch code — no review needed.
    if [[ "$r" == "tag" ]]; then echo "__DELETE__"; skipnext=1; continue; fi
    if [[ "$r" == :* ]]; then echo "__DELETE__"; continue; fi   # :dst = delete
    src="${r%%:*}"                # LEFT of the colon (source), or the whole token
    src="${src#+}"               # strip force '+'
    # A tag refspec ships a tag, not branch code.
    if [[ "$src" == refs/tags/* ]]; then echo "__DELETE__"; continue; fi
    src="${src#refs/heads/}"
    [[ -n "$src" ]] && echo "$src"
  done
}

# ---------- tier derivation ----------
# The declared tier decides which gates apply, so letting the author declare it
# after the fact reopens every loop the gate is meant to close. This derives a
# MINIMUM tier from the diff itself, using the same rules /review-init proposes,
# and exloom_validate_checklist blocks when the declared tier is below it.
# Over-declaration is always allowed — going one tier higher is the documented
# response to uncertainty.
#
# Echoes 0-3 and returns 0; returns 1 when the tier cannot be derived (no fork
# point, no diff) so the caller can fail open. Deliberately encodes only rules
# that are unambiguous from a file list — "frontend AND backend changed" and
# "more than one module" need stack knowledge the hook does not have, and stay
# with the skill as judgment.
exloom_derive_tier() {
  local tip="$1" base files f n docs_only=1
  base="$(git merge-base "$tip" origin/main 2>/dev/null \
       || git merge-base "$tip" origin/master 2>/dev/null \
       || git merge-base "$tip" origin/dev 2>/dev/null \
       || git merge-base "$tip" origin/develop 2>/dev/null || true)"
  [[ -n "$base" ]] || return 1
  # Review artifacts are not the change under review.
  files="$(git diff --name-only "$base" "$tip" -- . ':(exclude).claude/reviews' 2>/dev/null)"
  [[ -n "$files" ]] || return 1

  # Docs-only is checked FIRST so a markdown file under an `auth/` path does not
  # score Tier 3 on a path match.
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    case "$f" in
      *.md|*.txt|docs/*|*/docs/*|README*|*/README*) ;;
      *) docs_only=0; break ;;
    esac
  done <<< "$files"
  if [[ $docs_only -eq 1 ]]; then printf '0'; return 0; fi

  # Tier 3 — data migration, or the security surface /review-init enumerates.
  #
  # `auth` matches as a WORD, not a substring — a bare `auth` matched
  # `authoring-claude-md` and forced Tier 3 on a docs change, which the tier has
  # no escape hatch from.
  # Matches: auth/ auth- authentication authorization authz authn oauth
  # Does not match: authoring author authors
  if printf '%s\n' "$files" | grep -Eqi '(^|/)(migrations?|liquibase|flyway|changesets?)(/|$)|db/changelog'; then
    printf '3'; return 0
  fi
  if printf '%s\n' "$files" | grep -Eq '(^|[^A-Za-z])[Aa]uth([^A-Za-z]|[A-Z]|$|entic|oriz|z|n)|[Oo]auth|[Tt]enant|[Ss]ecret|[Cc]rypto|[Jj][Ww][Tt]|[Aa]pi[-_]?[Kk]ey'; then
    printf '3'; return 0
  fi

  # Tier 2 — deployment surface, an API/route surface, or a five-file blast
  # radius. Deployment paths floor at 2 rather than 3 because /review-init's rule
  # is conditional on the change being flag/prod-related, which a file list
  # cannot decide; the skill still says go to 3 when it is.
  if printf '%s\n' "$files" | grep -Eqi '(^|/)(deployment|deploy|k8s|kubernetes|helm|docker)(/|$)|docker-compose|Dockerfile'; then
    printf '2'; return 0
  fi
  if printf '%s\n' "$files" | grep -Eqi 'controller|(^|/)routes?[/.]|(^|/)api[/.]|endpoint|resolver'; then
    printf '2'; return 0
  fi
  n="$(printf '%s\n' "$files" | grep -c . || true)"
  if [[ "${n:-0}" -ge 5 ]]; then printf '2'; return 0; fi

  printf '1'
}

# ---------- reviewer verdict receipts ----------
# A receipt is the one piece of review evidence the authoring session does not
# author: hooks/record-reviewer-verdict.sh writes it when a reviewer subagent
# actually completes, and hooks/protect-verdicts.sh denies writing one by hand.
# So requiring a receipt tests an EVENT, where every checkbox in the checklist
# only tests an assertion.
#
# Receipts are read from the ref being validated, which means they must be
# committed with the checklist — the same rule the checklist itself lives under.
exloom_verdict_dir() { printf '%s' "${1%.md}.verdicts"; }

# Does this diff touch a security surface that does NOT derive to Tier 3?
# Dependency and deserialization changes derive to Tier 1 or 2, so without this
# they would never require the security auditor the skill promises for them.
#
# Deliberately narrow: manifests and lockfiles by filename, deserialization entry
# points by diff content. Outbound-request / SSRF shapes are NOT matched — every
# formulation tried forced security review on ordinary HTTP client code.
exloom_security_surface() {   # exloom_security_surface <base> <tip>
  local base="$1" tip="$2" files
  files="$(git diff --name-only "$base" "$tip" -- . ':(exclude).claude/reviews' 2>/dev/null)"
  [[ -n "$files" ]] || return 1

  # Dependency manifests and lockfiles: a bumped or added dependency is the
  # single most common way an unreviewed vulnerability enters a codebase, and a
  # one-line manifest change otherwise derives to Tier 1.
  if printf '%s\n' "$files" | grep -Eq '(^|/)(package\.json|package-lock\.json|yarn\.lock|pnpm-lock\.yaml|pom\.xml|build\.gradle(\.kts)?|gradle/libs\.versions\.toml|requirements[^/]*\.txt|Pipfile(\.lock)?|poetry\.lock|pyproject\.toml|go\.mod|go\.sum|Cargo\.(toml|lock)|Gemfile(\.lock)?|composer\.(json|lock)|.*\.csproj|packages\.lock\.json)$'; then
    return 0
  fi

  # Deserialization of untrusted input, by the API actually called.
  if git diff -U0 "$base" "$tip" -- . ':(exclude).claude/reviews' 2>/dev/null \
     | grep -Eq '^\+.*(ObjectInputStream|readObject\(|XMLDecoder|yaml\.load\(|pickle\.loads?\(|cPickle\.loads?\(|Marshal\.load|unserialize\(|JsonConvert\.DeserializeObject|BinaryFormatter|TypeNameHandling|SnakeYAML|readValue\(.*Object\.class)'; then
    return 0
  fi
  return 1
}

# ---------- lanes: rigour earned by stakes, not imposed by process ----------
#
# exloom shipped one lane, and it was the strictest one: the same ten steps for a
# null check and for a subsystem. That is why one-line fixes turned into features
# and why branches stopped landing. Tiers scale REVIEW DEPTH, derived from the
# diff; they do not scale CEREMONY, and ceremony is what a small change cannot
# afford.
#
# Three lanes, on a different axis from tier:
#
#   sprint     branch -> code -> prove -> smoke -> push. No spec, no plan, no
#              fidelity audit, L1 only. The gate still runs; the receipts are
#              still written; the checklist records that it was a Sprint, so a
#              skipped step is a recorded fact rather than a silent absence.
#   standard   the full flow. The default, and unchanged.
#   certified  standard with no escape hatches and mandatory signed provenance.
#
# WHAT A LANE MAY NOT DO IS WEAKEN A SAFETY CHECK. The proof receipt, the smoke
# test, the tier derivation, receipt forgery-resistance and the security surface
# are identical in all three. A lane changes how much happens BEFORE the code,
# and which reviewers the tier's ceremony demands after it — never whether the
# evidence is real.
exloom_repo_lane() {
  local f=".claude/exloom-lane" v=""
  if [[ -f "$f" ]] && git ls-files --error-unmatch "$f" >/dev/null 2>&1; then
    v="$(head -1 "$f" 2>/dev/null | tr -cd 'a-z')"
  fi
  case "$v" in sprint|standard|certified) printf '%s' "$v" ;; *) printf 'standard' ;; esac
}

# The lane declared in the checklist, if any. Reads content on stdin. Empty when
# the branch declares none, which is not an error — the repo default applies.
exloom_declared_lane() {
  local v
  v="$(grep -E '^\*\*Lane:\*\*' | head -1 | sed -E 's/.*Lane:\*\*[[:space:]]*//' \
       | tr '[:upper:]' '[:lower:]' | tr -cd 'a-z')"
  case "$v" in sprint|standard|certified) printf '%s' "$v" ;; *) printf '' ;; esac
}

# The tier the CEREMONY runs at, which is not always the tier of record. Sprint
# caps it at 1 — L1 and the smoke test, never adversarial or cross-layer — while
# the declared tier stays honest, because the tier describes the diff and lying
# about it would corrupt every other check that reads it.
exloom_effective_tier() {   # exloom_effective_tier <tier> <lane>
  local tier="$1" lane="${2:-standard}"
  if [[ "$lane" == "sprint" && "$tier" -gt 1 ]] 2>/dev/null; then printf '1'; else printf '%s' "$tier"; fi
}

# Reviewers required at a given tier, plus any the surface demands regardless.
exloom_required_reviewers() {
  local tier="$1" extra="${2:-}" list=""
  case "$tier" in
    0|1) list='l1-reviewer' ;;
    2)   list='l1-reviewer adversarial-reviewer' ;;
    3)   list='l1-reviewer adversarial-reviewer security-auditor' ;;
  esac
  if [[ "$extra" == "security" && "$list" != *security-auditor* ]]; then
    list="$list security-auditor"
  fi
  printf '%s' "$list"
}

# How many review rounds has this branch had? Distinct commits appearing in the
# L1 receipt, which is one JSON line per real dispatch. Deterministic — no model,
# no judgement.
# Counts BOTH the committed receipts and any sitting uncommitted in the working
# tree, then de-duplicates.
#
# Reading only the committed ref made this silently answer 0 whenever the
# receipts had not been committed yet — which is most of the time, since nothing
# commits them until /review-complete says so. On a real branch four dispatches
# were on disk and this returned zero, so the cap never fired and the push went
# through with no prompt. A counter that reports "no rounds" when it cannot see
# the rounds is worse than one that errors: it fails open in the mechanism whose
# only job is to notice accumulation.
exloom_round_count() {   # exloom_round_count <checklist> <tip>
  local vdir committed working
  vdir="$(exloom_verdict_dir "$1")"
  committed="$(MSYS_NO_PATHCONV=1 git show "${2}:${vdir}/l1-reviewer.json" 2>/dev/null || true)"
  working="$(cat "${vdir}/l1-reviewer.json" 2>/dev/null || true)"
  printf '%s\n%s\n' "$committed" "$working" \
    | sed -n 's/.*"head"[[:space:]]*:[[:space:]]*"\([0-9a-f]\{7,40\}\)".*/\1/p' \
    | sort -u | grep -c . || printf '0'
}

# The round cap. A repo may raise or lower it with a COMMITTED
# .claude/exloom-max-rounds holding a single number — committed because raising
# it weakens the gate, and that should be a reviewed change.
exloom_max_rounds() {
  local f=".claude/exloom-max-rounds" n=""
  if [[ -f "$f" ]] && git ls-files --error-unmatch "$f" >/dev/null 2>&1; then
    n="$(head -1 "$f" 2>/dev/null | tr -cd '0-9')"
  fi
  [[ -n "$n" && "$n" -ge 1 ]] 2>/dev/null && printf '%s' "$n" || printf '3'
}

# Has a human recorded a decision to ship at the cap? Mechanical: the checklist's
# escape-hatch section must carry a line naming the cap. The reason is for the
# next reader, not for the gate — the gate only checks that a person wrote one.
# Has the USER been asked and decided to ship at the cap?
#
# Recorded in the checklist by the session AFTER it puts the report in front of
# the user and asks. The control here is the asking, not the file: the block
# message below instructs the session to show the report in the conversation and
# take an explicit answer. A protected file was tried and is worse — it forces
# the person out of the session to run a shell command, which is not a decision
# point, it is an obstacle.
exloom_cap_override() {   # exloom_cap_override <checklist> <tip>
  local content
  content="$(MSYS_NO_PATHCONV=1 git show "${2}:${1}" 2>/dev/null || true)"
  [[ -n "$content" ]] || return 1
  printf '%s\n' "$content" \
    | grep -qiE '^[[:space:]]*-[[:space:]]*(user approved at round cap|shipped at round cap)[[:space:]]*—[[:space:]]*\S' || return 1
  return 0
}

# Severity of findings per round, so the report can say whether the branch is
# settling or falling apart. Reads <agent>.findings.jsonl, which records a
# severity and a round for every finding and which nothing else consumes.
# Echoes e.g. "round 1: 3 HIGH 2 MED | round 2: 1 HIGH | round 3: 0"
exloom_severity_trend() {   # exloom_severity_trend <checklist> <tip>
  local vdir all r line out="" hi med lo
  vdir="$(exloom_verdict_dir "$1")"
  all="$(MSYS_NO_PATHCONV=1 git show "${2}:${vdir}" 2>/dev/null | grep 'findings.jsonl' || true)"
  local combined=""
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    combined="${combined}$(MSYS_NO_PATHCONV=1 git show "${2}:${vdir}/${f}" 2>/dev/null || true)
"
  done <<< "$all"
  [[ -n "$(printf '%s' "$combined" | tr -d '[:space:]')" ]] || return 1
  for r in $(printf '%s\n' "$combined" | sed -n 's/.*"round":\([0-9]*\).*/\1/p' | sort -un); do
    line="$(printf '%s\n' "$combined" | grep "\"round\":${r},")"
    hi="$(printf '%s\n' "$line" | grep -c '"severity":"HIGH"' || true)"
    med="$(printf '%s\n' "$line" | grep -c '"severity":"MED"' || true)"
    lo="$(printf '%s\n' "$line" | grep -c '"severity":"LOW"' || true)"
    out="${out}round ${r}: ${hi} critical, ${med} important, ${lo} minor
"
  done
  printf '%s' "$out"
}

# How many unresolved CRITICAL findings are on record? This is what decides the
# recommendation — a branch with an open critical is not ready however many
# rounds it has had, and a branch with none is ready however many it took.
exloom_open_criticals() {   # exloom_open_criticals <checklist> <tip>
  local vdir all n=0
  vdir="$(exloom_verdict_dir "$1")"
  all="$(MSYS_NO_PATHCONV=1 git show "${2}:${vdir}" 2>/dev/null | grep 'findings.jsonl' || true)"
  local last=""
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    last="$(MSYS_NO_PATHCONV=1 git show "${2}:${vdir}/${f}" 2>/dev/null || true)"
    local maxr
    maxr="$(printf '%s\n' "$last" | sed -n 's/.*"round":\([0-9]*\).*/\1/p' | sort -un | tail -1)"
    [[ -n "$maxr" ]] || continue
    n=$(( n + $(printf '%s\n' "$last" | grep "\"round\":${maxr}," | grep -c '"severity":"HIGH"' || true) ))
  done <<< "$all"
  printf '%s' "$n"
}

# WHICH criticals are open, not how many. The cap question asks the user to
# choose between merging and fixing, and "2 open criticals" is not enough to
# choose on — a number is a score, a cite is a defect. Echoes up to four
# `file:line` cites from the latest round.
exloom_open_critical_cites() {   # exloom_open_critical_cites <checklist> <tip>
  local vdir all f last maxr out=""
  vdir="$(exloom_verdict_dir "$1")"
  all="$(MSYS_NO_PATHCONV=1 git show "${2}:${vdir}" 2>/dev/null | grep 'findings.jsonl' || true)"
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    last="$(MSYS_NO_PATHCONV=1 git show "${2}:${vdir}/${f}" 2>/dev/null || true)"
    maxr="$(printf '%s\n' "$last" | sed -n 's/.*"round":\([0-9]*\).*/\1/p' | sort -un | tail -1)"
    [[ -n "$maxr" ]] || continue
    out="${out}$(printf '%s\n' "$last" | grep "\"round\":${maxr}," | grep '"severity":"HIGH"' \
                 | sed -n 's/.*"cite":"\([^"]*\)".*/\1/p')
"
  done <<< "$all"
  printf '%s\n' "$out" | grep -v '^[[:space:]]*$' | sort -u | head -4 | paste -sd', ' - 2>/dev/null \
    || printf '%s\n' "$out" | grep -v '^[[:space:]]*$' | sort -u | head -4 | tr '\n' ' '
}

# Did the LAST review pass look at code anyone had changed?
#
# A review pass does not fix anything. Running a fourth pass on a tip identical
# to the third pass's is a guaranteed repeat of the third pass's findings — it
# spends a round and moves nothing. This is the mechanism behind "each feature is
# getting bigger and never completes": the counter counted reviews when the thing
# that has to happen between rounds is a FIX.
#
# Returns 0 when the last pass reviewed unchanged code (a no-op pass), 1 when
# code moved between the last two passes or there are not yet two to compare.
exloom_last_pass_was_noop() {   # exloom_last_pass_was_noop <checklist> <tip>
  local vdir committed working heads prev cur
  vdir="$(exloom_verdict_dir "$1")"
  committed="$(MSYS_NO_PATHCONV=1 git show "${2}:${vdir}/l1-reviewer.json" 2>/dev/null || true)"
  working="$(cat "${vdir}/l1-reviewer.json" 2>/dev/null || true)"
  # Order of first appearance, not sort order: these are passes in sequence.
  heads="$(printf '%s\n%s\n' "$committed" "$working" \
    | sed -n 's/.*"head"[[:space:]]*:[[:space:]]*"\([0-9a-f]\{7,40\}\)".*/\1/p' \
    | awk '!seen[$0]++' | tail -2)"
  [[ "$(printf '%s\n' "$heads" | grep -c .)" -eq 2 ]] || return 1
  prev="$(printf '%s\n' "$heads" | head -1)"
  cur="$(printf '%s\n' "$heads" | tail -1)"
  git cat-file -e "${prev}^{commit}" 2>/dev/null || return 1
  git cat-file -e "${cur}^{commit}" 2>/dev/null || return 1
  exloom_diff_is_behavioural "$prev" "$cur" && return 1
  return 0
}

# exloom_check_verdicts <checklist> <tier> <tip> <reviewed-sha> <action>
#
# Only the L1 reviewer's approval must cover the shipped commit. The others must
# have RUN and APPROVED at some point on this branch.
#
# Requiring every reviewer to approve the SAME commit is what produced the 7-12
# round loop: any fix creates a new commit, which cancels every approval —
# including from reviewers already satisfied — so N reviewers must simultaneously
# approve a target that moves each time one of them is answered. Expected rounds
# go as 1/p^N. Decoupling makes it 1/p: L1 covers what ships, the others cover
# that a hostile and a security pass happened and their findings were addressed.
exloom_check_verdicts() {
  local checklist="$1" tier="$2" tip="$3" reviewed="$4" action="$5" lane="${6:-standard}"
  local vdir agent file content sha ok approved_at behind seen_verdict legacy_at
  local -a missing=() stale=() unapproved=()
  vdir="$(exloom_verdict_dir "$checklist")"

  # Security review is triggered by SURFACE as well as by tier — see
  # exloom_security_surface. Computed once here rather than in the tier lookup,
  # because only this function knows which commits are being compared.
  local sec_base sec_extra=""
  sec_base="$(git merge-base "$reviewed" origin/main 2>/dev/null \
           || git merge-base "$reviewed" origin/master 2>/dev/null \
           || git merge-base "$reviewed" origin/dev 2>/dev/null \
           || git merge-base "$reviewed" origin/develop 2>/dev/null || true)"
  if [[ -n "$sec_base" ]] && exloom_security_surface "$sec_base" "$reviewed"; then
    sec_extra="security"
  fi

  for agent in $(exloom_required_reviewers "$tier" "$sec_extra"); do
    file="${vdir}/${agent}.json"
    # MSYS_NO_PATHCONV: Git Bash on Windows mangles the `ref:path` argument.
    content="$(MSYS_NO_PATHCONV=1 git show "${tip}:${file}" 2>/dev/null || true)"
    if [[ -z "$content" ]]; then missing+=( "$agent" ); continue; fi
    ok=0; rejected=0; approved_at=""; seen_verdict=0; legacy_at=""
    # Read whole receipt LINES, so the commit and the verdict on one line are
    # evaluated together. Reading them separately would let an APPROVED verdict
    # from an old commit vouch for a REJECTED review of the current one.
    while IFS= read -r rline || [[ -n "$rline" ]]; do
      [[ -z "$rline" ]] && continue
      sha="$(printf '%s' "$rline" | sed -n 's/.*"head"[[:space:]]*:[[:space:]]*"\([0-9a-f]\{7,40\}\)".*/\1/p')"
      [[ -n "$sha" ]] || continue
      git rev-parse --verify "${sha}^{commit}" >/dev/null 2>&1 || continue
      # Only L1 must cover the SHIPPED commit. For the others, having run and
      # approved anywhere on this branch is enough — see the header. A
      # checklist-only or comment-only commit must not invalidate even L1.
      if [[ "$agent" == "l1-reviewer" ]]; then
        if [[ -n "$(git diff --name-only "$sha" "$reviewed" -- . ':(exclude).claude/reviews' 2>/dev/null)" ]]; then
          exloom_diff_is_behavioural "$sha" "$reviewed" && continue
        fi
      fi

      # A dispatch is not a review. A reviewer that returned REJECTED must not
      # satisfy the gate it was dispatched to satisfy.
      #
      # GRANDFATHERED: receipts written before exloom recorded verdicts have no
      # "verdict" key at all. Those still count — refusing them would block every
      # in-flight branch the moment this version is installed, and a migration
      # that breaks running work does not get adopted, it gets uninstalled.
      # A dispatch and a completion both write a line at the same commit: the
      # first carries no verdict (the reviewer had not run), the second carries
      # the real one. Breaking on the first verdict-less line would grandfather a
      # REJECTED review through, so the legacy path is only reachable when NO
      # covering line carries a verdict at all — i.e. genuinely old receipts.
      case "$rline" in
        *'"verdict":"APPROVED"'*) seen_verdict=1; ok=1; approved_at="$sha"; break ;;
        *'"verdict":"REJECTED"'*|*'"verdict":"UNKNOWN"'*) seen_verdict=1; rejected=1 ;;
        *) legacy_at="$sha" ;;   # dispatch-only, or a pre-verdict receipt
      esac
    done < <(printf '%s\n' "$content")
    if [[ $ok -ne 1 && $seen_verdict -eq 0 && -n "$legacy_at" ]]; then
      ok=1; approved_at="$legacy_at"
    fi
    if [[ $ok -ne 1 ]]; then
      if [[ $rejected -eq 1 ]]; then unapproved+=( "$agent" ); else stale+=( "$agent" ); fi
    elif [[ "$agent" != "l1-reviewer" && -n "$approved_at" ]]; then
      # Decoupling means these reviewers approve code, then more code lands. That
      # gap is a real exposure — this branch's own round-1 fixes introduced six
      # round-2 defects, one of them at exactly the integration level only a
      # hostile pass catches. It cannot be closed without either re-running them
      # every commit (the loop) or delta review (unsound), so it is DISCLOSED
      # instead: a fact for whoever reads the PR, never a block.
      behind="$(git rev-list --count "${approved_at}..${reviewed}" 2>/dev/null || echo 0)"
      if [[ "${behind:-0}" -gt 0 ]]; then
        echo "exloom: ${agent} approved ${approved_at:0:12} — ${behind} commit(s) have landed since; it did not see them." >&2
      fi
    fi
  done

  # ---------- the round cap, checked BEFORE the reviewers are judged ----------
  # The cap is a property of the branch, not of the findings. It used to be
  # checked only when something was outstanding, so a branch that reached round
  # 10 and then satisfied every reviewer shipped silently — the count never
  # surfaced. And since verdict capture degraded on async dispatch, "outstanding"
  # became rare, which disabled the cap almost entirely.
  #
  # A counter that only goes up is the point: it cannot be satisfied by more
  # work, only by a person deciding the branch is done taking rounds.
  local rounds max
  rounds="$(exloom_round_count "$checklist" "$tip")"
  max="$(exloom_max_rounds)"
  if [[ "$rounds" -ge "$max" ]] && exloom_cap_override "$checklist" "$tip"; then
    # The user was shown the full report — findings by pass, reviewer status,
    # recommendation — and chose to merge. That answer settles the branch; it does
    # not then get second-guessed by the same reviewer state they just read.
    echo "exloom: shipping at ${rounds} passes on a decision recorded in ${checklist}." >&2
    return 0
  fi
  if [[ "$rounds" -ge "$max" ]]; then
    local outstanding=""
    [[ ${#unapproved[@]} -gt 0 ]] && outstanding="$(printf '  %s — reviewed this code and did NOT approve\n' "${unapproved[@]}")"
    [[ ${#stale[@]} -gt 0 ]]      && outstanding="${outstanding}$(printf '  %s — approved earlier code, not the current tip\n' "${stale[@]}")"
    [[ ${#missing[@]} -gt 0 ]]    && outstanding="${outstanding}$(printf '  %s — never dispatched\n' "${missing[@]}")"
    [[ -n "$outstanding" ]] || outstanding="  every required reviewer is satisfied at this commit
"
    local trend crit cites fix_opt rec noop=""
    trend="$(exloom_severity_trend "$checklist" "$tip" 2>/dev/null || true)"
    [[ -n "$trend" ]] || trend="  (no findings recorded)
"
    crit="$(exloom_open_criticals "$checklist" "$tip" 2>/dev/null || echo 0)"
    cites="$(exloom_open_critical_cites "$checklist" "$tip" 2>/dev/null || true)"

    # A pass is not a fix. If the last pass reviewed the same code as the one
    # before it, say so plainly — that round bought nothing, and repeating it
    # buys nothing either.
    if exloom_last_pass_was_noop "$checklist" "$tip" 2>/dev/null; then
      noop="
NOTE: the last review pass ran against the same code as the pass before it. No
fix landed between them, so it returned the same findings. Another pass with no
fix in front of it will do the same.
"
    fi

    if [[ "${crit:-0}" -gt 0 ]]; then
      if [[ -n "$cites" ]]; then
        fix_opt="Fix ${cites}, then re-review"
      else
        fix_opt="Fix the ${crit} open critical finding(s), then re-review"
      fi
      rec="FIX, THEN RE-REVIEW — ${crit} critical finding(s) are still open."
    else
      fix_opt="Fix something anyway, then re-review"
      rec="MERGE — no critical findings are open. The remaining items are important or minor."
    fi

    # NOT permissionDecision:"ask". That renders as approve/cancel on the push
    # itself, and cancel is a tool refusal rather than an answer: the push dies,
    # the session has nothing to act on, and the person has to retype their
    # intent. A cap is a decision point, so it has to produce a DECISION.
    #
    # So this blocks, and hands the session the question to put to the user. The
    # push stays blocked either way — the gate is still enforced here, in the
    # hook. What the session controls is only which of the named options gets
    # carried out.
    _exloom_block "$action" "Review has run ${rounds} passes on this branch (cap ${max}).

Findings by pass:
${trend}
Reviewer status:
${outstanding}${noop}
RECOMMENDATION: ${rec}

STOP AND ASK THE USER. Use AskUserQuestion with exactly these options, the
recommended one first, and do NOT decide it yourself:

  - ${fix_opt}
  - Merge as-is — the open items are acceptable
  - Show me the findings first

Then carry out what they choose:
  fix     -> make the fix, commit it, re-dispatch l1-reviewer, come back here
  merge   -> record their answer in ${checklist} under 'Escape hatches used' as
             '- User approved at round cap — <their words>', commit it, push again
  show    -> print the findings from ${vdir}/*.findings.jsonl and ask again

Do not record that answer unless they actually gave it. Re-running the reviewers
without a fix in between does not clear this — it is the same code and it will
return here with the same findings."
    return 2
  fi

  if [[ ${#missing[@]} -eq 0 && ${#stale[@]} -eq 0 && ${#unapproved[@]} -eq 0 ]]; then return 0; fi

  local detail="Tier ${tier} requires a verdict receipt from each of: $(exloom_required_reviewers "$tier" "$sec_extra")."
  # Say which lane set that bar. A Sprint branch asked for one reviewer where the
  # tier would have asked for three, and a reader of this message should not have
  # to work out why the demand looks light.
  [[ "$lane" == "sprint" ]] && detail="This branch is on the Sprint lane, so the reviewer set is capped at Tier 1.
${detail}"
  [[ -n "$sec_extra" ]] && detail="${detail}
security-auditor is required by the SURFACE this diff touches (a dependency
manifest or a deserialization entry point), not by the tier."
  [[ ${#missing[@]} -gt 0 ]] && detail="${detail}

Never dispatched (no receipt in ${vdir}/):
$(printf '  - %s\n' "${missing[@]}")"
  [[ ${#stale[@]} -gt 0 ]] && detail="${detail}

Dispatched, but only against code that has since changed (re-run them):
$(printf '  - %s\n' "${stale[@]}")
Only l1-reviewer has to cover the commit you ship; if it is listed here, re-run
just that one. The others need to have run and approved anywhere on this branch."
  [[ ${#unapproved[@]} -gt 0 ]] && detail="${detail}

Reviewed the current code, but did NOT approve it (fix the findings, then re-run):
$(printf '  - %s\n' "${unapproved[@]}")
A REJECTED verdict is not a passing review, and UNKNOWN means the reviewer's
report carried no 'VERDICT: APPROVED' line — neither counts as approval."

  _exloom_block "$action" "${detail}

Receipts are written by exloom when a reviewer subagent actually completes — they
cannot be written by hand. Dispatch the reviewers, commit the receipts with the
checklist, and re-run /review-complete."
  return 2
}

# ---------- change classification ----------
# exloom_diff_is_behavioural <from> <to>
# Returns 0 when the diff could change behaviour, 1 when it provably cannot.
#
# Without this, a comment-only fix invalidates every receipt and mandates another
# round, so the loop has no terminating state.
#
# CONSERVATIVE BY DESIGN: non-behavioural only when every added and removed line
# is blank or starts with a comment marker. Being wrong here costs one extra
# review; being wrong the other way ships unreviewed code.
exloom_diff_is_behavioural() {
  local from="$1" to="$2" files f ext body line stripped marker

  # ---------- binary and metadata changes are ALWAYS behavioural ----------
  # `git diff` emits only "Binary files a/x and b/x differ" for a binary change,
  # which carries no +/- lines at all — so a line-based classifier called it
  # non-behavioural and every reviewer receipt stayed "covering". Swapping a
  # vendored .jar, a .dll, a model weight, a keystore or a wasm blob kept a stale
  # review valid. Same shape for a pure rename and a file-mode change.
  # --numstat reports "-\t-\tpath" for binary, which is unambiguous.
  if git diff --numstat "$from" "$to" -- . ':(exclude).claude/reviews' 2>/dev/null \
     | grep -qE '^-[[:space:]]+-[[:space:]]'; then
    return 0
  fi
  if git diff --no-color "$from" "$to" -- . ':(exclude).claude/reviews' 2>/dev/null \
     | grep -qE '^(old mode|new mode|rename from|rename to|deleted file|new file) '; then
    return 0
  fi

  # ---------- comment markers are per-language, never universal ----------
  # Treating `#` as a comment everywhere classified real code as inert:
  #   #define TIMEOUT 300 / #include <stdlib.h>   (C/C++/ObjC/C#)
  #   #[derive(...)] / #![allow]                  (Rust attributes)
  #   #login { display: none }                    (CSS id selector)
  #   //go:build linux / //go:generate            (Go directives)
  #   #!/bin/sh                                   (shebang)
  # Each was verified to flip the whole diff to non-behavioural.
  #
  # So the marker set is chosen per file, and any file whose language is unknown
  # is treated as having NO comment markers — i.e. every changed line counts.
  # -z + tr: `git diff --name-only` quotes paths containing non-ASCII or special
  # characters (core.quotepath), and the quoted form then matched no file at all.
  files="$(git -c core.quotepath=false diff --name-only "$from" "$to" -- . ':(exclude).claude/reviews' 2>/dev/null)"
  [[ -n "$files" ]] || return 1

  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    ext="${f##*.}"
    case "$ext" in
      py|rb|yaml|yml|toml|ini|cfg|conf|tf|Dockerfile|dockerfile|gitignore|env)
        marker='#' ;;
      sh|bash|zsh)
        # No marker: a `#` line may be a heredoc body, and there is no way to tell
        # from a diff line. Every changed line counts.
        marker='' ;;
      java|kt|kts|scala|groovy|js|jsx|ts|tsx|mjs|cjs|go|swift|dart|php|c|h|cc|cpp|hpp|cs|rs|proto)
        # `//` only. NOT `#` (C preprocessor, C# directives, Rust attributes) and
        # NOT `--` (a wrapped CLI flag). `//go:` is a directive, excluded below.
        marker='//' ;;
      sql|hs|lua|elm)      marker='--' ;;
      md|markdown|html|htm|xml|svg|vue) marker='<!--' ;;
      *)                   marker='' ;;   # unknown language: nothing is a comment
    esac

    # `-w` ignores whitespace-only changes, which is right for a brace language
    # (reindenting a Java block changes nothing) and WRONG where indentation is
    # syntax. In Python, de-indenting a line moves it out of an `if` branch; in
    # YAML it re-parents a key. Both are behavioural and both are invisible to
    # `-w`, so such a change scored "not behavioural", a stale receipt stayed
    # valid, and the code shipped unreviewed. The suite pinned this as the spec:
    # its only fixture was blank-line churn, the one case where `-w` is correct.
    local wsflag='-w'
    case "$ext" in
      py|pyi|pyx|yaml|yml|sass|styl|pug|jade|haml|slim|coffee|nim|cr) wsflag='' ;;
    esac
    if [[ -n "$wsflag" ]]; then
      body="$(git diff -w --no-color "$from" "$to" -- "$f" 2>/dev/null)" || return 0
    else
      body="$(git diff --no-color "$from" "$to" -- "$f" 2>/dev/null)" || return 0
    fi
    while IFS= read -r line; do
      # Real diff headers have a space then a path; `+++i;` and `---force` do not.
      case "$line" in
        '+++ '*|'--- '*|'@@'*|'diff --git '*|'index '*) continue ;;
        '+'*|'-'*) ;;
        *) continue ;;
      esac
      stripped="${line:1}"
      stripped="${stripped#"${stripped%%[![:space:]]*}"}"
      [[ -z "$stripped" ]] && continue

      case "$marker" in
        '#')  case "$stripped" in '#!'*) return 0 ;; '#'*) continue ;; esac ;;
        '//') case "$stripped" in
                '//go:'*) return 0 ;;            # build/generate directive: code
                '//'*|'/*'*|'*/'*) continue ;;
                '* '*) continue ;;               # javadoc continuation: star SPACE
                '*'*) return 0 ;;                # `*p = x` is a dereference, not a comment
              esac ;;
        '--') case "$stripped" in '--'*) continue ;; esac ;;
        '<!--') case "$stripped" in '<!--'*|'-->'*) continue ;; esac ;;
      esac
      return 0
    done <<< "$body"
  done <<< "$files"
  return 1
}

# ---------- re-finds: the instance-not-the-rule detector ----------
# exloom_check_refinds <checklist> <tip> <action>
# Blocks when the same finding was reported in more than one review round and the
# checklist records no disposition for it.
#
# The same fingerprint two rounds apart is mechanical evidence that a fix
# addressed the instance rather than the rule. It forces a decision, not a fix:
# quantify the guard over the whole class, or say why this is a separate defect.
exloom_check_refinds() {
  local CHECKLIST_CONTENT="${CHECKLIST_CONTENT:-}"
  local checklist="$1" tip="$2" action="$3"
  local vdir content fp rounds refinds=""

  vdir="$(exloom_verdict_dir "$checklist")"
  # Findings files are per-agent, read from the working tree: they are written by
  # a hook and protected from hand-editing, same as every other receipt.
  content="$(cat "${vdir}"/*.findings.jsonl 2>/dev/null || true)"
  [[ -n "$content" ]] || return 0

  while IFS= read -r fp; do
    [[ -n "$fp" ]] || continue
    rounds="$(printf '%s\n' "$content" | grep -F "\"fingerprint\":\"${fp}\"" \
              | sed -n 's/.*"round":\([0-9]*\).*/\1/p' | sort -un | tr '\n' ',' | sed 's/,$//')"
    [[ "$rounds" == *,* ]] || continue
    local cite
    cite="$(printf '%s\n' "$content" | grep -F "\"fingerprint\":\"${fp}\"" \
            | sed -n 's/.*"cite":"\([^"]*\)".*/\1/p' | head -1)"
    # Disposed when the checklist names the cite in its Re-finds section.
    # Disposition rules, in order of strictness:
    #
    #   1. A `## Re-finds` section exists -> the cite must appear inside it, with a
    #      disposition keyword on that line or within the two lines after it (the
    #      template's entry is two lines: cite, then `FIXED THE CLASS:` beneath).
    #
    #   2. No `## Re-finds` section -> the checklist predates this mechanism; fall
    #      back to the cite appearing anywhere, so in-flight branches stay
    #      unblockable rather than being stranded with no migration path.
    if [[ -n "$cite" ]]; then
      local refind_section
      refind_section="$(printf '%s\n' "$CHECKLIST_CONTENT" \
        | awk '/^## Re-finds/{f=1;next} /^## /{f=0} f')"
      if [[ -n "$refind_section" ]]; then
        if printf '%s\n' "$refind_section" \
           | grep -A2 -F -- "$cite" \
           | grep -qE 'FIXED THE CLASS|GENUINELY SEPARATE|FIXED THE INSTANCE|DEFERRED'; then continue; fi
      else
        if printf '%s' "$CHECKLIST_CONTENT" | grep -qF -- "$cite"; then
          echo "exloom: '$cite' disposed by a checklist with no '## Re-finds' section (legacy format, audit)" >&2
          continue
        fi
      fi
    fi
    refinds="${refinds}  - ${cite:-<uncited>}  (reported in rounds ${rounds})"$'\n'
  done < <(printf '%s\n' "$content" | sed -n 's/.*"fingerprint":"\([^"]*\)".*/\1/p' | sort -u)

  [[ -n "$refinds" ]] || return 0

  _exloom_block "$action" "The same finding was reported in more than one review round, and the checklist
records no disposition for it:

${refinds}
A re-find often means the previous fix addressed the instance rather than the rule
behind it. That is worth a decision — it is NOT an instruction to close the class
here. Fixing the instance and tracking the class is a legitimate answer, and
usually the right one.

Record a disposition under '## Re-finds' in ${checklist}, naming the cite, and
pick whichever is true:

  1. FIXED THE INSTANCE — and where the class is tracked.
     \"src/Guard.java:88 FIXED THE INSTANCE — class tracked in PROJ-421\"
  2. DEFERRED — not fixed here, with the ticket.
  3. FIXED THE CLASS — you closed the whole set in this branch. Name the test.
  4. GENUINELY SEPARATE — why this defect is unrelated to the earlier one.

Option 1 used to be missing, so the only way past this gate was to close the class
in the current branch. That turned one-line changes into refactors, and every
addition became unreviewed code the next round found defects in.

The findings are recorded per reviewer under the verdicts directory, one JSON
line each, in <agent>.findings.jsonl."
  return 2
}

# ---------- proof-of-testedness receipt ----------
# exloom_check_proof <checklist> <tip> <reviewed-sha> <action>
# Returns 0 when a PROVED receipt covers the reviewed commit; prints a BLOCK
# message and returns 2 otherwise. Fails OPEN only on genuine git errors, never
# on a missing or failing proof — a gate that waves through "the check did not
# run" is the failure this whole mechanism exists to prevent.
exloom_check_proof() {
  local checklist="$1" tip="$2" reviewed="$3" action="$4"
  local vdir file content sha ok=0 seen_notproved=0 seen_cmdswap=0

  vdir="$(exloom_verdict_dir "$checklist")"
  file="${vdir}/proof.json"
  content="$(MSYS_NO_PATHCONV=1 git show "${tip}:${file}" 2>/dev/null || true)"

  if [[ -n "$content" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
      [[ -z "$line" ]] && continue
      sha="$(printf '%s' "$line" | sed -n 's/.*"head"[[:space:]]*:[[:space:]]*"\([0-9a-f]\{7,40\}\)".*/\1/p')"
      [[ -n "$sha" ]] || continue
      git rev-parse --verify "${sha}^{commit}" >/dev/null 2>&1 || continue
      # Same coverage rule as a reviewer receipt: it counts when no code differs
      # between the proved commit and the one being shipped.
      if [[ -n "$(git diff --name-only "$sha" "$reviewed" -- . ':(exclude).claude/reviews' 2>/dev/null)" ]]; then
        exloom_diff_is_behavioural "$sha" "$reviewed" && continue
      fi
      # The receipt records the hash of the pinned test command. Comparing it
      # here is what makes the proof bind to the command that was actually
      # proved: without this, a repo could prove with a real suite, then change
      # .claude/exloom-test-command to `true`, and the receipt stayed valid
      # because nothing compared the recorded hash to the current one. The field
      # was written and never read, and the suite asserted only that the key
      # existed — text, not behaviour.
      local rec_hash cur_hash="none"
      rec_hash="$(printf '%s' "$line" | sed -n 's/.*"cmd_hash"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
      if [[ -n "$rec_hash" && "$rec_hash" != "none" ]]; then
        cur_hash="$(MSYS_NO_PATHCONV=1 git rev-parse "${reviewed}:.claude/exloom-test-command" 2>/dev/null || echo none)"
        if [[ "$cur_hash" != "$rec_hash" ]]; then
          seen_cmdswap=1
          continue
        fi
      fi
      case "$line" in
        *'"result":"PROVED"'*)     ok=1; break ;;
        *'"result":"NOT_PROVED"'*) seen_notproved=1 ;;
      esac
    done < <(printf '%s\n' "$content")
  fi

  [[ $ok -eq 1 ]] && return 0

  local detail
  if [[ $seen_cmdswap -eq 1 ]]; then
    detail="A proof receipt covers this commit, but .claude/exloom-test-command has changed
since it was written, so the receipt proves a command that is no longer the one
this repo runs. Re-run the proof against the current command:

    bash \"$EXLOOM_LIB_DIR/../scripts/prove-change-is-tested.sh\""
  elif [[ $seen_notproved -eq 1 ]]; then
    detail="The proof ran on this code and came back NOT_PROVED: with your source change
removed and your tests kept, the tests still PASS. They do not notice the change.

That is one of:
  1. the assertions are too weak to detect it;
  2. the test runner did not actually run them (cached / UP-TO-DATE / filtered);
  3. the change genuinely has no observable behaviour — say so in the checklist."
  else
    detail="No proof receipt covers this commit (${vdir}/proof.json).

Run it, then commit the receipt with the checklist:

    bash \"$EXLOOM_LIB_DIR/../scripts/prove-change-is-tested.sh\"

It removes your source change in a throwaway worktree, keeps your tests, and runs
them. Your working tree is never touched. The receipt is written by that script
alone and cannot be written by hand."
  fi

  _exloom_block "$action" "${detail}

This check exists because review rounds are repeatedly spent on defects it finds
first: an assertion satisfied by any string, a write-path test with no read-path
test, a build that reported success without running the suite."
  return 2
}

# ---------- shared checklist validator ----------
# exloom_validate_checklist <checklist-path> <tip-ref> <worktree:0|1> <action>
#   checklist-path : .claude/reviews/<branch>.md (relative to repo root)
#   tip-ref        : the commit representing the code being shipped (HEAD for the
#                    current branch; refs/heads/<b> when validating another branch)
#   worktree       : 1 = read the checklist from the working tree and additionally
#                    verify it is committed & clean; 0 = read it from tip-ref (its
#                    committed state is implied)
#   action         : human phrase for messages ("push / open a PR", "claim done")
# Prints a BLOCK message to stderr and returns 2 on any failure; returns 0 when
# the checklist is complete and bound to tip-ref. Logs any recorded escape hatches.
exloom_validate_checklist() {
  local checklist="$1" tip="$2" worktree="$3" action="$4"
  local content

  if [[ "$worktree" == "1" ]]; then
    [[ -f "$checklist" ]] || { _exloom_block "$action" "Branch has no review checklist at $checklist.
The review gate has not run. Run /review-init, /smoke-test, /review-complete, then retry."; return 2; }
    content="$(cat "$checklist" 2>/dev/null)"
  else
    # MSYS_NO_PATHCONV: Git Bash on Windows otherwise mangles the `ref:path`
    # argument (colon -> ';', '/' -> '\'), breaking the read. Harmless elsewhere.
    content="$(MSYS_NO_PATHCONV=1 git show "$tip:$checklist" 2>/dev/null || true)"
    [[ -n "$content" ]] || { _exloom_block "$action" "The branch you are pushing has no committed review checklist ($checklist).
Check out that branch and run /review-init, /smoke-test, /review-complete."; return 2; }
  fi

  # Tier must be declared.
  local tier
  tier="$(printf '%s\n' "$content" | grep -E '^\*\*Tier:\*\*' | head -1 | sed -E 's/.*Tier:\*\*[[:space:]]*([0-9]).*/\1/')"
  if [[ ! "$tier" =~ ^[0-3]$ ]] || printf '%s\n' "$content" | grep -qE '^\*\*Tier:\*\*.*\|'; then
    # An unsubstituted template tier ([0 | 1 | 2 | 3]) or a missing tier.
    if printf '%s\n' "$content" | grep -qE '^\*\*Tier:\*\*.*\|'; then
      _exloom_block "$action" "$checklist does not declare a tier — the template placeholder is unfilled. Set Tier: 0/1/2/3."
      return 2
    fi
    if [[ ! "$tier" =~ ^[0-3]$ ]]; then
      _exloom_block "$action" "$checklist does not declare a valid tier (Tier: 0, 1, 2, or 3). Re-run /review-init."
      return 2
    fi
  fi

  # Which lane is this branch on? The checklist decides; the repo file is only a
  # default, because the lane is a property of the WORK, not of the repository.
  local lane eff_tier
  lane="$(printf '%s\n' "$content" | exloom_declared_lane)"
  [[ -n "$lane" ]] || lane="$(exloom_repo_lane)"

  # Sprint is not available at Tier 3. Migrations, auth, tenancy, secrets and
  # crypto are exactly the stakes that earn rigour, and the tier is derived from
  # the diff rather than declared — so this cannot be talked around by calling a
  # migration a weekend spike. "Rigour earned by stakes" has to cut both ways or
  # it is just a bypass with a nicer name.
  if [[ "$lane" == "sprint" && "$tier" -ge 3 ]]; then
    _exloom_block "$action" "$checklist declares the Sprint lane at Tier ${tier}.

Sprint exists so a small change does not need a spec, a plan and three reviewers.
Tier 3 means this diff touches migrations, auth, tenancy, secrets or crypto —
the stakes that earn the full flow. There is no Sprint lane at Tier 3.

Set **Lane:** standard (or certified) and run the gates the tier requires."
    return 2
  fi

  # Sprint caps the CEREMONY at Tier 1 while the declared tier stays honest for
  # the record: L1 and the smoke test, not adversarial or cross-layer. The
  # security surface is passed separately and still applies — a bumped dependency
  # gets a security auditor in every lane.
  eff_tier="$(exloom_effective_tier "$tier" "$lane")"

  # Certified has no escape hatches. That is the whole difference from Standard:
  # every other lane accepts a documented skip, because a documented skip beats an
  # undocumented one, and Certified exists for the reader who can accept neither.
  #
  # Checked HERE rather than beside the audit output at the end, because Certified
  # also mandates signed provenance — and that check would otherwise always fire
  # first, answering a content problem the author can fix in a minute with an
  # environment problem they may not be able to fix at all.
  #
  # A recorded round-cap answer is exempt. It lives in this section for want of a
  # better home, but it is a decision the user made when asked, not a step
  # somebody skipped, and blocking it would make the cap unanswerable in the one
  # lane most likely to reach it.
  if [[ "$lane" == "certified" ]]; then
    local c_eh c_used
    c_eh="$(printf '%s\n' "$content" | awk '/^## Escape hatches used/{f=1;next} /^## /{f=0} f')"
    if ! printf '%s\n' "$c_eh" | grep -q '^\- \[x\] None'; then
      c_used="$(printf '%s\n' "$c_eh" | grep -E '^[[:space:]]*-[[:space:]]' \
        | grep -vi 'None (default)' | grep -vi 'Skipped steps with written justification' \
        | grep -v '<step name>' \
        | grep -viE 'user approved at round cap|shipped at round cap' || true)"
      if [[ -n "$(printf '%s' "$c_used" | tr -d '[:space:]')" ]]; then
        _exloom_block "$action" "This branch is on the Certified lane, which has no escape hatches. Recorded:
$(printf '%s\n' "$c_used" | sed 's/^[[:space:]]*/  /')

Either do the step, or move the branch to the Standard lane (**Lane:** standard)
and ship with the skip on the record. Certified means a reader never has to take
a skip on trust, so it cannot also be the lane that permits them."
        return 2
      fi
    fi
  fi

  # Final verdict signed.
  if ! printf '%s\n' "$content" | grep -q '^\- \[x\] All required gates passed for declared tier' \
     || ! printf '%s\n' "$content" | grep -q '^\- \[x\] Checklist committed' \
     || ! printf '%s\n' "$content" | grep -q '^\- \[x\] Ready to ship'; then
    _exloom_block "$action" "$checklist is not marked complete (Final verdict has unticked boxes).
Run /review-complete — it names each tier-required section still missing."
    return 2
  fi

  # Placeholder scan, scoped to the sections that apply to the declared tier.
  local placeholder_re drop scan
  placeholder_re='<(paste output / screenshot link|exact command|exact steps|expected-result|Claude-session-or-human-reviewer|who-attests|path to committed runbook\.md|test id or path[^>]*|paste|list[^>]*|file:line — problem[^>]*|category \+ file:line[^>]*|N files changed[^>]*|Critical / Important / Minor[^>]*|reviewed-sha|ai-assisted|model-id|directed-by|base-sha|attested-date|severity \+ category \+ file:line[^>]*|fixed / deferred with reason per finding|one sentence why|secrets / dep-audit / static[^>]*|which hostile question[^>]*|step name|exact command, or "detected"|PROVED / NOT_PROVED|what is missing[^>]*)>'
  drop=''
  if   [[ "$eff_tier" -lt 1 ]]; then drop='^## (Smoke test|Cross-layer|Adversarial|Security review|Runbook)'
  elif [[ "$eff_tier" -lt 2 ]]; then drop='^## (Cross-layer|Adversarial|Security review|Runbook)'
  elif [[ "$eff_tier" -lt 3 ]]; then drop='^## (Security review|Runbook)'
  fi
  # HTML comments are guidance, not evidence, and the template uses them to show
  # what a filled-in line looks like — which necessarily quotes the placeholder
  # tokens. Scanning them made the template's own instructions block the push.
  scan="$(printf '%s\n' "$content" \
    | awk '/<!--/{inc=1} !inc{print} /-->/{inc=0}' \
    | awk -v drop="$drop" '/^## /{skip=(drop!="" && $0 ~ drop)?1:0} !skip{print}')"
  if printf '%s' "$scan" | grep -Eq "$placeholder_re" || printf '%s' "$scan" | grep -qE '^Date:[[:space:]]*YYYY-MM-DD[[:space:]]*$'; then
    _exloom_block "$action" "A required section of $checklist still contains template placeholder text.
Fill in the real evidence for the declared tier, or revert the final-verdict ticks."
    return 2
  fi

  # The "Checklist committed" box is self-attested — verify it against git.
  # Only meaningful for the working-tree case; the ref-read case is committed by
  # construction. Fail open on genuine git errors.
  if [[ "$worktree" == "1" ]] && git rev-parse --verify HEAD >/dev/null 2>&1; then
    if ! git ls-files --error-unmatch "$checklist" >/dev/null 2>&1 \
       || ! git diff --quiet HEAD -- "$checklist" 2>/dev/null; then
      _exloom_block "$action" "The checklist is marked \"Checklist committed\", but $checklist is untracked or has uncommitted changes.
The review evidence must ship with the code it reviews. Commit it, then retry."
      return 2
    fi
  fi

  # Staleness + provenance are only enforced when the tip ref resolves.
  if git rev-parse --verify "$tip" >/dev/null 2>&1; then
    local reviewed_sha stale
    reviewed_sha="$(printf '%s\n' "$content" | grep -E '^Reviewed code commit:' | head -1 | sed -E 's/^Reviewed code commit:[[:space:]]*//' | tr -d '[:space:]')"
    if [[ -z "$reviewed_sha" ]] || ! [[ "$reviewed_sha" =~ ^[0-9a-f]{7,40}$ ]] || ! git rev-parse --verify "${reviewed_sha}^{commit}" >/dev/null 2>&1; then
      _exloom_block "$action" "$checklist is marked complete but records no valid 'Reviewed code commit:', so the review cannot be bound to the code.
Re-run /review-complete to record the reviewed tip."
      return 2
    fi
    stale="$(git diff --name-only "$reviewed_sha" "$tip" -- . ':(exclude).claude/reviews' 2>/dev/null)"
    # Comment-only / doc-only commits do not invalidate a behavioural review.
    if [[ -n "$stale" ]] && ! exloom_diff_is_behavioural "$reviewed_sha" "$tip"; then
      echo "exloom: $(printf '%s
' "$stale" | grep -c .) file(s) changed since review, but no behavioural lines — review still valid (audit)" >&2
      stale=""
    fi
    if [[ -n "$stale" ]]; then
      _exloom_block "$action" "The review is stale. These files changed after the reviewed commit ($reviewed_sha) and are not covered:
${stale}

Re-run /review-complete to review the current tip."
      return 2
    fi

    # The declared tier must not be below the tier the diff itself derives to.
    # Fail open when it cannot be derived (no fork point / no diff).
    local derived
    if derived="$(exloom_derive_tier "$tip")" && [[ "$derived" =~ ^[0-3]$ ]]; then
      if [[ "$tier" -lt "$derived" ]]; then
        _exloom_block "$action" "$checklist declares Tier ${tier}, but this diff derives to Tier ${derived}.

The tier decides which gates apply, so a tier chosen after the diff is finished
reopens every gate it skips. Raise the tier to ${derived} (or higher) and run the
gates it requires. There is deliberately no escape hatch for this — if the
derivation is wrong for your repo, that is a rule to fix, not a review to skip."
        return 2
      fi
    fi

    # Reviewer verdict receipts — the one check that tests an event rather than
    # an assertion. Uses the DECLARED tier, which is >= derived by the check above.
    # 3 means the round cap emitted an "ask" decision: the harness now prompts
    # the USER. Propagated distinctly so the hook exits 0 — the JSON on stdout is
    # the decision, and a non-zero exit would discard it and hard-block instead.
    exloom_check_verdicts "$checklist" "$eff_tier" "$tip" "$reviewed_sha" "$action" "$lane"
    case "$?" in 0) ;; 3) return 3 ;; *) return 2 ;; esac

    # Author-side proof that the change is actually tested. Keyed on the DECLARED
    # tier, never the effective one: the proof is a safety check, not ceremony,
    # and it is the cheapest evidence exloom produces. Sprint keeps it.
    if [[ "$tier" -ge 1 ]]; then
      exloom_check_proof "$checklist" "$tip" "$reviewed_sha" "$action" || return 2
    fi

    # Re-finds: the same defect reported across rounds means the fix was
    # instance-level. Needs a recorded disposition, not another patch.
    CHECKLIST_CONTENT="$content" exloom_check_refinds "$checklist" "$tip" "$action" || return 2

    # Provenance attestation.
    if ! printf '%s\n' "$content" | grep -q '^- AI-assisted:' \
       || ! printf '%s\n' "$content" | grep -q '^- Model(s):' \
       || ! printf '%s\n' "$content" | grep -q '^- Directed by:' \
       || ! printf '%s\n' "$content" | grep -q '^- Base commit:'; then
      _exloom_block "$action" "Provenance is missing from $checklist (AI-assisted / Model / Directed by / Base commit).
Run /review-complete to record who and what produced this change."
      return 2
    fi

    # v2 (opt-in): the commit that recorded the checklist must be a verified
    # signed commit. The Certified lane requires it whether the marker exists or
    # not — an unsigned attestation is the one thing a regulated reader cannot
    # accept, and a lane that asked for it only when a file happened to be
    # present would not be worth declaring.
    if [[ -f ".claude/exloom-provenance-signed.enabled" || "$lane" == "certified" ]]; then
      local p_commit ref="$tip"
      [[ "$worktree" == "1" ]] && ref="HEAD"
      p_commit="$(git log -1 --format=%H "$ref" -- "$checklist" 2>/dev/null)"
      if [[ -z "$p_commit" ]] || ! git verify-commit "$p_commit" >/dev/null 2>&1; then
        _exloom_block "$action" "Signed provenance is required (.claude/exloom-provenance-signed.enabled) but the commit that recorded $checklist is not a verified signed commit.
Configure git signing and re-run /review-complete (it commits with -S), or remove the marker for v1."
        return 2
      fi
    fi
  fi

  # Surface recorded escape hatches so a skipped step is visible, not silent.
  # (An escape hatch is an accepted, documented skip — but a lazy or hallucinated
  # one should never pass unnoticed. This is audit output, not a block.)
  local eh used
  eh="$(printf '%s\n' "$content" | awk '/^## Escape hatches used/{f=1;next} /^## /{f=0} f')"
  if ! printf '%s\n' "$eh" | grep -q '^\- \[x\] None'; then
    used="$(printf '%s\n' "$eh" | grep -E '^[[:space:]]*-[[:space:]]' \
      | grep -vi 'None (default)' | grep -vi 'Skipped steps with written justification' \
      | grep -v '<step name>')"
    if [[ -n "$used" ]]; then
      echo "exloom: escape hatch(es) recorded on this review (audit):" >&2
      printf '%s\n' "$used" | sed 's/^[[:space:]]*/  /' >&2
    fi
  fi

  return 0
}

# Internal: print a uniform BLOCK message. Args: <action> <detail>
#
# There was a second emitter here, _exloom_ask, which printed the PreToolUse
# permission JSON with decision "ask" so Claude Code would show its own prompt.
# It is gone, and the round cap now blocks like everything else.
#
# The reasoning that put it there was sound and the outcome was not. `exit 2`
# plus "ask the user" in stderr is only an instruction, and a session did write
# its own approval line and push — so the decision was routed to the harness to
# take the model out of the path. But the harness renders that as approve/cancel
# on the push itself, and CANCEL IS NOT AN ANSWER: it refuses the tool, the push
# dies, the session has nothing to act on, and the person has to retype what they
# wanted. A cap exists to produce a decision, and two of its three real answers
# (fix these, show me the findings) cannot be expressed as approve or cancel.
#
# Named options need AskUserQuestion, which is a session tool and not a hook
# capability. So the cap blocks, and the block text tells the session which
# question to ask and what to do with each answer. The push stays blocked by the
# hook either way; what the session controls is only which named option runs.
_exloom_block() {
  local action="$1" detail="$2"
  cat >&2 <<EOF
exloom review gate: BLOCKED — cannot ${action}.

${detail}

Emergency bypass (audited): set EXLOOM_REVIEW_SKIP=1 in your Claude Code session
env (settings.json "env"), then retry. An inline "EXLOOM_REVIEW_SKIP=1 <cmd>"
will NOT work — the hook reads its own environment, not the command's.
EOF
}
