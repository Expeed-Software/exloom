---
name: systematic-debugging
description: Use when encountering any bug, test failure, or unexpected behavior before proposing fixes. Root-cause first, never patch symptoms.
---

# Systematic Debugging

## Overview

The single discipline: find the root cause before writing fix code. Not after. Not simultaneously. Before. The process is deliberately sequential because the most common debugging error is skipping ahead to a fix before understanding the problem.

The process applies to every class of defect: logic errors that produce wrong output, performance regressions that make things slow, integration failures where services disagree, flaky tests that pass "most of the time," and data corruption that only shows up downstream. The steps are identical. The evidence bar is identical. There are no shortcuts for "simple" bugs because the bugs that look simple are the ones that get patched incorrectly.

## Process

Follow these seven steps in order. Do not skip to step 5 because the fix seems obvious — skipping steps is how wrong fixes get committed with confidence.

The useful signal for progress is not the clock but narrowing: if you have cycled through hypotheses several times with no narrowing, you are stuck at step 3 or 4 and should consult the Decision Points section below.

### Step 1: Reproduce reliably

**What to do:** Before touching any code, write down the exact steps that trigger the bug. Run them. Confirm the bug appears consistently.

**How to do it well:** Create a concrete checklist with these elements:

- **Input data:** the exact request body, file, or user action that triggers the bug.
- **Environment state:** database contents, configuration values, feature flags, running services.
- **Sequence:** the exact order of operations, including any setup steps.
- **Expected result:** what should happen, stated precisely.
- **Actual result:** what does happen, stated precisely (not "it is wrong" but "card charged 209 cents instead of 210").

Run it three times. If it fails inconsistently, note the failure rate — "fails 2 of 5 runs" is useful data that constrains your hypothesis space. If the bug was reported from production, replicate the data shape locally with anonymized values; never debug against production directly. If reproduction requires specific data volume or timing, approximate those conditions locally — create a dataset with the same cardinality, use a load generator to simulate concurrent requests, or set your system clock to match the timezone where the bug appeared. If you absolutely cannot reproduce it, you cannot fix it — instrument with structured logging at the suspected code path, deploy the instrumentation, and wait for recurrence rather than guessing at code you have not seen fail.

**What bad looks like:** "It happened once in production, let me just read the code and guess where the problem is." You are now debugging an imaginary bug shaped by your assumptions, not the real one shaped by evidence. Without reproduction, you cannot verify any fix, and you will ship a change that addresses your mental model rather than reality. Another common failure: reproducing a different bug that looks similar. If your local reproduction does not match the exact symptoms in the report, you are not reproducing the reported bug.

### Step 2: Isolate to smallest failing case

**What to do:** Strip away everything that is not the bug. Reduce the failure to the smallest possible input, code path, or configuration that still triggers it.

**How to do it well:** Binary search the system. Remove half the components — does it still fail? Halve again. Concrete techniques by bug type:

- **Wrong output from an API:** Replace the business logic with a hardcoded correct response. Still fails? The bug is in routing, serialization, or middleware. Does not fail? Add logic back piece by piece until it breaks.
- **Failing test in a suite:** Run the failing test alone. If it passes alone but fails in the suite, you have a test-ordering dependency — the bug is shared state between tests. Run it with just the preceding test to confirm.
- **Performance regression:** Profile the request and identify the single longest span. Is it CPU, I/O, or waiting on a lock? Each points to a different category of root cause.
- **Intermittent failure:** Run 20 times, not 3. Record which runs fail. Look for patterns: every Nth run, only after a specific predecessor, only under specific timing.

The goal is a single input that produces wrong output through the shortest possible code path.

**What bad looks like:** Staring at the full request flow — controller, service, repository, database, message queue — trying to spot the problem by reading code top to bottom. You are searching a haystack one straw at a time. Isolation hands you the needle directly. Another bad pattern: isolating to a unit test that passes because the mock hides the bug. Isolation means reducing the real system, not replacing it with fakes that assume correctness at exactly the point where correctness is in question.

### Step 3: Form a hypothesis

**What to do:** State a falsifiable claim about what is causing the bug. Write it down in this form: "The bug occurs because X. If I am right, then when I do Y, I should see Z."

**How to do it well:** Be specific and testable. "The connection pool is exhausted because connections are not released when an exception is thrown in the transaction block" is a hypothesis — it names the mechanism, predicts the evidence, and can be proved wrong. "Something is wrong with the database" is a vague hunch that cannot be tested. Ground your hypothesis in the evidence from steps 1 and 2. If you isolated the failure to a specific function, your hypothesis should explain why that function produces wrong output for the failing input but correct output for other inputs. Use the boundary you found in step 2: if single-item orders work but multi-item orders do not, your hypothesis must account for that difference. Writing the hypothesis down — literally, in a comment, a note, or a debugging log — disciplines thinking and makes it obvious when evidence stops supporting it. Good hypotheses sound like: "The BigDecimal prices are converted to doubles before summation, and the accumulated IEEE 754 representation error exceeds the rounding threshold at 3+ items."

