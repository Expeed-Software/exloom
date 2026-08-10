---
name: planning-for-handoff
description: Use when you have a spec or requirements for a multi-step task — produces a handoff-ready plan that someone other than the author can execute without ambiguity.
---

# Planning for Handoff

## Overview

A plan is a contract between two people: the author who understands the problem and the executor who will solve it.

The test is simple and absolute: hand your plan to a skilled developer who has never seen this codebase. Can they execute it start to finish without sending you a single Slack message? If the answer is no, the plan is not done.

Even if you are executing your own plan — solo path, no handoff — the same rigor applies. Future-you does not remember why you chose that approach, which file had the pattern you wanted to follow, or what edge cases you considered and dismissed. Write every plan as if the executor is a stranger.

## Process

Follow these 9 steps in order. Do not skip steps — each one exists because skipping it causes specific, predictable failures described in the Failure Modes section below.

**Where the plan lives.** Save the plan where this repo keeps plans: if the repo's CLAUDE.md (or the user) specifies a location — e.g. `.claude/plans/current.md` — use that; otherwise default to `docs/exloom/plans/YYYY-MM-DD-<topic>-plan.md`. Commit it so it is reviewable and so `exloom:reviewing-plans`, `exloom:executing-handoff-plans`, and `exloom:auditing-plan-fidelity` can find it.

### Step 1: Start from a spec

**What to do.** Confirm you have a spec or design document before writing the first line of the plan. If no spec exists, stop and invoke `exloom:brainstorming` to produce one.

**How to do it well.** A spec answers "what are we building and why." A plan answers "how do we build it, in what order, with what validation." These are different documents solving different problems. The spec should give you acceptance criteria, constraints, and non-goals before you start sequencing work. If the spec is a vague paragraph, push back — a plan built on a vague spec inherits every ambiguity and amplifies it across tasks. A plan without a spec is guessing with structure. The spec does not need to be a 20-page document — even a focused half-page from brainstorming that nails the requirements, constraints, and boundaries is sufficient. What matters is that the design decisions are made before you start sequencing implementation.

**What bad looks like.** Jumping straight to task lists without a spec. You end up discovering requirements mid-plan, rewriting tasks, and shipping a plan that is really a draft design disguised as an execution guide. The executor inherits your confusion. Another variant: the spec exists but is a single paragraph of vague intent — the plan author fills in the design gaps implicitly, embedding design decisions inside task descriptions where nobody reviews them as design decisions.

### Step 2: Write acceptance criteria first

**What to do.** Before writing any tasks, write the observable, testable outcomes that define "done." These go at the top of the plan.

**How to do it well.** Every criterion must be verifiable by the executor without asking the author what they meant. "Users can log in" is not testable — testable by whom, using what, expecting what response? "POST `/auth/login` with valid credentials returns 200 with a JWT containing `sub`, `exp`, and `role` claims" is testable. An executor can write that test without any additional context. Aim for 4-8 criteria. If you have more than 10, your scope may be too large for a single plan.

**What bad looks like.** Vague outcomes like "the feature works" or "performance is acceptable." Criteria that require the author's interpretation to verify. Criteria that describe activities ("we refactored the service") instead of outcomes ("the service responds in under 200ms at p95"). Acceptance criteria that only the author can check — "the architecture is clean" — are not acceptance criteria, they are opinions.

### Step 3: Write non-goals explicitly

**What to do.** List what this plan deliberately does NOT cover. Be specific — name the features, optimizations, or integrations you are excluding.

**How to do it well.** Non-goals prevent scope creep during execution. "This plan does NOT add email notifications for CSV exports" is clear. Silence on email notifications is ambiguous — the executor might add it because it seems like an obvious next step. Non-goals protect the executor from well-intentioned overbuilding and protect the author from unreviewed scope expansion. Write 3-5 non-goals. If you cannot think of any, you have not thought hard enough about adjacent features.

**What bad looks like.** No non-goals section at all. Non-goals that are so obvious they add no information ("This plan does not rewrite the entire application"). Non-goals that are actually deferred goals disguised as exclusions — if you plan to do it next sprint, say that explicitly. The most dangerous failure: omitting non-goals entirely, which means every adjacent feature is implicitly in scope. The executor adds email notifications because "it seemed like the obvious next step," and now you have unreviewed, untested scope expansion in your branch.

### Step 4: Identify files to touch

