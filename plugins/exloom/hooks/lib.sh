#!/usr/bin/env bash
# exloom — shared hook library. SOURCED by the hooks; never executed directly.
#
# Checklist validation, branch classification and JSON extraction live here so
# that every hook answers "is this branch reviewed?" the same way. Two hooks with
# their own copy of that logic drift, and the drift shows up as a push refused
# for a reason no other hook agrees with.
#
# All functions assume the caller has already cd'd to the repo root when they
# touch git. Every git failure fails OPEN (return/exit 0 at the call site) —
# exloom blocks on missing evidence, never on an infrastructure hiccup.

# Resolved once, so block messages can print a command that actually runs.
# `${CLAUDE_PLUGIN_ROOT}` is interpolated into plugin.json by the harness and is
# NOT set in the Bash tool environment, so a remediation command built from it
# would fail with "No such file or directory" and leave the bypass as the only
# reachable option.
EXLOOM_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

# Repository policy (.exloom.yml), loaded once here so every hook reads it
# through the same functions. A push gate and a /review-init that each parsed the
# file their own way would eventually disagree about a change's tier, and that
# disagreement surfaces as a block nobody can explain.
# shellcheck source=/dev/null
[[ -r "$EXLOOM_LIB_DIR/policy.sh" ]] && . "$EXLOOM_LIB_DIR/policy.sh"

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
# Do not "simplify" this to `s/.*"key" *: *"\([^"]*\)".*/\1/`. That form fails
# open twice over: `[^"]*` stops at the first quote byte, truncating any value
# containing an escaped quote, and the leading `.*` is greedy, so it matches the
# LAST occurrence of the key rather than the first.
#
# Here `\\.` consumes an escaped pair before `[^"\\]` can stop on it, and
# `head -1` takes the first occurrence. The value stays JSON-escaped, which is
# what shape-matching wants — `\"` is not a quote character in the command.
_exloom_sed_str() {
  grep -o "\"$1\"[[:space:]]*:[[:space:]]*\"\(\\\\.\|[^\"\\\\]\)*\"" 2>/dev/null \
    | head -1 | sed -e "s/^\"$1\"[[:space:]]*:[[:space:]]*\"//" -e 's/"$//'
}

# Remove heredoc BODIES and here-string operands, keeping everything else, so a
# scanner sees write targets rather than prose.
#
# Commands AFTER the terminator must still be scanned. Truncating at the first
# `<<` would let `cat <<< '' ; rm <target>` through, which is the whole reason a
# scanner cannot simply ignore everything past a redirection.
#
# Written with bash string operations rather than awk: the caller flattens
# newlines first, so there is nothing awk buys here, and a small awk program
# nested inside three layers of quoting is far harder to test on its own.
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
  # jq built for Windows writes CRLF, so a multi-line command arrives as
  # `cmd\r\nnext` and every downstream word or line match sees `next\r` rather
  # than `next`. That is enough to defeat the heredoc-terminator match in
  # exloom_strip_heredocs, which then treats the body as unterminated and drops
  # the real write target. Git Bash is the primary environment here, so a scanner
  # that does not normalise line endings is a scanner that fails open. Normalise
  # CRLF only; a lone CR is left alone.
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
# names whose code the push ships — the branch each refspec's LEFT side names,
# because the checklist is keyed to the code being pushed and not to the remote
# destination.
#
#   git push origin foo            -> foo
#   git push origin HEAD:foo       -> HEAD   (caller maps HEAD to the current branch)
#   git push origin mybranch:foo   -> mybranch
#   git push / git push origin     -> nothing, meaning "the current branch"
#
# A `__DELETE__` line marks a refspec that ships no code (`:branch`, `--delete`,
# `tag <name>`). `--all` and `--mirror` echo nothing, because they cannot be
# scoped; the caller falls back to the current branch.
#
# Reading the left side is what stops `git push origin other-branch`, run from a
# reviewed branch, shipping an unreviewed one.
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
    # A shell redirection is not a refspec. Without this, `git push origin 2>&1`
    # parses as a push of a branch named `2>&1`, and the block message tells the
    # author to run /review-init for a branch that does not exist — an
    # argument-parsing slip that reads to them as a review failure.
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

# exloom_recorded_base <tip>
#   Prints the branch this branch's checklist says it forked from, or nothing.
#
# Read from the checklist at <tip>, so it must be committed to count - the same
# rule the tier, the lane and every receipt live under. A value that names no ref
# here is ignored by the caller, which falls back to the built-in candidates and
# so to a FURTHER base and a HIGHER tier. That is the safe direction for a typo.
exloom_recorded_base() {   # exloom_recorded_base <tip>
  local tip="$1" branch file val
  branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)" || return 0
  [[ -n "$branch" && "$branch" != "HEAD" ]] || return 0
  file=".claude/reviews/${branch}.md"
  val="$(MSYS_NO_PATHCONV=1 git show "${tip}:${file}" 2>/dev/null \
         | sed -n 's/^\*\*Base branch:\*\*[[:space:]]*//p' | head -1 \
         | tr -d '\r' | tr -d '[:space:]')"
  # `auto` is the template's shipped value and means "derive it": not an answer,
  # and deliberately not a `<placeholder>`, because an unstated base is a valid
  # end state rather than a gap somebody must fill.
  case "${val:-}" in ''|'<'*|auto|AUTO|Auto) return 0 ;; esac
  printf '%s' "$val"
}

# The fork point: the NEAREST candidate base wins, not the first that resolves.
# Where `main` is a release branch and `dev` the integration branch, taking main
# puts the whole release gap into the diff and every branch derives Tier 3.
# `origin/HEAD` is not consulted — it names the branch a clone checks out, which
# is a different question from where this work forked.
exloom_fork_point() {   # exloom_fork_point <tip>
  local tip="$1"

  # Memoised, and the refs listed in ONE call. Probing ten candidate names with
  # three git subprocesses each would cost seconds per gate evaluation on
  # Windows, where a process spawn is expensive — and both exloom_derive_tier and
  # exloom_check_verdicts call this.
  if [[ "${_EXLOOM_FP_TIP:-}" == "$tip" && -n "${_EXLOOM_FP:-}" ]]; then
    printf '%s' "$_EXLOOM_FP"; return 0
  fi

  local cand mb dist best="" best_dist="" existing recorded=""

  # A branch may record the base it actually forked from, in its own checklist.
  # Without it the derivation guesses from a fixed list of integration-branch
  # names, and a repo that calls its integration branch anything else forks from
  # `main` instead - inheriting every file changed in the gap as though this
  # branch had touched it, and citing a path the diff does not contain.
  #
  # Recorded per branch and never repo-wide: a hotfix off a release branch and a
  # feature off the integration branch have different answers.
  #
  # It is read from the COMMITTED checklist, so it travels in the diff a reviewer
  # reads. That visibility is the whole safety argument: a stated base can lower
  # the derived tier, so it has to be as legible as a bypass receipt rather than
  # silently changing what the gate asks for.
  recorded="$(exloom_recorded_base "$tip")"
  existing="$(git for-each-ref --format='%(refname:short)'                 refs/remotes/origin refs/heads 2>/dev/null)"

  if [[ -n "$recorded" ]]; then
    case "
${existing}
" in
      *"
${recorded}
"*) ;;
      *) echo "exloom: the checklist records base branch '${recorded}', which is not a ref here - deriving from the built-in candidates instead" >&2
         recorded="" ;;
    esac
  fi
  for cand in $recorded origin/main origin/master origin/dev origin/develop               origin/development origin/trunk main master dev develop; do
    case "
