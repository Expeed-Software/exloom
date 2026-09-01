# Worked Example — executing-handoff-plans

Extracted from SKILL.md so the skill loads lean. This is a full worked example.


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

Hand to `exloom:auditing-plan-fidelity`, then `/review-complete`.

Key takeaway from this example: the three deviations cover the three handling paths — a mechanical change self-resolved and logged (deviation 1), a codebase pattern that contradicts the plan's assumptions and needs an author decision (deviation 2), and a specification conflict between the plan and existing behavior (deviation 3). Each was logged as its own entry, and all were caught before they became bugs because execution followed the process: read sibling files first, run validation immediately, log before fixing.
