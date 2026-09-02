---
name: capturing-story-context
description: Use when starting test-case work from a user story, before any generation — fetches the story, numbers its acceptance criteria, and confirms navigation and dependencies with QA.
---

# Capturing Story Context

Produce a confirmed context block in `.claude/qa/<story-id>.md`. Generation does not start until this exists.

## 1. Get the identifiers

**The work item ID is all you need.** IDs are unique across the organisation, so the project is not required to fetch a story — it is read from the story itself and used later for publishing.

QA usually pastes a URL — from the board, a backlog, a sprint taskboard, a query result, or the item itself. Do not try to recognise each shape. Take the number:

- the `workitem=` query parameter when present,
- otherwise the numeric segment following `_workitems/edit/` (a trailing slash is not part of the ID).

```
…/_workitems/edit/10420/                                       -> 10420
…/_boards/board/t/Checkout%20Team/Stories?workitem=10420       -> 10420
…/_backlogs/backlog/Checkout%20Team/Stories?workitem=10517     -> 10517
```

A bare ID is equally fine. The organisation comes from `az` defaults, or from the URL host when working across organisations.

Never search for the story, never list projects, never fetch unrelated items. The scope of a run is exactly one story.

**Echo what you resolved** — `10420 — Guest checkout address validation (Checkout)` — before doing anything else. This is what makes an unrecognised URL shape harmless: either QA sees the right story named back, or they correct you immediately. It costs one line and removes the need to anticipate every URL form.

## 2. Fetch the story

`fetch_story` from `../references/tracker-adapters.md`. Read-only. This is the only tracker call permitted at this stage.

Extract: ID, title, description, acceptance criteria, state, and any existing links.

**Record `System.TeamProject`** — this is the project, taken from the story rather than asked for. Publishing creates the test cases there, and every create passes it explicitly. Never rely on the `az` configured default project; it is set per machine and is frequently some unrelated project.

## 3. Number the acceptance criteria — and show the numbering

Acceptance criteria arrive as free text. Enumerate them `AC-1`, `AC-2`, … and **display the numbered list to QA**.

This numbering is what the whole coverage matrix references. If QA never sees it, they cannot verify the matrix is honest, and the traceability is decorative. Ask QA to confirm the split before continuing — one criterion per line, splitting compound criteria that contain multiple checks.

If the story has no acceptance criteria, say so plainly and ask whether to proceed on the description alone. That fact goes in the artifact.

## 4. Load app knowledge

Read `.claude/qa/app-knowledge.md` if it exists. Absent file is a normal first run.

Use it to make the proposals in step 5 concrete. Entries marked `confirmed` are treated as fact; `seen once` and `volatile` as suggestions to verify with QA.

## 5. Propose, then confirm — one at a time

Never present a blank field. Draft each item, then use `AskUserQuestion` with the proposal as the recommended option.

**Navigation path.** Propose from app knowledge, or infer from the AC and story title. Include the role required to reach the screen — the role only, never credentials.

**Upstream dependencies.** What must exist, be active, or be configured first. Propose from app knowledge and from what the AC implies.

**Downstream dependencies.** What is affected afterwards — reports, notifications, invoices, dashboards, audit logs.

Each dependency directly generates cases later, so an empty list is a real answer but a lazy one. If QA answers "none", accept it and record it.

## 6. Write the artifact

Create `.claude/qa/<story-id>.md` from `../../templates/qa-artifact.md` with: story snapshot, numbered AC, confirmed navigation, upstream and downstream dependencies, and the app-knowledge entries relied upon.

## 7. Re-runs

If the artifact already exists, compare the story's current title, description, and AC against the snapshot.

- Unchanged → skip the interview, report that context was reused.
- Changed → show what changed, and re-confirm only the affected items.

Never re-interview from scratch when the story has not moved.

## Then

Hand to `generating-test-cases`.
