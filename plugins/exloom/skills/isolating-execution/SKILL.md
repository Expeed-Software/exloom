---
name: isolating-execution
description: Use before executing a plan — moves the work onto a feature branch so the review gate applies, or into a worktree for heavier isolation. Run it first, before executing-handoff-plans.
---

# Isolating Execution

Work committed on a protected branch (`main`, `master`, `dev`, `develop`) ships unreviewed, because the review-gate hooks skip those branches. Isolate before writing a line, and pick the lightest level that works.

## Level 0 — already isolated?

```bash
git rev-parse --abbrev-ref HEAD
git rev-parse --git-dir --git-common-dir
```

On a feature branch: stop, build. If the two git dirs differ you are in a linked worktree (unless `git rev-parse --show-superproject-working-tree` prints a path, which means a submodule): on a feature branch there, stop and build. On a protected branch or a detached HEAD: Level 1.

## Level 1 — a feature branch (the default)

```bash
git checkout -b feature/<topic>
```

Take `<topic>` from the plan or spec, in kebab-case. **Never carry a dirty base into the new branch**: if the working tree has unrelated uncommitted changes, stop and ask the user to commit or stash them. An empty project with no git: `git init`, then branch. A folder with code but no git: stop and ask first.

## Level 2 — a worktree (only with the user's yes)

For long-running work, a change you may abandon, or work alongside the current checkout. Ask before creating one. Prefer the harness's own worktree mechanism; otherwise:

```bash
git worktree add ../<repo>-<topic> -b feature/<topic>
```

Put it beside the repo, not inside it, and open the session from inside it: exloom's hooks resolve the repository from the session's directory, so a reviewer dispatched from elsewhere leaves no receipt there. Never nest worktrees. When done, integrate through the gate, then `git worktree remove <path>`. Parallel implementers who may touch the same files each get their own.

## Gated, or just isolated?

A feature branch is necessary for the gate, not sufficient. The hooks enforce where the branch's checklist is committed, or everywhere `.claude/exloom-gate.enabled` is. After isolating, run `/exloom`: it asks once whether to use exloom on this branch. Say plainly when a branch is not gated, and never create the repo-wide marker yourself.
