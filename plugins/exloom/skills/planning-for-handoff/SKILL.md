---
name: planning-for-handoff
description: Use when you have a spec or requirements for a multi-step task — produces a handoff-ready plan that someone other than the author can execute without ambiguity.
---

# Planning for Handoff

## Overview

A plan is a contract between the author who understands the problem and the executor who will solve it.

The test: a skilled developer who has never seen this codebase executes it start to finish without a single question to you. If not, the plan is not done — even when you execute it yourself.

## Process

Follow these 9 steps in order.

**Where the plan lives.** If the repo's CLAUDE.md (or the user) specifies a location — e.g. `.claude/plans/current.md` — use that; otherwise `docs/exloom/plans/YYYY-MM-DD-<topic>-plan.md`. Commit it so the executor, including a future session, can find it.

### Step 1: Start from a spec

Confirm a spec or design document exists before writing the plan. If none exists, stop and invoke `exloom:brainstorming`.

The spec says what and why; the plan says how, in what order, with what validation. The spec must supply acceptance criteria, constraints, and non-goals. A focused half-page is enough; a vague paragraph is not — push back.

### Step 2: Take the acceptance criteria from the spec — do not invent them

Copy the spec's criteria refs into the plan. Do not write new ones. The criteria live in the spec as `F-012/R-3/AC-2`; the plan says which tasks satisfy which. A criterion invented at plan time traces to nothing the user approved.

**If a criterion you need is missing, go back and add it to the spec** — an edit to a draft, or a change request against an approved one. Never a criterion that exists only in the plan.

**Every task cites at least one AC. Every AC is cited by at least one task.** An AC no task serves is forgotten scope; a task serving no AC is scope creep. `exloom:auditing-plan-fidelity` checks both after execution.

Every criterion must be verifiable by the executor without asking the author. Not "Users can log in", but "POST `/auth/login` with valid credentials returns 200 with a JWT containing `sub`, `exp`, and `role` claims." Aim for 4-8; more than 10 suggests the scope is too large. Reject vague outcomes ("the feature works"), activities, and opinions.

### Step 3: Write non-goals explicitly

List 3-5 things this plan deliberately does NOT cover, by name: "This plan does NOT add email notifications for CSV exports." Skip non-goals too obvious to inform. If something is deferred to a later sprint, say so.

### Step 4: Identify files to touch

List every file the executor will create, modify, or delete — one line each, exact path and short reason. Search the codebase and open the files yourself; confirm line ranges: "Modify `src/services/order-service.ts:45-60` — add discount calculation to the `calculateTotal` method." For new files, state what they contain; for deletions, why removal is safe. Never a directory or "the relevant service file". At 15+ files across 4 modules, consider splitting the plan.

### Step 5: Identify existing patterns

Point to specific files and name the pattern to follow: "See `src/services/user-service.ts` for the pattern: constructor injection, repository interface, service method returns `Result<T>` not raw values." Prose alone is ambiguous — point to the file.

### Step 6: Enumerate edge cases

For every major operation ask: null, empty, enormous input? Concurrent requests? External service down? Slow database? Include concurrent writes, partial failures and resource exhaustion.

Give each edge case a decision — handle it with specifics, or mark it out of scope:
- "Empty result set: return CSV with headers only, no rows."
- "100k rows: use streaming response, do not buffer in memory."
- "Concurrent exports by the same user: out of scope for v1, stateless endpoint means no conflict."

An edge case without a decision hands a design decision to the executor.

### Step 7: Write the executor FAQ

Answer 3-6 questions a cold reader would ask: "Q: Should I use the existing migration tool or write a new one? A: Use Flyway, same as the auth service — see `db/migrations/` for the naming convention." Quote the relevant part of any external document; "see the wiki" is not an answer.

### Step 8: Write tasks

Each task is one atomic change — one logical unit, one validation step, one commit — and self-contained.

Each task needs five things: (1) the acceptance criteria it serves, by ref (`F-012/R-3/AC-2`), (2) files involved with exact paths, (3) what to do in concrete terms, (4) a validation step with the command to run and the expected output, (5) a commit message.

**Name the test after the criterion it covers** - put the ref in the test's name, `@DisplayName("F-012/R-3/AC-2 - rejects an over-large discount")` or `def test_F012_R3_AC2_rejects_over_large_discount():`. `prove-change-is-tested.sh` records from the runner's JUnit XML which criteria actually passed. Use the name, not an annotation.

**A task that cites no criterion is scope creep** — if you cannot name what a task is for, that is the finding.