**What to do.** List every file the executor will create or modify. One line per file: exact path and a short reason.

**How to do it well.** Run the codebase search yourself. Open the files. Confirm the line ranges. "Modify `src/services/order-service.ts:45-60` — add discount calculation to the `calculateTotal` method" tells the executor exactly where to look. For new files, state the full path and what the file contains. For deletions, state the path and why it is safe to remove. This list is the executor's map — if the map is wrong, they wander. A good file list also reveals the blast radius of the plan — how many files, how many modules, how many teams' code you are touching. If the list is 15+ files across 4 modules, the plan may need to be split.

**What bad looks like.** "Update the relevant service file." "Add a test for this." "Modify the config as needed." These are not file references. They are homework assignments for the executor to figure out what you meant. Also bad: listing a directory instead of a file ("update something in `src/services/`") — the executor still has to figure out which file.

### Step 5: Identify existing patterns

**What to do.** Read the existing codebase and show the executor what patterns to follow. Point to specific files and describe the pattern.

**How to do it well.** This is the brownfield enforcement mechanism. Most work happens in existing codebases with existing conventions. "See `src/services/user-service.ts` for the pattern: constructor injection, repository interface, service method returns `Result<T>` not raw values" gives the executor a concrete reference. They read that file, understand the convention, and replicate it. Without this, every executor invents their own pattern, and the codebase diverges with every plan.

**What bad looks like.** No mention of existing patterns. Assuming the executor will discover conventions by reading the entire codebase. Describing a pattern in prose without pointing to a concrete example file — "use dependency injection" could mean constructor injection, setter injection, or a service locator depending on who reads it. Point to the file. Let the code speak.

### Step 6: Enumerate edge cases

**What to do.** For every major operation in the plan, ask: what if the input is null? Empty? Enormous? What if two requests hit this concurrently? What if the external service is down? What if the database is slow?

**How to do it well.** List each edge case and make a decision: handle it (with specifics) or mark it explicitly out of scope. "Empty result set: return CSV with headers only, no rows" is a decision. "100k rows: use streaming response, do not buffer in memory" is a decision. "Concurrent exports by the same user: out of scope for v1, stateless endpoint means no conflict" is an explicit scope boundary. An edge case without a decision next to it is a bug waiting to happen during execution.

**What bad looks like.** No edge cases section. A single bullet saying "handle errors appropriately." Edge cases listed without decisions — the executor sees the question but not the answer, and now they are making design decisions that belong in the spec. Another failure: listing only the happy-path edge cases (empty input) while ignoring the dangerous ones (concurrent writes, partial failures, resource exhaustion).

### Step 7: Write the executor FAQ

**What to do.** Anticipate the questions the executor will ask and answer them in the plan.

**How to do it well.** Think about what is obvious to you but would not be obvious to someone picking this up cold. "Q: Should I use the existing migration tool or write a new one? A: Use Flyway, same as the auth service — see `db/migrations/` for the naming convention." "Q: What format for the date column in the export? A: ISO 8601, same as the API response format." These are the questions that would otherwise become Slack messages at inconvenient times. Write 3-6 FAQ items. If you cannot think of any, you are too close to the problem — ask a teammate what they would wonder. Good FAQ items often emerge from the edge cases and non-goals sections — if you made a non-obvious decision there, the executor will want to know why.

**What bad looks like.** No FAQ section. An FAQ that answers questions nobody would ask ("Q: Should I use a computer? A: Yes."). An FAQ that references external documents without quoting the relevant part — "see the wiki" is not an answer, it is a scavenger hunt. An FAQ written after the executor already asked the questions — at that point you have already failed, the FAQ was supposed to prevent the interruption.

### Step 8: Write tasks

**What to do.** Break the work into bite-sized tasks. Each task should be a single atomic change — one logical unit of work, one validation step, one commit — and be self-contained.

