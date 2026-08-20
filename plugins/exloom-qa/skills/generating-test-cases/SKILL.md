---
name: generating-test-cases
description: Use after story context is captured, to produce the test-case set — assesses complexity, applies test-design techniques, and audits coverage before QA sees it.
---

# Generating Test Cases

Produce the canonical test-case set into `.claude/qa/<story-id>.md`. Generate once; later presentation or format changes never regenerate.

Requires a confirmed context block. If absent, run `capturing-story-context` first.

## 1. Assess complexity first

Classify the story per `../references/complexity-and-volume.md`, then **state the tier, the reason, and the resulting band** before generating anything. Write it to the artifact.

QA may override the tier. An override stands for the rest of the run.

## 2. Understand before designing

From the story, AC, navigation, and dependencies, establish: what the feature does, who uses it, what must exist first, what changes afterwards.

Do not convert acceptance criteria into test cases one-for-one. That produces a set that misses everything the AC did not think to say.

## 3. Derive with techniques

Apply `../references/technique-catalog.md`. Where a situation matches a technique, use it and record the technique on the case. Techniques bound the count; unguided generation does not.

Cover, where applicable: functional positive and negative, business rules, validation, boundaries, dependency states, workflow and state transitions, roles and permissions, integration failure modes, data persistence, error handling, and realistic user behavior.

Security cases come from `../references/manual-security-scope.md` — that scope, and no wider.

## 4. Write cases to schema

Every case carries all ten fields of `../references/test-case-schema.md`. Priority and Execution Tier per `../references/priority-rubric.md`. Steps and expected results per `../references/human-executability.md`.

Use real vocabulary and real error strings from `.claude/qa/app-knowledge.md` where available. Where a real error message is unknown, raise a QA Question rather than inventing one.

## 5. Audit before presenting

Dispatch the `coverage-auditor` agent with the story context and the generated set. It reports gaps, duplicate clusters, unjustified padding, manually infeasible cases, and checklist failures.

Apply its findings. Cutting cases is as valid an outcome as adding them — a set trimmed to the band is a success, not a loss.

## 6. Check the set

Run `../references/coverage-checklist.md`. Every item must pass, or the failures are named explicitly when presenting.

Produce the required outputs: complexity assessment, AC → TC matrix, dependency matrix, QA Questions (≤5), assumptions, exploratory charter, notes to development.

## 7. Write and hand off

Write the canonical set and all outputs to the artifact. This dataset is now fixed — review edits it in place; it is not regenerated.

Hand to `reviewing-test-coverage`.

## Do not

- Pad a small story to look thorough. Check the band.
- Generate cases for capabilities with no evidence they exist.
- Invent business rules, expected messages, or roles.
- Write steps only an engineer with a terminal could run.
- Renumber or regenerate an existing set to change its presentation.