- Show code snippets where code is needed, and commands with expected output.
- Write each task to be read out of order — no "as we did in Task 3"; repeat context.
- The validation step is non-negotiable: "Run `pytest tests/api/test_export.py -v` and confirm all 5 tests pass", never "make sure it works".
- For business logic (calculations, validation, branching, state changes), validation must be an **automated test**, not a manual check or build/curl. Build-only or manual checks are acceptable only for pure wiring with no logic (a button renders, a module imports).
- Order it **test-first**: "write the failing test, then implement until it passes", in the same task. Do NOT split "implement X" and "test X" into separate tasks. (Pure wiring is the exception.)
- Keep infrastructure and application changes in separate tasks — different systems, different validation.

### Step 9: Check coverage both ways

One grep, in two directions.

```bash
comm -3 <(grep -oE 'F-[0-9]+/R-[0-9]+/AC-[0-9]+' "$SPEC" | sort -u)         <(grep -oE 'F-[0-9]+/R-[0-9]+/AC-[0-9]+' "$PLAN" | sort -u)
```

A spec criterion no task cites is **forgotten scope**. A plan ref the spec does not define is a criterion **invented at plan time**. A task citing nothing is **scope creep**.

**This is the whole step** — a set difference, not self-review.

## Acceptance Criteria Are Not Optional

Good criteria are:

1. **Observable** — visible without reading the code. "The endpoint returns a 200", not "the code is well-structured".
2. **Testable** — an automated test or manual step yields pass/fail. "POST `/api/orders/export` returns `text/csv` content type."
3. **Author-independent** — anyone can verify without asking what the author meant.

Criteria come before tasks: every task exists to satisfy a criterion, and every criterion has a task.

Common mistakes:
- Writing criteria after tasks, so they describe what you built rather than what was needed
- Mixing in implementation details ("Use the `csv` module" is a choice, not a criterion)
- Omitting performance criteria when they matter ("Handles 100k rows without timeout")
- Criteria the executor cannot verify without production data or systems they lack

## File Paths Always Exact

The executor should never need to search the codebase to find where your plan applies.

Not file references: "update the relevant service file", "add a test for this", "modify the configuration", "update the frontend component".

File references:
- "Modify `src/services/order-service.ts:45-60` — add discount calculation to `calculateTotal`"
- "Create `tests/services/test_order_service.py::test_discount_calculation`"
- "Add export button template to `frontend/src/app/orders/orders.component.html:28` after the filter bar div"
- "Update `backend/app/core/config.py:12` — add `CSV_EXPORT_MAX_ROWS` with default `100000`"

If you do not know the path, find it; "TBD" means the plan is not ready. For new files state the placement reason: "Create `backend/app/services/order_export.py` — business logic, not HTTP concerns." For modifications, give line numbers or function names.

## Tasks Must Be Bite-Sized

See [task-sizing.md](task-sizing.md).

## Decision Points

| Situation | Decision |
|---|---|
| Task is not atomic (multiple unrelated changes, multiple validation steps) | Break it down. If you cannot, the design may be too coupled — go back to the spec. |
| Do not know the exact file path | Stop and find it. "TBD" is a plan failure, not a placeholder. |
| Edge case handling is complex | Promote it to its own task with its own validation step. |
| Plan is for yourself (solo path) | Same rigor, no shortcuts. |
| Spec is ambiguous on a detail | Do not embed a guess in a task. Resolve it via `exloom:brainstorming` first. |
| Executor will need context you have in your head | Write it in the FAQ. |
| Multiple valid approaches exist | Pick one and state why. The plan author decides, not the executor. |
| A task depends on another task's output | State it: "After Task 3 is committed and the migration has run, proceed to Task 4." |
| Plan references code that might change before execution | Pin the commit: "Based on `main` at `a1b2c3d` — if `order-service.ts` has changed, re-check the insertion point." |
| You are unsure if the plan is complete | Run the Step 9 coverage check. |

## Failure Modes

See [failure-modes.md](failure-modes.md).

## Worked Example

See [worked-example.md](worked-example.md).

## Integration

- **You arrive here from:** `exloom:brainstorming` (with an approved spec) or from a requirements document / ticket with clear scope
- **You leave here toward:** execution, then `exloom:review-gate` when closing. If a different executor will run the plan, have a human read it first.
- **Plan structure:** 11 sections, in this order — Metadata, Goal, Acceptance Criteria, Files to Touch, Existing Patterns to Follow, Edge Cases, Non-Goals, Executor FAQ, Tasks, Review Checklist, and an initially-empty Deviation Log. Add a one-paragraph Goal and a Review Checklist agreed with the reviewer. A plan missing any of the 11 is not handoff-ready.
- **Commit messages:** follow this repo's existing commit convention
- **Related skills:** `exloom:brainstorming` (produces the spec this plan cites), `exloom:executing-handoff-plans` (executes it), `exloom:auditing-plan-fidelity` (checks the diff against it), `exloom:review-gate` (the evidence gate at completion)

Run the Step 9 coverage check, then execute — whoever the executor is.

The plan is the contract. When reality differs during execution — a file moved, an API changed, an unanticipated edge case — the executor records it in the plan's Deviation Log, never absorbs it silently.