**How to do it well.** Each task needs four things: (1) files involved with exact paths, (2) what to do in concrete terms, (3) a validation step with the command to run and the expected output, (4) a commit message. Show code snippets where code is needed — do not describe code in prose when you can show it. Show commands with expected output so the executor knows they did it right. Write tasks as if the executor may read them out of order — do not rely on "as we did in Task 3." Repeat context where needed. The validation step is non-negotiable — it is the executor's proof that the task is complete. "Run `pytest tests/api/test_export.py -v` and confirm all 5 tests pass" is a validation step. "Make sure it works" is not. For any task that implements business logic (calculations, validation, branching, state changes), the validation step must be an **automated test**, not a manual check or a build/curl — "run `pytest …` and confirm N tests pass," not "curl the endpoint and eyeball the response." A manual or build-only check is acceptable only for pure wiring with no logic (e.g., a button renders, a module imports). Specifying "validation = build + curl" for logic is exactly how the test discipline gets silently skipped at execution time. And order it **test-first**: a business-logic task is "write the failing test, then implement until it passes" — the test comes before the code, in the same task. Do NOT split "implement X" into one task and "test X" into a later task; tests deferred to the end is how TDD silently becomes test-after, or never. (Pure wiring with no logic is the exception.)

**What bad looks like.** Tasks that take 30 minutes and contain multiple unrelated changes. Tasks with no validation step — the executor finishes and has no idea if it worked. Tasks that say "similar to above" instead of repeating the relevant information. Tasks described entirely in prose when a 5-line code snippet would eliminate all ambiguity. Tasks that mix infrastructure changes with application changes — "update the database schema and add the API endpoint" is two tasks in two different systems with two different validation steps.

### Step 9: Self-review

**What to do.** Before declaring the plan done, run three checks: placeholder scan, type consistency check, and spec coverage check.

**How to do it well.** Placeholder scan: search for "TBD", "TODO", "appropriate", "relevant", "as needed", "similar to" — these are all plan failures hiding in plain text. Replace every one with a concrete value or decision. Type consistency: verify that function names, variable names, file paths, and API routes are identical across all tasks that reference them. A function called `exportOrders` in Task 2 and `export_orders` in Task 5 will confuse the executor — pick one and use it everywhere. Spec coverage: walk through every requirement in the spec and confirm at least one task addresses it. Requirements without tasks are forgotten scope. Tasks without a corresponding spec requirement are scope creep — either add the requirement to the spec or remove the task.

**What bad looks like.** Shipping the plan without a self-review pass. Leaving "TBD" placeholders with the intention of filling them in later — you will not. Finding inconsistencies after the executor has already started, forcing rework. A particularly insidious failure: the function is called `exportOrders` in the plan text but `export_orders` in the code snippet three tasks later. The executor follows the code snippet (correct instinct) but then the tests reference `exportOrders` and nothing wires up.

## Acceptance Criteria Are Not Optional

The acceptance criteria section is the single most important part of the plan. Without it, the executor has no way to know when they are done — and neither does the reviewer.

Good acceptance criteria share three properties:

1. **Observable** — you can see the result without reading the code. "The endpoint returns a 200" is observable. "The code is well-structured" is not.
2. **Testable** — you can write an automated test or a manual verification step that produces a pass/fail answer. "POST `/api/orders/export` returns `text/csv` content type" can be tested with a single curl command.
3. **Author-independent** — anyone can verify the criterion without asking the plan author what they meant. If the criterion requires interpretation, it is not a criterion — it is a wish.

Write criteria before tasks. This ordering is deliberate. Criteria constrain the tasks — every task exists to satisfy a criterion, and every criterion must have at least one task that satisfies it. If you write tasks first, you end up with tasks that serve no criterion (scope creep) or criteria that no task addresses (forgotten scope).

A plan with strong acceptance criteria and mediocre tasks is recoverable — a skilled executor can figure out the tasks. A plan with great tasks and weak acceptance criteria is dangerous — the executor delivers something polished that was not what anyone needed.

Common mistakes with acceptance criteria:

- Writing criteria after tasks (inverted order — you end up with criteria that describe what you built, not what you needed)
- Mixing acceptance criteria with implementation details ("Use the `csv` module" is an implementation choice, not an acceptance criterion)
- Omitting performance criteria when they matter ("Handles 100k rows without timeout" is a criterion. Discovering it should have been after shipping is a postmortem.)
- Writing criteria the executor cannot verify without access to production data or systems they do not have

## File Paths Always Exact

Vague file paths are plan failures. Every time you write "update the relevant service" instead of a real path, you are asking the executor to do detective work that you already did (or should have done). The executor should never need to search the codebase to find where your plan applies.

Bad examples — these are not file references, they are riddles:
- "update the relevant service file"
- "add a test for this"
- "modify the configuration"
- "update the frontend component"

