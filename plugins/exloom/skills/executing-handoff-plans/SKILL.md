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

Bad pattern: "The test failed but I can see why — let me fix it and move on." Fixing a test failure without logging it means the deviation is invisible. Maybe the fix is correct. Maybe it masks a deeper issue the plan did not anticipate. Log it, describe what failed and why, then decide with the author whether to proceed. If the failure points to a systemic issue, this is the moment to invoke `exloom:systematic-debugging` rather than applying a local patch.

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

All tasks are complete. This is the most dangerous moment in execution — the temptation to declare victory is strong. Resist it. Before declaring the work done, verify each of these conditions explicitly:

- **All checkboxes checked.** Every task in the plan has been marked complete. If any are unchecked, execution is not finished.
- **All deviations resolved.** Not just logged — resolved. Every deviation entry must have a status of "Resolved" with a brief summary. "Paused" entries mean there are open questions. Open questions mean execution is not complete.
- **Final validation passed.** The plan's overall acceptance criteria or final validation step has been run and passed. Task-level validations passing does not guarantee the integrated result works.
- **No unplanned file changes.** Every file you created or modified should trace back to a plan task. If you touched a file that is not mentioned in the plan, that is a deviation that needs to be logged and resolved, even retroactively.

Once all four conditions are met, compile a brief execution summary: how many tasks completed, how many deviations were logged and resolved, what the final test count looks like, and any out-of-scope observations worth revisiting. This summary becomes input for the verification step.

Then hand execution to `exloom:proving-done`. Execution completing is not the same as the work being correct. Verification is a separate concern — it checks that the integrated result meets the plan's acceptance criteria end-to-end, not just task-by-task.

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
| Test fails unexpectedly | Stop. This triggers `exloom:systematic-debugging`, not a workaround. |
| Finished early / plan was easier than expected | Suspicious. Re-read plan — did you miss something? Check acceptance criteria. |
| External dependency is unavailable | Log deviation. Don't substitute without author guidance. |
| You need to change a file not in the plan | Log deviation. Unplanned file changes are the #1 source of audit failures. |
| Plan references a file that does not exist | Log deviation. The plan may be outdated or the file may have been renamed. Do not create the file at the referenced path without author confirmation. |
| Two plan tasks contradict each other | Stop. Log both tasks and the contradiction. This is an authoring error that the executor cannot resolve. |

## Failure Modes

These are the five most common ways execution goes wrong. Each one feels reasonable in the moment — that is what makes them dangerous. The pattern across all five: the executor substitutes their own judgment for the plan's specification, and the substitution is invisible to everyone except the executor. By the time anyone else notices, the damage is done.


**1. "The plan says X but Y is obviously better."**

The thought pattern: you are mid-execution, you see a cleaner approach, and the plan's approach feels suboptimal. You switch to Y because you are confident it is superior.

Why it feels right: you are closer to the code than the plan author was. You can see things they could not. Your judgment is probably correct — Y probably is better.

What actually happens: the code diverges from the plan. The reviewer reads the plan, expects X, finds Y, and has to investigate whether this was intentional, accidental, or a misunderstanding. The auditing skill flags it as an undocumented deviation. Time is spent justifying the change after the fact instead of before. And even if Y is better, the decision was made unilaterally — the team did not agree to Y, you did.

The correction: log it. Write "Out of scope observation: Y may be better than X because [reason]." Then execute X as written. If Y is genuinely better, it will survive the review and become the plan for the next iteration. The discipline is not about ignoring better ideas — it is about routing them through the right process.

**2. "I'll log the deviation later."**

The thought pattern: you hit a discrepancy but you are in flow. You will note it when you finish this task.

Why it feels right: stopping to write a log entry breaks concentration. You are making progress. The deviation is small. You will remember it.

What actually happens: you forget. Or you remember but the details are fuzzy — was the file in `src/utils/` or `src/helpers/`? Or you remember but rationalize that it was too minor to log. By the end of execution, the deviation log is incomplete and the plan-code gap is undocumented. The auditor finds discrepancies with no explanation.

