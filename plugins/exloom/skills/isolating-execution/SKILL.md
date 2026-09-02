---
name: isolating-execution
description: Use before executing a plan — puts the work in an isolated, gated workspace. At minimum a feature branch (so the review gate applies, since the hooks skip protected branches), or a dedicated worktree for heavier isolation. Run it first, before executing-handoff-plans or orchestrating-execution.
---

# Isolating Execution

## Overview

Execution has to happen somewhere. If it happens on the branch you were already
standing on — often `main`, `dev`, or a shared branch — two things go wrong.
First, the review gate does not fire: the hooks deliberately skip protected
branches (`main`, `master`, `dev`, `develop`), so work committed there ships
with no enforced review. Second, the plan's commits interleave with whatever
else that branch was carrying, and the 1:1 mapping between plan tasks and
commits that `exloom:auditing-plan-fidelity` depends on is polluted from the
first commit.

Isolating execution fixes both before a single line is written. It puts the work
in its own workspace so the gate *can* apply to it (once the repo's gate marker
is enabled — see "Gated, or just isolated?" below) and the base branch is never
touched by half-finished work. This is the setup step for
`exloom:executing-handoff-plans` — run it
first, once, and the rest of the loop inherits a clean, gated place to build.

Isolation here is not about a tidy branch for its own sake. It makes two
guarantees mechanical: the work is **reviewable** (it is on a gated branch) and
**auditable** (its commits stand alone).

## The three levels

Scale the isolation to the work. Detect first, then pick the lightest level that
makes both guarantees hold.

### Level 0 — Detect existing isolation

Before creating anything, check where you already are:

```bash
git rev-parse --is-inside-work-tree        # a git repo at all?
git rev-parse --abbrev-ref HEAD            # current branch (or HEAD if detached)
git rev-parse --git-dir                    # per-checkout git dir
git rev-parse --git-common-dir             # shared git dir
```

- If `--git-dir` and `--git-common-dir` differ, you are already in a linked
  worktree — but rule out a submodule first (`git rev-parse
  --show-superproject-working-tree` prints a path when you are inside one). A
  real worktree on a feature branch is already isolated: stop here and build.
- If you are on a feature branch (not a protected one), you are isolated enough
  for the gate. Stop here.
- If you are on a protected branch (`main`/`master`/`dev`/`develop`) or a
  detached HEAD, go to Level 1.

This protected-branch list must stay identical to the review-gate hooks' skip
list. If the hooks change which branches they skip, change this list too — they
are a pair.

### Level 1 — Feature branch (default)

The lightest isolation that makes the gate apply. Create a branch named for the
work and switch to it in place:

```bash
git checkout -b feature/<topic>
```

Derive `<topic>` from the plan or spec, in kebab-case. Confirm the branch does
not already exist; if it does, append a short suffix or ask.

**Never carry a dirty base into the new branch.** If the working tree has
uncommitted changes that are not part of this work, stop and ask the operator to
commit or stash them first. A branch created on top of unrelated pending changes
mixes them into the plan's commits — exactly the audit pollution isolation
exists to prevent.

For a brand-new or empty project with no git, `git init` first, then branch, and
note it. For an existing folder that has code but no git, STOP and ask before
initializing — the same rule `exloom:executing-handoff-plans` uses.

Level 1 is enough for most work: single session, single implementer, one plan.
The base branch is untouched because you are on a new branch; the gate applies
because that branch is not protected.

### Level 2 — Dedicated worktree (opt-in, heavier)

When you want the base checkout completely untouched — long-running work, a risky
change you may abandon, or work you want to run alongside the current checkout —
put it in its own worktree.

Ask before creating one; it makes directories on disk. Prefer the harness's
native worktree mechanism if it has one; otherwise:

```bash
git worktree add ../<repo>-<topic> -b feature/<topic>
```

- **Then work from inside it.** Open your session at the worktree path — do not
  create it and keep working from the base checkout. exloom's hooks resolve the
  repository from the session's own directory, so a reviewer dispatched from
  beside the worktree writes its receipt somewhere else, or nowhere; the gate
  then reports that reviewer as never dispatched and re-running cannot clear it.
  The hook says so on stderr rather than failing silently, but the fix is to be
  in the right directory, not to interpret the warning.
- Put the worktree beside the repo, not inside it (a worktree nested in the repo
  must be gitignored or it pollutes status).
- The plan, spec, and review checklist travel with the branch because they are
  committed — the worktree has them.
- `.exloom/` scratch is per-worktree and gitignored; nothing to move.
- When the work is done, integrate the branch through the normal finish flow
  (`exloom:review-gate`, then merge/PR) and remove the worktree:
  `git worktree remove <path>`.

Do not nest worktrees. If Level 0 found you already in one, do not create
another.

## Gated, or just isolated?

Isolating onto a feature branch is **necessary** for the gate but not
**sufficient**. The review-gate hooks enforce only when the repo has opted in —
they do nothing unless `.claude/exloom-gate.enabled` exists and is committed. So
a fresh feature branch in a repo that never enabled the gate is isolated but
**not** gated: nothing will block a premature "done" or `git push`.

After isolating, check the marker and report honestly:

```bash
test -f .claude/exloom-gate.enabled && echo "gated" || echo "isolated, NOT gated"
```

If the marker is absent, say so plainly — do not imply the gate is protecting the
work. Then either enable enforcement (`mkdir -p .claude && touch
.claude/exloom-gate.enabled`, then commit it — see the README's gate section and
`exloom:review-gate`) or continue knowingly without enforcement. What you must
not do is call the branch "gated" when the marker isn't there.

## Decision table

| Situation | Level |
|---|---|
| Already on a feature branch, or in a worktree on one | 0 — already isolated, build |
| On `main`/`dev`/a protected branch, normal single-session work | 1 — feature branch |
| Detached HEAD | 1 — name a branch |
| Long-running / abandonable / run-alongside work | 2 — worktree (with consent) |
| Parallel implementers that may touch overlapping files | give each one its own worktree |
| Dirty base with unrelated changes | STOP — commit/stash first, then isolate |

## Why this is exloom's, not generic worktree advice

Generic isolation protects your current branch. exloom's isolation exists to make
the **enforced gate** apply: Level 1 is chosen specifically because the review-gate
hooks skip protected branches, so putting the work on a feature branch is what
turns the gate on. And at the high end, isolation is not one sandbox but a
**fan-out** — parallel implementers each get their
own worktree and gates each one's branch before integrating. Isolation here is
always in service of review, never tidiness alone.

## Integration

- **Before:** `exloom:executing-handoff-plans` — run this first.
- **Pairs with:** `exloom:review-gate` — the feature branch is what the gate
  protects.
- **At finish:** integrate the branch and (for Level 2) remove the worktree.
