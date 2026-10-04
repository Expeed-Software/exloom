---
name: review-init
description: Bootstrap .claude/reviews/<branch>.md from the checklist template. Propose a tier from git diff stats and user description. Commit the skeleton so it's visible in the PR.
---

# /review-init

## Step 1 — Gather context

Run:
- `git rev-parse --abbrev-ref HEAD` — refuse if it is `main`, `master`, `dev`, or `develop`.
- The fork point — the nearest merge-base to HEAD:

  ```bash
  LIB="$(find ~/.claude/plugins -path '*exloom*/hooks/lib.sh' | sort -V | tail -1)"
  . "$LIB"; exloom_fork_point HEAD
  ```

  The push gate uses this function; do not reimplement it. Step 2a confirms it.
- `git diff --stat <fork-point>...HEAD` and `git diff --name-only <fork-point>...HEAD`.

If `.claude/exloom.local.md` exists, read its frontmatter overrides.

## Step 1a — Check that the review files can be committed

```bash
exloom_ignored_settings "$(git rev-parse --abbrev-ref HEAD)"
```

Each printed path is git-ignored, so the gate can never pass. If any, stop and show the list and the minimum fix (keeps `settings.local.json` ignored):

```
.claude/*
!.claude/reviews/
!.claude/exloom-*
```

## Step 2 — Propose a tier

Apply mechanically, then confirm with the user:

- If the ONLY changed files are `*.md`, `README*`, or live under the top-level `docs/` directory → Tier 0. `.txt` files and nested `docs/` folders do not count.
- If any file under a `migrations/`, `liquibase/`, `db/changelog/` path → Tier 3.
- Else if any file touches auth, tenancy, secrets, crypto (search paths for `auth`, `tenant`, `secret`, `crypto`, `jwt`, `apikey`) → Tier 3.
- Else if any file under a `deployment/`, `k8s/`, `docker/`, `helm/` path AND flag/prod-related → Tier 3.
- Else if any frontend file changed AND any backend file changed → Tier 2.
- Else if any controller / route / API definition file changed → Tier 2.
- Else if the diff touches more than one module / service / package → Tier 2.
- Else if the diff touches ≥5 files → Tier 2.
- Else → Tier 1.

Show the tier, triggering rule and `git diff --stat`; ask to confirm or override; record tier and a one-sentence rationale.

**The override is upward only.** The push gate blocks anything below the derived minimum; if asked to go lower, say the push will fail.

You apply what the hook cannot judge: deployment paths (floor Tier 2, Tier 3 when flag- or prod-related), frontend+backend, multi-module.

A committed `.exloom.yml` may add tier-raising globs. Take the tier from the derivation, which merges both:

```bash
# ${CLAUDE_PLUGIN_ROOT} is set for plugin.json hooks, NOT in your shell.
# Resolve the installed plugin instead; several versions live in the cache,
# so take the highest.
LIB="$(find ~/.claude/plugins -path '*exloom*/hooks/lib.sh' | sort -V | tail -1)"
. "$LIB"
exloom_derive_tier HEAD; exloom_tier_reasons
```

If it disagrees with the rules above, it wins. Return 1, no output: no base found; Step 2a must set `**Base branch:**`. Return 2: no diff yet.

## Step 2a - Confirm the base branch

exloom guesses the base from a fixed name list, often wrongly. Compute the distance to every remote branch:

```bash
for r in $(git for-each-ref --format='%(refname:short)' refs/remotes/origin); do
  mb=$(git merge-base HEAD "$r" 2>/dev/null) || continue
  echo "$(git rev-list --count "$mb..HEAD") $r"
done | sort -n | head -6
```

Offer the nearest few plus likely integration branches, with counts; allow a typed answer:

```
  origin/dev-deploy     3 commits back
  origin/main          57 commits back   <- currently used
```

**Do not auto-pick the nearest** — a colleague's branch forked from this one is nearer. The user decides.

Write it into `**Base branch:**` (read at push time), or leave `auto` if the guess was right. This field can lower a tier; if the choice shrinks the change a lot, ask once whether the work really forked there.

## Step 2b — Propose a lane

The **lane** is the user's call.

| Lane | For | Before the code | After it |
|---|---|---|---|
| `sprint` | a spike, a demo, a bug fix you already understand | nothing — branch and go | L1, smoke, proof |
| `standard` | work meant to become a real system | spec, plan, fidelity audit | whatever the tier requires |
| `certified` | regulated, or someone outside the team must be able to audit it | same as standard | tier's requirements, **no workflow-step escape hatches**, signed provenance |

On Certified, a skipped step under `## Escape hatches used` blocks the push. `EXLOOM_REVIEW_SKIP=1` overrides the hooks on any lane and leaves a bypass receipt.

Ask once. Default to the committed `.claude/exloom-lane`, else `standard`; recommend `sprint` only for a small self-contained fix or spike.

**Sprint is not available at Tier 3**; do not offer it.

Write the answer into `**Lane:**`.

## Step 3 — Create the checklist

Generate it; never hand-fill a template:

```bash
LIB="$(find ~/.claude/plugins -path '*exloom*/hooks/lib.sh' | sort -V | tail -1)"
. "$LIB"
exloom_render_report "$(git rev-parse --abbrev-ref HEAD)"
```

This writes `.claude/reviews/<branch-name>.md`: editable fields (`**Base branch:**`, `**Lane:**`, `## Rulings`) plus an evidence block rebuilt from receipts. Set:

- `**Base branch:**` → the branch confirmed in Step 2a, or leave `auto`.
- `**Lane:**` → the answer from Step 2b.
- `**Spec:**` and `**Plan:**` → their paths when this branch has them (`F-nnn-*.md`, the plan file), else leave `none`.

## Step 4 — Commit the skeleton

Stage only `.claude/reviews/<branch>.md` and commit:

```
chore(review): initialize review report for <branch-name>
```

## Step 5 — Tell the user what comes next

Print:

> Review checklist initialized at `.claude/reviews/<branch>.md` (Tier <N>) — committed as `chore(review): initialize Tier <N> review checklist`.
> Required remaining steps for Tier <N>:
> - <list based on tier>
> Next commands: `/smoke-test` to fill the smoke-test section, then `/review-complete` when ready to ship.
> Tier <N> requires a real dispatch of: <reviewers for the tier>. Each completion records a receipt under `.claude/reviews/<branch>.verdicts/`; the gate reads receipts, not checkboxes. Dispatch each reviewer **without a name** - a named subagent's report never reaches the hook.

## Refusals

- Refuse on protected branches.
- Refuse if `.claude/reviews/<branch>.md` exists — continue in it, or delete it explicitly to start over.
