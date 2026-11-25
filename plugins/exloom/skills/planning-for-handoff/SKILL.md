---
name: planning-for-handoff
description: Use when you have a spec or requirements for a multi-step task — produces a handoff-ready plan that someone other than the author can execute without ambiguity.
---

# Planning for Handoff

The test of a plan: a skilled developer who has never seen this codebase executes it start to finish without asking you a question. Hold to that even when you will execute it yourself.

**Where it lives.** Where the repo's CLAUDE.md or the user says; otherwise `docs/exloom/plans/YYYY-MM-DD-<topic>-plan.md`. Commit it.

## Process

1. **Start from a spec.** No spec: stop and invoke `exloom:brainstorming`. The spec says what and why; the plan says how, in what order, with what validation.

2. **Take the acceptance criteria from the spec.** Copy its refs (`F-012/R-3/AC-2`); never write a criterion that exists only in the plan. If one is missing, add it to the spec first. Every task cites at least one criterion and every criterion is cited by a task.

3. **Write non-goals.** Three to five things this plan deliberately does not cover, by name.

4. **List the files to touch.** Every file to create, modify or delete, with its exact path and a short reason: "Modify `src/services/order-service.ts:45-60` — add discount calculation to `calculateTotal`." Open the files yourself; "TBD" or "the relevant service file" means the plan is not ready. List the reference docs this change affects, or `Docs affected: none — <reason>` (see `exloom:maintaining-reference-docs`).

5. **Point at existing patterns.** Name the file and the pattern: "See `src/services/user-service.ts`: constructor injection, service methods return `Result<T>`."

6. **Decide the edge cases.** Null, empty and enormous input; concurrent requests; a failed or slow dependency. Give each a decision — handle it this way, or out of scope. An edge case without a decision hands a design choice to the executor.

7. **Write the executor FAQ.** Three to six questions a cold reader would ask, answered. Quote any external document; "see the wiki" is not an answer.

8. **Write the tasks**, each under a `### Task <n>` heading. A task is one logical change, one validation, one commit, and reads on its own — no "as in Task 3". Each has:
   - the criteria it serves, by ref;
   - the files, with exact paths;
   - what to do, concretely, with code where code is needed;
   - a validation step: the command and its expected output, never "make sure it works";
   - a commit message, in the repo's convention.

   Business logic is validated by an automated test, written first in the same task: write the failing test, then implement until it passes. Never split "implement X" and "test X". Put the criterion ref in the test's name — `@DisplayName("F-012/R-3/AC-2 - rejects an over-large discount")` or `test_F012_R3_AC2_...` — because the proof reads which criteria passed from the test names. Only pure wiring with no logic may be validated by a build or a manual check. A task that changes a screen, in a project with an end-to-end runner, also writes an end-to-end test of the user action: the smoke step runs it. Sizing: [task-sizing.md](task-sizing.md).

9. **Check coverage both ways.**

   ```bash
   comm -3 <(grep -oE 'F-[0-9]+/R-[0-9]+/AC-[0-9]+' "$SPEC" | sort -u) <(grep -oE 'F-[0-9]+/R-[0-9]+/AC-[0-9]+' "$PLAN" | sort -u)
   ```

   A spec criterion no task cites is forgotten scope. A plan ref the spec does not define was invented. A task citing nothing is scope creep.

## Plan structure

Eleven sections, in this order: Metadata, Goal, Acceptance Criteria, Files to Touch, Existing Patterns to Follow, Edge Cases, Non-Goals, Executor FAQ, Tasks, Review Checklist, and an empty Deviation Log. A plan missing one is not ready.

## Decisions

| Situation | Decision |
|---|---|
| A task has several unrelated changes or validations | Break it down; if you cannot, the design is too coupled. |
| The spec is ambiguous | Do not embed a guess: resolve it through `exloom:brainstorming`. |
| Several approaches are valid | Pick one and say why. The author decides, not the executor. |
| A task depends on another | Say so: "After Task 3 is committed and the migration has run." |
| The code may change before execution | Pin the commit the plan was written against. |

When reality differs during execution, the executor records it in the Deviation Log and never absorbs it silently.

See [failure-modes.md](failure-modes.md) and [worked-example.md](worked-example.md).