The correction: log when it happens. Every time. The 90 seconds it takes to write a deviation entry is cheaper than the 30 minutes it takes to reconstruct what happened during an audit. Keep the deviation log open alongside your work — it should be as natural as saving a file.

**3. "This is close enough."**

The thought pattern: the validation expects a response with `{ "status": "rate_limited" }` but your implementation returns `{ "status": "RATE_LIMITED" }`. Close enough.

Why it feels right: the semantics are identical. Case differences are trivial. No reasonable system would break on this.

What actually happens: downstream consumers that check for the exact string break. Or they do not break now, but break when someone adds a case-sensitive check later. Or the inconsistency propagates and the codebase has two conventions for the same concept. "Close enough" compounds — three "close enough" decisions later, the system has subtle inconsistencies that are individually harmless and collectively create debugging nightmares.

The correction: if the validation expects X and you produced X-ish, that is a deviation. Log it. Either update your code to match exactly, or get the validation criteria updated. Do not ship "close enough."

**4. "I'll just do this one extra thing."**

The thought pattern: while implementing task 4, you notice that a nearby function has a bug, or could use a small improvement, or is missing a null check. It would take two minutes to fix.

Why it feels right: you are already in the file. Leaving a known issue feels irresponsible. It is a small change. Nobody will mind.

What actually happens: the "two minute fix" is untested, unreviewed, and unplanned. It may introduce a regression. It definitely makes the commit harder to review because the diff contains changes unrelated to the plan. The reviewer has to figure out which changes are plan-driven and which are improvised. And if the fix breaks something, it is interleaved with planned work — making rollback messy.

The correction: note it. Do not do it. Write "Out of scope observation: [function] has [issue], should be addressed separately." Extra work belongs in a new plan. If the issue is urgent, pause execution and raise it — but do not silently fix it mid-task.

**5. "The tests pass, I'm done."**

The thought pattern: all tests are green. That means the code works. Time to wrap up.

Why it feels right: passing tests are the universal signal for "this is correct." Green is green.

What actually happens: tests passing means the automated checks pass. But the plan may have validation steps beyond tests — manual verification, performance benchmarks, documentation updates, migration scripts tested against production-like data. "Tests pass" is necessary but not sufficient. A plan that says "response time under 200ms at p95" is not validated by a test that only checks the response shape. A plan that says "documentation updated" is not validated by a test suite that does not touch docs.

The correction: go back to the plan. Read the final acceptance criteria. Run every validation step listed, not just the test suite. If the plan says "verify the rate limit header appears in the response," curl the endpoint and check. Do not assume the test covers it unless the test explicitly asserts it.

## Worked Example

The following walks through a complete execution from start to finish. Pay attention to the three deviations — they show all three handling paths: a self-resolved mechanical change (logged anyway), a paused design decision, and a specification conflict that required author input. Each is logged as its own entry, demonstrating the core discipline: log first, resolve second, never improvise.

**Scenario:** Executing a plan for "Add rate limiting to the payments API" in a Node.js Express service. The plan has 5 tasks.

### Before Starting

Read the full plan. Five tasks: (1) add rate limiter middleware, (2) wire it to payment routes, (3) add Redis config, (4) add integration tests, (5) update API docs. Acceptance criteria: rate limiting returns 429 with `Retry-After` header, existing tests still pass, docs updated.

Verify environment. Express 4.18 installed — matches plan. Redis running locally on port 6379 — confirmed with `redis-cli ping`. Run `npm test` — 247 tests, all passing. Clean baseline established.

Check for ambiguity. All tasks have specific file paths, specific validation steps, and specific acceptance criteria. No "TBD" markers, no vague language. Plan is ready for execution.

### Task 1 — Add rate limiter middleware

Read task: "Create `src/middleware/rate-limiter.js` exporting a configurable rate limiter using `express-rate-limit` with Redis store." Validation: "Unit test in `src/middleware/__tests__/rate-limiter.test.js` passes."

Read sibling files in `src/middleware/`. Find `auth-guard.ts`, `request-logger.ts`, `error-handler.ts`. All TypeScript. All use a common `MiddlewareFactory` pattern from `src/middleware/types.ts`. All have tests in `__tests__/` using the same setup helper.

