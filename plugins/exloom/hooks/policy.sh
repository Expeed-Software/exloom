#!/usr/bin/env bash
# exloom — repository policy (.exloom.yml).
#
# Sourced by lib.sh; never executed directly.
#
# WHY THIS EXISTS. Tier derivation matches hard-coded words: auth, tenant,
# secret, crypto, jwt, apikey, migrations/. A repository that calls the same
# thing `identity`, `iam`, `rbac`, `membership` or `access-control` derives a
# lower tier for a change that should be the highest one — and the tier is the
# single thing with no escape hatch, because it decides which gates apply. So
# this is not configuration ergonomics; it is whether the gate classifies a
# repository's own architecture correctly.
#
# THREE RULES THAT SHAPE EVERYTHING BELOW.
#
# 1. Policy comes from COMMITTED state — `git show HEAD:.exloom.yml`, never the
#    working tree. Otherwise a developer deletes a rule locally, pushes past the
#    gate, and the policy the team agreed on never applied to the one change
#    that needed it.
#
# 2. Repository policy may only ESCALATE. Built-in rules always run, and the
#    effective tier is the highest anything matched. There is no downgrade key
#    and no flag reserving one: a config that can lower a built-in protection is
#    an escape hatch on the one check that deliberately has none.
#
# 3. An invalid policy BLOCKS. It must never fall back to the built-in defaults,
#    because the failure that matters is an author who believes a security rule
#    is in force when a typo means it was skipped. Valid -> enforce. Absent ->
#    built-ins. Invalid -> stop.
#
# THE PARSER IS SMALL BECAUSE THE SCHEMA IS. This reads a strict format that
# happens to look like YAML: fixed known keys, an integer version, and lists of
# double-quoted glob strings. Anchors, aliases, multiline scalars, inline
# arrays, comments inside values, tabs, and any key not in the schema are
# errors. That boundary is what stops a small reader growing into a bad YAML
# implementation — the next value that needs richer syntax gets a validation
# error rather than an accommodating patch to the parser.

# Case-sensitivity is a correctness property, not a preference: git paths are
# case-sensitive and Windows filesystems often are not, so without this the same
# repository derives different tiers on different machines.
shopt -u nocasematch 2>/dev/null || true

EXLOOM_POLICY_FILE=".exloom.yml"
EXLOOM_POLICY_AGENTS="l1-reviewer adversarial-reviewer security-auditor"

# ---------------------------------------------------------------- glob matching
#
# Deterministic, and deliberately NOT the shell's filesystem globbing. These
# patterns are matched against strings from `git diff --name-only`, so nothing
# should depend on `globstar`, on what exists on disk, or on the host's case
# rules. Translating to an anchored ERE once makes the semantics readable and
# testable in isolation:
#
#   **/   at the start   ->  (.*/)?    zero or more leading directories
#   /**   at the end     ->  (/.*)?    this path, or anything beneath it
#   **    elsewhere      ->  .*
#   *                    ->  [^/]*     never spans a separator
#   ?                    ->  [^/]
#   .                    ->  \.
#
# The separator rule is the one that matters: `src/*/auth/**` must match
# `src/main/auth/X.java` and must NOT match `src/a/b/auth/X.java`. A `*` that
# quietly spans `/` turns a narrow rule into a broad one, and nothing about the
# match output would say so.
exloom_policy_glob_to_re() {   # exloom_policy_glob_to_re <glob>
  local g="$1" re="" i=0 n c nxt
  n=${#g}
  # A leading `**/` is the "at any depth" form and consumes the separator, so it
  # also matches the path with no leading directory at all.
  if [[ "${g:0:3}" == "**/" ]]; then re="(.*/)?"; i=3; fi
  while [[ $i -lt $n ]]; do
    c="${g:$i:1}"
    nxt="${g:$((i+1)):1}"
    case "$c" in
      '*')
        if [[ "$nxt" == "*" ]]; then
          # A trailing `/**` was already consumed as part of the previous
          # character; here `**` is mid-pattern and spans anything.
          re="${re}.*"; i=$((i+2)); continue
        fi
        re="${re}[^/]*"; i=$((i+1)) ;;
      '?')  re="${re}[^/]";  i=$((i+1)) ;;
      '.')  re="${re}\\.";   i=$((i+1)) ;;
      '/')
        if [[ "${g:$i:3}" == "/**" && $((i+3)) -eq $n ]]; then
          re="${re}(/.*)?"; i=$n; continue
        fi
        re="${re}/"; i=$((i+1)) ;;
      *)    re="${re}${c}";  i=$((i+1)) ;;
    esac
  done
  printf '^%s$' "$re"
}

