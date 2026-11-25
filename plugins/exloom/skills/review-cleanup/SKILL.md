---
name: review-cleanup
description: Find and archive orphaned review checklists in .claude/reviews/ whose branches no longer exist (merged or deleted). Nothing is removed without confirmation; git history keeps every checklist regardless.
---

# /review-cleanup

Archive checklists in `.claude/reviews/` whose branches are gone. Never touch a live branch's checklist, and never act without the user's choice. Outside a git repo, or with no `.claude/reviews/`, say so and stop.

## 1. Find the orphans

```bash
find .claude/reviews -type f -name '*.md' ! -name '*.ledger.md' 2>/dev/null | grep -v '/archive/'
```

The branch is the path without the `.claude/reviews/` prefix and `.md` suffix. A branch `<b>` is live if either of these resolves, and the current branch is always live:

```bash
git show-ref --verify --quiet "refs/heads/<b>"
git show-ref --verify --quiet "refs/remotes/origin/<b>"
```

If a check fails for any reason other than a clean "not found", treat the branch as live.

## 2. Report and ask

List the live checklists (kept) and the orphans, saying for each orphan whether it looks merged into the default branch. No orphans: say so and stop. Otherwise offer:

1. **Archive** (recommended) — move each orphan and its evidence under `.claude/reviews/archive/`, keeping its relative path. All of them or none:

   ```bash
   mkdir -p "$(dirname ".claude/reviews/archive/<b>.md")"
   git mv ".claude/reviews/<b>.md" ".claude/reviews/archive/<b>.md"
   [ -d ".claude/reviews/<b>.verdicts" ] && git mv ".claude/reviews/<b>.verdicts" ".claude/reviews/archive/<b>.verdicts"
   [ -f ".claude/reviews/<b>.bypass.json" ] && git mv ".claude/reviews/<b>.bypass.json" ".claude/reviews/archive/<b>.bypass.json"
   [ -f ".claude/reviews/<b>.ledger.md" ] && git mv ".claude/reviews/<b>.ledger.md" ".claude/reviews/archive/<b>.ledger.md"
   ```

2. **Delete** — `git rm` the checklist and the same companions. They stay in git history.
3. **Cancel**.

## 3. Commit

Stage only the moved or removed files and commit `chore(review): archive N orphaned review checklist(s)`. Print one line saying what moved and that git history keeps all of it.
