---
name: review-cleanup
description: Find and archive orphaned review checklists in .claude/reviews/ whose branches no longer exist (merged or deleted). Nothing is removed without confirmation; git history keeps every checklist regardless.
---

# /review-cleanup

Over time `.claude/reviews/` accumulates one checklist per branch and never shrinks on its own — merged branches leave dead checklists, and branch renames orphan files. This command finds the orphans and archives them so the directory stays legible. It never touches a checklist for a live branch, and because every checklist is already in git history, archiving or deleting one loses nothing recoverable.

Execute in order.

## Step 1 — Enumerate checklists

From the repo root:

```bash
find .claude/reviews -type f -name '*.md' 2>/dev/null | grep -v '/archive/'
```

For each path, derive its branch name by stripping the `.claude/reviews/` prefix and the `.md` suffix (e.g. `.claude/reviews/feature/csv-export.md` → `feature/csv-export`). Nested paths map to slashed branch names.

## Step 2 — Classify each as live or orphan

For each derived branch name `<b>`, it is **live** if any of these resolve, otherwise **orphan**:

```bash
git show-ref --verify --quiet "refs/heads/<b>"        # local branch exists
git show-ref --verify --quiet "refs/remotes/origin/<b>"   # remote branch exists
```

Also treat the **current** branch (`git rev-parse --abbrev-ref HEAD`) as live regardless. When in doubt (the ref check errors for an infra reason rather than a clean "not found"), classify as **live** — never archive on uncertainty.

## Step 3 — Report

Show two lists:

- **Live** (keep): branch → checklist path.
- **Orphan** (branch gone): branch → checklist path, plus whether the branch appears merged into the default branch (`git branch --merged origin/main` / `origin/master` / `origin/dev` if resolvable) so the user can tell "merged and done" from "abandoned".

If there are no orphans, say so and stop.

## Step 4 — Ask what to do (never act unprompted)

Offer the user three choices for the orphan set:

1. **Archive** (default, recommended) — move each orphan checklist under `.claude/reviews/archive/` preserving its relative path:
   ```bash
   mkdir -p "$(dirname ".claude/reviews/archive/<b>.md")"
   git mv ".claude/reviews/<b>.md" ".claude/reviews/archive/<b>.md"
   ```
   Archiving keeps the evidence in-tree and in history while clearing the active directory. The gate only ever reads `.claude/reviews/<current-branch>.md`, so archived files never affect enforcement.
2. **Delete** — `git rm ".claude/reviews/<b>.md"`. The checklist remains in git history; only the working tree loses it.
3. **Cancel** — do nothing.

Wait for an explicit choice. Do not default to acting.

## Step 5 — Commit

If the user chose archive or delete, stage only the moved/removed checklists and commit:

```
chore(review): archive N orphaned review checklist(s)
```

Do not touch any other file in this commit. Print a one-line summary of what moved or was removed, and note that git history retains all of them.

## Refusals / safety

- Never archive or delete the current branch's checklist, or any checklist whose branch still exists locally or on `origin`.
- Never act without the Step 4 confirmation.
- If not inside a git repo, or `.claude/reviews/` does not exist, say so and stop.
