---
name: capturing-learnings
description: Use when the user asks to record a lesson — a gotcha, a convention, an incident, a pattern — so it lands in the right durable place. Never start unprompted.
---

# Capturing Learnings

Route each learning to the place where it helps the right people at the right time. The job is routing, not writing documentation. The trigger is "I wish someone had told me that": a gotcha, an agreed convention nobody wrote down, an incident's lesson, a retro's "always do X", or a shared doc that turned out wrong for this project.

## Where it goes

**Specific to one repository** — it would mislead developers on other projects: the repo's `CLAUDE.md`, in the most specific section that fits, else a "Gotchas" section at the bottom. Show the user the exact change and edit only once the user approves it; commit only once the user approves the commit.

For an org-wide learning, a new skill, or personal memory, and for the entry shape, see [gotchas.md](gotchas.md).

## When it contradicts what is already written

Search the target file for the topic first. Then update; never add a second entry.

- **The old content is wrong or outdated** — replace it, quoting the old text and saying why it changed.
- **Each is right in different cases** — add the condition that tells them apart: "Use Redis when state is shared across instances; Caffeine for a single-instance cache."
- **They cannot be reconciled** — the convention is contested. Take it to a team discussion before capturing either.

A proposal that changes existing content quotes the before and the after.

## Pull requests

Open a PR only on a repository the user names, and only after they agree. One learning per PR; the body says what was learned, where, the proposed change and who it helps. Never propose changes to exloom itself.

## Do not capture

Generic best practice ("never commit secrets"), ephemeral state ("staging was down on March 3rd") unless it reveals a missing convention, what the repo's CLAUDE.md already says, speculation, or a procedure that belongs in an IT knowledge base.

See [failure-modes.md](failure-modes.md).