Two distinct discrepancies surface here — the file extension and the internal pattern. They are different decisions, so they get **two separate deviation entries**, not one bundled entry. (Per the logging rule, every deviation is its own entry, even a self-resolved one.)

**Deviation #1 (self-resolved):**

```
### Deviation 1 — 2026-04-12 14:23
**Step:** Task 1 — Add rate limiter middleware
**Expected:** Plan specifies `rate-limiter.js` (JavaScript)
**Found:** The project is entirely TypeScript
**Action taken:** Self-resolved — created `rate-limiter.ts`. The extension is the only mechanically obvious choice in an all-TypeScript project; two reasonable developers would make the same call.
**Resolution needed:** None — self-resolved.
**Status:** Resolved — extension changed to `.ts`. No author input required.
```

**Deviation #2 (paused for author):**

```
### Deviation 2 — 2026-04-12 14:25
**Step:** Task 1 — Add rate limiter middleware
**Expected:** Plan implies a plain exported function
**Found:** All existing middleware is built on a shared `MiddlewareFactory` pattern from `src/middleware/types.ts`
**Action taken:** None — paused before creating the file
**Resolution needed:** Should the rate limiter adopt the `MiddlewareFactory` pattern? That changes the file's internal design — reasonable developers could disagree (follow the house pattern vs. keep the plan's simpler function), so it is an author decision, not a mechanical fix.
**Status:** Resolved — Author confirms: adopt MiddlewareFactory to match existing middleware. Plan updated.
```

Together these show the split cleanly: Deviation 1 was self-resolved but still logged (one obvious choice, no author input); Deviation 2 was a genuine design decision and paused for the author. Logging them separately is the rule — one entry per deviation, even the trivial one. Implement `src/middleware/rate-limiter.ts` following the `MiddlewareFactory` pattern. Write unit test matching the sibling test structure. Run test — passes (1 new unit test, 248 total; the limiter uses the default local Redis at this point, and Task 3 externalizes the connection via config). Mark checkbox, commit: "plan:payments-rate-limit task-1: add rate limiter middleware."

### Task 2 — Wire rate limiter to payment routes

Read task: "Import rate limiter in `src/routes/payments.ts` and apply as route-level middleware." Validation: "Existing payment route tests still pass. Manual curl returns `X-RateLimit-Limit` header."

Read sibling route files. All route files apply middleware via the router-level `use()` pattern, not per-handler. The plan does not specify the wiring approach, but brownfield discipline is clear — use the router-level pattern.

Apply rate limiter the same way. Existing payment tests pass — 14 of 14. Curl confirms header present. No deviations. Mark checkbox, commit: "plan:payments-rate-limit task-2: wire rate limiter to payment routes."

### Task 3 — Add Redis configuration

Read task: "Add rate limiter Redis connection config to `src/config/redis.ts` with environment variable overrides." Validation: "Rate limiter works with `RATE_LIMIT_REDIS_URL` set to a non-default value."

Read `src/config/`. Config files follow a pattern: each exports a typed config object, reads from `process.env` with fallbacks, and has a corresponding `.env.example` entry. Implement following the same pattern. Set `RATE_LIMIT_REDIS_URL` to a non-default port and confirm via the middleware unit test that the limiter connects to the configured Redis. No deviations. Mark checkbox, commit: "plan:payments-rate-limit task-3: add Redis configuration for rate limiter."

### Task 4 — Add integration tests

Read task: "Add integration test verifying 429 response when rate limit exceeded." Validation: "Test sends 11 requests in 10 seconds, 11th returns 429." (Redis config from Task 3 is in place, so the limiter has a working store to exercise.)

Implement the test. Run it. The 11th request returns 503, not 429. Investigation reveals `src/shared/error-envelope.ts` maps all service-level limit errors to 503 with a generic "service unavailable" message.

**Deviation #3:**