exloom_policy_match() {   # exloom_policy_match <glob> <path>
  local re
  re="$(exloom_policy_glob_to_re "$1")"
  [[ "$2" =~ $re ]]
}

# ------------------------------------------------------------------- the schema
#
# Every key exloom accepts, as a full dotted path. A key not on this list is an
# error rather than a silently ignored line, because the failure this guards
# against is an author who wrote `risk.teir3` and believes a rule is in force.
_exloom_policy_known_key() {   # _exloom_policy_known_key <dotted-path>
  case "$1" in
    version|risk|reviewers|reviewers.require) return 0 ;;
    risk.tier1|risk.tier2|risk.tier3) return 0 ;;
    risk.tier1.paths|risk.tier2.paths|risk.tier3.paths) return 0 ;;
    reviewers.require.*.paths)
      local a="${1#reviewers.require.}"; a="${a%.paths}"
      case " ${EXLOOM_POLICY_AGENTS} " in *" $a "*) return 0 ;; esac
      return 1 ;;
    reviewers.require.*)
      local a="${1#reviewers.require.}"
      case " ${EXLOOM_POLICY_AGENTS} " in *" $a "*) return 0 ;; esac
      return 1 ;;
  esac
  return 1
}

# A near-miss suggestion, so a typo names its own fix. Cheap: the schema is a
# fixed short list, so this is a character-overlap check rather than a real edit
# distance.
_exloom_policy_did_you_mean() {   # _exloom_policy_did_you_mean <bad-key>
  local bad="$1" cand best="" bl cl common ch score best_score=0
  bad="${bad##*.}"
  bl=${#bad}
  for cand in version risk reviewers require tier1 tier2 tier3 paths \
              l1-reviewer adversarial-reviewer security-auditor; do
    cl=${#cand}
    [[ $((bl > cl ? bl - cl : cl - bl)) -le 2 ]] || continue
    common=0
    for (( ch=0; ch<bl; ch++ )); do
      case "$cand" in *"${bad:$ch:1}"*) common=$((common+1)) ;; esac
    done
    score=$(( common * 100 / (cl > bl ? cl : bl) ))
    if [[ $score -gt $best_score ]]; then best_score=$score; best="$cand"; fi
  done
  [[ $best_score -ge 70 && -n "$best" ]] && printf ' — did you mean `%s`?' "$best"
}

# ------------------------------------------------------------------ load + parse
#
# Populates, on success:
#   _EXLOOM_POL_LOADED=1
#   _EXLOOM_POL_PRESENT=0|1     a committed .exloom.yml exists
#   _EXLOOM_POL_RISK            lines of "<tier>\t<glob>"
#   _EXLOOM_POL_REVIEWERS       lines of "<agent>\t<glob>"
#   _EXLOOM_POL_FINGERPRINT     sha of the policy content
# On failure: _EXLOOM_POL_ERR holds a complete, printable message.
#
# Loading is idempotent and cached per HEAD. The hooks call this from several
# places on a single push, and a git object read per call is expensive enough on
# Windows to be worth avoiding.
exloom_policy_load() {
  local head content line indent key val path depth
  local -a stack=()
  head="$(git rev-parse HEAD 2>/dev/null || printf 'none')"
  if [[ "${_EXLOOM_POL_LOADED:-0}" == "1" && "${_EXLOOM_POL_HEAD:-}" == "$head" ]]; then
    [[ -z "${_EXLOOM_POL_ERR:-}" ]]; return
  fi
  _EXLOOM_POL_LOADED=1; _EXLOOM_POL_HEAD="$head"
  _EXLOOM_POL_PRESENT=0; _EXLOOM_POL_RISK=""; _EXLOOM_POL_REVIEWERS=""
  _EXLOOM_POL_ERR=""; _EXLOOM_POL_FINGERPRINT=""

  # COMMITTED state only. A working-tree read would let a local edit decide what
  # the gate enforces, which is the whole point of putting policy in the repo.
  content="$(MSYS_NO_PATHCONV=1 git show "HEAD:${EXLOOM_POLICY_FILE}" 2>/dev/null || true)"
  [[ -n "$content" ]] || return 0
  _EXLOOM_POL_PRESENT=1
  _EXLOOM_POL_FINGERPRINT="$(printf '%s' "$content" \
    | { sha256sum 2>/dev/null || shasum -a 256 2>/dev/null || printf 'unavailable  -'; } \
    | cut -d' ' -f1)"

  local lineno=0 version_seen=0
  while IFS= read -r line || [[ -n "$line" ]]; do
    lineno=$((lineno + 1))
    case "$line" in
      *$'\t'*) _exloom_policy_fail "$lineno" "tabs are not permitted — indent with two spaces per level"; return 1 ;;
    esac
    # Whole-line comments and blanks. A `#` anywhere else is an error rather
    # than a trailing comment: values are quoted globs, and guessing where a
    # value ends is exactly the ambiguity this format exists to avoid.
    [[ -z "${line//[[:space:]]/}" ]] && continue
    case "${line#"${line%%[![:space:]]*}"}" in '#'*) continue ;; esac
    case "$line" in *'#'*) _exloom_policy_fail "$lineno" "\`#\` may only start a whole-line comment"; return 1 ;; esac
    case "$line" in
      '---'*|'...'*) _exloom_policy_fail "$lineno" "document markers are not supported — one document, no \`---\`"; return 1 ;;
      *'&'*|*'<<'*)  _exloom_policy_fail "$lineno" "anchors and merge keys are not supported"; return 1 ;;
      *'|'*|*'>'*)   _exloom_policy_fail "$lineno" "block scalars are not supported — values are single-line quoted strings"; return 1 ;;
      *'['*|*'{'*)   _exloom_policy_fail "$lineno" "inline arrays and maps are not supported — use one \`- \"glob\"\` per line"; return 1 ;;
    esac

    indent="${line%%[![:space:]]*}"
    if [[ $(( ${#indent} % 2 )) -ne 0 ]]; then
      _exloom_policy_fail "$lineno" "indent must be two spaces per level, found ${#indent}"; return 1
    fi
    depth=$(( ${#indent} / 2 ))
    line="${line#"$indent"}"

    # ---- a list item ----
    if [[ "$line" == '- '* ]]; then
      val="${line#- }"
      path="$(_exloom_policy_path stack "$depth")"
      case "$path" in
        risk.tier?.paths|reviewers.require.*.paths) ;;
        '') _exloom_policy_fail "$lineno" "a list item with nothing above it"; return 1 ;;
        *)  _exloom_policy_fail "$lineno" "\`${path}\` does not take a list"; return 1 ;;
      esac
      case "$val" in
        '"'*'"') val="${val:1:${#val}-2}" ;;
        *) _exloom_policy_fail "$lineno" "glob patterns must be double-quoted: \`- \"${val}\"\`"; return 1 ;;
      esac
      if [[ -z "$val" || "$val" =~ [^A-Za-z0-9_./*?-] ]]; then
        _exloom_policy_fail "$lineno" "\`${val}\` is not a glob — permitted characters are letters, digits, and \`_ . / * ? -\`"; return 1
      fi
      case "$path" in
        risk.tier1.paths) _EXLOOM_POL_RISK="${_EXLOOM_POL_RISK}1	${val}"$'\n' ;;
        risk.tier2.paths) _EXLOOM_POL_RISK="${_EXLOOM_POL_RISK}2	${val}"$'\n' ;;
        risk.tier3.paths) _EXLOOM_POL_RISK="${_EXLOOM_POL_RISK}3	${val}"$'\n' ;;
        reviewers.require.*.paths)
          local agent="${path#reviewers.require.}"; agent="${agent%.paths}"
          _EXLOOM_POL_REVIEWERS="${_EXLOOM_POL_REVIEWERS}${agent}	${val}"$'\n' ;;
      esac
      continue
    fi

    # ---- a key ----
    case "$line" in
      *': '*) key="${line%%:*}"; val="${line#*: }" ;;
      *':')   key="${line%:}";   val="" ;;
      *) _exloom_policy_fail "$lineno" "expected \`key:\` or \`- \"glob\"\`"; return 1 ;;
    esac
    if [[ ! "$key" =~ ^[A-Za-z][A-Za-z0-9_-]*$ ]]; then
      _exloom_policy_fail "$lineno" "\`${key}\` is not a valid key name"; return 1
    fi
    stack=( "${stack[@]:0:$depth}" )
    stack[$depth]="$key"
    path="$(_exloom_policy_path stack "$((depth + 1))")"
    if ! _exloom_policy_known_key "$path"; then
      case "$path" in
        reviewers.require.*)
          _exloom_policy_fail "$lineno" "unknown reviewer \`${path#reviewers.require.}\`
Available reviewers: ${EXLOOM_POLICY_AGENTS}" ; return 1 ;;
        *)
          _exloom_policy_fail "$lineno" "unknown configuration key \`${path}\`$(_exloom_policy_did_you_mean "$path")"; return 1 ;;
      esac
    fi
    if [[ -n "$val" ]]; then
      if [[ "$path" != "version" ]]; then
        _exloom_policy_fail "$lineno" "\`${path}\` takes a nested block, not a value"; return 1
      fi
      [[ "$val" =~ ^[0-9]+$ ]] || { _exloom_policy_fail "$lineno" "version must be an integer, found \`${val}\`"; return 1; }
      [[ "$val" == "1" ]] || { _exloom_policy_fail "$lineno" "unsupported policy version ${val} — this exloom understands version 1"; return 1; }
      version_seen=1
    fi
  done <<< "$content"

  if [[ $version_seen -ne 1 ]]; then
    _EXLOOM_POL_ERR="exloom policy error in ${EXLOOM_POLICY_FILE}:

  no \`version:\` — the first line must be \`version: 1\`, so a later exloom
  can migrate this file rather than guess at it."
    return 1
  fi
  return 0
}

# The dotted path of the first <n> stack entries.
_exloom_policy_path() {   # _exloom_policy_path <arrayname> <n>
  local -n _st="$1"; local n="$2" i out=""
  for (( i=0; i<n && i<${#_st[@]}; i++ )); do
    [[ -n "${_st[$i]:-}" ]] || continue
    out="${out:+${out}.}${_st[$i]}"
  done
  printf '%s' "$out"
}

_exloom_policy_fail() {   # _exloom_policy_fail <line> <message>
  _EXLOOM_POL_ERR="exloom policy error in ${EXLOOM_POLICY_FILE}, line ${1}:

  ${2}

The policy is committed repository configuration and the gate will not run
without understanding it. Fix the file, commit it, and retry.

exloom does not fall back to its built-in rules here. A policy that silently
failed to load is how a security rule everyone believes in turns out never to
have run."
}

# Printable error, or empty. Callers block on a non-empty value.
exloom_policy_error() { printf '%s' "${_EXLOOM_POL_ERR:-}"; }

exloom_policy_fingerprint() {
  exloom_policy_load >/dev/null 2>&1 || true
  printf '%s' "${_EXLOOM_POL_FINGERPRINT:-none}"
}

# ------------------------------------------------------------------- evaluation
#
# exloom_policy_tier <newline-separated-paths>
# Prints the highest tier any repository rule matched, or nothing when none did.
# Reasons land in _EXLOOM_POL_REASONS, one per line:
#     <path>\t<glob>\t<source>
# The caller merges this with the built-in tier by taking the maximum. There is
# no path by which a repository rule lowers anything.
#
# NOTHING HERE MAY RUN IN A SUBSHELL, and both of the obvious calling styles put
# it in one. Reading the file list from stdin forces a pipe; assigning the result
# with `x="$(exloom_policy_tier …)"` forces a command substitution. Either way the
# reasons recorded in the global die with the subshell, and the caller is left
# holding a tier with no stated cause — the one thing this exists to provide.
#
# So the file list is an ARGUMENT, and the tier is published through
# _EXLOOM_POL_TIER as well as printed. Call it plainly and read both globals.
exloom_policy_tier() {
  local files="${1:-}" tier best="" glob f
  _EXLOOM_POL_REASONS=""; _EXLOOM_POL_TIER=""
  exloom_policy_load >/dev/null 2>&1 || return 1
  [[ -n "${_EXLOOM_POL_RISK:-}" ]] || return 0
  while IFS=$'\t' read -r tier glob; do
    [[ -n "$tier" && -n "$glob" ]] || continue
    while IFS= read -r f; do
      [[ -n "$f" ]] || continue
      if exloom_policy_match "$glob" "$f"; then
        _EXLOOM_POL_REASONS="${_EXLOOM_POL_REASONS}${f}	${glob}	.exloom.yml:risk.tier${tier}"$'\n'
        [[ -z "$best" || "$tier" -gt "$best" ]] && best="$tier"
        break
      fi
    done <<< "$files"
  done <<< "${_EXLOOM_POL_RISK}"
  _EXLOOM_POL_TIER="$best"
  [[ -n "$best" ]] && printf '%s' "$best"
  return 0
}

exloom_policy_reasons() { printf '%s' "${_EXLOOM_POL_REASONS:-}"; }

# Reviewers the repository requires for these files, beyond whatever the tier
# already asks for. ADDITIVE only — there is no key that removes a reviewer the
# tier requires, for the same reason there is no tier downgrade.
exloom_policy_reviewers() {   # exloom_policy_reviewers <newline-separated-paths>
  local files="${1:-}" agent glob f out=""
  exloom_policy_load >/dev/null 2>&1 || return 1
  [[ -n "${_EXLOOM_POL_REVIEWERS:-}" ]] || return 0
  while IFS=$'\t' read -r agent glob; do
    [[ -n "$agent" && -n "$glob" ]] || continue
    case " $out " in *" $agent "*) continue ;; esac
    while IFS= read -r f; do
      [[ -n "$f" ]] || continue
      if exloom_policy_match "$glob" "$f"; then out="${out:+$out }$agent"; break; fi
    done <<< "$files"
  done <<< "${_EXLOOM_POL_REVIEWERS}"
  printf '%s' "$out"
}
