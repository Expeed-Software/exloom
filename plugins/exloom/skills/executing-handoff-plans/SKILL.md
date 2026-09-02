---
name: executing-handoff-plans
description: Use when you have a written plan to execute — runs tasks in order, flags any deviation inline, and refuses to improvise.
---

# Executing Handoff Plans

## Overview

Execution is not implementation. Implementation is writing code. Execution is following a plan while writing code. The difference is discipline: writing code that solves the problem in the way the team agreed upon, documented, and will later audit against.

The defining rule: **flag deviations, don't improvise.** When reality diverges from the plan — a file has moved, a dependency behaves differently, a pattern in the codebase contradicts the plan's assumption — the correct response is to log the deviation and pause. Not to figure it out. Not to pick the option that seems reasonable. Log it, describe it precisely, and wait for the author to decide. Unlogged decisions are invisible decisions, and invisible decisions cannot be reviewed, audited, or learned from.

This skill works whether you wrote the plan yourself or picked it up from someone else. The rules are identical. Executing someone else's plan is the better test of execution discipline — you cannot fall back on "I know what I meant." You only have what the plan says.

## Process

### Before Starting

Do not begin execution until all four preconditions are satisfied. Skipping any of them is how execution goes sideways in the first hour.

**1. Read the plan in full.**

Read from the first task to the last, including acceptance criteria, edge cases, and any appendix. Do not start at task 1 without reading to the end. Step 8 may constrain how you approach step 2. An edge case documented at the bottom may invalidate an assumption you would otherwise make in the first task. Reading the plan in full takes minutes. Recovering from a wrong assumption takes hours.

Bad pattern: "I'll read each task as I get to it." This produces locally correct, globally incoherent execution. You build task 3 in a way that makes task 7 impossible, then have to rework.

**2. Confirm the plan is unambiguous.**

Every task must have a concrete action and a concrete validation step. If any task contains "TBD", vague file paths, language like "appropriate" or "as needed" without specifics, or references to decisions not yet made — the plan is not ready for execution. Return it to the author with the specific ambiguities listed. Do not interpret ambiguity charitably. "Update the relevant service" is not a task. Which service? What update? The plan must say.

Bad pattern: "I think I know what they mean." Maybe you do. But the deviation log exists precisely because what you think they mean and what they actually mean diverge often enough to matter.

**3. Verify environment readiness.**

Before touching any code, confirm the development environment matches what the plan assumes. Required tools installed at the expected versions. Dependencies resolved. Database accessible and migrated. Test suite passing with zero changes. This establishes a clean baseline. If tests are already failing before you start, you need to know that now — not after you have made changes and cannot tell which failures are yours. Confirm the working tree is a git repository, too — per-task commits (step 6) are what make the plan an auditable contract, so if `git rev-parse --is-inside-work-tree` fails, do not silently proceed: for a brand-new or empty project, run `git init`, note it in the deviation log, and continue; for an existing folder that already has code but no git, STOP and ask before initializing. Either way, never execute without per-task commits — that discards the entire audit trail.

Then isolate the workspace before the first commit: run `exloom:isolating-execution`. It moves the work onto a feature branch where the review gate can fire — the hooks skip `main`/`dev`, so building straight onto a protected branch means the gate never fires — and it checks whether the repo has actually enabled the gate (`.claude/exloom-gate.enabled`), telling you if you are isolated but not gated. Skip it only if Level 0 there finds you are already on a feature branch or in a worktree.

Bad pattern: "I'll set up as I go." This interleaves environment issues with execution issues. When a test fails, you cannot tell if it is your change or a missing dependency. Separate the concerns.

**4. Refuse to start on an ambiguous plan.**

This is not the executor's job to resolve. If the plan has gaps, the author needs to close them. Starting execution on an ambiguous plan produces improvised execution that cannot be audited, cannot be reproduced, and teaches the team that plans do not need to be precise. Sending the plan back is not a failure — it is quality enforcement.

When you are both author and executor (solo path), "send it back to the author" means stop executing and switch into author mode: re-open the plan, resolve the ambiguity as a planning decision, update the plan, and only then resume execution. Do not paper over the gap by deciding it mid-execution — that is the exact improvisation this precondition exists to prevent. The role switch is the point: you fix the plan as the author before you act as the executor.

Bad pattern: "I'll just make reasonable assumptions and note them." This sounds responsible but produces the same outcome as improvisation — the code diverges from the plan, and the reviewer has to reverse-engineer which parts are plan and which parts are assumption.

### During Execution — Per Task

For each task in the plan, follow this cycle exactly. Do not skip steps. Do not reorder them. The cycle is designed so that each step prevents a specific class of execution error — reading validation first prevents scope drift, reading siblings prevents pattern violations, and logging deviations prevents invisible decisions.

**1. Read the task AND its validation step before writing any code.**

Understanding what "done" looks like before you start prevents gold-plating and under-delivery equally. If the validation step says "returns 404 for missing resources," you know the scope before you write a line. If the validation step is missing or vague, that is a deviation — log it before proceeding. Pay attention to the validation's specificity: does it check a status code? A response body shape? A side effect in the database? A log entry? These details define what you actually need to build.

