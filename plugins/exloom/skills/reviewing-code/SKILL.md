---
name: reviewing-code
description: Use when reviewing a pull request or someone else's code — applies your org's consistency checklist with severity ratings and flags conflicts with existing repo conventions.
---

# Reviewing Code

## Overview

A code review is a collaboration between reviewer and author, not a gate where one person proves the other wrong. The reviewer's job is to catch what the author could not — the blindness that comes from having written the code yourself. The author knows the intent; the reviewer brings fresh eyes, knowledge of adjacent systems, and perspective on long-term maintenance. When both sides understand this, reviews become one of the most effective quality tools a team has.

The consistency problem is real and measurable. Without a checklist, reviews are personality-dependent. One reviewer fixates on style. Another cares only about architecture. A third reviews nothing but tests. The result is that the same PR gets meaningfully different scrutiny depending on who draws the review. A checklist does not make reviews mechanical — it makes coverage reliable. Every category gets checked every time, regardless of who reviews.

The severity problem is equally damaging. Without calibration, every comment from a reviewer feels like "you must fix this." Authors cannot distinguish a blocking defect from a style preference, so they either over-react to every comment or learn to ignore them all. Severity ratings solve this by making the reviewer's intent explicit. A Blocker means "this cannot merge." A Nit means "your call entirely." The author's judgment is respected on minor items, and the reviewer's authority is preserved for items that matter.

Reviews are worth the investment only when done consistently and with calibrated severity. A rubber-stamp "LGTM" catches nothing. A review where every comment is a blocker exhausts the author and erodes trust. The goal is the middle ground: thorough, fair, calibrated.

## Process

### Pre-Review

Before reading a single line of code, establish context. Reviewing code you do not understand the purpose of is a waste of both your time and the author's.

1. **Check for a plan.** If this work had a plan or design document, invoke `exloom:auditing-plan-fidelity` first. Plan fidelity answers "did the implementation match what was agreed?" Code review answers "is the implementation correct and consistent?" These are different questions. Running fidelity first means you already know whether deviations are intentional when you start reading code.

2. **Read the PR body.** If the PR description is empty, says "fixed the thing," or contains only a ticket number with no explanation, stop. Request a proper description before reviewing code. You cannot review what you do not understand. A good PR body explains what changed, why it changed, and what the reviewer should pay attention to.

3. **Understand the context.** What ticket does this relate to? What is the user-facing goal? What system does it touch? Open the ticket if needed. Skim the commit history to understand how the author arrived at the current state.

4. **Check PR size.** If the PR exceeds 400 changed lines, request a split before reviewing. Large PRs get shallow reviews — this is not a character flaw, it is a cognitive limit. Research consistently shows that review quality degrades sharply after 200-400 lines. Five 200-line PRs will receive better review than one 1000-line PR. The exception is generated code, large-scale renames, or dependency updates where the diff is mechanical and can be verified structurally rather than read line-by-line.

### Review Time Expectations

Budget real time for reviews. A rushed review is worse than no review — it creates false confidence that someone checked the code.

| PR Size | Expected Review Time | Notes |
|---|---|---|
| Under 100 lines | 10-15 minutes | Quick but still run every checklist category |
| 100-200 lines | 20-30 minutes | The sweet spot — thorough review is feasible |
| 200-400 lines | 30-60 minutes | Attention starts to fade past 30 minutes. Take a break if needed. |
| Over 400 lines | Request a split | Do not attempt a thorough review of 400+ lines in one sitting. You will miss things. |

If you finish a review in under 10 minutes for a non-trivial PR, you skimmed. Go back and run the checklist categories you skipped. If a review takes over an hour, the PR is probably too large — note this in your review comment so the author considers splitting next time.

### During Review — The Checklist

Run every category below. Do not skip categories because the change seems unrelated — a performance-focused change can still introduce a security issue; a UI change can still break an API contract.

