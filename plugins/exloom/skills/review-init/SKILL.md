---
name: review-init
description: Used by /exloom at its init step; do not start it directly. Bootstraps .claude/reviews/<branch>.md from the checklist template, records the lane, and commits the skeleton so it's visible in the PR.
---

# /review-init

Refuse on `main`, `master`, `dev` or `develop`, and if `.claude/reviews/<branch>.md` already exists: continue in it, or delete it explicitly to start over.

## 1. Load the library and check the files can be committed

```bash
XL_ROOT='${CLAUDE_PLUGIN_ROOT}';XL_FILE="$XL_ROOT/hooks/lib.sh";[[ $XL_ROOT =~ ^(/|[A-Za-z]:/) && -f $XL_FILE ]]||{ echo "exloom: $XL_FILE missing; reinstall exloom or update Claude Code">&2;exit 1;};. "$XL_FILE"
exloom_ignored_settings "$(git rev-parse --abbrev-ref HEAD)"
```

Each path printed is git-ignored, so the gate could never pass. If any, stop and show the list with the minimum fix:

```
.claude/*
!.claude/reviews/
!.claude/exloom-*
```

## 2. The tier

```bash
XL_ROOT='${CLAUDE_PLUGIN_ROOT}';XL_FILE="$XL_ROOT/hooks/lib.sh";[[ $XL_ROOT =~ ^(/|[A-Za-z]:/) && -f $XL_FILE ]]||{ echo "exloom: $XL_FILE missing; reinstall exloom or update Claude Code">&2;exit 1;};. "$XL_FILE"
exloom_fork_point HEAD
exloom_derive_tier HEAD; exloom_tier_reasons
```

Show the tier, its reasons and `git diff --stat <fork-point>...HEAD`. Nothing is recorded: the push gate derives it again, so it cannot be lowered. No diff yet (return 2): the tier is pending. No base found (return 1): step 3 must set `**Base branch:**`.

## 3. Confirm the base branch

exloom guesses the base from a fixed list of names, often wrongly. Show the distance to the nearest remote branches:

```bash
for r in $(git for-each-ref --format='%(refname:short)' refs/remotes/origin); do
  mb=$(git merge-base HEAD "$r" 2>/dev/null) || continue
  echo "$(git rev-list --count "$mb..HEAD") $r"
done | sort -n | head -6
```

Offer the nearest few with their counts, mark the one currently used, and allow a typed answer. Do not pick the nearest yourself: a colleague's branch forked from this one is nearer. This field can lower a tier, so if the choice shrinks the change a lot, ask once whether the work really forked there.

## 4. The lane

Ask once. Default to the committed `.claude/exloom-lane`, else `standard`.

| Lane | For | Before the code | After it |
|---|---|---|---|
| `sprint` | a spike, a demo, a fix you already understand | nothing | L1, smoke, proof |
| `standard` | work meant to become a real system | spec, plan | what the tier requires |
| `certified` | regulated or externally audited work | spec, plan | the same, with no escape hatches and a signed commit |

Sprint is not available at Tier 3; do not offer it.

## 5. Create and commit the checklist

Generate it; never hand-fill a template:

```bash
XL_ROOT='${CLAUDE_PLUGIN_ROOT}';XL_FILE="$XL_ROOT/hooks/lib.sh";[[ $XL_ROOT =~ ^(/|[A-Za-z]:/) && -f $XL_FILE ]]||{ echo "exloom: $XL_FILE missing; reinstall exloom or update Claude Code">&2;exit 1;};. "$XL_FILE"
exloom_render_report "$(git rev-parse --abbrev-ref HEAD)"
```

In `.claude/reviews/<branch>.md` set `**Base branch:**` (the confirmed branch, or leave `auto`), `**Lane:**`, and `**Spec:**` and `**Plan:**` when the branch has them, else `none`. Stage only that file and commit `chore(review): initialize review report for <branch-name>`.

Tell the user the checklist is committed, its tier or that it is pending, and that `/exloom` runs what comes next.