**What bad looks like:** A mental model you never articulate: "I think it is probably the caching." You cannot test what you have not stated. Vague hypotheses lead to vague fixes and wasted cycles. If you cannot write your hypothesis as a falsifiable "if X then Y" statement, you do not yet have a hypothesis — you have a feeling, and feelings do not debug software.

### Step 4: Test the hypothesis

**What to do:** Change ONE thing — add a log line, an assertion, a breakpoint — at exactly the location your hypothesis predicts the failure. Run the reproduction case. Did the predicted outcome happen?

**How to do it well:** The key discipline is one variable at a time. If your hypothesis says the value is null at line 47, add a log at line 46 that prints the value. Do not simultaneously add logging in three other places "just in case" — each extra observation point adds noise and makes it harder to interpret results. If the evidence confirms your hypothesis, proceed to step 5. If it refutes it — the value was not null, the branch was not taken, the timing was not what you expected — that is valuable data, not a failure. Ask: what does the actual result tell me? What hypotheses does this evidence eliminate? What new hypothesis does the evidence support? Return to step 3 with a revised hypothesis that accounts for all evidence collected so far, including the new disconfirming data. Keep a running list of tested and refuted hypotheses so you do not re-test the same idea after a long debugging session.

**What bad looks like:** Changing three things at once, then when the bug disappears, not knowing which change fixed it. You now have a "fix" you cannot explain, which means you cannot trust it and your reviewer cannot evaluate it. Or worse: the bug disappears due to a side effect of your instrumentation (a timing change, an initialization order shift), and you conclude a wrong hypothesis was right. When the instrumentation is removed, the bug returns. Single-variable testing is not optional — it is the difference between science and superstition.

### Step 5: Fix at root cause

**What to do:** Write a fix that makes the confirmed root cause impossible, not one that handles its symptom.

**How to do it well:** The fix should address WHY the bad state exists, not THAT it exists. Apply these principles:

- If a value is null, do not add a null check — find where the value should have been set and fix that code path so it always sets it.
- If a race condition causes stale reads, do not add a retry — fix the synchronization or make the operation idempotent.
- If the root cause is in a library or shared service you do not own, fix your usage of it correctly and file an upstream issue with your reproduction case attached.
- Keep the fix minimal: change only what is necessary to eliminate the root cause. Do not bundle refactoring with bug fixes.
- If a clean fix requires refactoring, note the refactoring need in the PR description but do not let the refactor expand scope — fix the bug first, refactor as a follow-up commit or ticket.

Ask yourself: "If someone else encounters this same root cause in another part of the codebase, will my fix prevent it there too, or only here?" If only here, consider whether the fix belongs at a lower layer — a shared utility, a base class, a framework configuration.

**What bad looks like:** Adding a defensive null check at the crash site. The exception stops, the code review approves it because the diff is small and looks "safe," and the actual source of the null value continues corrupting data silently in every other code path that reads it. The null check did not fix the bug — it silenced the one alarm that was telling you something was wrong. Six months later, a data quality audit discovers thousands of records with missing fields, all traceable back to the same root cause that was never addressed.

Similarly: wrapping a block in a try-catch that logs and continues. The operation still fails, but now it fails silently. The user sees a partial result and does not know data is missing.

### Step 6: Verify the fix

**What to do:** Run the original reproduction case from step 1 AND the isolated case from step 2. Both must pass. Then run the full test suite to check for regressions.

**How to do it well:** Verification has three layers, and all three are required:

1. **Isolated case:** Does the minimal reproduction from step 2 now produce correct output? This confirms the mechanism of your fix works at the unit level.
2. **Original scenario:** Does the full end-to-end flow that triggered the bug report now work correctly? This confirms the fix resolves the user-facing problem, not just the isolated unit.
3. **Regression sweep:** Does the full test suite still pass? If you changed shared code, manually verify affected flows beyond what automated tests cover — other callers of that function, other endpoints that share the same service, other configurations that exercise the same code path.

Verification is the step where shortcuts are most tempting and most dangerous — "the unit test passes" means nothing if you never re-ran the original user-facing scenario that the bug reporter will check when you mark the ticket as resolved.

**What bad looks like:** "The unit test I wrote passes, so it is fixed." But the unit test mocks half the system. The original scenario still fails because the mock did not capture the real behavior of the dependency. You ship the "fix," close the ticket, and reopen it three days later when the reporter checks and finds it still broken. Worse, you have now trained the team not to trust your fixes.

Another failure pattern: running only the tests in the file you changed. Your fix may have broken a test in a completely different module that depends on the same shared code. Run the full suite.