As a default, review the tests before the implementation — they tell you what the author thinks the code should do, which frames your understanding of everything else. But read them skeptically, not as ground truth: the tests themselves can be wrong, can assert the buggy behavior, or can test the happy path only. Treat them as the author's stated intent to be verified, not as a correct specification to absorb. For a bug fix, check that the regression test actually fails without the fix before trusting it. If reading the tests first risks anchoring you on a flawed assumption, read the implementation first and come back to the tests with fresh suspicion.

**Correctness** — Does the code do what the PR description and ticket say it should? Do acceptance criteria from the ticket match what is implemented? Are edge cases handled — null inputs, empty collections, boundary values, concurrent access? Are logical conditions correct (off-by-one, inverted predicates, short-circuit assumptions)? Are all code paths reachable and handled? Does the code handle concurrent access correctly if more than one thread or process can reach it? Are there any TOCTOU (time-of-check/time-of-use) issues?

**Tests** — Do tests exist for every new or changed behavior? Do the tests actually verify what they claim (read the assertions, not just the test names)? Do they test the failure path, not just the happy path? Are they testing behavior rather than implementation details? Would these tests catch a naive regression if the implementation were reverted? Is there a regression test if this change was prompted by a bug? Are tests isolated — no dependency on execution order, shared mutable state, or specific external conditions?

**Security** — Is user-supplied input validated and sanitized before use? Are there SQL injection, command injection, path traversal, or XSS vectors? Are secrets, credentials, or PII handled correctly (not logged, not returned to clients, not stored in plain text)? Are authentication and authorization checks at the right boundaries? Does the change expose any new attack surface?

**Performance** — Are there N+1 query patterns? Unbounded loops or collections loaded entirely into memory? Blocking I/O in an async context? Missing timeouts on external calls? Algorithms that are O(n^2) or worse on data sets that could realistically be large? Event listeners or subscriptions that are registered but never cleaned up? Are external service calls appropriately bounded with timeouts and circuit breakers?

**Readability** — Can an engineer unfamiliar with this code understand what it does without reading five surrounding files? Are names accurate and meaningful? Are functions focused on a single responsibility? Do comments explain why, not what? Is dead code removed? Is the happy path easy to follow without getting lost in error handling? Are there code smells: deeply nested conditions, methods longer than they need to be, classes with too many responsibilities?

**Conventions** — Does the code follow the conventions already established in this repo (and its CLAUDE.md)? Does error handling use the standard error envelope? Does logging follow structured conventions with correct levels and correlation IDs? Are new dependencies justified, and do they overlap with something already in the project? Does the code use established shared abstractions (utilities, base classes, platform libraries) rather than reinventing them?

For EACH finding, produce a structured comment using the Review Output Format below.

### Post-Review

Decide based on what you found:

- **Blocker or Major found** — Request Changes. Clearly state which comments are blocking and which are informational. Use the platform's "Request Changes" mechanism so the PR cannot be merged accidentally.
- **Only Minor and Nit findings** — Approve with comments. Do not block the PR on minor items. Use the platform's "Comment" or "Approve" mechanism, not "Request Changes."
- **No findings** — Approve. Say what was done well. Positive feedback is valuable and costs nothing. If the middleware pattern is clean, say so. If the test coverage is thorough, acknowledge it. Positive comments also teach the author which patterns to repeat.
- **If you found nothing, be suspicious.** Did you actually review each checklist category, or did you skim? A PR with zero findings is possible but uncommon for non-trivial changes. Go back and check the category you are least confident about.

When the author pushes fixes for Blocker and Major items: re-review only the changed sections and their immediate context. Do not re-review the entire PR unless the fixes introduced new concerns or touched unrelated code. Outstanding Minor and Nit items do not block approval — they were explicitly marked as non-blocking when you wrote them.

Do not use the approval to signal agreement with every line of code. Use it to signal that the change is safe to merge. Those are different things. You can approve a PR that contains a Minor you wish were fixed. You cannot approve a PR that contains a Blocker.

