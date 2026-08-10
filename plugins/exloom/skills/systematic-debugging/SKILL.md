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

When a bug spans multiple services, the standard 7-step process still applies — but steps 1-2 (reproduce and isolate) require cross-service evidence. This is where most teams waste time: each service team assumes the bug is in the other service, and nobody reproduces it end-to-end.

**1. Reconstruct the timeline.** Collect logs from all involved services using the correlation ID (per your logging setup). Sort by timestamp. The goal is a single chronological narrative: request entered Service A at T1, left at T2, entered Service B at T3, failed at T4. If your services don't emit correlation IDs, add them before debugging — you cannot trace what you cannot correlate.

**2. Find the boundary where data changed.** The bug lives at the point where correct data becomes incorrect. Compare the outbound payload from Service A with the inbound payload at Service B. If they match and the data is already wrong, the bug is upstream. If Service A sent correct data but Service B received something different, the bug is in serialization, transport, or deserialization — check content types, encoding, field name casing, date format assumptions, and timezone handling. If Service B received correct data and produced wrong output, the bug is in Service B's logic.

**3. Own-service-first rule.** Assume the bug is in your service until evidence proves otherwise. Do not open a ticket on another team's service saying "your service returns wrong data" without a reproduction case that demonstrates their service returning wrong data for a valid request. The reproduction case must include the exact request you sent (not a paraphrase), the exact response you received, and why the response is wrong according to the API contract. Without this, you are sending another team on a wild goose chase based on your assumption.

**4. Reproduce at the boundary.** Once you've identified which service boundary the bug crosses, isolate it: call the upstream service directly with the same input and verify its output. Then call the downstream service directly with that output and verify its behavior. This turns a distributed bug into two local bugs that can each be debugged with the standard 7-step process.

**5. Shared state bugs.** The hardest cross-service bugs involve shared state — a database both services read, a cache one service writes and another reads, an event stream with ordering assumptions. For these, the timeline reconstruction in step 1 is critical: you need to know the exact order of reads and writes across services to identify the race or staleness window.

## Failure Modes

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

## Worked Example

This example walks through all 7 steps including a wrong first hypothesis. The messy middle — the hypothesis that looked right but was not — is where real debugging happens. Pay attention to how the wrong hypothesis still produced useful evidence that narrowed the search.

**Scenario:** A Spring Boot payments API. The QA report states: "Order with items priced at $1.15, $0.70, and $0.25 shows an invoice total of $2.10, but the customer's card is charged $2.09 — a cent short."

The temptation: glance at the code, see a `double` somewhere, change it to `BigDecimal`, and call it done. That might even work. But you would not know whether it is the only cause, why the invoice total and the charged amount disagree, or whether some other money path has the same flaw. Follow the process.

### Step 1: Reproduce

Write the reproduction case before anything else:

```
POST /api/orders
Body: { "items": [{"sku":"A","price":1.15},{"sku":"B","price":0.70},{"sku":"C","price":0.25}] }
Expected: invoice total 2.10, card charged 2.10 (210 cents)
Actual:   invoice total 2.10, card charged 2.09 (209 cents)
```

Run it three times against the local dev server. The charge is $2.09 every time — deterministic, not intermittent. Note the precise discrepancy: the invoice total is correct ($2.10); only the *charged* amount is short. That asymmetry is the most important clue in the report — write it down exactly, do not flatten it to "the total is wrong."

### Step 2: Isolate

Find the boundary:

- Order totaling $3.50 (items $1.00, $2.00, $0.50): invoice $3.50, charged $3.50. Correct.
- Order from the report, totaling $2.10 (items $1.15, $0.70, $0.25): invoice $2.10, charged $2.09. Wrong.
- A different order also totaling $2.10 (items $0.70, $0.70, $0.70): invoice $2.10, charged $2.09. Same symptom.

Two facts emerge. First, the invoice total is correct in every case — so the display/total path is not where the money is lost. Second, the charge breaks for the $2.10 total but not the $3.50 total, and it breaks regardless of which SKUs produce the $2.10. The bug is in the charge path and depends on the total's *value*, not the item count or specific prices. Smallest failing case: any order whose total is $2.10.

### Step 3: First hypothesis

The cent is lost somewhere in the charge path. Two candidates:

1. The payment gateway rounds the amount down on its side.
2. Our code computes the cents amount wrong before sending it.

Start with hypothesis 1: "We send 210 cents and the gateway truncates to 209."

Falsifiable prediction: if the gateway is at fault, the cents value we compute and send should be 210; only the gateway's recorded charge would be 209.

### Step 4: Test first hypothesis

Add a log line where the charge request is built, before it leaves our service:

```java
log.debug("Charging {} cents for order {}", amountInCents, order.getId());
```

