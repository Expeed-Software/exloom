---
name: review-init
description: Bootstrap .claude/reviews/<branch>.md from the checklist template. Propose a tier from git diff stats and user description. Commit the skeleton so it's visible in the PR.
---

# /review-init

Run the steps in order; skip none.

## Step 1 — Gather context

Run:
- `git rev-parse --abbrev-ref HEAD` — refuse if it is `main`, `master`, `dev`, or `develop`.
- The fork point — the nearest merge-base to HEAD:

  ```bash
  LIB="$(find ~/.claude/plugins -path '*exloom*/hooks/lib.sh' | sort -V | tail -1)"
  . "$LIB"; exloom_fork_point HEAD
  ```

  The push gate runs the same function. Do not reimplement it. Step 2a confirms the answer.
- `git diff --stat <fork-point>...HEAD` and `git diff --name-only <fork-point>...HEAD`.

If `.claude/exloom.local.md` exists, read its frontmatter (boot command and adversarial grep root overrides).

## Step 1a — Check that the review files can be committed

```bash
exloom_ignored_settings "$(git rev-parse --abbrev-ref HEAD)"
```

Every path it prints is git-ignored, so exloom ignores it and the gate can never pass. If anything is listed, stop and show the user the list and the minimum fix (it keeps `settings.local.json` ignored):

```
.claude/*
!.claude/reviews/
!.claude/exloom-*
```

## Step 2 — Propose a tier

Apply these rules mechanically, then ask the user to confirm:

- If the ONLY changed files are `*.md`, `README*`, or live under the top-level `docs/` directory → Tier 0. A `.txt` file (such as `requirements.txt`) and a nested `docs/` folder inside source do not count.
- If any file under a `migrations/`, `liquibase/`, `db/changelog/` path → Tier 3.
- Else if any file touches auth, tenancy, secrets, crypto (search paths for `auth`, `tenant`, `secret`, `crypto`, `jwt`, `apikey`) → Tier 3.
- Else if any file under a `deployment/`, `k8s/`, `docker/`, `helm/` path AND flag/prod-related → Tier 3.
- Else if any frontend file changed AND any backend file changed → Tier 2.
- Else if any controller / route / API definition file changed → Tier 2.
- Else if the diff touches more than one module / service / package → Tier 2.
- Else if the diff touches ≥5 files → Tier 2.
- Else → Tier 1.

Show the tier, the triggering rule, and the `git diff --stat`. Ask the user to confirm or override; record the tier and a one-sentence rationale.

**The override is upward only.** The push gate derives the same minimum and blocks anything lower. If the user asks to go lower, say the push will fail; raise the tier or fix the derivation rule.

Apply yourself what the hook cannot judge: deployment paths floor at Tier 2 there (raise to 3 when flag- or prod-related), and the frontend+backend and multi-module rules.

A committed `.exloom.yml` may add path globs that raise the tier. Take the tier from the derivation, which merges both:

```bash
# ${CLAUDE_PLUGIN_ROOT} is set for plugin.json hooks, NOT in your shell.
# Resolve the installed plugin instead; several versions live in the cache,
# so take the highest.
LIB="$(find ~/.claude/plugins -path '*exloom*/hooks/lib.sh' | sort -V | tail -1)"
. "$LIB"
exloom_derive_tier HEAD; exloom_tier_reasons
```

If it disagrees with the rules above, it is right. Return 1 with no output: no base branch found, so Step 2a must set `**Base branch:**`. Return 2: no diff yet.

## Step 2a - Confirm the base branch

The base decides what counts as changed. exloom guesses from a fixed name list, so repos with other integration branch names are guessed wrong. Compute the distance to every remote branch:

```bash
for r in $(git for-each-ref --format='%(refname:short)' refs/remotes/origin); do
  mb=$(git merge-base HEAD "$r" 2>/dev/null) || continue
  echo "$(git rev-list --count "$mb..HEAD") $r"
done | sort -n | head -6
```

Offer the nearest few plus likely integration branches, with counts, and allow a typed answer:

```
  origin/dev-deploy     3 commits back
  origin/main          57 commits back   <- currently used
```

**Do not auto-pick the nearest.** A colleague's branch forked from this one is nearer and would shrink the diff. The user decides.

Write the answer into `**Base branch:**`; the gate reads it at push time. Tell the user this field can lower a tier; if their choice makes the change much smaller, ask once whether the work really forked there. Leave `auto` if the guess was right.

## Step 2b — Propose a lane

The **lane** is the user's call: how much happens *before* the code.

| Lane | For | Before the code | After it |
|---|---|---|---|
| `sprint` | a spike, a demo, a bug fix you already understand | nothing — branch and go | L1, smoke, proof |
| `standard` | work meant to become a real system | spec, plan, fidelity audit | whatever the tier requires |
| `certified` | regulated, or someone outside the team must be able to audit it | same as standard | tier's requirements, **no workflow-step escape hatches**, signed provenance |

On Certified, a skipped step under `## Escape hatches used` blocks the push. `EXLOOM_REVIEW_SKIP=1` overrides the hooks on any lane and leaves a bypass receipt.

Ask once. Default to the committed `.claude/exloom-lane`, else `standard`. Recommend `sprint` for a small, self-contained fix or spike; otherwise `standard`.

**Sprint is not available at Tier 3.** Do not offer it; the gate refuses the combination.

Write the answer into `**Lane:**`.

## Step 3 — Create the checklist

Generate it; do not copy or fill a template by hand:

```bash
LIB="$(find ~/.claude/plugins -path '*exloom*/hooks/lib.sh' | sort -V | tail -1)"
. "$LIB"
exloom_render_report "$(git rev-parse --abbrev-ref HEAD)"
```

This writes `.claude/reviews/<branch-name>.md`: editable fields (`**Base branch:**`, `**Lane:**`, `## Rulings`) and an evidence block exloom rebuilds from receipts. Then set:

- `**Base branch:**` → the branch confirmed in Step 2a, or leave `auto`.
- `**Lane:**` → the answer from Step 2b.

## Step 4 — Commit the skeleton

Stage `.claude/reviews/<branch>.md` and commit with message:

```
chore(review): initialize review report for <branch-name>
```

Commit nothing else.

## Step 5 — Tell the user what comes next

Print:

> Review checklist initialized at `.claude/reviews/<branch>.md` (Tier <N>) — committed as `chore(review): initialize Tier <N> review checklist`.
> Required remaining steps for Tier <N>:
> - <list based on tier>
> Next commands: `/smoke-test` to fill the smoke-test section, then `/review-complete` when ready to ship.
> Tier <N> requires a real dispatch of: <reviewers for the tier>. exloom records a receipt under `.claude/reviews/<branch>.verdicts/` when each one completes; the gate requires those receipts and does not read any checkbox for them. Dispatch each reviewer **without a name** - a named subagent's report never reaches the hook, so its receipt records only the launch.

## Refusals

- Refuse on protected branches.
- Refuse if `.claude/reviews/<branch>.md` exists — continue in it, or delete it explicitly to start over.
