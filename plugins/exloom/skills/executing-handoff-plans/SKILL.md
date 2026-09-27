---
name: executing-handoff-plans
description: Use when you have a written plan to execute — runs tasks in order, flags any deviation inline, and refuses to improvise.
---

# Executing Handoff Plans

## Overview

The defining rule: **flag deviations, don't improvise.** When reality diverges from the plan, log the deviation precisely and pause for the author. The rules are identical whether you wrote the plan or picked it up from someone else.

## Process

### Before Starting

Do not begin until all four preconditions hold.

**1. Read the plan in full.** First task to last, including acceptance criteria, edge cases and appendices. A later task or edge case may constrain how you approach an early one.

**2. Confirm the plan is unambiguous.** Every task needs a concrete action and a concrete validation step. "TBD", vague file paths, "appropriate" or "as needed" without specifics, or references to undecided decisions mean the plan is not ready. Return it to the author with the specific ambiguities listed. Do not interpret charitably.

**3. Verify environment readiness.** Before touching code: required tools at expected versions, dependencies resolved, database accessible and migrated, test suite passing with zero changes. If tests already fail, record that now.

Confirm the working tree is a git repository. If `git rev-parse --is-inside-work-tree` fails: for a brand-new or empty project, run `git init`, note it in the deviation log, and continue; for an existing folder that already has code but no git, STOP and ask before initializing. Never execute without per-task commits.

Then isolate the workspace before the first commit: run `exloom:isolating-execution`. It moves the work onto a feature branch where the review gate can fire (the hooks skip `main`/`dev`) and checks whether the repo has enabled the gate (`.claude/exloom-gate.enabled`), telling you if you are isolated but not gated. Skip it only if Level 0 there finds you are already on a feature branch or in a worktree.

**4. Refuse to start on an ambiguous plan.** The author closes the gaps, not the executor. "Reasonable assumptions, noted" is still improvisation.

When you are both author and executor (solo path), "send it back to the author" means stop executing and switch into author mode: resolve the ambiguity as a planning decision, update the plan, then resume. Do not decide it mid-execution.

### During Execution — Per Task

For each task, follow this cycle exactly. Do not skip or reorder steps.

**1. Read the task AND its validation step before writing any code.** The validation defines the scope — status code, response shape, database side effect, log entry. If the validation step is missing or vague, log a deviation before proceeding.

**2. Read sibling files in the same module.** Match naming, error handling, logging, import ordering and code organization, whether or not the plan says so.

**3. Implement the task as specified.** Not more, not less, not differently. An improvement not in the plan (e.g. an in-memory fallback for a planned Redis cache) is noted as an out-of-scope observation, not built.

**4. Run the validation step.** Exactly the validation the plan specifies — not a substitute. If it passes, proceed. If it fails, STOP: a failing validation is a deviation. Do not debug speculatively or fix it silently; log what failed and why, find the root cause rather than applying a local patch, and decide with the author whether to proceed. If a task implements real business logic (calculations, validation, branching, state changes) but its only validation is a manual check, a curl, or a build — with no automated test — that is itself a deviation: log it and add a test.

**5. If reality diverges from plan, log deviation and pause.** Any difference — file location, function signature, dependency version, contradicting pattern — is a deviation. Log every one, regardless of size, using the format below. The only question is whether to self-resolve or pause.

- **Self-resolve** (log with status "Resolved" immediately): the answer is mechanically obvious with exactly one option. Example: plan says `rate-limiter.js`, the project is all TypeScript → use `rate-limiter.ts`.
- **Pause for author**: a choice between two or more valid options, a change to the plan's intent, or touching files not in the plan. Example: plan says HTTP 429, existing error envelope uses 503. The executor does not make design decisions.

The test: "Would two reasonable developers make the same choice?" If yes, self-resolve. If they might disagree, pause.

**Solo path:** pausing becomes a deliberate context switch. Stop executing, re-read the spec, and decide as the author on the merits — not on which choice needs the least rework from where you are. Log the decision with the same rigor. If it changes scope or design, revisit the plan.