Result: the log shows `Charging 209 cents`. We are sending 209, not 210. Hypothesis refuted — the gateway is faithfully charging exactly what we send. The bug is upstream of the gateway, in our own cents conversion.

This is not a failure — refuting a hypothesis is progress. We have eliminated the gateway, the network, and their rounding policy from consideration and localized the bug to one line of our own code: wherever `amountInCents` is computed.

### Step 3 again: Second hypothesis

With the gateway eliminated, the bug is in our cents conversion.

"The order total is held as a `double`, and converting it to an integer number of cents truncates the fractional part instead of rounding."

Falsifiable prediction: the conversion will look like `(long)(total * 100)` with `total` a `double` holding a value microscopically below 2.10. Reproduce in a REPL: sum `1.15 + 0.70 + 0.25` as doubles (→ `2.0999999999999996`), multiply by 100 (→ `209.99999999999997`), cast to `long` (→ `209`).

### Step 4 again: Test second hypothesis

Search `PaymentService.java` for the cents conversion:

```java
double total = order.getItems().stream()
    .mapToDouble(i -> i.getPrice().doubleValue())
    .sum();                                  // 2.0999999999999996
long amountInCents = (long) (total * 100);   // (long) 209.99999999999997 = 209
```

Confirmed. Prices are summed as `double` (producing `2.0999999999999996`, a hair below 2.10), and the cast to cents truncates: `total * 100` is `209.99999999999997`, and `(long)` drops the fraction to `209`. The invoice total looked correct only because the display formatter rounds `2.0999999999999996` to `2.10` for presentation — but the charge path *truncates* instead of rounding, so it loses the cent. Root cause: money held and converted as `double`. Mechanism identified down to the line.

### Step 5: Fix at root cause

Extract the cents conversion into a method that computes the total as `BigDecimal` and converts exactly (this is the `amountInCents` the regression test in Step 7 calls):

```java
long amountInCents(Order order) {
    BigDecimal total = order.getItems().stream()
        .map(Item::getPrice)
        .reduce(BigDecimal.ZERO, BigDecimal::add);     // exactly 2.10
    return total.movePointRight(2).longValueExact();   // exactly 210
}
```

This removes `double` from the money path entirely. The root cause — representing currency as binary floating point — is made impossible, not patched with a rounding heuristic.

Note what we did NOT do:
- We did NOT change `(long)(total * 100)` to `Math.round(total * 100)`. That hides this case but still routes money through `double`, and rounding can bite the other direction (over-charging) on different inputs.
- We did NOT keep the `double` sum and fix only the cast. The sum is already imprecise; fixing only the conversion leaves a latent fault.
- We did NOT add a "+0.001 then truncate" fudge factor. Financial code does not tolerate fudge.

The fix eliminates the entire category of floating-point money error for this path, not just the specific instance in the QA report.

### Step 6: Verify

Run the full verification stack — all three layers:

**Layer 1 — Isolated case:** Order totaling $2.10 ($1.15 + $0.70 + $0.25): `amountInCents` is now 210, card charged $2.10. Correct. (Was 209 before fix.)

**Layer 2 — Original scenario:** The exact reproduction from the QA report — invoice $2.10 and card charged $2.10 (210 cents). The $0.70 × 3 variant also charges 210. The clean $3.50 order still charges 350. No regression.

**Layer 3 — Regression sweep:** Full test suite passes, zero failures, zero skipped.

All three layers are green. The fix can be committed with confidence that it resolves the reported bug without introducing regressions.

### Step 7: Regression test

```java
@Test
void test_order_charged_in_exact_cents() {
    Order order = new Order(List.of(
        new Item("A", new BigDecimal("1.15")),
        new Item("B", new BigDecimal("0.70")),
        new Item("C", new BigDecimal("0.25"))
    ));

    long cents = paymentService.amountInCents(order);

    assertThat(cents).isEqualTo(210L);   // not 209
}
```

Revert the fix temporarily and run the test: it fails with `expected 210 but was 209`. Re-apply the fix: test passes. This confirms the regression test actually catches the bug — a regression test that passes regardless of the fix is worthless.

The test is named after the behavior (the order is charged the exact cents), not the implementation detail (uses BigDecimal). If someone later swaps in a money library, the test still validates correctness because it asserts on the charged amount, not the mechanism.

**Key takeaway from this example:** The wrong first hypothesis (the gateway) was not wasted time — it conclusively eliminated everything outside our service and localized the bug to one line, fast. That is the value of falsifiable hypotheses: even when wrong, they narrow the search. And note where the cent actually hid — the invoice total *looked* correct because display rounding masked an already-imprecise `double`; only the truncating charge path exposed it. A guess-and-patch that "saw a double and switched to BigDecimal" might have landed the same fix, but without isolation it could have missed that the display path relied on the same bad value, and without the regression test it would ship with no guard against recurrence.

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