## Severity Calibration

This section is the single most important section for team consistency. Every review comment must include a severity. This is not optional and not a suggestion — it is a requirement of your org's review process. Untagged comments force authors to guess whether they need to act, which leads to either over-reacting to suggestions or under-reacting to defects. Severity turns implicit expectations into explicit signals.

### Blocker

**Definition:** Merging this will cause a production incident, data loss, security vulnerability, or break existing functionality for users.

**Examples:**
- SQL injection via unsanitized user input in a query
- Authentication bypass — endpoint missing auth middleware
- Infinite loop triggered by a common input
- Data corruption — writing to the wrong table or overwriting existing records
- Breaking change to a public API with no migration path

**Action:** Request Changes. Author MUST fix before merge. No exceptions.

**Not a Blocker:** A style disagreement is never a blocker. An alternative approach that is equally correct is not a blocker. A missing optimization for a code path that handles 10 requests per day is not a blocker. A convention violation, even an important one, is Major at most — conventions are about consistency, not about preventing outages.

### Major

**Definition:** Significant quality issue that will cause real problems — not immediately catastrophic, but bad enough that it should not ship as-is.

**Examples:**
- Missing error handling for a failure mode that will realistically occur (e.g., network timeout on an external call)
- Untested critical path — a new payment flow with no test coverage
- N+1 query pattern in a code path that handles realistic production load
- Convention violation that will actively confuse future developers (e.g., error responses that don't match the standard envelope)
- Missing database migration for a schema change

**Action:** Request Changes. Author should fix.

**Not a Major:** An unlikely edge case that would require adversarial input is not a major unless it is a security vector. A style preference is not a major. A slightly unclear variable name is not a major — that is Minor at most.

### Minor

**Definition:** Worth fixing if easy, but not worth blocking the PR. The code works correctly; this is about making it better.

**Examples:**
- Variable name that is technically accurate but could be clearer
- Missing test for an unlikely edge case
- Style inconsistency with the rest of the file
- A comment that would help future readers understand non-obvious logic
- Missed opportunity to use an existing shared utility

**Action:** Approve with comment. Author decides whether to address it. Respect their judgment.

### Nit

**Definition:** Optional. Author's call entirely. Purely stylistic or preference-level.

**Examples:**
- Formatting preference within the bounds of the style guide
- Synonym preference in a variable name ("fetch" vs. "retrieve")
- Removing a blank line or reordering imports
- An alternative approach that is equally valid

**Action:** Approve with comment. Prefix with "Nit:" so the author knows immediately. Never request changes for a Nit.

**Not a Nit:** If the alternative approach would prevent a real problem, it is Minor or Major, not Nit. Nit is reserved for genuinely equivalent alternatives.

### Calibration Rule

If you are about to mark something Major and the author pushes back, ask yourself honestly: "Would I block this PR over this single item?" If the answer is no, it is Minor, not Major. Severity is about merge decisions, not about how strongly you feel. If you would not actually block the merge, do not use a severity that blocks the merge.

A second calibration check: count your Blockers and Majors. If a 200-line PR has more than 2-3 blocking items, either the code has fundamental problems that warrant a conversation (not 15 inline comments), or you are over-calibrating severity. Step back and ask whether a higher-level comment would be more effective than annotating every line.

## Review Output Format

Every review comment follows this structure. Consistency in format makes reviews scannable — the author can quickly identify severity and category without reading the full text of every comment.

```
**[Severity]** [Category]
File: `path/to/file.ext:line`

[What is wrong — observation, not judgment]

Suggestion: [specific fix, alternative, or question]
```

**Example — Blocker:**
```
**[Blocker]** Security
File: `src/api/users.controller.ts:47`

The `userId` parameter is concatenated directly into the SQL query string. This is a SQL injection vulnerability that is exploitable with any crafted input.

Suggestion: Use a parameterized query: `db.query("SELECT * FROM users WHERE id = $1", [userId])`.
```

**Example — Major:**
```
**[Major]** Tests
File: `src/services/payment.service.ts:89`

The `processRefund` method has no test coverage. This is a financial operation where a regression could cause incorrect refund amounts.

Suggestion: Add tests covering: successful refund, partial refund, refund exceeding original amount (should reject), and refund on an already-refunded transaction.
```

**Example — Nit:**
```
**[Nit]** Readability
File: `src/middleware/auth.ts:23`

`checkAuth` could be `requireAuthentication` for consistency with the other middleware names in this directory (`requireAdmin`, `requireScope`).

Suggestion: Rename to `requireAuthentication` if you agree it reads better in context.
```

Line references are required for all file-specific comments. "There is a SQL injection somewhere" is not actionable. "Line 47, SQL injection via string concatenation in query" is. Suggestions or questions are required for all Blocker and Major comments — do not tell the author there is a problem without giving them at least a direction for resolution.

## Reviewing AI-Assisted Code

A growing portion of PRs contain code written or assisted by AI tools (Claude Code, Copilot, etc.). AI-generated code requires different review attention — not more scrutiny, but attention to different failure modes than human-written code.

**What AI code gets right:** Syntax, formatting, boilerplate, standard patterns, consistent naming. Do not spend review time on these — they are almost always correct.

**What AI code gets wrong — watch for these:**

- **Plausible but incorrect logic.** AI code reads well and looks professional, which makes bugs harder to spot. Read the actual logic, not just the structure. A function that "looks like it handles pagination correctly" may have an off-by-one error in the boundary condition that a human would have caught through manual testing.
- **Unnecessary abstractions.** AI tends to over-engineer — adding strategy patterns, factory methods, and builder classes where a simple function would do. Ask: "Does the complexity of this abstraction earn its keep, or would a simpler approach be equally correct and easier to maintain?"
- **Unfamiliar dependencies.** AI may introduce libraries the team has never used, especially when a project dependency already covers the same use case. Check new `import` statements against the existing dependency list.
- **Hallucinated APIs.** AI occasionally calls methods or uses configuration options that do not exist in the version of the library the project uses. Verify that imported functions and method signatures match the actual dependency version.
- **Missing edge cases despite clean happy paths.** AI-generated tests often cover the happy path thoroughly but miss error paths, boundary conditions, and concurrent access scenarios. Check whether the tests actually stress the failure modes.
- **Generic rather than project-specific patterns.** AI defaults to textbook patterns rather than the conventions established in this specific codebase. Check whether the new code matches existing patterns in sibling files.

The review checklist is the same for AI and human code. The difference is where to focus your limited attention.

## Handling Disagreements

Disagreements during code review are normal, expected, and healthy. The way they are handled determines whether the review process builds trust or erodes it over time. A team that handles disagreements well produces better code than a team where the reviewer always wins or the author always capitulates.

**Author pushes back on a Blocker** — A Blocker requires evidence, not authority. If the author disagrees that it is a production risk, discuss the specific scenario. Provide evidence: a reproduction path, a realistic input that triggers the issue, a code path that leads to the failure. If you cannot demonstrate the risk concretely, reconsider the severity — perhaps it is Major, not Blocker. If you still disagree after discussion, bring in a third person familiar with the system. Do not escalate to a stronger position out of frustration.

**Author pushes back on a Major** — Discuss. If you cannot reach agreement, get a third opinion from someone familiar with the system. Do not let disagreement on a Major stall the PR for days. Timebox the discussion.

**Author pushes back on a Minor or Nit** — Accept. Minor and Nit are explicitly defined as "author's call." If you find yourself arguing for a Minor, you have mis-calibrated the severity. Either upgrade it to Major with a concrete justification, or let it go.

**Convention conflict (your org's default vs. existing repo pattern)** — Flag the conflict explicitly. Do not silently enforce one over the other. Brownfield code wins by default — existing repo conventions take precedence over your org's defaults unless there is a specific reason to migrate. Ask which convention should win for THIS repository. Document the decision in the repo's `CLAUDE.md` under a conventions section so the same conflict is not re-litigated in every future PR. This is especially important for error handling patterns, logging conventions, test structure, and API response formats.

**Philosophical disagreement** — A PR comment thread is not the place to debate whether the team should use Result types instead of exceptions. If the review surfaces a genuine architectural question, take it to a team discussion. Do not hold the PR hostage to a design philosophy debate. The author should not be penalized for following the current convention while the team decides on the next one.

**Tone** — Review comments are written communication, which lacks vocal tone and facial expression. What you intend as helpful can read as condescending. Write observations, not judgments. "This does not handle the timeout case" is an observation. "You forgot to handle timeouts" implies carelessness. The difference matters over hundreds of reviews.

## Decision Points

Use this table as a quick reference for common review situations. The full reasoning for each is covered in the sections above.

| Situation | Decision |
|---|---|
| PR body is empty or vague | Request a proper description before reviewing code |
| PR exceeds 400 changed lines | Request a split. Smaller PRs get better reviews. |
| All findings are Minor or Nit | Approve. Do not block on minor items. |
| One Blocker among many nits | Request Changes for the Blocker only. PR is approvable after fixing that one item. |
| Author's approach differs from yours | Different is not wrong. Only flag if there is a concrete problem. |
| Same issue appears in 5+ places | Comment once with full detail, then note "same pattern in N other locations." Do not spam. |
| You are unsure if something is a bug | Ask as a question: "Is this intentional? It looks like X could happen when Y." |
| PR touches code you do not understand | Say so. Ask the author to explain. Do not pretend to review code you cannot evaluate. |
| Author is more senior than you | Review anyway. Seniority does not make code immune to bugs. Be respectful, be specific, be confident. |
| Test coverage is missing entirely | Major. New behavior without tests is a regression waiting to happen. |
| You spot the same bug you saw last month | Flag it, then consider whether this should become a `capturing-learnings` item or a lint rule. |
| Code works but is hard to understand | Minor for readability. If understanding requires tribal knowledge, the code needs comments or better structure. |
| New dependency is introduced | Check if the project already has a library that does the same thing. Check license compatibility. Flag as Minor if redundant. |

## Failure Modes

These are the five most common ways reviews fail. Each one feels reasonable in the moment, which is exactly why they persist. Recognizing the thought pattern is the first step to correcting it.

### 1. "Looks good to me" (LGTM without reading)

**Thought pattern:** "I trust this author. They know what they are doing. I will skim the diff and approve."

**Why it feels right:** The author has a good track record. The PR is from a senior engineer. You are busy with your own work.

**What happens:** The review catches nothing because it examined nothing. A subtle bug ships. When it surfaces in production, the review history shows an approval with no substantive comments, which undermines confidence in the entire review process.

**Correction:** Run every checklist category. If you genuinely cannot find issues after a thorough review, that is fine — approve and note what was done well. But "I looked and found nothing" is fundamentally different from "I did not look."

### 2. "Every comment is a blocker"

**Thought pattern:** "This code has problems and the author needs to fix all of them before merge."

**Why it feels right:** You care about quality. Every issue you found is real. Why would you not want them all fixed?

**What happens:** Authors stop taking your reviews seriously. When everything is critical, nothing is. The author cannot distinguish your actual blockers from your preferences, so they either fix everything resentfully or push back on everything defensively. Review cycles become adversarial.

**Correction:** Use severity ratings honestly. Ask yourself for each comment: "Would I block the merge over this alone?" If no, it is not a Blocker or Major. Your preferences are valid as Minor or Nit — they just should not block a merge.

### 3. "I would have done it differently"

**Thought pattern:** "This works, but I would have used a different pattern / library / structure. I should mention it."

**Why it feels right:** You have experience with an approach that you believe is better. Sharing knowledge is part of the review process.

**What happens:** The author receives feedback that amounts to "rewrite this my way" with no concrete problem identified. If the reviewer cannot articulate a specific issue (performance, correctness, maintainability, readability), the comment is a preference, not a finding.

**Correction:** Before commenting on an alternative approach, ask: "What concrete problem does the current approach cause?" If you cannot answer that, the comment is a Nit at best. Frame it as "Have you considered X? It might help with Y" rather than "This should be X."

### 4. "I will review the tests later"

**Thought pattern:** "Let me focus on the implementation first. I will circle back to the tests."

**Why it feels right:** The implementation is the "real" code. Tests are supporting artifacts. You want to understand the logic before evaluating the tests.

**What happens:** You never go back. Or you review the tests superficially because you have already spent your review energy on the implementation. The tests — which are the most important part of the review because they document intended behavior and catch regressions — get the least attention.

**Correction:** Review the tests as part of the same pass as the implementation, not as an afterthought — by default, before the implementation, so they frame your understanding. But scrutinize them rather than trusting them: confirm they assert real behavior, cover failure paths, and would actually catch a regression. The tests are the author's claim about correctness; your job is to verify the claim, not accept it.

### 5. "The PR is too big to review carefully"

**Thought pattern:** "This is 1500 lines. I will do my best to review it all."

**Why it feels right:** The author already wrote it. Asking them to split it feels like creating more work. You do not want to be the bottleneck.

**What happens:** You review the first 300 lines carefully and skim the rest. Critical issues in the later files are missed. The review provides a false sense of security — the approval suggests thorough review, but coverage was shallow.

**Correction:** Request a split. A 1500-line PR reviewed shallowly is worse than five 300-line PRs reviewed thoroughly. This is not about being difficult — it is about being honest that humans cannot maintain review quality over large diffs. The request to split is itself a valuable review comment. If the author says "it cannot be split," discuss it — most PRs can be split into a refactoring PR followed by a feature PR, or split by layer (data access, business logic, API surface).

## Worked Example

This example walks through a complete review from pre-review through post-review decision, demonstrating severity calibration across five findings.

**Scenario:** A PR adds rate limiting to a Node.js Express API. The PR body says: "Adds rate limiting middleware to prevent abuse. Limits to 100 requests per minute per IP. Closes PROJ-4521." The PR modifies 4 files: the middleware itself, its test file, the route registration, and a constants file.

### Pre-Review

1. **Read the PR body.** Present and clear: explains the feature, the limit (100/min/IP), and links to PROJ-4521. Good — no need to request a better description.
2. **Check for a plan.** PROJ-4521 is a small feature ticket with acceptance criteria but no formal design plan. No need to run `auditing-plan-fidelity`.
3. **Check PR size.** 180 lines changed across 4 files (middleware, test, route registration, config). Well within the 400-line threshold.
4. **Understand context.** The API is a Node.js Express service running behind a load balancer with 4 instances. This context is critical — it affects how stateful middleware like rate limiting must work.

### During Review

Start with the test file to understand what the author expects the middleware to do. Then review the middleware implementation against both the tests and the checklist. Reviewing against the checklist, five findings emerge across three severity levels:

**Finding 1 — Blocker (Correctness):**
```
**[Blocker]** Correctness
File: `src/middleware/rateLimit.ts:15`

The rate limit counter is stored in an in-process `Map<string, number>`. This application runs behind a load balancer with 4 instances. Each instance maintains its own counter, so a client can make 400 requests per minute (100 per instance) before being limited. Under a targeted attack, a single client rotates across instances and is never rate-limited.

Suggestion: Use a shared store (Redis is already in the project dependencies). Replace the in-memory Map with a Redis-backed counter using `INCR` with `EXPIRE`. The existing `src/lib/redis.ts` client can be reused.
```

**Finding 2 — Major (Tests):**
```
**[Major]** Tests
File: `src/middleware/__tests__/rateLimit.test.ts:42`

The test verifies that a 429 response is returned, but does not check the response body format. The project's error envelope expects `{ error: { code: string, message: string } }`, but the rate limiter returns `{ message: "Too many requests" }`. This means clients parsing the standard error envelope will get `undefined` for `error.code`, which will cause downstream error handling to break.

Suggestion: Update the rate limiter to return the standard error envelope: `{ error: { code: "RATE_LIMIT_EXCEEDED", message: "Too many requests. Retry after {retryAfter} seconds." } }`. Add a test assertion on the response body structure.
```

**Finding 3 — Minor (Conventions):**
```
**[Minor]** Conventions
File: `src/middleware/rateLimit.ts:8`

The rate limit threshold is hardcoded as `const MAX_REQUESTS = 100`. Other operational thresholds in this project (connection pool size, timeout durations, batch sizes) are externalized to `config/default.yml`. A hardcoded threshold means a limit change requires a code deployment.

Suggestion: Move to `config/default.yml` under `rateLimit.maxRequests` and read via the existing `config.get()` pattern used elsewhere in the project.
```

**Finding 4 — Minor (Conventions):**
```
**[Minor]** Conventions
File: `src/middleware/rateLimit.ts:31`

The error code returned is `RATE_LIMITED`, but the existing error codes in `src/constants/errorCodes.ts` use the pattern `RATE_LIMIT_EXCEEDED` for this scenario (it appears in a comment as a planned code). Using a different format creates an inconsistency that clients must handle as a special case.

Suggestion: Use `RATE_LIMIT_EXCEEDED` to match the existing pattern in `errorCodes.ts`.
```

**Finding 5 — Nit (Readability):**
```
**[Nit]** Readability
File: `src/middleware/rateLimit.ts:5`

The function is named `checkLimit`. The other middleware functions in this directory follow the verb pattern `requireAdmin`, `requireScope`, `validateBody`. `enforceRateLimit` would be more consistent and more descriptive of what the middleware actually does (it enforces, it does not just check).

Suggestion: Rename to `enforceRateLimit` if you agree it reads better alongside the existing middleware names.
```

### Post-Review Decision

**Decision:** Request Changes. One Blocker (in-memory counter will not work in a multi-instance deployment) and one Major (error response format mismatch). The remaining findings are Minor and Nit — author's call on those.

**Summary comment on the PR:**

> Requesting changes for two items. The rate limit counter needs a shared store (Blocker — the in-memory Map will not work across your 4 instances), and the error response needs to match the standard envelope format (Major — clients parsing the envelope will get undefined fields). The config externalization and error code consistency are minor — your call. Nice work on the middleware pattern overall; it is clean, well-separated, and the retry-after logic is solid.

**Positive feedback:** The middleware pattern is clean — single responsibility, well-separated from route handlers, and the retry-after header calculation is correct and well-tested. Good use of the existing middleware chain pattern. Acknowledging what was done well is not politeness — it tells the author which patterns to keep using.

## Integration

- **You arrive here from:** A PR assigned to you for review, or when asked to review someone else's code changes.
- **Before starting:** If a plan or design document exists for the work being reviewed, invoke `exloom:auditing-plan-fidelity` before beginning the code review. This separates "did they build what was planned?" from "is what they built correct?"
- **Conventions:** defer to the conventions already established in this repo (and its CLAUDE.md). When a general default and an existing repo pattern conflict, follow the Handling Disagreements section above.
- **Security:** any Blocker-severity security finding should include a specific exploitation scenario, not just a general warning.
- **After review:** Findings that reveal systemic issues — the same mistake appearing across multiple PRs, an unclear convention that causes repeated confusion, a missing guardrail that should be automated — should flow into `exloom:capturing-learnings` so they become team knowledge rather than one-off PR comments.
- **Re-reviews:** When the author pushes fixes, re-review only the changed sections. Do not re-review the full PR unless the fixes touched unrelated code or introduced new concerns. Approve once Blockers and Majors are resolved.
