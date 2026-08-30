---
name: reviewing-code
description: Use when reviewing a pull request or someone else's code — applies your org's consistency checklist with severity ratings and flags conflicts with existing repo conventions.
---

# Reviewing Code

## Overview

A code review answers two questions: is the implementation correct, and is it consistent with the rest of the codebase. The reviewer's job is to catch what the author could not — the blind spots that come from having written the code yourself.

This skill applies two mechanisms for consistency across a team: a checklist, so every category gets checked every time regardless of who reviews, and severity ratings, so the author can distinguish a blocking defect (Blocker: "this cannot merge") from a style preference (Nit: "your call entirely"). It covers the review process, severity calibration, output format, reviewing AI-assisted code, and handling disagreements.

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

See [severity-calibration.md](severity-calibration.md).
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

See [handling-disagreements.md](handling-disagreements.md).
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

See [failure-modes.md](failure-modes.md).
## Worked Example

See [worked-example.md](worked-example.md).
## Integration

- **You arrive here from:** A PR assigned to you for review, or when asked to review someone else's code changes.
- **Before starting:** If a plan or design document exists for the work being reviewed, invoke `exloom:auditing-plan-fidelity` before beginning the code review. This separates "did they build what was planned?" from "is what they built correct?"
- **Conventions:** defer to the conventions already established in this repo (and its CLAUDE.md). When a general default and an existing repo pattern conflict, follow the Handling Disagreements section above.
- **Security:** any Blocker-severity security finding should include a specific exploitation scenario, not just a general warning.
- **After review:** Findings that reveal systemic issues — the same mistake appearing across multiple PRs, an unclear convention that causes repeated confusion, a missing guardrail that should be automated — should flow into `exloom:capturing-learnings` so they become team knowledge rather than one-off PR comments.
- **Re-reviews:** When the author pushes fixes, re-review only the changed sections. Do not re-review the full PR unless the fixes touched unrelated code or introduced new concerns. Approve once Blockers and Majors are resolved.