Good examples — the executor opens the file and starts working:
- "Modify `src/services/order-service.ts:45-60` — add discount calculation to `calculateTotal`"
- "Create `tests/services/test_order_service.py::test_discount_calculation`"
- "Add export button template to `frontend/src/app/orders/orders.component.html:28` after the filter bar div"
- "Update `backend/app/core/config.py:12` — add `CSV_EXPORT_MAX_ROWS` with default `100000`"

If you do not know the exact path, stop and find it. Open the codebase, search, confirm. "TBD" in a file path means the plan is not ready for handoff. Ship it with TBDs and the executor will guess — and they will guess differently than you would have.

For new files, the path is a design decision — state it explicitly and explain the placement: "Create `backend/app/services/order_export.py` — placed in services because it contains business logic, not in api because it does not handle HTTP concerns." For modifications, include line numbers or function names so the executor does not have to read the entire file to find the insertion point.

## Tasks Must Be Bite-Sized

Each task should be one atomic change the executor can complete, validate, and commit in a single focused sitting. The size signal is atomicity, not a stopwatch — one logical change with one validation step. (As a rough feel, that is often on the order of minutes, not an afternoon; do not treat any specific minute count as a rule.) This is a forcing function against hidden ambiguity: if a task sprawls into many unrelated changes, it contains decisions the author did not make, edge cases the author did not address, and complexity the author did not decompose.

The smell test: if a task bundles *unrelated* concerns, split it. The signal is not the literal word "and" — it is whether the parts belong to the same coherent increment. "Add the export endpoint and write the streaming logic" is two tasks (two distinct units of backend logic, each independently testable). "Add the database migration and add the API endpoint" is two tasks (two systems, two validation steps). But "add the export button and its click handler" is *one* task — a button with no handler does nothing, so the increment is the button-plus-handler together, validated as one behavior (clicking downloads a file). Ask: does splitting produce two independently valid, independently testable units? If yes, split. If one half is meaningless without the other, it is one task.

Each task needs exactly four things:

1. **Files involved** — exact paths, not descriptions
2. **What to do** — concrete changes, code snippets where helpful
3. **Validation step** — a command the executor runs and the output they expect to see
4. **Commit message** — so the git history reads as a coherent narrative

Small tasks also make code review easier. A reviewer can approve a 15-line diff in 2 minutes. A reviewer staring at a 200-line diff across 6 files will either rubber-stamp it or send it back — neither outcome is good.

When task ordering matters, state it. "Task 4 depends on Task 3 — the migration must run before the service can reference the new column." When tasks are independent, say that too — the executor may parallelize or reorder based on their working context. Never leave ordering implicit. If the executor does Task 7 before Task 4 and it breaks, that is the plan's fault, not the executor's.

A well-sized task list for a medium feature runs 8-15 tasks. Fewer than 5 usually means tasks are too large and hide decisions. More than 20 usually means the feature should be split into multiple plans. If you find yourself writing 25 tasks, step back and ask whether you are really planning one feature or three.

## Decision Points

| Situation | Decision |
|---|---|
| Task is not atomic (multiple unrelated changes, multiple validation steps) | Break it down. If you cannot decompose it, the underlying design may be too coupled — go back to the spec. |
| Do not know the exact file path | Stop and find it. Search the codebase. "TBD" is a plan failure, not a placeholder. |
| Edge case handling is complex | Promote it to its own task with its own validation step. Do not bury it as a bullet inside another task. |
| Plan is for yourself (solo path) | Same rigor, no shortcuts. Future-you is a different person who does not remember your reasoning. |
| Spec is ambiguous on a detail | Do not guess and embed the guess in a task. Go back to `exloom:brainstorming` to resolve the ambiguity first. |
| Executor will need context you have in your head | Write it in the FAQ section. Knowledge in your head is not in the plan. If it is not in the plan, it does not exist for the executor. |
| Multiple valid approaches exist | Pick one and state why. Do not present options — the executor is not the decision-maker, the plan author is. |
| A task depends on another task's output | State the dependency explicitly. "After Task 3 is committed and the migration has run, proceed to Task 4." |
| Plan references code that might change before execution | Pin to the current commit hash or note the assumption. "Based on `main` at `a1b2c3d` — if `order-service.ts` has changed, re-check the insertion point." |
| You are unsure if the plan is complete | Run the self-review in Step 9. If you skip self-review, the executor will discover your oversights at the worst time. |

## Failure Modes

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

## Worked Example

