#!/usr/bin/env bash
# exloom — shared hook library. SOURCED by verify-review.sh and
# block-unverified-push.sh; never executed directly. Keeping the checklist
# validation, branch classification, and JSON extraction in one place means the
# Stop hook and the push gate can never silently disagree about what "complete"
# means (they used to duplicate ~150 lines).
#
# All functions assume the caller has already cd'd to the repo root when they
# touch git. Every git failure fails OPEN (return/exit 0 at the call site) —
# exloom blocks on missing evidence, never on an infrastructure hiccup.

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
    out="$(printf '%s' "$json" | sed -n "s/.*\"$field\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -1)"
  fi
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
  placeholder_re='<(paste output / screenshot link|exact command|exact steps|expected-result|Claude-session-or-human-reviewer|path to committed runbook\.md|test id or path[^>]*|paste|list[^>]*|file:line — problem[^>]*|category \+ file:line[^>]*|N files changed[^>]*|Critical / Important / Minor[^>]*|reviewed-sha|ai-assisted|model-id|directed-by|base-sha|attested-date)>'
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
    if [[ -n "$stale" ]]; then
      _exloom_block "$action" "The review is stale. These files changed after the reviewed commit ($reviewed_sha) and are not covered:
${stale}

Re-run /review-complete to review the current tip."
      return 2
    fi

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
