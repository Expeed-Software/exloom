---
name: isolating-execution
description: Use before executing a plan — puts the work in an isolated, gated workspace. At minimum a feature branch (so the review gate applies, since the hooks skip protected branches), or a dedicated worktree for heavier isolation. Run it first, before executing-handoff-plans.
---

# Isolating Execution

## Overview

Work done on a protected branch (`main`, `master`, `dev`, `develop`) ships unreviewed, because the review-gate hooks skip those branches. It also interleaves the plan's commits with the branch's other work, breaking the task-to-commit mapping `exloom:auditing-plan-fidelity` relies on.

Isolate before writing a line, so the work is **reviewable** (on a gated branch, once the repo enables the gate — see "Gated, or just isolated?") and **auditable** (its commits stand alone). Run this once, before `exloom:executing-handoff-plans`.

## The three levels

Detect first, then pick the lightest level that gives both guarantees.

### Level 0 — Detect existing isolation

```bash
git rev-parse --is-inside-work-tree        # a git repo at all?
git rev-parse --abbrev-ref HEAD            # current branch (or HEAD if detached)
git rev-parse --git-dir                    # per-checkout git dir
git rev-parse --git-common-dir             # shared git dir
```

- If `--git-dir` and `--git-common-dir` differ, you are in a linked worktree — but rule out a submodule first (`git rev-parse --show-superproject-working-tree` prints a path inside one). A real worktree on a feature branch is isolated: stop and build.
- On a feature branch (not protected): isolated enough. Stop.
- On a protected branch (`main`/`master`/`dev`/`develop`) or detached HEAD: go to Level 1.

This protected-branch list must match the review-gate hooks' skip list. Change both together.

### Level 1 — Feature branch (default)

```bash
git checkout -b feature/<topic>
```

Derive `<topic>` from the plan or spec, in kebab-case. If the branch exists, append a short suffix or ask.

**Never carry a dirty base into the new branch.** If the working tree has uncommitted changes unrelated to this work, stop and ask the operator to commit or stash them.

For a brand-new or empty project with no git, `git init` first, then branch, and note it. For an existing folder with code but no git, STOP and ask before initializing.

Level 1 suffices for single-session, single-implementer, one-plan work.

### Level 2 — Dedicated worktree (opt-in, heavier)

For long-running work, a risky change you may abandon, or work run alongside the current checkout. Ask before creating one; it makes directories on disk. Prefer the harness's native worktree mechanism; otherwise:

```bash
git worktree add ../<repo>-<topic> -b feature/<topic>
```

- **Then work from inside it.** Open the session at the worktree path. exloom's hooks resolve the repository from the session's directory, so a reviewer dispatched from outside the worktree writes its receipt elsewhere or nowhere, and the gate reports it as never dispatched. The hook warns on stderr; the fix is to be in the right directory.
- Put the worktree beside the repo, not inside it (a nested worktree must be gitignored or it pollutes status).
- Plan, spec, and review checklist are committed, so the worktree has them.
- `.exloom/` scratch is per-worktree and gitignored.
- When done, integrate through `exloom:review-gate`, then merge/PR, and remove the worktree: `git worktree remove <path>`.

Do not nest worktrees. If Level 0 found you in one, do not create another.

## Gated, or just isolated?

A feature branch is necessary for the gate but not sufficient. The hooks enforce only when `.claude/exloom-gate.enabled` exists and is committed.

After isolating, check and report:

```bash
test -f .claude/exloom-gate.enabled && echo "gated" || echo "isolated, NOT gated"
```

If the marker is absent, say so plainly. Then either enable enforcement (`mkdir -p .claude && touch
.claude/exloom-gate.enabled`, then commit it — see the README's gate section and
`exloom:review-gate`) or continue knowingly without it. Never call the branch "gated" when the marker isn't there.

## Decision table

| Situation | Level |
|---|---|
| Already on a feature branch, or in a worktree on one | 0 — already isolated, build |
| On `main`/`dev`/a protected branch, normal single-session work | 1 — feature branch |
| Detached HEAD | 1 — name a branch |
| Long-running / abandonable / run-alongside work | 2 — worktree (with consent) |
| Parallel implementers that may touch overlapping files | give each one its own worktree |
| Dirty base with unrelated changes | STOP — commit/stash first, then isolate |

Each parallel implementer's branch is gated separately before it integrates.

## Integration

- **Run this first**, before `exloom:executing-handoff-plans`.
- **Pairs with:** `exloom:review-gate` — the feature branch is what the gate protects.
- **At finish:** integrate the branch and (for Level 2) remove the worktree.
