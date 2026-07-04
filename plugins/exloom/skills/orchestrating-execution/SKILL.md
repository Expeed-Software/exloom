---
name: orchestrating-execution
description: Use when executing a written plan task-by-task in the current session by dispatching a fresh subagent per task, with exloom's review run as a gate between tasks. For solo or team work where you want speed plus a review panel on every task.
---

# Orchestrating Execution

Execute a plan by dispatching a **fresh subagent per task**, gating each finished task through **exloom's review** (tier-scaled), looping fixes until clean, and running one **whole-branch review** at the end. You — the controller — never write the code; you coordinate, curate context, and hold the line on the gate.

This is the high-throughput execution mode. A solo developer gets a task-by-task review panel they wouldn't otherwise have; a team gets the same with the handoff discipline enforced. It pairs with `exloom:planning-for-handoff` (which produces the plan) and `exloom:review-gate` (which defines the tiers and the reviewers).

## When to use it

- You have a written plan with discrete tasks (`exloom:planning-for-handoff`).
- You want to stay in this session (no parallel-session handoff).
- Tasks are mostly independent or have a clear order.

If the plan doesn't exist yet, go to `planning-for-handoff` first. If a task needs design work the plan didn't anticipate, stop and go to `brainstorming` — don't improvise it inside an implementer.

## Why a fresh subagent per task

Each implementer is constructed with exactly what it needs — its task, the interfaces it touches, nothing else. It never inherits your session history. This keeps each implementer focused and keeps **your** context clean for coordination. The cost of a task lives in its own subagent, not in your context window.

## Workspace setup (once)

Before the first dispatch, isolate the run: invoke `exloom:isolating-execution` so the whole run lands on a feature branch where the review gate can enforce if the repo enabled it (the hooks skip `main`/`dev`, and only act when `.claude/exloom-gate.enabled` is present) — not on whatever branch you were on. That skill reports whether the branch is actually gated or merely isolated, and also governs the per-implementer worktrees for the isolated-parallel mode below.

Then make sure scratch never gets committed: add `.exloom/` **and** your stack's build artifacts (`__pycache__/`, `*.pyc`, `node_modules/`, `target/`, `dist/`, …) to `.gitignore`. The `.exloom/` directory is **per-run scratch** — briefs, reports, diff packages, and the resume ledger, all regenerable — and must never enter git. If it isn't ignored, an implementer's `git add -A` will sweep it (and build artifacts) straight into a task commit. Either gitignore it up front, or instruct implementers to stage only the files they changed.

## The loop

For each task, in order:

