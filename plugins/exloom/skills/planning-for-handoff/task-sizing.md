# Tasks Must Be Bite-Sized — planning-for-handoff

Extracted from SKILL.md so the skill loads lean.


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
