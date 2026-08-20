---
name: reviewing-test-coverage
description: Use when a QA engineer is reviewing generated test cases, requesting changes, or approving them for publication — also captures what QA's corrections teach about the application.
---

# Reviewing Test Coverage

Present the set, apply feedback surgically, record approval, and capture what the corrections taught.

## 1. Present in chat

Summary table first:

| Test Case ID | Objective | Test Type | Priority | Tier |
|---|---|---|---|---|

Then full details per case: ID, Objective, Covers, Type, Priority, Execution Tier, Preconditions, Test Data, Test Steps, Expected Result.

Then the complexity assessment, AC → TC matrix, dependency matrix, QA Questions, assumptions, charter, and notes to development.

Never hide cases in a file. Never require a download to review. Generate Excel or CSV only if explicitly asked, and never regenerate the set to do it.

If the checklist failed on any item, name the failures at the top rather than presenting a clean-looking set.

## 2. Apply feedback surgically

QA may change priorities, remove cases, rewrite steps or expected results, add missing scenarios, or regenerate one case.

- Change **only** what was named.
- Preserve every unmentioned case byte-for-byte — objective, type, steps, expected result, priority, tier.
- **Never renumber.** A removed TC-012 leaves a gap; that is correct.
- New cases continue the sequence from the highest ID ever used.
- Never regenerate the whole set unless explicitly asked.

Re-run `../references/coverage-checklist.md` after edits and report any item the changes broke — for example, removing the only case covering AC-3.

## 3. Record approval

Ask which IDs are approved. Accept ranges (`TC-001 to TC-045`), lists, or `approve all`.

Write to the artifact:

```markdown
## Approval Record
Approved by: <name>
Date: <YYYY-MM-DD>
Approved: TC-001..TC-012, TC-015, TC-018
```

Only IDs in this record may be published. The hook reads it.

## 4. Capture deviations

After approval, diff the generated set against the approved set. For each edit QA made, classify it per `../references/deviation-learning.md` and propose the durable ones for confirmation — one at a time, with the classification stated.

Only confirmed entries are written to `.claude/qa/app-knowledge.md`. Never write silently. When unsure whether an edit generalizes, classify it story-specific and discard it.

Skip this step when QA made no edits.

## 5. Hand off

Approved cases go to `publishing-test-cases`.

## Do not

- Renumber, reorder, or regenerate unaffected cases.
- Treat silence as approval.
- Publish anything from this skill.