Bad pattern: "I'll figure out validation after I build it." This inverts the relationship. The validation step defines the task's scope. Building first and validating second means you built to your interpretation, not to the plan's specification. You end up with code that works but does not satisfy the validation, then you retrofit — which is rework disguised as progress.

**2. Read sibling files in the same module.**

Before creating or modifying a file, read the surrounding files. Match naming conventions, error handling patterns, logging patterns, import ordering, and code organization. The plan may say "create a rate limiter middleware" but the existing middleware files use a specific base class, a specific error format, a specific test structure. Brownfield discipline applies during execution. The plan specifies what to build. The codebase specifies how it should look when built.

Bad pattern: "The plan didn't mention matching existing patterns." It does not need to. Matching existing patterns is a baseline expectation, not something each plan must explicitly state. A new file that ignores the conventions of its neighbors creates inconsistency that the next developer has to reconcile.

**3. Implement the task as specified.**

Write the code the plan describes. Not more, not less, not differently. If the plan says "add a Redis-backed cache with a 5-minute TTL," you add a Redis-backed cache with a 5-minute TTL. You do not add an in-memory fallback because "what if Redis is down." That may be a good idea. It is not in the plan. Note it as an out-of-scope observation and keep going.

Bad pattern: "I improved it while I was in there." Improvements that are not in the plan are scope creep. They introduce untested, unreviewed changes that the auditing skill will flag. The improvement may be correct, but correctness is not the bar — the bar is "was this planned, reviewed, and tracked."

**4. Run the validation step.**

Execute exactly the validation the plan specifies. If the plan says "run the integration test suite for the payments module," run that. Not the unit tests. Not a quick manual check. The specified validation. If it passes, proceed. If it fails, STOP. Do not debug speculatively. A failing validation is a deviation. And if a task implements real business logic (calculations, validation, branching, state changes) but its only validation is a manual check, a curl, or a build — with no automated test — that under-specification is itself a deviation: log it and add a test, because manual checks do not protect the logic from the next change.

Bad pattern: "The test failed but I can see why — let me fix it and move on." Fixing a test failure without logging it means the deviation is invisible. Maybe the fix is correct. Maybe it masks a deeper issue the plan did not anticipate. Log it, describe what failed and why, then decide with the author whether to proceed. If the failure points to a systemic issue, find the root cause rather than applying a local patch.

**5. If reality diverges from plan, log deviation and pause.**

Any difference between what the plan says and what you find — a file in a different location, a function with a different signature, a dependency at a different version, a pattern that contradicts the plan's approach — is a deviation. Log it using the format below. All deviations get logged regardless of size. The question is not whether to log — it is whether to self-resolve or pause.

**Self-resolve** (log with status "Resolved" immediately): The correct answer is mechanically obvious and has exactly one option. No judgment, no trade-off, no ambiguity. Example: plan says `rate-limiter.js`, entire project is TypeScript → use `rate-limiter.ts`. There is no other reasonable choice. Log it, resolve it, move on.

**Pause for author**: The deviation involves a choice between two or more valid options, changes the plan's intent, or requires touching files not in the plan. Example: plan says HTTP 429, existing error envelope uses 503 → which convention wins? That is a design decision, not a mechanical correction. The executor does not make design decisions.

The test: "Would two reasonable developers make the same choice?" If yes → self-resolve. If they might disagree → pause.

**When you are both author and executor (solo path):** "pause for the author" does not disappear — it becomes a deliberate context switch. Stop executing. Step out of execution mode and make the decision as the author: re-read the spec, weigh the options, and decide on the merits — not on which choice requires the least rework from where you currently are. Log the decision in the deviation log with the same rigor you would use to answer someone else. The value is the deliberate switch from "how do I keep coding" to "what is the right design call," which is exactly the judgment that gets skipped when you let momentum decide. If the deviation changes scope or design, treat it as a trigger to revisit the plan, not a reason to improvise through it.

Bad pattern: "This is too small to log." Small deviations compound. Three "too small to log" deviations later, the code has silently diverged from the plan in ways that are individually trivial and collectively significant.

**6. Mark checkbox and commit.**

Check off the task in the plan document. Commit the changes with a message that references the plan and task number. This creates a 1:1 mapping between plan tasks and commits that makes auditing straightforward and rollback granular.

Bad pattern: "I'll commit everything at the end." Bulk commits destroy traceability. If task 5 introduced a bug, you cannot revert task 5 without also reverting tasks 6 through 10. Additionally, per-task commits give reviewers a narrative — they can follow the plan by reading commits in order, which makes review faster and more accurate.

Commit message format should include the plan reference and task number. Example: `plan:payments-rate-limit task-3: add Redis configuration for rate limiter`. This makes it possible to trace any line of code back to the plan task that introduced it, which is exactly what `exloom:auditing-plan-fidelity` relies on.

### After Execution

All tasks are complete. Run `exloom:auditing-plan-fidelity`.