### Step 7: Add a regression test

**What to do:** Commit a test that fails without your fix and passes with it. Name the test after the bug behavior, not the fix mechanism.

**How to do it well:** The test should reproduce the exact failure from step 2 — same input, same code path, same assertion on the correct output. Name it descriptively: `test_multi_item_order_total_uses_exact_arithmetic` tells the next developer what broke and what the test guards against. Avoid generic names like `test_order_fix` or `test_bug_1234` — the name should communicate the invariant being protected without requiring the reader to look up a ticket. If a test already existed (the failing test was how the bug was found), ensure it stays in the suite and is not marked as ignored or skipped. If the test requires setup that is too expensive to run on every build, mark it with the appropriate category or tag but do not skip it entirely — a skipped regression test is a deleted regression test with extra steps. Critically: confirm the test actually fails when you revert your fix. A regression test that passes regardless of whether the fix is present proves nothing and creates false confidence.

**What bad looks like:** Writing a test that verifies the fix mechanism ("assert BigDecimal is used") instead of the original failure ("assert 3-item order total equals expected value"). The next developer could refactor the calculation to use a different approach, pass your implementation-checking test, and reintroduce the exact bug you just fixed. Test the behavior, not the implementation.

Another anti-pattern: writing the regression test but not confirming it fails without the fix. If the test passes both with and without your change, it does not test anything related to the bug. Always verify: revert fix, test fails; apply fix, test passes.

## Decision Points

Not every bug follows the clean path of steps 1 through 7. These are the common forks where you need to make a judgment call instead of following the next step mechanically. The default action for each situation is listed — deviate only with evidence that the default does not apply to your case.

| Situation | Decision |
|---|---|
| Cannot reproduce the bug | Do not guess. Instrument with structured logging at the suspected code path, deploy, and wait for recurrence. Guessing without reproduction evidence produces wrong fixes. |
| Hypothesis wrong 3 times in a row | Stop. You are missing context. Read wider — git blame the area, check recent changes, read the original design doc. Ask a colleague who knows the subsystem. Trace from a completely different entry point. |
| Root cause is in shared code you do not own | Fix it if your team owns it. If another team owns it: add a defensive check on your side, document the root cause clearly, and file an upstream issue with your reproduction case attached. Do not silently work around it. |
| Fix works but you cannot explain why | Not done. A fix you cannot explain is a fix you cannot trust. It may be masking the real cause or fixing a coincidental side effect. Keep investigating until you can state precisely why it works. |
| Performance bug vs logic bug | Different starting point. Profile first — flame graph for CPU, query plan for database, heap dump for memory. The profile gives you step 2 (isolation) and step 3 (hypothesis) simultaneously. Then follow steps 4-7 as normal. |
| Bug crosses service boundaries | See the dedicated section below — this is common enough in a microservices org to warrant a process, not a one-liner. |
| Flaky test | It is not flaky — it is a real bug with a non-obvious trigger. The trigger is usually shared mutable state, test-ordering dependency, timing sensitivity, or resource contention. Find the trigger; do not add a retry annotation or rerun-on-failure configuration. |

## Debugging Across Service Boundaries

See [service-boundaries.md](service-boundaries.md).
## Failure Modes

See [failure-modes.md](failure-modes.md).
## Worked Example

See [worked-example.md](worked-example.md).
## Integration

This skill connects to the broader development workflow at specific handoff points. Debugging rarely happens in isolation — it is triggered by something and leads to something.

**Entry points — you arrive here from:**

- A bug report from QA, support, or production monitoring.
- A failing test discovered during `exloom:executing-handoff-plans`.
- Unexpected behavior caught during `exloom:proving-done`.
- A discrepancy between expected and actual output at any stage of development.
- Any time something is not working as expected, this skill applies — do not skip it because the fix "seems obvious."

**Exit points — you leave here toward:**
- `exloom:proving-done` to formally verify the fix is complete and no regressions were introduced before claiming the work is done.
- Back to `exloom:executing-handoff-plans` if the bug was a deviation from the implementation plan and the plan can now continue with the fix in place.

**Cross-cutting concerns:**
- If the bug reveals a systemic issue (wrong pattern used across the codebase, missing team convention, flawed shared utility): route it through `exloom:capturing-learnings` so the fix propagates beyond this one instance and the team does not rediscover the same root cause independently in another module.
- If the fix needs a regression test and you want to write it test-first: use `exloom:test-driven-development` to structure the regression test before writing the fix, so the test drives the fix rather than being bolted on afterward. This is especially valuable when the bug is complex enough that you want the test to define "correct" before you attempt to achieve it.
- If the bug was found during code review rather than testing: the reviewer should cite the specific step from this process that was missed (usually step 6 or 7) so the feedback is actionable rather than generic.
