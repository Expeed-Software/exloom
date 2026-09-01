# Failure Modes — executing-handoff-plans

Extracted from SKILL.md so the skill loads lean. This is the failure modes this skill exists to prevent — thought pattern, why it feels right, what actually happens, and the correction.


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