```
### Deviation 3 — 2026-04-12 15:47
**Step:** Task 4 — Add integration tests
**Expected:** Rate limit exceeded returns HTTP 429 per plan and RFC 6585
**Found:** Existing error envelope in src/shared/error-envelope.ts maps all limit errors to HTTP 503
**Action taken:** Test written and confirmed failing with 503 instead of 429
**Resolution needed:** Should rate limiting return 429 (HTTP standard, plan spec) or 503 (existing error envelope pattern)? If 429, the error envelope needs a new error type — that's a file change not in the plan.
**Status:** Resolved — Author decides: use 429. Add rate-limit error type to error-envelope.ts. Plan updated to include the error envelope change; the 429 error response is documented in Task 5's docs update.
```

Update error envelope with new `RateLimitExceeded` error type. Fix test to assert 429. This task adds 5 integration tests. Run full test suite — all 253 tests pass (247 original + 1 unit test from Task 1 + 5 integration tests here). Mark checkbox, commit: "plan:payments-rate-limit task-4: add integration tests and update error envelope."

Note: the error envelope change was an unplanned file modification, but it was explicitly approved by the author during deviation resolution and the plan was updated to include it. This is the correct flow — not silently changing the file, but getting approval and updating the plan first.

### Task 5 — Update API docs

Read task: "Add rate limiting section to `docs/api/payments.md` documenting limits, headers, and error response." Validation: "Docs build passes. Rate limiting section visible at `/api/payments#rate-limiting`."

Implement the docs section, including the `429` error response and `Retry-After` header introduced by the Deviation 3 resolution (this is the "error response" the task already calls for — it closes the loop on that deviation). Run `npm run docs:build` — builds clean. Check the rendered output — section visible and correctly linked, 429 response documented. No deviations. Mark checkbox, commit: "plan:payments-rate-limit task-5: add rate limiting documentation."

### After Execution

All 5 checkboxes checked. 3 deviations logged, all resolved. No unplanned file changes (the error envelope change was approved and the plan was updated before the change was made).

Final validation against acceptance criteria:
- Rate limiting returns 429 with `Retry-After` header — confirmed via curl, 11th request in 10 seconds returns `429` with `Retry-After: 7`.
- Existing tests still pass — 247 original tests all green, plus 6 new (1 unit test from Task 1, 5 integration tests from Task 4) = 253.
- Docs updated — rate limiting section renders at the expected URL.

Execution summary: 5 tasks completed, 3 deviations — file extension (self-resolved), middleware pattern adoption (author input), and status-code conflict (author input) — all resolved. One out-of-scope observation noted: the error envelope could benefit from a centralized error code registry, but that is a separate concern.

Hand to `exloom:proving-done`.

Key takeaway from this example: the three deviations cover the three handling paths — a mechanical change self-resolved and logged (deviation 1), a codebase pattern that contradicts the plan's assumptions and needs an author decision (deviation 2), and a specification conflict between the plan and existing behavior (deviation 3). Each was logged as its own entry, and all were caught before they became bugs because execution followed the process: read sibling files first, run validation immediately, log before fixing.

## Integration

This skill sits at the center of the plan-execute-verify pipeline. Understanding where it connects prevents gaps in the workflow.

- **You arrive here from:** `exloom:planning-for-handoff` (if you wrote the plan yourself) or `exloom:reviewing-plans` (if the plan was handed to you after review).
- **You leave here toward:** `exloom:proving-done` to confirm the work is correct before declaring it done. Never skip this step — execution completing and work being correct are different claims.
- **If you hit a bug during execution:** `exloom:systematic-debugging`. Do not debug ad hoc — follow the structured process. Log the bug as a deviation and pause execution until debugging produces a root cause.
- **If a task needs design work the plan did not anticipate:** `exloom:brainstorming`. The plan may need updating before execution can continue. This is a deviation — log it.
- **After completion:** `exloom:auditing-plan-fidelity` checks your executed work against the plan for undocumented deviations. A clean audit is the proof that execution discipline was maintained.
- **For implementation tasks that include test work:** use `exloom:test-driven-development` for the TDD cycle within each task. The plan's task defines what to build; TDD defines the red-green-refactor cycle for building it.

The key principle across all these integrations: execution is one phase in a larger workflow. It has clear entry conditions (a reviewed, unambiguous plan), clear exit conditions (all tasks done, all deviations resolved, verification passed), and clear escalation paths (debugging, brainstorming, author consultation). Staying within these boundaries is what makes the workflow reliable across a team of any size.