**6. Mark checkbox and commit.** Check off the task in the plan and commit with a message referencing the plan and task number, one commit per task. Example: `plan:payments-rate-limit task-3: add Redis configuration for rate limiter`. `exloom:auditing-plan-fidelity` relies on this mapping.

**7. Review the task.**

Dispatch `exloom:l1-reviewer`, unnamed, with exactly:

```
Review task <n> of <plan path>. Diff: git diff <commit before the task>..<task commit>
Task text:
<the task's text, verbatim>
```

It returns a spec verdict (`MATCHES`, `MISSING`, `EXTRA`, `MISUNDERSTOOD`) and quality findings. EXTRA means remove the code the task does not ask for, or log it as a deviation for the author. Blocking findings go to `exloom:fixer` with the findings verbatim (prompt in `/review-complete`); you do not fix them yourself. Then re-dispatch in verify mode with `Verify fixes for task <n> on branch <branch>. Fix range: <last-reviewed-sha>..<sha>` followed by its previous findings. After `.claude/exloom-max-rounds` fix rounds (default 3) exloom refuses the next dispatch; rule on what is left instead (see `/review-complete`). The receipt goes to `l1-reviewer.tasks.json` and does not count as a branch round. The whole-branch review runs once, in `/review-complete`.

### After Execution

Run `exloom:auditing-plan-fidelity`. It compares the plan's file list against the diff, checks the spec's criteria against the tasks in both directions, and reads the Deviation Log for open entries. Do not also check these by hand.

Bring the one thing it cannot compute: **a paused deviation is not a resolved one.** If you logged something and moved on without settling it, say so now.

Then run `/review-complete`. Execution completing is not the same as the work being correct.

## Deviation Log Format

The Deviation Log lives in the plan document itself, not a separate file. If the plan has none, create the section before starting. Append entries using this format:

```
### Deviation [N] — [Date] [Time]
**Step:** Task [number] — [task title]
**Expected:** [What the plan said]
**Found:** [What was actually found]
**Action taken:** [What was done before pausing]
**Resolution needed:** [Specific question for the author]
**Status:** [Paused | Resolved — brief summary]
```

Every field is required. "It was different so I fixed it" is not an acceptable Action taken. Resolution needed must be a specific, answerable question: not "What should I do?" but "Should the rate limiter use HTTP 429 (standard) or HTTP 503 (existing pattern in error-envelope.ts)?"

Self-resolved deviations are logged with status "Resolved" and the reasoning. If the justification needs more than one sentence, it is not a self-resolve — pause and ask. An empty log after non-trivial execution should be questioned. Log related deviations individually and cross-reference them ("See also Deviation 1 — same root cause").

## Decision Points

When in doubt, stop and log.

| Situation | Decision |
|---|---|
| Plan step is ambiguous | Stop. Log as deviation. Don't interpret. |
| Plan step seems wrong | Stop. Log deviation. Author decides, not executor. |
| You see a better way | Note as "out of scope observation." Execute as written. |
| Test fails unexpectedly | Stop. Find the root cause and log it as a deviation — never work around it. |
| Finished early / plan was easier than expected | Suspicious. Re-read plan — did you miss something? Check acceptance criteria. |
| External dependency is unavailable | Log deviation. Don't substitute without author guidance. |
| You need to change a file not in the plan | Log deviation. Unplanned file changes are the #1 source of audit failures. |
| Plan references a file that does not exist | Log deviation. Do not create the file at the referenced path without author confirmation. |
| Two plan tasks contradict each other | Stop. Log both tasks and the contradiction. The executor cannot resolve it. |

## Failure Modes

See [failure-modes.md](failure-modes.md).

## Worked Example

See [worked-example.md](worked-example.md).

## Integration

- **You arrive here from:** `exloom:planning-for-handoff` — whether you wrote the plan or it was handed to you.
- **You leave here toward:** `exloom:auditing-plan-fidelity`, then `/review-complete`. Never skip this.
- **If you hit a bug during execution:** log it as a deviation and pause until debugging produces a root cause; fix only then.
- **If a task needs design work the plan did not anticipate:** `exloom:brainstorming`. Log it as a deviation; the plan may need updating before execution continues.
- **For implementation tasks that include test work:** write the failing test first, inside the same task.