1. **Brief the task.** Run `scripts/task-brief.sh <plan-file> <N>` (from this skill's directory) — it extracts the task's full text to its own file and prints the path. Hand the implementer the *path*, not the pasted text.

2. **Dispatch a fresh implementer subagent** (choose the model per role — see below). **For Tier 2+ tasks, first run an independent test-author stage** (see *Build verification scales by tier*) so the implementer must pass tests it did not write. The implementer prompt contains: where the task fits (one line), the brief-file path ("read this first — it is your requirements"), the exact interfaces from earlier tasks it depends on, your resolution of any ambiguity you spotted, the path to any pre-authored failing tests it must satisfy, and a report-file path. It implements (TDD where the task says so), tests, commits, self-reviews, writes a full report to the report file, and returns a short status: `DONE` / `DONE_WITH_CONCERNS` / `BLOCKED` / `NEEDS_CONTEXT` + commit SHAs + a one-line test summary.

3. **Handle the status.** `BLOCKED`/`NEEDS_CONTEXT` → supply context or re-dispatch on a stronger model or split the task; never force the same model to retry unchanged. `DONE_WITH_CONCERNS` → read the concerns before proceeding.

4. **Gate the task through exloom's review** (this is the differentiator — see next section). Build the diff package with `scripts/review-package.sh <base> <head>` (prints a file path), and dispatch the tier-appropriate reviewers against it.

5. **Fix loop.** Any Blocking/Critical/Important finding → dispatch a fix subagent (same implementer contract, re-runs covering tests) → re-review until clean. Record Minor findings for the final pass.

6. **Record progress.** Append one line to the resume ledger (below) **and** make sure the task's tier, smoke evidence, and findings are written to the *committed* review checklist (`.claude/reviews/<branch>.md`, from `exloom:review-gate`) — that file, not the scratch ledger, is the team-facing audit trail. Then move to the next task.

After all tasks: run one **whole-branch review** over `merge-base..HEAD`, then finish the branch.

## The gate — exloom's review, scaled by tier

This is what makes exloom's engine different from "run tasks and hope." Decide the task's tier (from `exloom:review-gate`'s blast-radius matrix) and run the matching reviewers as subagents against the diff package:

- **Every task:** `l1-reviewer` (correctness, null safety, resource leaks, test quality) **and** a real smoke check — boot or exercise the change and observe the result, evidence pasted into the report. Reading the diff is not the smoke check.
- **User-facing / cross-module / new API / new event / new config (Tier 2+):** add `cross-layer-auditor` (orphan fields/endpoints/events/columns/config) and `adversarial-reviewer` (hostile: assume the prior reviews missed something).
- **Migration / flag cutover / prod / auth/tenant/secrets (Tier 3):** add a runbook + a tested rollback before the task is done.

Construct each reviewer prompt cleanly: give it the brief, the report, the diff-package path, and the plan's global constraints verbatim. Never tell a reviewer what *not* to flag, and never pre-rate a finding's severity — adjudicate in the loop.

The gate's durable output is the **committed** review checklist `.claude/reviews/<branch>.md` (owned by `exloom:review-gate`): tier, smoke-test evidence, and each finding with its disposition. Record findings there as you adjudicate them — not only in the scratch ledger — so the audit trail ships with the PR.

## Build verification scales by tier

The blast-radius tier does not only scale the *review* — it scales how the code is *built and verified*, moving quality upstream into the build instead of relying on the review to catch it afterward. Same matrix as the gate:

- **Tier 0–1 (trivial / internal):** the implementer writes its own tests (standard TDD). Parity with a plain subagent-per-task engine — fine, because the blast radius is small.
- **Tier 2+ (user-facing / cross-module / new API / logic-heavy):** dispatch an **independent test-author subagent first**. It writes the acceptance tests *and* **property-based tests for the plan's stated invariants** (e.g. "total is never negative", "round-trips", "monotonic in quantity") — committed and failing — *before* the implementer runs. The implementer then has to make tests it did not write pass. This removes two failure modes: (1) the implementer grading its own homework — its tests assert what it built, not what was required; and (2) example tests missing edge cases, because a property test generates inputs nobody thought to write, so an invariant violation surfaces *at build time* rather than in review. (Dogfooded: a property `total >= 0 for all inputs` caught a negative-total bug from a single negative price — the exact bug a full suite of hand-written example tests had missed and only the whole-branch review had found.)
  - *No change-detector tests.* A property test must assert an **independent structural invariant** (e.g. "the result is non-increasing", "sum is conserved", "output reparses to the input") — never re-derive the implementation's own formula inside the test. A test that recomputes what the code computes passes by construction and catches nothing. (Dogfooded: a reviewer caught an order-property test that rebuilt the implementation's `divmod` split instead of asserting the structural fact "larger parts come first" — `result == sorted(result, reverse=True)`.)
- **Tier 3 (migration / flags / prod / auth / money):** additionally dispatch a **second independent implementer** and run **differential testing** — both implementations must agree on random inputs; any disagreement is a bug in one. Expensive, so reserved for the highest blast radius.

This is the engine's out-build lever, and it is honestly costed: the extra test-author pass, property tests, and (at Tier 3) a second implementer spend more tokens, so they are **tier-scaled** — parity on trivial work, increasingly ahead as blast radius rises. The invariants come from the plan's acceptance criteria, so the sharper the plan (`exloom:planning-for-handoff`), the stronger the property tests it yields.

## File handoffs (keep your context clean)

Everything pasted into a dispatch prompt, and everything a subagent prints back, stays resident in your context for the rest of the session. So move artifacts as **files**, not pasted text:

- **Task brief** → `scripts/task-brief.sh <plan> <N>` writes `…/task-N-brief.md`, prints the path.
- **Report** → name it after the brief (`…/task-N-report.md`); the implementer writes the detail there and returns only a short status.
- **Diff package** → `scripts/review-package.sh <base> <head>` writes the commit list + stat + full diff to one file; the reviewer reads that one file.

## Durable ledger (survive compaction)

Conversation memory does not survive compaction; a controller that loses its place can re-dispatch finished tasks. Track progress in a file, not only in your head.

- At start, check `.exloom/execution/progress.md`. Tasks marked complete there are done — resume at the first that isn't.
- When a task's review comes back clean, append: `Task N: complete (commits <base7>..<head7>, review clean)`.
- After any compaction, trust the ledger and `git log` over recollection.

The ledger is **your** scratch for this run — gitignored and regenerable from `git log` (each finished task is a commit). It is *not* how a teammate picks up the work. Cross-person handoff travels through git: the committed plan, the commits, and the review checklist (`.claude/reviews/<branch>.md`). A teammate resumes by reading those and re-running `scripts/task-brief.sh` for the next unfinished task — they never need your `.exloom/` files. Ignoring `.exloom/` therefore costs the team nothing: it forces coordination onto durable git artifacts instead of a regenerable scratch file (and avoids ledger merge-conflicts when people work in parallel).

## Model per role

Use the least powerful model that fits, and **always set the model explicitly** (an omitted model inherits your session's, usually the most expensive):

- Mechanical task with complete spec (1–2 files) → cheap model.
- Multi-file integration / judgment → standard model.
- Architecture, or the final whole-branch review → most capable model.
- Reviewers → scale to the diff's size and risk; a subtle concurrency change earns a capable reviewer, a one-line fix does not.

## Parallel dispatch (independent tasks)

When several tasks are genuinely independent (no shared files, no ordering), you can run their implementers concurrently to cut wall-clock. There are two ways, and the second is exloom's real parallel mode.

**Shared tree (simple, limited).** Dispatch the implementers concurrently in the current worktree — but only when they touch strictly disjoint files. Two implementers editing the same file in one tree corrupt each other. Review each result through the same gate as it returns. Use this only for obviously non-overlapping tasks.

**A worktree per implementer (isolated — the real parallel mode).** For higher parallelism — including tasks that might touch overlapping files — give each implementer its own worktree on its own `task/<feature-slug>/<N>` branch, cut from the feature branch (dispatch it with `isolation: worktree`). Each implementer builds and commits in isolation, so nothing it does can collide with a sibling. Create and tear these down with the helpers in this skill's `scripts/` dir — `create-task-worktree.sh <N> <feature-branch>` (guards a clean, non-protected base and prints the worktree path to hand the implementer; branches are named `task/<feature-slug>/<N>` so features don't collide), `list-task-worktrees.sh` (what is still live), and `cleanup-task-worktree.sh <N> <feature-branch>` (refuses to remove a task worktree whose branch isn't yet merged into the feature branch, unless you pass `--force`). If a worktree folder is deleted by hand, run `git worktree prune` to clear the stale registration. Then:

1. **Gate each task branch as it returns** — the same tier-scaled reviewers (l1 / cross-layer / adversarial + smoke) against that branch's diff; the reviewed-commit binding works per branch. Write each task's tier, evidence, and findings into the one authoritative feature-branch checklist (`.claude/reviews/<feature>.md`). The `task/<feature-slug>/<N>` branches are ephemeral, so the audit trail stays in one place instead of fragmenting across per-task checklists.
2. **Integrate passing branches** — merge each cleared `task/<feature-slug>/<N>` into the feature branch in a deliberate order. A conflict here is a *recoverable merge*, not the silent corruption two implementers in one tree would cause — resolve it (or dispatch a fix subagent to) and log it.
3. **Re-gate the integrated result** — after the merges, run the whole-branch review over the feature branch. A merge can break what each branch passed alone (one task changed an interface another task built against). This re-gate is not optional; it is the whole point of integrating under review.
4. **Hold failing branches out** — a `task/<feature-slug>/<N>` that cannot pass review is not merged. Report it, re-dispatch or split it, and integrate only once it is clean. Never merge a branch with open Blocking/Critical/Important findings to "fix later."

Cap the number of live worktrees to the same concurrency you would give any fan-out (a handful, not dozens), and record each task's branch, worktree path, and merge state in the ledger so a compaction cannot lose which branches are already integrated. If tasks share state or must run in order, do not parallelize them — run them sequentially through the normal loop.

## Red flags

- Letting an implementer read the whole plan instead of its brief → context bloat, lost focus.
- Skipping the gate because a task "looks small" → small tasks ship the silent integration bugs.
- Pasting prior-task summaries into later dispatches → your context balloons; hand files instead.
- Pre-judging findings for a reviewer ("treat as minor") → that's grading your own work.
- Re-dispatching a task the ledger already marks complete → wasted work after a compaction.
- Marking a task done with open Blocking/Critical/Important findings.
- Merging a `task/<feature-slug>/<N>` branch before it clears the gate ("integrate now, fix later") → integrate only clean branches, and re-gate the merged result.

## Integration

- **Isolate first:** `exloom:isolating-execution` — puts the run on a gated feature branch, and (for the isolated-parallel mode) a worktree per implementer.
- **Plan from:** `exloom:planning-for-handoff`.
- **Gate via:** `exloom:review-gate` (tiers + the l1 / cross-layer-auditor / adversarial reviewers + smoke test).
- **Alternative:** `exloom:executing-handoff-plans` for disciplined single-agent execution in this session (no subagents); use that for small or tightly-coupled plans where orchestration overhead isn't worth it.
- **After completion:** `exloom:auditing-plan-fidelity` confirms what shipped matches the plan, then finish the branch.
