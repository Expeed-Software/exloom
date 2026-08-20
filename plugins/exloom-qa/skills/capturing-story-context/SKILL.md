---
name: capturing-story-context
description: Use when starting test-case work from a user story, before any generation — fetches the story, numbers its acceptance criteria, and confirms navigation and dependencies with QA.
---

# Capturing Story Context

Produce a confirmed context block in `.claude/qa/<story-id>.md`. Generation does not start until this exists.

## 1. Get the identifiers

Accept either form:

**A work item URL** — the usual case, because QA is already looking at the story and copies the address bar. Parse organisation, project, and ID from it:

```
https://dev.azure.com/<org>/<project>/_workitems/edit/<id>
https://<org>.visualstudio.com/<project>/_workitems/edit/<id>
```

Both may carry query strings; ignore them. A URL is the preferred input — project and ID come from one string, so they cannot disagree.

**Project name and work item ID stated separately** — also fine.

Ask only for what is genuinely missing. Never search for the story, never list projects, never fetch unrelated items. The scope of a run is exactly one story.

## 2. Fetch the story

`fetch_story` from `../references/tracker-adapters.md`. Read-only. This is the only tracker call permitted at this stage.

Extract: ID, title, description, acceptance criteria, state, and any existing links.

**Verify the project before using anything.** Work-item IDs are unique per organisation, not per project, and `az boards work-item show` takes no project argument — it will return a story from a different project without complaint. Compare `System.TeamProject` against the project QA named. If they differ, stop and report both; do not continue. A story from the wrong project yields a fully plausible test set for the wrong feature, and no later step catches it.

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
