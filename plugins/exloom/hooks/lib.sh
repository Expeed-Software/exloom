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
  if printf '%s\n' "$files" | grep -Eqi '(^|/)(migrations?|liquibase|flyway|changesets?)(/|$)|db/changelog'; then
    printf '3'; return 0
  fi
  if printf '%s\n' "$files" | grep -Eqi 'auth|tenant|secret|crypto|jwt|apikey|api[-_]key'; then
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

# Reviewers required at a given tier. Security review is surface-triggered as
# well as tier-triggered, but the surface that triggers it (auth / tenancy /
# secrets / crypto) also derives to Tier 3 above, so the tier list covers it.
exloom_required_reviewers() {
  case "$1" in
    0|1) printf 'l1-reviewer' ;;
    2)   printf 'l1-reviewer cross-layer-auditor adversarial-reviewer' ;;
    3)   printf 'l1-reviewer cross-layer-auditor adversarial-reviewer security-auditor' ;;
  esac
}

# exloom_check_verdicts <checklist> <tier> <tip> <reviewed-sha> <action>
# Returns 0 when every reviewer the tier requires has a receipt covering the
# reviewed commit; prints a BLOCK message and returns 2 otherwise.
exloom_check_verdicts() {
  local checklist="$1" tier="$2" tip="$3" reviewed="$4" action="$5"
  local vdir agent file content sha ok
  local -a missing=() stale=()
  vdir="$(exloom_verdict_dir "$checklist")"

  for agent in $(exloom_required_reviewers "$tier"); do
    file="${vdir}/${agent}.json"
    # MSYS_NO_PATHCONV: Git Bash on Windows mangles the `ref:path` argument.
    content="$(MSYS_NO_PATHCONV=1 git show "${tip}:${file}" 2>/dev/null || true)"
    if [[ -z "$content" ]]; then missing+=( "$agent" ); continue; fi
    ok=0
    while IFS= read -r sha; do
      [[ -z "$sha" ]] && continue
      git rev-parse --verify "${sha}^{commit}" >/dev/null 2>&1 || continue
      # A receipt covers the reviewed commit when no code differs between the two
      # — a checklist-only commit landing in between must not invalidate a real
      # review, and a code commit must.
      if [[ -z "$(git diff --name-only "$sha" "$reviewed" -- . ':(exclude).claude/reviews' 2>/dev/null)" ]]; then
        ok=1; break
      fi
    done < <(printf '%s\n' "$content" | sed -n 's/.*"head"[[:space:]]*:[[:space:]]*"\([0-9a-f]\{7,40\}\)".*/\1/p')
    [[ $ok -eq 1 ]] || stale+=( "$agent" )
  done

  if [[ ${#missing[@]} -eq 0 && ${#stale[@]} -eq 0 ]]; then return 0; fi

  local detail="Tier ${tier} requires a verdict receipt from each of: $(exloom_required_reviewers "$tier")."
  [[ ${#missing[@]} -gt 0 ]] && detail="${detail}

Never dispatched (no receipt in ${vdir}/):
$(printf '  - %s\n' "${missing[@]}")"
  [[ ${#stale[@]} -gt 0 ]] && detail="${detail}

Dispatched, but only against code that has since changed (re-run them):
$(printf '  - %s\n' "${stale[@]}")"

  _exloom_block "$action" "${detail}

Receipts are written by exloom when a reviewer subagent actually completes — they
cannot be written by hand. Dispatch the reviewers, commit the receipts with the
checklist, and re-run /review-complete."
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
  placeholder_re='<(paste output / screenshot link|exact command|exact steps|expected-result|Claude-session-or-human-reviewer|who-attests|path to committed runbook\.md|test id or path[^>]*|paste|list[^>]*|file:line — problem[^>]*|category \+ file:line[^>]*|N files changed[^>]*|Critical / Important / Minor[^>]*|reviewed-sha|ai-assisted|model-id|directed-by|base-sha|attested-date)>'
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
