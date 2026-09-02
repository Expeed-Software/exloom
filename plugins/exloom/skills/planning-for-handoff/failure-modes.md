# Failure Modes — planning-for-handoff

The failure modes this skill exists to prevent: thought pattern, why it feels right, what actually happens, and the correction.

### 1. "They'll figure it out"

**Thought pattern:** "The executor is a skilled developer, they'll know what I mean by 'handle the error cases.'"

**Why it feels right:** You respect the executor's ability. You do not want to be condescending by spelling out every detail. Over-specifying feels like micromanagement.

**What actually happens:** The executor figures out *something*, but not what you intended. They handle errors by returning 500 with a generic message. You wanted them to return structured error responses matching the existing API contract in `src/shared/errors.ts`. Two days later, code review catches the mismatch and the task is reworked.

**Correction:** Specify every decision. "Handle errors by returning `ApiError` responses matching the pattern in `src/shared/errors.ts:15-30` — include error code, message, and correlation ID." Respecting skill means giving precise requirements, not vague ones.

### 2. "TBD — I'll fill this in later"

**Thought pattern:** "I don't know the exact migration file name yet, I'll fill it in before handoff."

**Why it feels right:** You want to make progress on the plan structure without blocking on details. Filling in TBDs feels like a quick follow-up task.

**What actually happens:** You do not fill it in. The plan ships with TBDs because something urgent came up, or you forgot, or you assumed someone else would resolve them. The executor hits the TBD, guesses, and creates a migration file with a different naming convention than the rest of the project.

**Correction:** Resolve every TBD before marking the plan as ready. If you cannot resolve it now, it means you need more research — do the research or mark the plan as draft. A plan with TBDs is a draft, not a plan.

### 3. "Similar to Task 3"

**Thought pattern:** "This task follows the same pattern as Task 3, so I'll just say 'similar to Task 3' to avoid repetition."

**Why it feels right:** DRY is a good principle in code. Repeating the same instructions in multiple tasks feels wasteful and makes the plan longer.

**What actually happens:** The executor reads Task 7 first because that is where their current work starts. They see "similar to Task 3," scroll up, read Task 3, try to adapt it to the Task 7 context, and miss a critical difference because the similarity is only partial. Plans are not code — they are reference documents read non-linearly.

**Correction:** Repeat the relevant content in every task that needs it. Plans are optimized for executor clarity, not author brevity. If two tasks share a pattern, each task states the full pattern. The plan gets longer. The executor gets faster.

### 4. "Add appropriate error handling"

**Thought pattern:** "The executor knows what good error handling looks like. I don't need to specify every catch block."

**Why it feels right:** You are describing *what* to build, not *how* to build it. Error handling is an implementation detail that a competent developer handles as a matter of course.

**What actually happens:** "Appropriate" means different things to different people. One developer adds try-catch with logging. Another adds retry logic. Another adds circuit breakers. A fourth adds nothing because they think the framework handles it. You get inconsistent error handling across the codebase and a code review that turns into a design discussion.

**Correction:** State the errors, the handling strategy, and the response format. "If the database query fails, catch `DatabaseException`, log the error with correlation ID, and return `ApiError(500, 'EXPORT_FAILED', 'Failed to generate export')`. Do not retry — the caller can retry the request." This is a plan step. "Add appropriate error handling" is not.

### 5. "The plan is too long"

**Thought pattern:** "This plan is 80 lines. Nobody is going to read an 80-line plan. I should shorten it."

**Why it feels right:** You value conciseness. You have seen long documents that nobody reads. Shorter feels more likely to be consumed.

**What actually happens:** You cut details to shorten the plan. You remove the edge cases section because "they're obvious." You compress three tasks into one because "they're related." You drop the FAQ because "the executor can ask if they're stuck." The plan is now 30 lines and looks clean. The executor spends 3 days on what should have been 1 day because every cut detail is a question they need answered.

**Correction:** Long and precise beats short and ambiguous, every time. If the plan feels too long, cut scope — fewer features, smaller deliverable. Do not cut precision. A 100-line plan that the executor can follow without questions is faster to execute than a 30-line plan that generates 15 Slack threads.

There is a real upper bound — a 500-line plan with 40 tasks is probably multiple features crammed into one plan. The solution is not to shorten the plan by removing detail; the solution is to split the plan into multiple plans, each with full precision for a smaller scope. Length is not the problem. Ambiguity is the problem. Cut scope, not clarity.
