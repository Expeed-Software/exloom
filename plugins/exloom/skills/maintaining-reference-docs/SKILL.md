---
name: maintaining-reference-docs
description: Use when planning a change, and at the gate, to keep the repository's architecture, data-model, database and API docs true to the code in the same branch. Also used by /exloom-setup when it offers to create the derivable docs for an existing codebase. Not for READMEs, specs, plans or changelogs.
---

# Maintaining Reference Docs

Reference docs describe the system as it is. They stay true only if the doc change ships with the code change: same branch, same diff, same review. You write them; hooks never do.

## Where they live

| Doc | Directory | Written from |
|---|---|---|
| Database | `docs/db/` | migrations |
| API | `docs/api/` | the OpenAPI document, else controllers and routes |
| Data model | `docs/data-model/` | ORM entities and models |
| Architecture | `docs/architecture/` | people — never derived |

A repository laid out differently commits `.claude/exloom-docs`, one line per doc directory followed by the code paths that feed it. Once committed it replaces the defaults entirely:

```
documentation/schema: sql/* db/changelog/*
documentation/endpoints: *Controller.cs
```

## Only existing docs are maintained

No reference docs at all: do nothing and say nothing. Some exist: maintain only those. The one exception is `/exloom-setup`, below.

## When planning

1. Read the docs covering the area the plan touches.
2. Where a doc and the code disagree, the code wins. Note it in the plan's Executor FAQ so nobody changes the code to match a stale doc.
3. Name the affected docs in Files to Touch with exact paths, or write `Docs affected: none` with the reason.

## Before the final review

1. List the branch's changed files against its base.
2. For each existing doc directory, decide whether its sources changed: a migration for `docs/db/`, an endpoint or the OpenAPI file for `docs/api/`, an entity for `docs/data-model/`.
3. Update the doc by reading the code. Edit the affected section in place, matching its headings, tone and level of detail; never reorganise or rewrite a page.
4. If the doc needs nothing, record `- Doc impact: none — <reason>` under `## Rulings`. Use it only when the doc would not change.
5. Commit. A commit touching only document files in the reference-doc directories keeps an earlier L1 approval; an OpenAPI or SQL file there needs review.

The push gate warns when code for an existing doc changed without the doc or a `Doc impact` line. It never blocks.

## Writing derived docs

Read the source of truth; never write from memory or from the plan. No generator scripts.

- **Database.** Apply the migrations in order and describe the end state, not the history. Per table: its purpose, columns with type, nullability and default, keys, indexes, foreign keys with their on-delete rule, enumerated values, and the migration that last changed it. A dropped table is removed, not marked deprecated.
- **API.** Per endpoint: method and path, what it does, who may call it, parameters and body fields with types, status codes and response shapes, and what the signature does not say (pagination, idempotency, side effects). If the doc is generated elsewhere, link to it and document only what it lacks.
- **Data model.** Per entity: what it represents, fields and identity, relationships with cardinality and ownership, the invariants the code enforces, and the table it is stored in.

Never include what you inferred: if the code does not say whether a field may be null, write that it is unspecified. Leave out private helpers and copies of the code.

## Architecture

Hand-written. Update only the paragraph or component list a change touches — a new service, integration, queue or boundary. Never regenerate it or draw diagrams automatically.

If an existing doc is badly wrong outside your change, tell the user and leave it; fixing it is its own change.

## /exloom-setup on an existing codebase

When the repository has the code for a derivable doc and none of the docs, setup asks once whether to create them. On yes, write the database, API and data-model docs from the code on the current branch, as their own commit. On no, create nothing and do not ask again. Setup never creates architecture docs. It writes `.claude/exloom-docs` only when the docs live somewhere other than the defaults.