${existing}
" in *"
${cand}
"*) ;; *) continue ;; esac
    mb="$(git merge-base "$tip" "$cand" 2>/dev/null)" || continue
    [[ -n "$mb" ]] || continue
    dist="$(git rev-list --count "${mb}..${tip}" 2>/dev/null)" || continue
    [[ "$dist" =~ ^[0-9]+$ ]] || continue
    if [[ -z "$best_dist" || "$dist" -lt "$best_dist" ]]; then
      best="$mb"; best_dist="$dist"
      # Nothing can be nearer than the tip itself.
      [[ "$dist" -eq 0 ]] && break
    fi
  done
  [[ -n "$best" ]] || return 1
  _EXLOOM_FP_TIP="$tip"; _EXLOOM_FP="$best"
  printf '%s' "$best"
}

# Records why a tier was chosen: one line per matched rule,
#     <path>\t<rule>\t<source>
#
# A tier with no stated cause is a number people argue with. With one, the
# checklist, the PR reader and anything re-deriving the tier in CI all see the
# same reasoning, and a rule that matched the wrong file is visible rather than
# mysterious.
_exloom_tier_reason() {   # _exloom_tier_reason <files> <ere> <rule-label>
  local hit
  hit="$(printf '%s\n' "$1" | grep -Em1 "$2" 2>/dev/null || true)"
  [[ -n "$hit" ]] || hit='(no file)'
  _EXLOOM_TIER_REASONS="${_EXLOOM_TIER_REASONS}${hit}	${3}	built-in"$'\n'
}

exloom_tier_reasons() { printf '%s' "${_EXLOOM_TIER_REASONS:-}"; }

exloom_derive_tier() {
  local tip="$1" base files f n docs_only=1 pol_tier=""
  _EXLOOM_TIER_REASONS=""
  base="$(exloom_fork_point "$tip")"
  [[ -n "$base" ]] || return 1
  # Review artifacts are not the change under review.
  files="$(git diff --name-only "$base" "$tip" -- . ':(exclude).claude/reviews' 2>/dev/null)"
  [[ -n "$files" ]] || return 1

  # Repository policy runs alongside the built-in rules, never instead of them.
  # The effective tier is the highest anything matched, so a repo can teach the
  # gate its own vocabulary — `identity`, `iam`, `rbac` — and cannot use the same
  # file to lower a protection the built-ins already applied.
  #
  # Called plainly, NOT inside a command substitution: the reasons are published
  # through a global, and a subshell would discard them, leaving a tier with no
  # explanation attached.
  exloom_policy_tier "$files" >/dev/null 2>&1 || true
  pol_tier="${_EXLOOM_POL_TIER:-}"
  _EXLOOM_TIER_REASONS="${_EXLOOM_POL_REASONS:-}"

  # Docs-only is checked FIRST, before any path rule, so a markdown file that
  # happens to live under `auth/` or `identity/` does not score Tier 3 on a path
  # match. Matching a glob does not make a document into code, and this ordering
  # is what makes that true for repository rules as well as built-in ones.
  while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    case "$f" in
      *.md|*.txt|docs/*|*/docs/*|README*|*/README*) ;;
      *) docs_only=0; break ;;
    esac
  done <<< "$files"
  if [[ $docs_only -eq 1 ]]; then _EXLOOM_TIER_REASONS=""; printf '0'; return 0; fi

  _exloom_max_tier() {   # _exloom_max_tier <built-in>
    if [[ -n "$pol_tier" && "$pol_tier" -gt "$1" ]]; then printf '%s' "$pol_tier"
    else printf '%s' "$1"; fi
  }

  # Tier 3 — data migration, or the security surface /review-init enumerates.
  #
  # `auth` matches as a WORD, not a substring, because the tier has no escape
  # hatch: a bare substring match would put every path containing "authoring" or
  # "author" at Tier 3 with no way to argue.
  #   Matches:         auth/ auth- authentication authorization authz authn oauth
  #   Does not match:  authoring author authors
  if printf '%s\n' "$files" | grep -Eqi '(^|/)(migrations?|liquibase|flyway|changesets?)(/|$)|db/changelog'; then
    _exloom_tier_reason "$files" '(^|/)(migrations?|liquibase|flyway|changesets?)(/|$)|db/changelog' 'data migration'
    printf '3'; return 0
  fi
  if printf '%s\n' "$files" | grep -Eq '(^|[^A-Za-z])[Aa]uth([^A-Za-z]|[A-Z]|$|entic|oriz|z|n)|[Oo]auth|[Tt]enant|[Ss]ecret|[Cc]rypto|[Jj][Ww][Tt]|[Aa]pi[-_]?[Kk]ey'; then
    _exloom_tier_reason "$files" '(^|[^A-Za-z])[Aa]uth([^A-Za-z]|[A-Z]|$|entic|oriz|z|n)|[Oo]auth|[Tt]enant|[Ss]ecret|[Cc]rypto|[Jj][Ww][Tt]|[Aa]pi[-_]?[Kk]ey' 'auth / tenancy / secrets / crypto'
    printf '3'; return 0
  fi
  # Tier 3 is already the ceiling, so those two exits answer directly. Below it a
  # repository rule can still be the higher of the two, so every remaining exit
  # takes the maximum rather than returning its own answer.

  # Tier 2 — deployment surface, an API or route surface, or a five-file blast
  # radius. Deployment paths floor at 2 rather than 3 because /review-init's rule
  # is conditional on the change being flag- or prod-related, which a file list
  # cannot decide; the skill still says go to 3 when it is.
  if printf '%s\n' "$files" | grep -Eqi '(^|/)(deployment|deploy|k8s|kubernetes|helm|docker)(/|$)|docker-compose|Dockerfile'; then
    _exloom_tier_reason "$files" '(^|/)(deployment|deploy|k8s|kubernetes|helm|docker)(/|$)|docker-compose|Dockerfile' 'deployment surface'
    _exloom_max_tier 2; return 0
  fi
  if printf '%s\n' "$files" | grep -Eqi 'controller|(^|/)routes?[/.]|(^|/)api[/.]|endpoint|resolver'; then
    _exloom_tier_reason "$files" 'controller|(^|/)routes?[/.]|(^|/)api[/.]|endpoint|resolver' 'API or route surface'
    _exloom_max_tier 2; return 0
  fi
  n="$(printf '%s\n' "$files" | grep -c . || true)"
  if [[ "${n:-0}" -ge 5 ]]; then
    _exloom_tier_reason "$files" '.' "${n} files changed"
    _exloom_max_tier 2; return 0
  fi

  _exloom_max_tier 1
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

