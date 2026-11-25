---
name: executing-handoff-plans
description: Use when you have a written plan to execute — runs tasks in order, flags any deviation inline, and refuses to improvise.
---

# Executing Handoff Plans

**Flag deviations, don't improvise.** When reality diverges from the plan, log it and pause for the author. The rules are the same whether or not you wrote the plan.

## Before starting

1. **Read the whole plan**, including edge cases: a later task may constrain an early one.
2. **Refuse an ambiguous plan.** "TBD", a vague path, "as needed", or a task with no concrete validation goes back to the author with the gaps listed. "Reasonable assumptions, noted" is still improvisation. If you are also the author, stop executing, settle it as a planning decision, update the plan, then resume.
3. **Check the environment.** Tools, dependencies and database ready, and the test suite passing before you change anything. If tests already fail, record that now.
4. **Check git.** No repository in an empty project: `git init` and log it. No repository in a folder that already has code: stop and ask. Never execute without per-task commits.
5. **Isolate.** Run `exloom:isolating-execution` unless you are already on a feature branch or in a worktree.

## Per task

1. **Read the task and its validation step first.** The validation defines the scope. Read the sibling files and match their naming, error handling and layout.
2. **Implement the task as written** — not more, not less. An improvement the plan does not ask for is noted as an out-of-scope observation, not built.
3. **Run the validation the plan specifies**, not a substitute. If it fails, stop: find the root cause and log a deviation; never patch around it. Business logic validated only by a manual check or a build is itself a deviation: log it and add a test, written first.
4. **Log every divergence**, however small, in the format below.
   - **Self-resolve** when there is exactly one mechanical answer (the plan says `rate-limiter.js`, the project is all TypeScript). Log it as Resolved.
   - **Pause for the author** when there are two valid options, the plan's intent changes, or a file outside the plan must change. The test: would two reasonable developers make the same choice?
5. **Tick the task and commit**, one commit per task, naming the plan and task: `plan:payments-rate-limit task-3: add Redis configuration for rate limiter`.
6. **Review the task.** Dispatch `exloom:l1-reviewer` with exactly:

   ```
   Review task <n> of <plan path>. Diff: git diff <commit before the task>..<task commit>
   Task text:
   <the task's text, verbatim>
   ```

   It returns a spec verdict (`MATCHES`, `MISSING`, `EXTRA`, `MISUNDERSTOOD`) and quality findings. EXTRA means remove the code the task does not ask for, or log it as a deviation. Blocking findings go to `exloom:fixer`, verbatim (prompt in `/review-complete`); you do not fix them yourself. Then verify:

   ```
   Verify fixes for task <n> on branch <branch>. Fix range: <last-reviewed-sha>..<sha>
   Previous findings:
   <its finding lines, verbatim>
   ```

   After `.claude/exloom-max-rounds` fix rounds (default 3) the next dispatch is refused: rule on what is left, as `/review-complete` describes. A task review is not a branch round; the whole-branch review runs once, from `/exloom`.

## After the last task

Run `exloom:auditing-plan-fidelity`; do not repeat its checks by hand. Say plainly if a deviation was logged and never settled: a paused deviation is not a resolved one. Then return to `/exloom`.

## Deviation Log

It lives in the plan. Create the section if it is missing. Every field is required:

```
### Deviation [N] — [Date] [Time]
**Step:** Task [number] — [task title]
**Expected:** [What the plan said]
**Found:** [What was actually found]
**Action taken:** [What was done before pausing]
**Resolution needed:** [Specific question for the author]
**Status:** [Paused | Resolved — brief summary]
```

"Resolution needed" is a question the author can answer: "Should the rate limiter return 429 (standard) or 503 (the pattern in error-envelope.ts)?" A self-resolve that needs more than one sentence of justification is not one: pause.

## When in doubt, stop and log

| Situation | Decision |
|---|---|
| A step is ambiguous, seems wrong, or contradicts another | Stop and log. The author decides. |
| You see a better way | Note it as out of scope. Execute as written. |
| A test fails unexpectedly | Stop. Root cause, then a deviation. |
| It was easier than expected | Re-read the plan and its criteria. |
| A dependency is unavailable, or a named file does not exist | Log it. Do not substitute or create without the author. |
| A file outside the plan must change | Log it: unplanned files are the top cause of audit failures. |

See [failure-modes.md](failure-modes.md) and [worked-example.md](worked-example.md).
