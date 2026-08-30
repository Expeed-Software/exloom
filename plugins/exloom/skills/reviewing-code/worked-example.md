# Worked Example — reviewing-code

Extracted from SKILL.md so the skill loads lean. This is a full worked example.


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