**Scenario:** Add CSV export to the orders page in an existing app (Angular frontend, FastAPI backend, PostgreSQL database). This is a brownfield feature — the app already has an orders listing page with filters, a reports module with a streaming PDF endpoint, and a shared download utility on the frontend.

What follows is a condensed but structurally complete plan. A real plan would have 8-12 tasks; we show 4 to illustrate the pattern.

---

**Acceptance Criteria:**

1. An "Export CSV" button appears on the `/orders` page, right-aligned in the filter bar
2. Clicking the button downloads a CSV file of the currently filtered orders
3. CSV includes columns: `order_id`, `date`, `customer_name`, `total`, `status`
4. Export respects the currently active filters (date range, status, search term)
5. Export handles 100k rows without browser timeout (streaming response, no full buffering)
6. Empty result set produces a CSV with headers only, no error dialog

**Non-Goals:**

- PDF export (separate feature, separate plan)
- Scheduled or recurring exports
- Email delivery of export files
- Export of individual order line items

**Files to Touch:**

| File | Action | Reason |
|---|---|---|
| `backend/app/api/orders.py` | Modify | Add `/api/orders/export` GET endpoint |
| `backend/app/services/order_export.py` | Create | Streaming CSV generation service |
| `frontend/src/app/orders/orders.component.ts` | Modify | Add export button click handler |
| `frontend/src/app/orders/orders.component.html` | Modify | Add export button to filter bar |
| `frontend/src/app/orders/orders.service.ts` | Modify | Add `exportCsv()` method |
| `tests/api/test_order_export.py` | Create | Endpoint and integration tests |

**Existing Patterns to Follow:**

- Streaming response: see `backend/app/api/reports.py:34-52` for `StreamingResponse` usage with CSV content type
- Angular service method: see `frontend/src/app/orders/orders.service.ts:28-35` for how `getOrders()` passes filter params to the API
- Test structure: see `tests/api/test_orders.py` for fixture setup and the `authenticated_client` helper

**Edge Cases:**

| Case | Decision |
|---|---|
| Empty result set | Return CSV with header row only. No error, no empty file. |
| 100k+ rows | Stream rows using `StreamingResponse`. Do not load all rows into memory. |
| Special characters in customer name (commas, quotes, newlines) | Use Python `csv` module — it handles RFC 4180 escaping correctly. |
| Concurrent exports by same user | Stateless endpoint, no server-side state. No conflict possible. |
| Database timeout on large query | Set query timeout to 30s via `statement_timeout`. If exceeded, return 504 with structured `ApiError`. |
| User has no orders matching current filters | Same as empty result set — CSV with headers only. |

**Executor FAQ:**

Q: New endpoint or extend existing `/api/orders`?
A: New endpoint at `/api/orders/export`. Keeps export concerns (streaming, CSV formatting) separate from list/pagination concerns.

Q: Date format in the CSV output?
A: ISO 8601 (`2026-04-12T14:30:00Z`), consistent with the existing API response format.

Q: How does the frontend trigger the file download?
A: Create a temporary `<a>` element with a `blob:` URL. See the existing pattern in `frontend/src/app/shared/download.util.ts:5-18`.

Q: Does the export endpoint require authentication?
A: Yes. Apply the same `@require_auth` decorator used on all other order endpoints.

Q: What if the user changes filters while an export is in progress?
A: No issue. The export captures the filter state at request time. The frontend disables the export button during the download to prevent confusion, but concurrent requests are safe.

Q: Should I add a progress indicator?
A: No. This is a non-goal for v1. Streaming means the browser shows its native download progress, which is sufficient.

**Tasks (showing 4 of ~9 total):**

**Task 1: Create streaming CSV service**
- File: Create `backend/app/services/order_export.py`
- Pattern: Follow service structure from `backend/app/services/order_service.py` — class with injected repository
- What to do: Implement `OrderExportService` with a `generate_csv_rows(filters)` generator method. Use `csv.writer` writing to `io.StringIO`, yielding each row as a string. First yield is the header row: `order_id,date,customer_name,total,status`.
- Validation: `python -c "from app.services.order_export import OrderExportService; print('import ok')"` prints `import ok` with no errors
- Commit: `feat(orders): add streaming CSV generation service`

