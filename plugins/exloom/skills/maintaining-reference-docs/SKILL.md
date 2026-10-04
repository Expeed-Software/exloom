---
name: maintaining-reference-docs
description: Use when planning a change, and in /review-complete, to keep the repository's architecture, data-model, database and API docs true to the code in the same branch. Also used by /exloom-setup when it offers to create the derivable docs for an existing codebase. Not for READMEs, specs, plans or changelogs.
---

# Maintaining Reference Docs

## Overview

Reference docs describe the system as it is: its architecture, its data model, its database and its API. They are only useful while they are true, and they stop being true the first time a change ships without them. This skill keeps them true by making the doc change part of the code change: same branch, same diff, same review.

A team needs this more than an individual does. The person who changed the schema knows what changed; the five people who read `docs/db/` next month do not, and they will trust whatever it says.

You write the docs. Hooks never do. A doc change shows in the diff and is reviewed like code.

## Where the docs live

The defaults follow the Expeed docs template:

| Doc | Directory | Written from |
|---|---|---|
| Database | `docs/db/` | migrations (Flyway, Liquibase, EF Core, Alembic, Prisma, plain SQL) |
| API | `docs/api/` | the OpenAPI document, or controllers and routes when there is none |
| Data model | `docs/data-model/` | ORM entities and models |
| Architecture | `docs/architecture/` | people — never derived |

A repository whose layout differs commits `.claude/exloom-docs`, one line per doc directory, followed by the code paths that feed it:

```
documentation/schema: sql/* db/changelog/*
documentation/endpoints: *Controller.cs
```

Once committed, the file replaces the defaults entirely. An uncommitted one is ignored, like every exloom setting, and `/review-init` lists it if `.gitignore` would keep it out.

## Only existing docs are maintained

Check which of these directories exist before doing anything.

- **No reference docs at all:** do nothing, say nothing. This skill does not start a documentation effort on its own.
- **Some exist:** maintain only those. A repository with `docs/api/` and no `docs/db/` gets API updates and no database doc.
- **The one exception** is `/exloom-setup`, which offers once to create the derivable docs (below).

## In planning

Called from `exloom:planning-for-handoff`.

1. Read the existing docs that cover the area the plan touches. They are the fastest map of the system, and they say which conventions the team already wrote down.
2. Where a doc and the code disagree, the code wins. Note the disagreement in the plan's Executor FAQ so nobody "fixes" the code to match a stale doc.
3. Name the docs the change affects in the plan's Files to Touch, with exact paths, like any other file — or write `Docs affected: none` with the reason.

## In /review-complete

Before the final review is dispatched, bring each affected doc up to date in the same branch:

1. List the branch's changed files against its base.
2. For each existing doc directory, decide whether its sources changed: a migration for `docs/db/`, an endpoint or the OpenAPI file for `docs/api/`, an entity for `docs/data-model/`.
3. Update the doc by reading the code (below). Edit the existing page in place; do not reorganise it.
4. If the code changed and the doc genuinely needs nothing — an index that is not documented, an internal refactor of a controller with the same contract — record it in the checklist under `## Rulings`:

   ```
   - Doc impact: none — <reason>
   ```

5. Commit the doc changes. A commit that touches only document files (Markdown, Mermaid, Office, PDF, images, plus `.claude/exloom-doc-patterns`) in the reference-doc directories keeps an earlier L1 approval, so docs updated after a review need no new round. Anything else there, such as an OpenAPI or SQL file, needs review.

The push gate warns when code for an existing doc changed without the doc and without a `Doc impact` line. It is a warning; it never blocks. Treat it as a reminder, not as a check you can satisfy with the escape line.

## Writing derived docs

Derived docs are written by reading the source of truth, never from memory or from the plan. No generator scripts: read the files.

### Database, from migrations

Apply the migrations in order in your head, then describe the end state, not the history.

- One section per table: purpose in one line, then columns with type, nullability and default.
- Primary key, unique constraints, indexes, foreign keys with their on-delete rule.
- Enumerated values and check constraints, in words a reader can use.
- The migration that last changed the table, so a reader can find the history.

A table the migrations drop is removed from the doc, not marked deprecated.

### API, from OpenAPI or controllers

Prefer the OpenAPI document when one exists; it is the contract. Without one, read the controllers or route definitions.

- One entry per endpoint: method and path, what it does in one line, who may call it.
- Request: path and query parameters, body fields with type and whether required.
- Response: status codes and body shape for success and for each documented error.
- Anything a caller must know that the signature does not say: pagination, idempotency, rate limits, side effects.

When the doc is generated elsewhere (a published OpenAPI page), link to it and document only what it lacks.

### Data model, from ORM models

- One section per entity: what it represents, its fields with types, and its identity.
- Relationships, with cardinality and which side owns them.
- Invariants the code enforces: required fields, validation rules, state transitions.
- Where the entity is persisted, by table name, linking to the database doc.

### What derived docs never contain

- Anything you inferred rather than read. If the code does not say whether a field may be null, write that it is unspecified.
- Implementation detail a caller cannot rely on: private helpers, internal class names, cache layout.
- Copies of the code. Describe; link to the file for the rest.

## Architecture docs

Architecture is written by people and maintained by you only where a change touches it: a new service, a new integration, a new queue, a changed boundary. Update the paragraph or the component list it affects and say what changed. Never regenerate an architecture doc and never draw diagrams automatically; onboarding an existing codebase's architecture is a separate, deliberate piece of work (the store's brownfield-onboard skill).

## Brownfield

Existing docs win over these defaults, as existing code wins over Expeed defaults for new code.

- Match the doc's existing headings, tone, table style and level of detail.
- Edit the section the change affects. A full rewrite of a page nobody asked about is noise in the diff and hides the real change from the reviewer.
- If an existing doc is badly wrong outside your change, say so to the user and leave it; fixing it is its own change.

## /exloom-setup on an existing codebase

When the repository has the code for a derivable doc (migrations, an API, ORM models) and none of the docs, `/exloom-setup` asks once whether to create them. On yes, write the database, API and data-model docs from the code as above, on the current branch, and commit them as their own commit. On no, create nothing and do not ask again. Architecture docs and diagrams are never created by setup.

When the repository keeps its docs somewhere other than the defaults, setup writes `.claude/exloom-docs` with the real paths. When the defaults fit, it writes nothing.

## Failure modes

| Failure | Prevention |
|---|---|
| Doc describes the plan, not the code | Write derived docs only from the merged code on the branch. |
| `Doc impact: none` used to silence the warning | Use it only when the doc would not change; say why. |
| A rewrite hides the real doc change | Edit the affected section in place. |
| A new docs tree appears in a repo that had none | Only setup creates docs, and only when the user says yes. |
| Architecture doc regenerated from code | Architecture is hand-written; update the affected part only. |

## Integration

- **Called from:** `exloom:planning-for-handoff` (read the docs, name the affected ones), `/review-complete` (update them before the final review), `/exloom-setup` (the one-time offer).
- **Gate:** the push hook warns on code changed without its doc; it never blocks.
- **Related:** `exloom:brainstorming` (specs and mocks are not reference docs), `exloom:capturing-learnings` (conventions, not system descriptions).