# ---------- is the evidence pipeline alive? ----------
# exloom_evidence_blind <checklist> <tip>
#   prints the number of dispatches when receipts exist but NONE of them, for any
#   reviewer, carries a verdict. Prints nothing, and returns 1, otherwise.
#
# The model here is that receipts are evidence, and the failure that model does
# not survive is receipt CAPTURE degrading. When a reviewer's report never
# reaches the hook, every line records a launch and no conclusion — and every
# mechanism downstream then reads blank and renders blank as fine. The severity
# trend prints "(no findings recorded)", indistinguishable from a clean branch,
# and the reviewer status prints "satisfied".
#
# Hence a liveness check, stated wherever the evidence surfaces. A tool whose
# claim is evidence has to be able to say when it has none; the one thing it may
# never do is present an absence of evidence as evidence of absence.
exloom_evidence_blind() {   # exloom_evidence_blind <checklist> <tip>
  local checklist="$1" tip="$2" vdir agent content lines=0 verdicts=0
  vdir="$(exloom_verdict_dir "$checklist")"
  for agent in l1-reviewer adversarial-reviewer security-auditor; do
    content="$(MSYS_NO_PATHCONV=1 git show "${tip}:${vdir}/${agent}.json" 2>/dev/null || true)"
    [[ -n "$content" ]] || continue
    lines=$(( lines + $(printf '%s\n' "$content" | grep -c '"head"' || true) ))
    verdicts=$(( verdicts + $(printf '%s\n' "$content" | grep -c '"verdict"' || true) ))
  done
  [[ "$lines" -gt 0 && "$verdicts" -eq 0 ]] || return 1
  printf '%s' "$lines"
}

# The same fact as a printable block, for the places that show it to a person.
exloom_evidence_blind_note() {   # exloom_evidence_blind_note <checklist> <tip>
  local n
  n="$(exloom_evidence_blind "$1" "$2")" || return 1
  printf '%s' "EVIDENCE PIPELINE IS NOT RECORDING. ${n} reviewer dispatch(es) are on
file for this branch and NOT ONE carries a verdict, so exloom has never observed
what any reviewer concluded here. Everything below that looks clean — no
findings, reviewers satisfied — is an absence of data, not a result.

The usual cause is a reviewer dispatched with a NAME, which routes its report to
the mailbox instead of the tool result the hook reads. Re-dispatch one reviewer
without a name and check that a line carrying \"verdict\" appears in
$(exloom_verdict_dir "$1")/ before treating any of this as review evidence."
}

# ---------- the bypass leaves a trace ----------
# exloom_bypass_receipt <action>
#
# EXLOOM_REVIEW_SKIP=1 turns the gate off unconditionally, and that is the right
# behaviour: a gate with no exit gets removed rather than bypassed, and the one
# thing worse than a skipped review is a team that uninstalled the plugin.
#
# An announcement on stderr is not enough, though — it scrolls past, and
# afterwards nothing can answer which changes shipped around the gate, neither a
# person reading the repo nor anything running in CI. So the bypass writes a
# file, committed alongside the change like every other piece of evidence.
#
# It records what the hook can observe: the branch, the commit, the action let
# through, the git identity, the time. It does NOT record a reason, because
# nothing here can verify one, and a field that invites a sentence nobody checks
# is worse than an absent field. The reason belongs in the checklist's
# escape-hatch section, in the diff, where a reviewer reads it.
#
# NEVER blocks and never changes the exit code. A bypass that failed because its
# receipt could not be written would be a gate turning back on at the worst
# possible moment.
exloom_bypass_receipt() {
  local action="${1:-unknown}" root branch sha who when file
  root="$(git rev-parse --show-toplevel 2>/dev/null)" || return 0
  [[ -n "$root" && -f "$root/.claude/exloom-gate.enabled" ]] || return 0
  branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  [[ -n "$branch" && "$branch" != "HEAD" ]] || return 0
  sha="$(git rev-parse HEAD 2>/dev/null || true)"
  who="$(git config user.email 2>/dev/null || true)"
  [[ -n "$who" ]] || who="$(git config user.name 2>/dev/null || true)"
  when="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true)"

  # Same sanitising rule as the verdict receipts: strip anything that could
  # close a JSON field, rather than escaping it. A value that cannot change the
  # line's shape cannot forge a neighbouring key however it is later parsed.
  action="$(printf '%s' "$action" | tr -cd 'A-Za-z0-9:._ -' | cut -c1-120)"
  who="$(printf '%s' "$who" | tr -cd 'A-Za-z0-9@:._ -' | cut -c1-200)"

  file="${root}/.claude/reviews/${branch}.bypass.json"
  mkdir -p "$(dirname "$file")" 2>/dev/null || return 0
  printf '{"bypass":"EXLOOM_REVIEW_SKIP","action":"%s","branch":"%s","head":"%s","by":"%s","at":"%s"}\n' \
    "$action" "$branch" "$sha" "$who" "$when" >> "$file" 2>/dev/null || return 0

  echo "exloom: bypass recorded in .claude/reviews/${branch}.bypass.json — commit it with the change, and write the reason in the checklist's 'Escape hatches used' section. Nothing verifies either; both exist so the next reader can see this happened." >&2
  return 0
}

# Does this diff touch a security surface that does NOT derive to Tier 3?
# Dependency and deserialization changes derive to Tier 1 or 2, so without this
# they would never require the security auditor the skill promises for them.
#
# Deliberately narrow: manifests and lockfiles by filename, deserialization entry
# points by diff content. Outbound-request and SSRF shapes are NOT matched,
# because any pattern broad enough to catch them also forces a security review on
# ordinary HTTP client code, and a check that fires on everything is one people
# route around.
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