**Task 2: Add export endpoint**
- File: Modify `backend/app/api/orders.py` — add new route after the existing `get_orders` route (line ~45)
- What to do: Add `GET /api/orders/export` that accepts the same query params as `get_orders` (`date_from`, `date_to`, `status`, `search`). Inject `OrderExportService`, call `generate_csv_rows(filters)`, wrap in `StreamingResponse(media_type="text/csv")`. Set header: `Content-Disposition: attachment; filename="orders-export-{iso_timestamp}.csv"`.
- Validation: `curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $TOKEN" "http://localhost:8000/api/orders/export"` returns `200`
- Commit: `feat(orders): add CSV export endpoint with streaming response`

**Task 3: Write export endpoint tests**
- File: Create `tests/api/test_order_export.py`
- Pattern: Follow `tests/api/test_orders.py` — same `authenticated_client` fixture, same database seeding approach
- What to do: Write 5 tests: (1) authenticated GET returns 200 with `text/csv` content type, (2) response body contains correct CSV header row, (3) filter params are applied (seed 3 orders, filter to 1, assert 1 data row), (4) empty result returns header row only, (5) unauthenticated GET returns 401
- Validation: `pytest tests/api/test_order_export.py -v` — all 5 tests pass
- Commit: `test(orders): add CSV export endpoint tests`

**Task 4: Add export button to orders page**
- File: Modify `frontend/src/app/orders/orders.component.html` — insert after the filter bar closing div (line ~28)
- What to do: Add `<button class="btn btn-outline" (click)="onExportCsv()">Export CSV</button>` inside the filter bar, right-aligned using the existing `ml-auto` utility class pattern from the page header.
- File: Modify `frontend/src/app/orders/orders.component.ts` — add `onExportCsv()` method
- What to do: `onExportCsv()` calls `this.ordersService.exportCsv(this.currentFilters)`, subscribes to the blob response, and triggers download using the helper in `frontend/src/app/shared/download.util.ts`.
- Validation: `ng serve`, navigate to `/orders`, confirm the Export CSV button appears right-aligned in the filter bar. Click it, confirm a `.csv` file downloads.
- Commit: `feat(orders): add CSV export button to orders page`

Notice what this example plan does:

- Every task names exact files with paths, not descriptions
- Every task has a validation command with specific expected output
- Every edge case has a decision — handle it or mark it out of scope
- Every FAQ answers a question the executor would actually ask during execution
- Existing patterns are pointed to by file path and line number, not described in prose
- Non-goals are explicit — no one will accidentally build PDF export

The plan is long. It is also unambiguous. An executor picks this up and starts working within minutes — no Slack messages, no reverse-engineering intent, no rework from misunderstood requirements. That is the goal of every plan you write.

---

## Integration

- **You arrive here from:** `exloom:brainstorming` (with an approved spec) or from a requirements document / ticket with clear scope
- **You leave here toward:** `exloom:reviewing-plans` (if the plan will be handed off to a different executor) or `exloom:executing-handoff-plans` (if you are executing your own plan)
- **Plan structure:** a handoff plan has 11 sections, in this order — Metadata, Goal, Acceptance Criteria, Files to Touch, Existing Patterns to Follow, Edge Cases, Non-Goals, Executor FAQ, Tasks, Review Checklist, and an initially-empty Deviation Log. The Process steps above produce the core — Acceptance Criteria, Non-Goals, Files to Touch, Existing Patterns to Follow, Edge Cases, Executor FAQ, and Tasks; add Metadata and a one-paragraph Goal at the top, a Review Checklist agreed with the reviewer, and the empty Deviation Log at the end. `exloom:reviewing-plans` checks all 11.
- **Commit messages:** follow this repo's existing commit convention
- **Related skills:** `exloom:auditing-plan-fidelity` (checks execution against plan), `exloom:reviewing-code` (reviews the output)

The handoff path matters. If you are handing the plan to someone else, `reviewing-plans` catches structural problems before the executor starts — missing file paths, vague tasks, uncovered spec requirements. If you are executing your own plan, you still benefit from the self-review in Step 9, but you can proceed directly to execution.

Either way, the plan is the contract. Deviations from it during execution get logged in the plan's deviation log, not silently absorbed. When the executor discovers that reality differs from the plan — a file moved, an API changed, an edge case the plan did not anticipate — they record it. The deviation log is how the team learns which parts of the planning process need improvement. A plan with zero deviations was either perfect or the executor did not bother logging. Over time, recurring deviation patterns point to systemic planning gaps worth fixing.
