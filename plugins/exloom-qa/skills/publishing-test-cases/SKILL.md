---
name: publishing-test-cases
description: Use when approved test cases need to be created on the board and linked to the story.
---

# Publishing Test Cases

Create approved Test Cases on the board and link each to the story. Every command comes from `../references/tracker-adapters.md`.

## 1. Verify approval

Read the approval record in `.claude/qa/<story-id>.md`. No record, or an empty list → stop and say so. Do not attempt a write.

Publish **only** the IDs in the record. A case QA edited but did not approve is not published.

## 2. Resolve what already exists

For each approved case:

1. Check the `TC → work-item-id` map in the artifact.
2. If the map is missing or incomplete, query the board by the story-level tag `exloom-qa:<story-id>` to recover the published set in one call.
3. Found → update. Not found → create.

Never create a case whose TC-level tag is already on the board. Report the create/update split before starting.

## 3. Build the Steps payload

Convert Test Steps and Expected Result into the Steps XML per `../references/tracker-adapters.md`. One `<step>` per step, action first, expected result second, entities escaped, ids starting at 2.

Preconditions and Test Data do not belong in the steps grid. Put them in the description so the tester sees them before step 1.

## 4. Create or update

Set title from the objective, `Microsoft.VSTS.Common.Priority` from Priority, the Steps payload, and tags:

```
exloom-qa:<story-id>; exloom-qa:<story-id>:TC-<nnn>; <Test Type>; <Test Type>
```

Both provenance tags are mandatory. A create without the TC-level tag is denied by the hook.

## 5. Link to the story

`link_test_case` for each newly created case. One call writes both sides.

The story's **fields are never modified**. Its relation collection does gain a `Tested By` link — that is the point of the operation, and it is the only change publishing makes to the story.

## 6. Record the map

Write each `TC-nnn → work-item-id` back to the artifact as you go, not at the end. If publishing is interrupted, the map must reflect exactly what reached the board.

## 7. Report

State what was created, what was updated, what was skipped and why, and the story link. Give work item IDs so QA can open them.

## Never

- Publish an unapproved case.
- Delete anything. Azure DevOps deletion of Test Cases requires a different API and is permanent with no recycle bin — a wrong publish cannot be cleanly undone, so verify before writing rather than fixing after.
- Touch Test Plans or Test Suites.
- Modify the story's fields, or any work item outside the approved set.