# Lanes scale CEREMONY; tiers scale review depth. sprint = no spec/plan, L1 only.
# standard = the full flow. certified = no escape hatches, signed commit.
# No lane weakens a safety check: proof, smoke, tier derivation and the security
# surface are identical in all three.
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

# The tier the ceremony runs at. Sprint caps it at 1; the declared tier stays as
# it is, because other checks read it.
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
  # Reviewers the repository's own policy demands for the paths in this diff.
  # ADDITIVE, exactly like the tier: there is no key that removes a reviewer the
  # tier already requires, because a config able to subtract a reviewer is an
  # escape hatch on the check that decides whether anything was reviewed.
  local repo a
  repo="${3:-}"
  for a in $repo; do
    case " $list " in *" $a "*) ;; *) list="$list $a" ;; esac
  done
  printf '%s' "$list"
}

# The reviewers repository policy adds for the files in this diff.
exloom_policy_required_reviewers() {   # exloom_policy_required_reviewers <base> <tip>
  local files
  files="$(git diff --name-only "$1" "$2" -- . ':(exclude).claude/reviews' 2>/dev/null)"
  [[ -n "$files" ]] || return 0
  exloom_policy_reviewers "$files" 2>/dev/null || true
}

# How many review rounds has this branch had? Distinct commits appearing in the
# L1 receipt, which holds one JSON line per real dispatch. Deterministic — no
# model, no judgement.
#
# Counts BOTH the committed receipts and any sitting uncommitted in the working
# tree, then de-duplicates. Reading only the committed ref would answer 0
# whenever the receipts have not been committed yet, which is most of the time,
# since nothing commits them until /review-complete says so. A counter that
# reports "no rounds" when it cannot see the rounds is worse than one that
# errors: it fails open in the mechanism whose only job is to notice
# accumulation.
exloom_round_count() {   # exloom_round_count <checklist> <tip>
  local vdir committed working
  vdir="$(exloom_verdict_dir "$1")"
  committed="$(MSYS_NO_PATHCONV=1 git show "${2}:${vdir}/l1-reviewer.json" 2>/dev/null || true)"
  working="$(cat "${vdir}/l1-reviewer.json" 2>/dev/null || true)"
  # awk, not `grep -c . || printf 0`: on no match grep prints 0 AND exits 1, so
  # the fallback also fires and the answer becomes the two-line string "0\n0",
  # which every arithmetic test on it rejects with a syntax error.
  printf '%s\n%s\n' "$committed" "$working" \
    | sed -n 's/.*"head"[[:space:]]*:[[:space:]]*"\([0-9a-f]\{7,40\}\)".*/\1/p' \
    | sort -u | awk 'END{print NR}'
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

# Has the user been asked, and decided to ship at the cap?
#
# The session records this in the checklist AFTER it puts the report in front of
# the user and takes an explicit answer. The control is the asking, not the file:
# the block message instructs the session to show the report in the conversation
# and offer named options.
#
# Mechanically, all this checks is that the escape-hatch section carries a line
# naming the cap with a reason after it. The reason is for the next reader, not
# for the gate. A protected file the person must edit from a shell would be
# worse — that is an obstacle, not a decision point.
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
    # DISTINCT defects, by fingerprint, not finding lines. The same defect
    # reported in three passes is one thing still open; counting lines would
    # report "3 critical findings" beside a single cite.
    n=$(( n + $(printf '%s\n' "$last" | grep "\"round\":${maxr}," | grep '"severity":"HIGH"' \
                 | sed -n 's/.*"fingerprint":"\([^"]*\)".*/\1/p' | sort -u | awk 'END{print NR}') ))
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
# A review pass does not fix anything. Running a pass on a tip identical to the
# previous pass's is a guaranteed repeat of the previous pass's findings: it
# spends a round and moves nothing. The thing that has to happen between rounds
# is a FIX, so the report needs to be able to say when one did not.
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

# A short answer to "where does the gate stand right now", printed after every
# reviewer completes rather than only when someone runs /review-complete.
#
# Without this, the bookkeeping is invisible until the push, which is why a
# session hand-dispatches reviewers and never invokes the command: dispatching
# directly produces the same findings, so it feels equivalent, and nothing
# contradicts that until the push is refused. What the command adds — the tier
# derived from the diff, which receipts are missing or stale, which sections are
# unfilled — is real work that otherwise produces no visible output at the moment
# it matters.
#
# So it is printed at that moment. A reviewer just finished; this says what that
# changed and what is still outstanding. Nothing here blocks, and it does not
# replace the command — it removes the reason to defer it.
exloom_gate_status() {   # exloom_gate_status <branch> <tip>
  local branch="$1" tip="$2" checklist vdir content lane tier derived eff
  checklist=".claude/reviews/${branch}.md"
  vdir="$(exloom_verdict_dir "$checklist")"

  content="$(cat "$checklist" 2>/dev/null || true)"
  tier="$(printf '%s\n' "$content" | grep -E '^\*\*Tier:\*\*' | head -1 \
          | sed -E 's/.*Tier:\*\*[[:space:]]*([0-9]).*/\1/')"
  lane="$(printf '%s\n' "$content" | exloom_declared_lane)"
  [[ -n "$lane" ]] || lane="$(exloom_repo_lane)"
  derived="$(exloom_derive_tier "$tip" 2>/dev/null || true)"
  [[ "$tier" =~ ^[0-3]$ ]] || tier="$derived"
  [[ "$tier" =~ ^[0-3]$ ]] || return 0
  eff="$(exloom_effective_tier "$tier" "$lane")"

  local sec_base sec_extra=""
  sec_base="$(exloom_fork_point "$tip" 2>/dev/null || true)"
  [[ -n "$sec_base" ]] && exloom_security_surface "$sec_base" "$tip" && sec_extra="security"

  # The block's APPEARANCE is the signal. Printing the same shape whether or not
  # anything is wrong puts "your branch cannot ship" on the same channel, with
  # the same prefix, as "receipt recorded" — several times a round, mostly
  # unchanged. That is how a status line gets tuned out, which would rebuild the
  # problem it exists to fix, with more output.
  #
  # So the detail prints only when something is ACTIONABLE, and a satisfied gate
  # is one line. A reader can then tell there is something to read without
  # reading it.
  local -a lines=()
  local actionable=0 covered=0 required=0
  # Set only for the reviewer states that have NO escape hatch: rejected, never
  # reported, never dispatched. A stale receipt is deliberately excluded - see
  # the cap block below.
  local must_clear=0

  # ---------- past the cap, this stops asking for rounds ----------
  #
  # This function runs after every reviewer completes, and a fix commit always
  # leaves the L1 receipt behind the tip — so without this it prints "covers an
  # earlier commit, re-run it" on every pass, indefinitely. That makes the status
  # a motor for the very loop the cap exists to stop, and the cap cannot correct
  # it, because the cap is checked at the push and a session in a review loop is
  # not pushing.
  #
  # Past the cap, then, the status stops instructing and starts asking. It still
  # does not block — a status line that blocks would be a second gate — but it
  # must not be the thing that keeps the loop running either.
  #
  # Note the state here, do NOT return on it. Going silent past the cap would
  # hide a reviewer that was never dispatched. The problem is not that this
  # function speaks; it is that it INSTRUCTS. The per-reviewer detail is useful
  # at every round, and "re-run it" is the part that must stop.
  local st_rounds st_max at_cap=0 st_answered=0
  st_rounds="$(exloom_round_count "$checklist" "$tip" 2>/dev/null || echo 0)"
  st_max="$(exloom_max_rounds 2>/dev/null || echo 3)"
  [[ "${st_rounds:-0}" -ge "${st_max:-3}" ]] && at_cap=1
  exloom_cap_override "$checklist" "$tip" 2>/dev/null && st_answered=1

  if [[ -n "$derived" && "$derived" =~ ^[0-3]$ && "$tier" -lt "$derived" ]]; then
    lines+=("  tier          declared ${tier}, but this diff derives to ${derived} - the push will be refused until it is raised")
    actionable=1
  fi

  # Coverage is judged the way the GATE judges it, not by an exact match on the
  # tip. A status line stricter than the check it reports on tells people to
  # re-run a reviewer the gate is content with — and once its demands are known
  # to be inflated, the ones that are real stop being read as well.
  #
  # So an APPROVED verdict at any commit whose diff to the tip cannot change
  # behaviour counts as current, and a line carrying no verdict is a launch,
  # never coverage.
  local agent file sha rline state
  for agent in $(exloom_required_reviewers "$eff" "$sec_extra"); do
    required=$((required + 1))
    file="${vdir}/${agent}.json"
    if [[ ! -s "$file" ]]; then
      lines+=("  ${agent}  NOT DISPATCHED")
      actionable=1; must_clear=1
      continue
    fi
    state="stale"
    while IFS= read -r rline || [[ -n "$rline" ]]; do
      [[ -n "$rline" ]] || continue
      sha="$(printf '%s' "$rline" | sed -n 's/.*"head"[[:space:]]*:[[:space:]]*"\([0-9a-f]\{7,40\}\)".*/\1/p')"
      [[ -n "$sha" ]] || continue
      git rev-parse --verify "${sha}^{commit}" >/dev/null 2>&1 || continue
      # Only l1-reviewer has to cover the shipped commit; the others count as
      # covered once they have approved anywhere on the branch. Same rule as the
      # gate — see exloom_check_verdicts.
      if [[ "$agent" == "l1-reviewer" && "$sha" != "$tip" ]] \
         && exloom_diff_is_behavioural "$sha" "$tip"; then continue; fi
      case "$rline" in
        *'"verdict":"APPROVED"'*) state="ok"; break ;;
        *'"verdict":"'*)          state="unapproved" ;;
        *'"dispatch":true'*)      [[ "$state" == "stale" ]] && state="launched" ;;
      esac
    done < "$file"
    case "$state" in
      ok)         covered=$((covered + 1)) ;;
      unapproved) lines+=("  ${agent}  reviewed this code and did NOT approve it"); actionable=1; must_clear=1 ;;
      launched)   lines+=("  ${agent}  launched, but its report never reached exloom - re-dispatch it without a name"); actionable=1; must_clear=1 ;;
      *)
        # Past the cap the fact is still worth stating; the instruction is not.
        # A fix commit always leaves the L1 receipt behind the tip, so an
        # unconditional "re-run it" here asks for a round after every completion,
        # forever.
        if [[ "$at_cap" -eq 1 ]]; then
          lines+=("  ${agent}  covers an earlier commit - do NOT re-run, the branch is past its round cap")
        else
          lines+=("  ${agent}  covers an earlier commit - re-run it if code changed since")
        fi
        actionable=1 ;;
    esac
  done

  if [[ -z "$content" ]]; then
    lines+=("  checklist     none yet - run /review-init")
    actionable=1
  else
    local unfilled
    unfilled="$(printf '%s\n' "$content" | grep -cE '<(paste output|exact command|exact steps|expected-result|file:line|category \+ file:line|list|severity \+|what is missing|PROVED / NOT_PROVED|reviewed-sha|ai-assisted|model-id|directed-by|base-sha|attested-date|rows rewritten[^>]*|the mechanism, e\.g\.[^>]*|one line per rule[^>]*|policy-fingerprint)' || true)"
    if [[ "${unfilled:-0}" -gt 0 ]]; then
      lines+=("  checklist     ${unfilled} placeholder line(s) still unfilled")
      actionable=1
    fi
  fi

  # Printed before anything else in this block, because every other line here is
  # derived from receipts, and if none of them recorded a verdict then none of
  # those lines mean what they appear to mean.
  local st_blind2
  if st_blind2="$(exloom_evidence_blind_note "$checklist" "$tip" 2>/dev/null)"; then
    echo "exloom: ${st_blind2}" >&2
  fi

  # Satisfied is reported whether or not the branch is past its cap: the two are
  # different facts, and suppressing this one at the cap would leave a branch
  # whose reviewers are all current with no confirmation of it. Past the cap the
  # STOP block follows, so the reader gets both.
  if [[ "$actionable" -eq 0 ]]; then
    echo "exloom: gate satisfied at ${tip:0:12} - ${covered}/${required} receipts current, Tier ${tier}, ${lane} lane" >&2
    [[ "$at_cap" -eq 0 ]] && return 0
  fi

  if [[ "$actionable" -eq 1 ]]; then
    local cap=""
    [[ "$eff" != "$tier" ]] && cap=", reviewer set capped at Tier ${eff}"
    echo "exloom: ACTION NEEDED - ${branch} cannot ship as it stands (Tier ${tier}, ${lane} lane${cap})" >&2
    printf '%s\n' "${lines[@]}" >&2
    echo "  next          /review-complete does this bookkeeping and records it; dispatching reviewers by hand does none of it" >&2
  fi

  # The cap, stated where the loop is actually spinning. The push gate asks the
  # same question, but a session in a review loop is not pushing — it is
  # reviewing — so this is the only place the question reliably gets asked.
  if [[ "$at_cap" -eq 1 ]]; then
    # The cap counts review ROUNDS - passes opened to look for new findings. A
    # reviewer that was rejected, went stale, or never reported has not finished
    # the round it was already required for, and re-running it is not a new one.
    #
    # Forbidding that dispatch deadlocks the gate against itself: a rejected
    # receipt has no escape hatch, the push gate says to clear it, and this
    # message says not to. The only way out was a person overriding what the
    # gate itself demanded.
    if [[ "$must_clear" -eq 1 ]]; then
      echo "exloom: ${branch} is at the round cap (${st_rounds}/${st_max}), but the reviewers above have not cleared." >&2
      echo "  Dispatch them - that is not another round, it finishes the one already required." >&2
      echo "  The cap forbids opening a NEW pass to look for new findings. It does not" >&2
      echo "  forbid clearing a rejected, stale or never-reported receipt." >&2
    elif [[ "$st_answered" -eq 1 ]]; then
      echo "exloom: ${branch} has ${st_rounds} passes and a recorded cap decision - the round question is answered, do not dispatch another reviewer." >&2
    else
      echo "exloom: STOP - ${branch} has had ${st_rounds} review passes (cap ${st_max}). Do not dispatch another reviewer." >&2
      echo "  A pass is not a fix. Ask the user, with AskUserQuestion and these options:" >&2
      echo "    - Fix the open critical findings, then re-review" >&2
      echo "    - Merge as-is - the open items are acceptable" >&2
      echo "    - Show me the findings first" >&2
      echo "  Their answer goes in ${checklist} under 'Escape hatches used' as" >&2
      echo "  '- User approved at round cap - <their words>'. The push gate asks the" >&2
      echo "  same question and will not pass this branch until it is answered." >&2
    fi
  fi
  return 0
}

