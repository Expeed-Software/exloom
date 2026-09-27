---
name: review-cleanup
description: Find and archive orphaned review checklists in .claude/reviews/ whose branches no longer exist (merged or deleted). Nothing is removed without confirmation; git history keeps every checklist regardless.
---

# /review-cleanup

Find checklists in `.claude/reviews/` whose branches no longer exist and archive them. Never touch a checklist for a live branch. Execute in order.

## Step 1 — Enumerate checklists

From the repo root:

```bash
find .claude/reviews -type f -name '*.md' ! -name '*.ledger.md' 2>/dev/null | grep -v '/archive/'
```

Derive each branch name by stripping the `.claude/reviews/` prefix and `.md` suffix (`.claude/reviews/feature/csv-export.md` → `feature/csv-export`).

## Step 2 — Classify each as live or orphan

A branch `<b>` is **live** if either resolves, otherwise **orphan**:

```bash
git show-ref --verify --quiet "refs/heads/<b>"        # local branch exists
git show-ref --verify --quiet "refs/remotes/origin/<b>"   # remote branch exists
```

The current branch (`git rev-parse --abbrev-ref HEAD`) is always live. If a ref check errors for an infra reason rather than a clean "not found", classify as **live**.

## Step 3 — Report

Show two lists:

- **Live** (keep): branch → checklist path.
- **Orphan** (branch gone): branch → checklist path, plus whether it appears merged into the default branch (`git branch --merged origin/main` / `origin/master` / `origin/dev` if resolvable).

If there are no orphans, say so and stop.

## Step 4 — Ask what to do (never act unprompted)

Offer three choices for the orphan set:

1. **Archive** (default, recommended) — move each orphan checklist under `.claude/reviews/archive/` preserving its relative path, **together with its evidence**:
   ```bash
   mkdir -p "$(dirname ".claude/reviews/archive/<b>.md")"
   git mv ".claude/reviews/<b>.md" ".claude/reviews/archive/<b>.md"
   # the receipts and any bypass record belong with the checklist they document
   [ -d ".claude/reviews/<b>.verdicts" ] && git mv ".claude/reviews/<b>.verdicts" ".claude/reviews/archive/<b>.verdicts"
   [ -f ".claude/reviews/<b>.bypass.json" ] && git mv ".claude/reviews/<b>.bypass.json" ".claude/reviews/archive/<b>.bypass.json"
   [ -f ".claude/reviews/<b>.ledger.md" ] && git mv ".claude/reviews/<b>.ledger.md" ".claude/reviews/archive/<b>.ledger.md"
   ```
   Move them all or none. The gate reads only `.claude/reviews/<current-branch>.md`, so archived files never affect enforcement.
2. **Delete** — `git rm` the checklist and the same companions. They remain in git history.
3. **Cancel** — do nothing.

Wait for an explicit choice.

## Step 5 — Commit

If the user chose archive or delete, stage only the moved/removed files and commit:

```
chore(review): archive N orphaned review checklist(s)
```

Touch no other file. Print a one-line summary of what moved or was removed, noting git history retains all of them.

## Refusals / safety

- Never archive or delete the current branch's checklist, or any checklist whose branch still exists locally or on `origin`.
- Never act without the Step 4 confirmation.
- If not inside a git repo, or `.claude/reviews/` does not exist, say so and stop.
