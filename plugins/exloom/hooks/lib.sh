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

# exloom_check_verdicts <checklist> <tier> <tip> <reviewed-sha> <action>
# Returns 0 when every reviewer the tier requires has a receipt covering the
# reviewed commit; prints a BLOCK message and returns 2 otherwise.
exloom_check_verdicts() {
  local checklist="$1" tier="$2" tip="$3" reviewed="$4" action="$5"
  local vdir agent file content sha ok
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
    ok=0; rejected=0
    # Read whole receipt LINES, so the commit and the verdict on one line are
    # evaluated together. Reading them separately would let an APPROVED verdict
    # from an old commit vouch for a REJECTED review of the current one.
    while IFS= read -r rline || [[ -n "$rline" ]]; do
      [[ -z "$rline" ]] && continue
      sha="$(printf '%s' "$rline" | sed -n 's/.*"head"[[:space:]]*:[[:space:]]*"\([0-9a-f]\{7,40\}\)".*/\1/p')"
      [[ -n "$sha" ]] || continue
      git rev-parse --verify "${sha}^{commit}" >/dev/null 2>&1 || continue
      # A receipt covers the reviewed commit when no code differs between the two
      # — a checklist-only commit landing in between must not invalidate a real
      # review, and a code commit must.
      # Covers the reviewed commit when nothing behavioural differs. A
      # checklist-only or comment-only commit landing in between must not
      # invalidate a real review; a code commit must.
      if [[ -n "$(git diff --name-only "$sha" "$reviewed" -- . ':(exclude).claude/reviews' 2>/dev/null)" ]]; then
        exloom_diff_is_behavioural "$sha" "$reviewed" && continue
      fi

      # A dispatch is not a review. A reviewer that returned REJECTED must not
      # satisfy the gate it was dispatched to satisfy.
      #
      # GRANDFATHERED: receipts written before exloom recorded verdicts have no
      # "verdict" key at all. Those still count — refusing them would block every
      # in-flight branch the moment this version is installed, and a migration
      # that breaks running work does not get adopted, it gets uninstalled.
      case "$rline" in
        *'"verdict":"APPROVED"'*) ok=1; break ;;
        *'"verdict":"REJECTED"'*|*'"verdict":"UNKNOWN"'*) rejected=1 ;;
        *) ok=1; break ;;   # legacy receipt, no verdict recorded
      esac
    done < <(printf '%s\n' "$content")
    if [[ $ok -ne 1 ]]; then
      if [[ $rejected -eq 1 ]]; then unapproved+=( "$agent" ); else stale+=( "$agent" ); fi
    fi
  done

  if [[ ${#missing[@]} -eq 0 && ${#stale[@]} -eq 0 && ${#unapproved[@]} -eq 0 ]]; then return 0; fi

  local detail="Tier ${tier} requires a verdict receipt from each of: $(exloom_required_reviewers "$tier" "$sec_extra")."
  [[ -n "$sec_extra" ]] && detail="${detail}
security-auditor is required by the SURFACE this diff touches (a dependency
manifest or a deserialization entry point), not by the tier."
  [[ ${#missing[@]} -gt 0 ]] && detail="${detail}

Never dispatched (no receipt in ${vdir}/):
$(printf '  - %s\n' "${missing[@]}")"
  [[ ${#stale[@]} -gt 0 ]] && detail="${detail}

Dispatched, but only against code that has since changed (re-run them):
$(printf '  - %s\n' "${stale[@]}")"
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
           | grep -qE 'FIXED THE CLASS|GENUINELY SEPARATE'; then continue; fi
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
A re-find is not a new defect. It is evidence that the previous fix addressed the
instance you were shown rather than the rule behind it — which is why the next
round found the adjacent case. Patching this one schedules the third.

Record a disposition under '## Re-finds' in ${checklist}, naming the cite, and
pick one:

  1. FIXED THE CLASS — name the test that quantifies over the whole set (every
     codepoint, every branch, every member), not the instance. \"One test that
     asserts no single codepoint in any position defeats the marker would have
     found all of this before round one, and would keep finding it.\"
  2. GENUINELY SEPARATE — say why this defect is unrelated to the earlier one
     despite matching it.

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
  if   [[ "$tier" -lt 1 ]]; then drop='^## (Smoke test|Cross-layer|Adversarial|Security review|Runbook)'
  elif [[ "$tier" -lt 2 ]]; then drop='^## (Cross-layer|Adversarial|Security review|Runbook)'
  elif [[ "$tier" -lt 3 ]]; then drop='^## (Security review|Runbook)'
  fi
  scan="$(printf '%s\n' "$content" | awk -v drop="$drop" '/^## /{skip=(drop!="" && $0 ~ drop)?1:0} !skip{print}')"
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
    exloom_check_verdicts "$checklist" "$tier" "$tip" "$reviewed_sha" "$action" || return 2

    # Author-side proof that the change is actually tested (Tier 1+). The receipt
    # is written only by scripts/prove-change-is-tested.sh, into the directory
    # protect-verdicts.sh guards, so the result cannot be typed.
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

    # v2 (opt-in): the commit that recorded the checklist must be a verified signed commit.
    if [[ -f ".claude/exloom-provenance-signed.enabled" ]]; then
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