# exloom_check_verdicts <checklist> <tier> <tip> <reviewed-sha> <action>
#
# Only the L1 reviewer's approval must cover the shipped commit. The others must
# have RUN and APPROVED at some point on this branch.
#
# Requiring every reviewer to approve the SAME commit is what makes a review loop
# fail to converge: any fix creates a new commit, which cancels every approval —
# including from reviewers already satisfied — so N reviewers must simultaneously
# approve a target that moves each time one of them is answered, and the expected
# number of rounds grows as 1/p^N. Decoupling makes it 1/p. L1 covers what ships;
# the others cover that a hostile pass and a security pass happened and that
# their findings were addressed.
exloom_check_verdicts() {
  local checklist="$1" tier="$2" tip="$3" reviewed="$4" action="$5" lane="${6:-standard}"
  local vdir agent file content sha ok approved_at behind seen_verdict dispatch_only
  local -a missing=() stale=() unapproved=() launched=()
  vdir="$(exloom_verdict_dir "$checklist")"

  # Security review is triggered by SURFACE as well as by tier — see
  # exloom_security_surface. Computed once here rather than in the tier lookup,
  # because only this function knows which commits are being compared.
  local sec_base sec_extra=""
  # The same fork point the tier uses. Taking the first base that resolves would
  # compare the branch against a stale release branch, so a dependency bump
  # somebody else made months ago would read as this change's security surface.
  sec_base="$(exloom_fork_point "$reviewed" || true)"
  if [[ -n "$sec_base" ]] && exloom_security_surface "$sec_base" "$reviewed"; then
    sec_extra="security"
  fi

  for agent in $(exloom_required_reviewers "$tier" "$sec_extra"); do
    file="${vdir}/${agent}.json"
    # MSYS_NO_PATHCONV: Git Bash on Windows mangles the `ref:path` argument.
    content="$(MSYS_NO_PATHCONV=1 git show "${tip}:${file}" 2>/dev/null || true)"
    if [[ -z "$content" ]]; then missing+=( "$agent" ); continue; fi
    ok=0; rejected=0; approved_at=""; seen_verdict=0; dispatch_only=""

    # A receipt with no verdict is NOT accepted, whatever wrote it.
    #
    # Such a line says a reviewer was launched. It does not say what the reviewer
    # concluded, and "we do not know what it concluded" is not approval. The
    # asymmetry is not close: refusing one costs a single re-dispatch, accepting
    # one ships code nobody has been shown to have reviewed. The gate may not
    # guess in the permissive direction.
    #
    # Read whole receipt LINES, so that the commit and the verdict on one line
    # are evaluated together. Reading the two fields separately would let an
    # APPROVED verdict from an old commit vouch for a REJECTED review of the
    # current one.
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

      # A dispatch is not a review, and a reviewer that returned REJECTED must
      # not satisfy the gate it was dispatched to satisfy. A line either states a
      # verdict or it records a launch; only the first is evidence.
      case "$rline" in
        *'"verdict":"APPROVED"'*) seen_verdict=1; ok=1; approved_at="$sha"; break ;;
        *'"verdict":"REJECTED"'*|*'"verdict":"UNKNOWN"'*) seen_verdict=1; rejected=1 ;;
        *) dispatch_only="$sha" ;;
      esac
    done < <(printf '%s\n' "$content")
    if [[ $ok -ne 1 ]]; then
      if   [[ $rejected -eq 1 ]];        then unapproved+=( "$agent" )
      elif [[ -n "$dispatch_only" ]];    then launched+=( "$agent" )
      else                                    stale+=( "$agent" ); fi
    elif [[ "$agent" != "l1-reviewer" && -n "$approved_at" ]]; then
      # Decoupling means these reviewers approve code and then more code lands.
      # That gap is a real exposure: fixes made in response to round-1 findings
      # are exactly the commits most likely to touch an integration seam, and a
      # hostile pass is what catches those. It cannot be closed without either
      # re-running every reviewer per commit (the loop) or reviewing only the
      # delta (unsound), so it is DISCLOSED instead — a fact for whoever reads
      # the PR, never a block.
      behind="$(git rev-list --count "${approved_at}..${reviewed}" 2>/dev/null || echo 0)"
      if [[ "${behind:-0}" -gt 0 ]]; then
        echo "exloom: ${agent} approved ${approved_at:0:12} — ${behind} commit(s) have landed since; it did not see them." >&2
      fi
    fi
  done

  # ---------- the round cap ----------
  #
  # The cap is a property of the branch, not of the findings, so it is evaluated
  # whether or not anything is outstanding. Checking it only when a reviewer is
  # unsatisfied would let a branch reach round ten, satisfy everyone, and ship
  # without the count ever surfacing.
  #
  # A counter that only goes up is the point: it cannot be satisfied by more
  # work, only by a person deciding the branch is done taking rounds.
  local rounds max
  rounds="$(exloom_round_count "$checklist" "$tip")"
  max="$(exloom_max_rounds)"

  local outstanding=""
  [[ ${#unapproved[@]} -gt 0 ]] && outstanding="$(printf '  %s — reviewed this code and did NOT approve\n' "${unapproved[@]}")"
  [[ ${#stale[@]} -gt 0 ]]      && outstanding="${outstanding}$(printf '  %s — approved earlier code, not the current tip\n' "${stale[@]}")"
  [[ ${#launched[@]} -gt 0 ]]   && outstanding="${outstanding}$(printf '  %s — launched, but its report never reached exloom\n' "${launched[@]}")"
  [[ ${#missing[@]} -gt 0 ]]    && outstanding="${outstanding}$(printf '  %s — never dispatched\n' "${missing[@]}")"

  # The cap override answers a question about ROUNDS. It is not an answer about
  # whether anyone reviewed the code.
  #
  # Checked here rather than above the receipt evaluation, because returning
  # early would let a recorded "merge as-is" waive the requirement that reviewers
  # ran at all — and the report a person answers that question against is built
  # from those same receipts, so a broken pipeline makes the question itself
  # wrong. The override clears the cap and nothing else; outstanding reviewers
  # still block, and say so.
  if [[ "$rounds" -ge "$max" ]] && exloom_cap_override "$checklist" "$tip"; then
    if [[ -z "$outstanding" ]]; then
      echo "exloom: shipping at ${rounds} passes on a decision recorded in ${checklist}." >&2
      return 0
    fi
    _exloom_block "$action" "A round-cap decision is recorded in ${checklist}, but it does not
cover this.

The cap answers 'have we reviewed enough times'. It does not answer 'did anyone
review this', and these reviewers have not:


${outstanding}
$(exloom_evidence_blind_note "$checklist" "$tip" || true)
Fix the reviewers listed above, or remove the cap decision if it was made on a
report that showed them as satisfied."
    return 2
  fi

  if [[ "$rounds" -ge "$max" ]]; then
    [[ -n "$outstanding" ]] || outstanding="  every required reviewer is satisfied at this commit
"
    local trend crit cites fix_opt rec noop="" blind=""
    trend="$(exloom_severity_trend "$checklist" "$tip" 2>/dev/null || true)"
    # "(no findings recorded)" reads as a clean branch. When the pipeline is
    # blind it instead means nothing was ever parsed, and rendering the two the
    # same way tells an author there is nothing to fix when the truth is that
    # nobody knows.
    if blind="$(exloom_evidence_blind_note "$checklist" "$tip")"; then
      trend="  (nothing was recorded — see the warning above)
"
      blind="${blind}

"
    elif [[ -z "$trend" ]]; then
      trend="  (no findings recorded)
"
    fi
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
    # intent. A cap is a decision point, so it must produce a DECISION.
    #
    # So this blocks, and hands the session the question to put to the user. The
    # push stays blocked either way — the gate is enforced here, in the hook.
    # What the session controls is only which of the named options is carried
    # out.
    _exloom_block "$action" "${blind}Review has run ${rounds} passes on this branch (cap ${max}).

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

  if [[ ${#missing[@]} -eq 0 && ${#stale[@]} -eq 0 && ${#unapproved[@]} -eq 0 && ${#launched[@]} -eq 0 ]]; then return 0; fi

  local detail="Tier ${tier} requires a verdict receipt from each of: $(exloom_required_reviewers "$tier" "$sec_extra")."
  # Say which lane set that bar. A Sprint branch is asked for one reviewer where
  # the tier would have asked for three, and a reader of this message should not
  # have to work out why the demand looks light.
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
  [[ ${#launched[@]} -gt 0 ]] && detail="${detail}

Launched, but their report never reached exloom (re-dispatch them):
$(printf '  - %s\n' "${launched[@]}")
The receipt records the launch and nothing else, so what the reviewer concluded
is unknown — and an unknown conclusion is not an approval. The usual cause is a
subagent dispatched with a NAME, which routes its report to the mailbox instead
of the tool result exloom reads. Dispatch it again without a name."
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
  # For a binary change `git diff` emits only "Binary files a/x and b/x differ",
  # with no +/- lines at all, so a purely line-based classifier would call it
  # non-behavioural — and swapping a vendored .jar, a .dll, a model weight, a
  # keystore or a wasm blob would keep a stale review valid. A pure rename and a
  # file-mode change have the same shape.
  #
  # --numstat reports "-\t-\tpath" for binary content, which is unambiguous.
  if git diff --numstat "$from" "$to" -- . ':(exclude).claude/reviews' 2>/dev/null \
     | grep -qE '^-[[:space:]]+-[[:space:]]'; then
    return 0
  fi
  if git diff --no-color "$from" "$to" -- . ':(exclude).claude/reviews' 2>/dev/null \
     | grep -qE '^(old mode|new mode|rename from|rename to|deleted file|new file) '; then
    return 0
  fi

  # ---------- comment markers are per-language, never universal ----------
  # Treating `#` as a comment everywhere classifies real code as inert:
  #   #define TIMEOUT 300 / #include <stdlib.h>   (C/C++/ObjC/C#)
  #   #[derive(...)] / #![allow]                  (Rust attributes)
  #   #login { display: none }                    (CSS id selector)
  #   //go:build linux / //go:generate            (Go directives)
  #   #!/bin/sh                                   (shebang)
  # Any one of those is enough to flip a whole diff to non-behavioural.
  #
  # So the marker set is chosen per file, and a file whose language is unknown is
  # treated as having NO comment markers — every changed line counts.
  #
  # core.quotepath=false: git otherwise quotes paths containing non-ASCII or
  # special characters, and the quoted form matches no file on disk.
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

    # `-w` ignores whitespace-only changes. That is right for a brace language,
    # where reindenting a block changes nothing, and WRONG wherever indentation
    # is syntax: in Python, de-indenting a line moves it out of an `if` branch;
    # in YAML it re-parents a key. Both are behavioural and both are invisible to
    # `-w`, which would score the change inert and leave a stale receipt valid.
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
                '*') continue ;;                 # a BARE star is a javadoc paragraph break
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
    #   2. No `## Re-finds` section -> a checklist from an older template; fall
    #      back to the cite appearing anywhere, so a branch already in flight is
    #      not stranded with no way past the gate.
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

Option 1 matters. Without it the only way past this gate is to close the class in
the current branch, which turns a one-line change into a refactor — and every
line that refactor adds is unreviewed code for the next round to find defects in.

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
  local vdir file content sha ok=0 seen_notproved=0 seen_cmdswap=0 seen_notapplicable=0

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
      # The receipt records the hash of the pinned test command, and comparing it
      # here is what binds the proof to the command that was actually run.
      # Without this comparison a repo could prove with a real suite, then change
      # .claude/exloom-test-command to `true`, and the receipt would stay valid.
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
        # An additive change cannot satisfy the three-run proof: its tests do not
        # compile at base. Mutation asks the same question without needing the
        # code to be absent.
        *'"result":"PROVED_BY_MUTATION"'*) ok=1; break ;;
        # The tests could not compile without the change, so the question could
        # not be asked. That is a property of additive code, not a weak test, and
        # it must not read as the same failure. Accepted and reported, because
        # the alternative was a bypass - which lets the same push through while
        # recording less about why.
        *'"result":"NOT_APPLICABLE"'*) ok=1; seen_notapplicable=1 ;;
        *'"result":"NOT_PROVED"'*) seen_notproved=1 ;;
      esac
    done < <(printf '%s\n' "$content")
  fi

  if [[ $ok -eq 1 ]]; then
    # Stated every time, because the whole value of accepting this result is that
    # the reader knows which of the three they got. A silent pass would make the
    # weakest evidence look like the strongest.
    if [[ $seen_notapplicable -eq 1 ]]; then
      echo "exloom: proof recorded NOT_APPLICABLE - the tests do not compile without the change, so it could not be run. The receipt says so; it is the weakest of the three results." >&2
    fi
    return 0
  fi

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

This check exists because these defects are otherwise found by a human, a round
or two later: an assertion satisfied by any string, a write-path test with no
read-path test, a build that reported success without running the suite."
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

  # FAIL CLOSED on a policy that cannot be read. Falling back to the built-in
  # rules is the worst available outcome: an author writes a Tier 3 rule for
  # their identity module, a typo means it never loads, the built-ins score the
  # change Tier 1, and everyone believes a rule is in force that never ran.
  # Three outcomes only — valid: enforce; absent: built-ins; invalid: stop.
  if ! exloom_policy_load 2>/dev/null; then
    _exloom_block "$action" "$(exloom_policy_error)"
    return 2
  fi

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

  # Certified has no escape hatches. Checked before the signing check so a fixable
  # content problem is reported ahead of an environment one. A recorded round-cap
  # answer is exempt — it is a decision, not a skipped step.
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
  placeholder_re='<(paste output / screenshot link|exact command|exact steps|expected-result|Claude-session-or-human-reviewer|who-attests|path to committed runbook\.md|test id or path[^>]*|paste|list[^>]*|file:line — problem[^>]*|category \+ file:line[^>]*|N files changed[^>]*|Critical / Important / Minor[^>]*|reviewed-sha|ai-assisted|model-id|directed-by|base-sha|attested-date|severity \+ category \+ file:line[^>]*|fixed / deferred with reason per finding|one sentence why|secrets / dep-audit / static[^>]*|which hostile question[^>]*|step name|exact command, or "detected"|PROVED / NOT_PROVED|what is missing[^>]*|rows rewritten[^>]*|the mechanism, e\.g\.[^>]*|one line per rule[^>]*|policy-fingerprint)>'
  drop=''
  if   [[ "$eff_tier" -lt 1 ]]; then drop='^## (Smoke test|Cross-layer|Adversarial|Security review|Runbook)'
  elif [[ "$eff_tier" -lt 2 ]]; then drop='^## (Cross-layer|Adversarial|Security review|Runbook)'
  elif [[ "$eff_tier" -lt 3 ]]; then drop='^## (Security review|Runbook)'
  fi
  # HTML comments are guidance, not evidence. The template uses them to show what
  # a filled-in line looks like, which necessarily quotes the placeholder tokens,
  # so scanning them would let the template's own instructions block the push.
  scan="$(printf '%s\n' "$content" \
    | awk '/<!--/{inc=1} !inc{print} /-->/{inc=0}' \
    | awk -v drop="$drop" '/^## /{skip=(drop!="" && $0 ~ drop)?1:0} !skip{print}')"
  if printf '%s' "$scan" | grep -Eq "$placeholder_re" || printf '%s' "$scan" | grep -qE '^Date:[[:space:]]*YYYY-MM-DD[[:space:]]*$'; then
    # NAME THE LINES. "A required section is unfilled" would leave the author
    # reading a regex out of this file to work out which one. Each line is
    # reported with the heading it sits under, since a bare line is not always
    # enough to place it.
    local unfilled
    unfilled="$(printf '%s\n' "$scan" \
      | EXLOOM_PH_RE="$placeholder_re" awk '
          BEGIN{ re = ENVIRON["EXLOOM_PH_RE"] }
          /^## /{sec=$0}
          $0 ~ re || /^Date:[[:space:]]*YYYY-MM-DD[[:space:]]*$/ {
            printf "  %s\n      %s\n", (sec==""?"(header)":sec), $0
          }' | head -20)"
    _exloom_block "$action" "$checklist still contains template placeholder text:

${unfilled}
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
    # an assertion. Uses the effective tier; the declared tier is already known
    # to be at least the derived one from the check above.
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
        # Name the reason that actually applies. Naming the marker when the LANE
        # is what demanded signing would send the reader looking for a file that
        # is not there, and tell them to remove it.
        local why="the repo has .claude/exloom-provenance-signed.enabled" out="remove that marker"
        if [[ "$lane" == "certified" ]]; then
          why="this branch is on the Certified lane"
          out="move the branch to the Standard lane (**Lane:** standard)"
        fi
        _exloom_block "$action" "Signed provenance is required — ${why} — but the commit that recorded $checklist is not a verified signed commit.
Configure git commit signing (GPG or SSH) and re-run /review-complete, which commits with -S. Otherwise ${out}."
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
# Every refusal in this file goes through here, including the round cap. A hook
# has exactly one user-facing primitive — block with a message — and the
# alternative, a PreToolUse permission decision of "ask", renders as
# approve/cancel on the push itself. Cancel is not an answer: it refuses the
# tool, the push dies, the session has nothing to act on, and the person has to
# retype what they wanted. Two of the cap's three real answers, "fix these" and
# "show me the findings", cannot be expressed as approve or cancel at all.
#
# Named options need AskUserQuestion, which is a session tool rather than a hook
# capability. So a block carries the question in its text: the hook refuses, and
# the message tells the session what to ask and what to do with each answer. The
# push stays blocked either way; the session only chooses which option runs.
_exloom_block() {
  local action="$1" detail="$2"
  cat >&2 <<EOF
exloom review gate: BLOCKED — cannot ${action}.

${detail}

Emergency bypass: set EXLOOM_REVIEW_SKIP=1 in your Claude Code session env
(settings.json "env"), then retry. An inline "EXLOOM_REVIEW_SKIP=1 <cmd>" will
NOT work — the hook reads its own environment, not the command's.

It records itself in .claude/reviews/<branch>.bypass.json. Commit that with the
change and write the reason in the checklist's "Escape hatches used" section.
Nothing verifies either; they exist so the next reader can see this happened.
EOF
}
