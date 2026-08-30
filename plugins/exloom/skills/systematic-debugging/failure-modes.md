# Failure Modes — systematic-debugging

Extracted from SKILL.md so the skill loads lean. This is the failure modes this skill exists to prevent — thought pattern, why it feels right, what actually happens, and the correction.


These are the six most common ways debugging goes wrong in practice. Each is a thought pattern to recognize in the moment, as it happens, so you can correct course before the cost compounds.

### 1. "Let me just try this"

**The thought pattern:** You glance at the error, form an instant hunch, and start editing code before you have a reproduction case or a written hypothesis.

**Why it feels right:** Sometimes the first guess works, and when it does, it feels efficient. You saved all that tedious reproduction and isolation time. The dopamine hit of a quick fix reinforces the behavior powerfully — you remember the wins and forget the losses.

**What actually happens:** When the first guess is wrong — and it is wrong more often than you remember — you are now debugging two things: the original bug and the side effects of your guess. Each wrong guess adds noise to the system. After three guesses you have lost track of what the original behavior even was, because your changes have altered it.

**The correction:** Write down reproduction steps before you touch code. Thirty seconds of writing saves thirty minutes of undo. If you catch yourself editing code before you can state the reproduction steps, stop, revert your change, and go back to step 1. The revert is important — your untested change is now part of the system state and will interfere with diagnosis.

### 2. "Works on my machine"

**The thought pattern:** You reproduced the bug locally, applied a fix, verified it locally, and declared it done. But the bug persists in staging or production and you cannot understand why.

**Why it feels right:** Your local environment is the one you control and understand. If the test passes here, the code must be correct. Environment differences feel like infrastructure's problem, not yours.

**What actually happens:** The bug was environment-specific: a different JVM version, a different timezone setting, a missing environment variable, a different database collation, a different volume of data. Your local fix addressed something that was never broken locally in the first place. The real cause — the environment delta — is untouched.

**The correction:** When a bug is reported from a specific environment, compare that environment's configuration to yours before concluding your reproduction is valid. Check: runtime versions, OS, timezone, locale, feature flags, data volume, connection pool sizes, timeout values, and memory limits. If any differ materially, your local reproduction may not be reproducing the same bug. The gold standard: reproduce in the same environment type (staging, container with same image) rather than assuming your dev machine is equivalent.

### 3. "I fixed it!" (but did not verify)

**The thought pattern:** You found the root cause, wrote a fix that logically should work, and moved on to the next task without running the original scenario end to end.

**Why it feels right:** You understand the root cause. The fix directly addresses it. Running the whole scenario again feels like wasted time when you already know why it was broken and can see that your code change addresses that exact cause.

**What actually happens:** The fix stopped the exception, but data is still wrong downstream because a second code path also had the same problem. Or the fix works for the 3-item case you tested but not for the 50-item case in the original report. You close the ticket, and it reopens three days later with the same reporter, less patience, and lower confidence in your team.

**The correction:** Run the original reproduction case from step 1. Not a simplified version. Not just the unit test. The actual scenario that was reported, with the actual data shape that triggered it. Budget five minutes for verification — it is the cheapest insurance against a reopened ticket and the embarrassment of a fix that does not fix.

### 4. "The test passes so it is fixed"

**The thought pattern:** You wrote a unit test for the fix. It passes green. You commit without re-running the original user-facing scenario because the test covers the logic.

**Why it feels right:** Tests are the verification mechanism. A passing test means correct code. That is literally the point of automated testing.

**What actually happens:** The unit test mocks dependencies that are part of the bug's causal chain. The mock returns the right data; the real dependency does not. Or the test covers the happy path of your fix but not the original failure path that the user reported. The bug is alive in production and dead in your test suite — the worst possible outcome because it creates false confidence.

**The correction:** Unit tests verify components in isolation. Integration tests verify component interactions. The original reproduction scenario is the only test that proves the user-facing bug is gone as far as the user is concerned. You need all three layers, and the original scenario is the one most often skipped because it requires the most setup. That setup time is not optional — it is the difference between a verified fix and a hope.

### 5. "It is probably a race condition"

**The thought pattern:** The bug is intermittent, so you immediately attribute it to concurrency. You add a synchronized block or a sleep or a volatile keyword and move on.

**Why it feels right:** Race conditions are real, intermittent, and notoriously hard to prove. Claiming "race condition" feels like a sophisticated diagnosis and neatly explains why the bug is not deterministic. Few reviewers push back because race conditions are genuinely hard to disprove from a code review.

**What actually happens:** Most intermittent bugs are not race conditions. They are order-dependent initialization, cache expiration timing, resource exhaustion under specific load, test pollution from a previous test, or sensitivity to garbage collection pauses. The synchronization you added either does nothing (because it was not a race) or masks the real issue by changing the timing enough that the real trigger no longer fires in your environment. The bug remains, now even harder to reproduce.

**The correction:** Produce concrete evidence of concurrent access to shared mutable state with conflicting operations. Timestamps from two threads accessing the same field, a missing lock acquisition in a critical section, a non-atomic read-modify-write sequence. Reproduce it with a concurrency test that runs the suspected operation from multiple threads simultaneously. No evidence, no race condition diagnosis. "It is intermittent" is not evidence of concurrency — it is evidence of a trigger you have not found yet. Investigate the non-concurrent explanations first: they are more common and easier to prove.

### 6. "I will add a retry"

**The thought pattern:** The operation fails intermittently. Adding a retry with exponential backoff makes it succeed reliably on the second or third attempt. The user never sees the error. Problem solved.

**Why it feels right:** Retries are a legitimate resilience pattern endorsed by every distributed systems guide. The system is now more robust against transient failures. The error rate dropped to zero.

**What actually happens:** The bug fires on every single request but is immediately retried and succeeds on the second attempt. You have doubled the latency and resource consumption for that operation permanently. The bug is still there, happening on 100% of requests, completely hidden by the retry. When the system is under load, the retry amplifies the problem — every failing request now consumes two attempts worth of connections, threads, and database queries. Under sufficient load, the retries themselves cause cascading failure.

**The correction:** A retry is appropriate only when you understand WHY the operation fails transiently (genuine network partition, leader election in progress, brief lock contention during deployment) and have confirmed the failure is genuinely transient with evidence. If you cannot explain what causes the transient failure and why it resolves on retry, the retry is a mask, not a fix. After adding any retry, instrument it: measure the retry rate and alert if it exceeds a threshold. If the retry rate is not converging toward zero over time, you have a permanent bug wearing a retry costume, and the costume is costing you latency and capacity on every request.