It compares the plan's file list against the diff, checks the spec's criteria against the tasks in both directions, and reads the Deviation Log for entries left open. Three of those are set differences, and a model re-reading its own work finds fewer of them than `comm` does — so do not also check them by hand.

The one thing to bring to it that it cannot compute: **a paused deviation is not a resolved one.** If you logged something and moved on without settling it, say so now rather than letting the audit find an entry with no resolution.

Then run `/review-complete`. Execution completing is not the same as the work being correct. Verification is a separate concern — it checks that the integrated result meets the plan's acceptance criteria end-to-end, not just task-by-task.

## Deviation Log Format

Every plan should have a Deviation Log section. If it does not, create one before starting execution. Append entries using this format:

```
### Deviation [N] — [Date] [Time]
**Step:** Task [number] — [task title]
**Expected:** [What the plan said]
**Found:** [What was actually found]
**Action taken:** [What was done before pausing]
**Resolution needed:** [Specific question for the author]
**Status:** [Paused | Resolved — brief summary]
```

Every field is required. "It was different so I fixed it" is not an acceptable Action taken entry — that is improvisation wearing a log entry as a disguise. The Resolution needed field must contain a specific, answerable question. "What should I do?" is not specific. "Should the rate limiter use HTTP 429 (standard) or HTTP 503 (existing pattern in error-envelope.ts)?" is specific.

Even minor deviations get logged. A resolved deviation is still a deviation. The author should know about it. The auditor will check for it. An empty deviation log at the end of a non-trivial execution should be questioned, not celebrated — it usually means deviations happened but were not recorded.

Self-resolved deviations must still be logged with status "Resolved" and the reasoning stated. Obvious to the executor must also be obvious to the auditor reading the log later. If you find yourself writing more than one sentence of justification, it is not a self-resolve — pause and ask.

The deviation log lives in the plan document itself, not in a separate file. This keeps the plan as the single source of truth for what was intended and what actually happened. When someone reads the plan six months from now, the deviations are right there — they do not need to go searching for a separate execution report.

When multiple deviations are related (e.g., three tasks all hit the same pattern mismatch), log each one individually but cross-reference them. "See also Deviation 1 — same root cause." This helps the auditor understand that three deviations are really one issue encountered three times, not three independent problems.

## Decision Points

Execution is a series of micro-decisions. Most are straightforward — the plan says what to do and you do it. But some situations require judgment about process, not about code. The table below covers the common ones. The pattern across all of them: when in doubt, stop and log. The cost of a false stop (logging something that turns out to be trivial) is minutes. The cost of a false continue (improvising through something that should have been flagged) is hours of audit and rework.

| Situation | Decision |
|---|---|
| Plan step is ambiguous | Stop. Log as deviation. Don't interpret. |
| Plan step seems wrong | Stop. Log deviation. Author decides, not executor. |
| You see a better way | Note as "out of scope observation." Execute as written. |
| Test fails unexpectedly | Stop. Find the root cause and log it as a deviation — never work around it. |
| Finished early / plan was easier than expected | Suspicious. Re-read plan — did you miss something? Check acceptance criteria. |
| External dependency is unavailable | Log deviation. Don't substitute without author guidance. |
| You need to change a file not in the plan | Log deviation. Unplanned file changes are the #1 source of audit failures. |
| Plan references a file that does not exist | Log deviation. The plan may be outdated or the file may have been renamed. Do not create the file at the referenced path without author confirmation. |
| Two plan tasks contradict each other | Stop. Log both tasks and the contradiction. This is an authoring error that the executor cannot resolve. |

## Failure Modes

See [failure-modes.md](failure-modes.md).

## Worked Example

See [worked-example.md](worked-example.md).

## Integration

This skill sits at the center of the plan-execute-verify pipeline. Understanding where it connects prevents gaps in the workflow.

- **You arrive here from:** `exloom:planning-for-handoff` — whether you wrote the plan or it was handed to you.
- **You leave here toward:** `exloom:auditing-plan-fidelity`, then `/review-complete`, to confirm the work is correct before declaring it done. Never skip this step — execution completing and work being correct are different claims.
- **If you hit a bug during execution:** find the root cause before fixing. Log the bug as a deviation and pause execution until debugging produces a root cause.
- **If a task needs design work the plan did not anticipate:** `exloom:brainstorming`. The plan may need updating before execution can continue. This is a deviation — log it.
- **After completion:** `exloom:auditing-plan-fidelity` checks your executed work against the plan for undocumented deviations. A clean audit is the proof that execution discipline was maintained.
- **For implementation tasks that include test work:** write the failing test first, inside the same task. The plan's task defines what to build; the test defines the red-green-refactor cycle for building it.

The key principle across all these integrations: execution is one phase in a larger workflow. It has clear entry conditions (a reviewed, unambiguous plan), clear exit conditions (all tasks done, all deviations resolved, verification passed), and clear escalation paths (debugging, brainstorming, author consultation). Staying within these boundaries is what makes the workflow reliable across a team of any size.
