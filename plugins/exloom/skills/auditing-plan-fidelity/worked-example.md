# Worked Example — auditing-plan-fidelity

One audit taken through every step.

**Scenario:** Auditing the plan for "Add rate limiting to the payments API" (Node.js Express backend) after execution. The plan was agreed before execution, specified 4 files in its "Files to Touch" section, listed 3 acceptance criteria, and was executed on the `feature/rate-limiting` branch. The executor ran `exloom:executing-handoff-plans` and populated the Deviation Log with 2 entries.

We will walk through all 4 audit steps and arrive at a verdict.

### Step 1: File Audit

Plan's "Files to Touch" listed:
- `src/middleware/rate-limiter.ts` [new]
- `src/routes/payments.ts` (modify — wire middleware)
- `src/config/app-config.ts` (modify — add rate limit settings)
- `tests/middleware/rate-limiter.test.ts` [new]

Actual files changed (`git diff --name-only <base>...HEAD`, where `<base>` resolved to `main` for this repo):
- `src/middleware/rate-limiter.ts` (new)
- `src/routes/payments.ts` (modified)
- `src/config/app-config.ts` (modified)
- `src/config/rate-limits.ts` (new) — NOT in plan
- `tests/middleware/rate-limiter.test.ts` (new)

Categorization:
- `src/middleware/rate-limiter.ts` — Planned [new] + Created = **expected**
- `src/routes/payments.ts` — Planned [modify] + Modified = **expected**
- `src/config/app-config.ts` — Planned [modify] + Modified = **expected**
- `tests/middleware/rate-limiter.test.ts` — Planned [new] + Created = **expected**
- `src/config/rate-limits.ts` — NOT in plan + Created = **drift**

Result: 4 files planned+changed (expected). 0 files planned+unchanged. 1 file unplanned+changed (drift). Check deviation log for the unplanned file: Deviation #1 says "Extracted rate limit constants to dedicated config file for reusability across future endpoints." Logged and justified — this drift is accounted for.

### Step 2: Acceptance Criteria Verification

Criterion 1: "Rate limiting returns HTTP 429 when threshold exceeded."
Status: **Verified.** Diff shows `rate-limiter.ts` returns `res.status(429).json({ error: 'Rate limit exceeded' })`. Test file includes assertion for 429 response.

Criterion 2: "Rate limit state uses Redis for multi-instance support."
Status: **Deviated.** Diff shows rate limiter uses an in-memory `Map` with TTL, not Redis. Check deviation log: not logged. This is silent drift on a core acceptance criterion.

Criterion 3: "Rate limit window resets after 60 seconds."
Status: **Unverified.** The diff shows a `windowMs: 60000` config value, which suggests 60-second windows, but actual reset behavior depends on runtime timing. Needs manual test with timed requests.

### Step 3: Deviation Log Review

The executor's deviation log contains 2 entries:
- Deviation #1: "Extracted rate limit config to `src/config/rate-limits.ts`." Justification: "Keeps rate limit constants separate for reuse when we add rate limiting to other endpoints." Complete and justified.
- Deviation #2: "Used TypeScript strict mode for new files." Justification: "Existing `tsconfig.json` has strict enabled; new files follow existing convention." Complete and justified.

Missing: the Redis-to-memory change is not in the deviation log. This is a significant unlogged deviation — it affects a core acceptance criterion (multi-instance support) and changes the operational characteristics of the feature.

### Step 4: Verdict

**FAIL.** One unlogged deviation: acceptance criterion #2 (Redis for multi-instance support) was silently changed to in-memory storage. This affects production behavior and was not recorded.

Blockers before code review can proceed:
1. The executor must add a deviation log entry explaining why Redis was dropped and what triggered the decision during implementation.
2. The team must confirm whether in-memory rate limiting is acceptable for the deployment topology (single instance vs. multi-instance).
3. If in-memory is not acceptable, the executor must implement Redis as originally planned.
4. Re-run this audit after the deviation log is updated or the implementation is corrected.

Note what a Pass would have looked like here: if the executor had logged "Dropped Redis in favor of in-memory Map because the staging environment has no Redis instance and the rate limiter needs to work in local dev. Will revisit for production multi-instance deployment," that would be a complete deviation log entry. The verdict would shift to Pass with notes, and the reviewer would know to evaluate the tradeoff rather than discovering it by accident in the diff.
