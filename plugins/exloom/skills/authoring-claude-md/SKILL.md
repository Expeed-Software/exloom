---
name: authoring-claude-md
description: Use when scaffolding or updating a repo's CLAUDE.md — auto-detects stack, infers existing conventions for brownfield repos, merges with the baselines.
---

# Authoring CLAUDE.md

Document what the code does, never what it should do. **Existing code wins**: if the repo uses tabs and the org says spaces, the CLAUDE.md says tabs, and the conflict goes under Overrides. Never commit without the user's approval.

## Existing repo, no CLAUDE.md or a thin one

1. **Detect the stack** from `package.json`, `pom.xml`, `build.gradle*`, `pyproject.toml`, `Cargo.toml`, `go.mod`, `composer.json`: language and version, framework, test framework, package manager. A polyglot repo needs every stack.
2. **Map the top two directory levels**: source and test roots, config, generated or vendor directories, monorepo markers.
3. **Sample three to five source files from different layers** and record naming, indentation, error handling, import order and test naming. If they are inconsistent, say so and let the user decide.
4. **Pick a template** (below) and fill it with what you observed: JUnit 4 in the code means JUnit 4 in the doc. Read a build or run command before running it; if it mutates state or reaches external systems, document it from config without executing.
5. **Add the Baselines section**, and put each baseline the repo conflicts with under Overrides with its reason:
   - Planning: `exloom:planning-for-handoff` for non-trivial changes.
   - Review: `/exloom` before opening a PR.
   - New code follows the org's naming standards; existing code is not refactored to match.
   - 80% line coverage for new code, not retroactive.
   - Secrets in environment variables only.
   - Structured logging with correlation IDs for services.
6. **Show the full draft** and ask: does it reflect the project's conventions, and should any baseline move to Overrides?

## New project

For a project with no code yet, `exloom:starting-a-project` settles the product and the stack first and then calls this mode; use its answers and do not ask again. Otherwise ask once what stack it uses. Fill the matching template with the project name, description and all baselines, and leave Overrides in place but empty. Propose `docs: add CLAUDE.md for <project>` and wait.

## CLAUDE.md already exists

Never overwrite. Read it fully, then propose an annotated diff, each change with what and why ("Build command: `mvn clean install` → `./gradlew build` — migrated to Gradle"). Apply only what the user approves. Keep its structure and add Baselines at the end. Where it contradicts a baseline, it wins: record that under Overrides. Never remove an Override entry without the user's confirmation.

## Templates

In `../../assets/claude-md-templates/`. Do not create new ones; extend `default.md`.

| Template | Use when |
|---|---|
| `spring.md` | Spring Boot starters in `pom.xml` or `build.gradle` |
| `micronaut.md` | Micronaut dependencies or `micronaut-cli.yml` |
| `nodejs.md` | A Node.js runtime in `package.json` |
| `strapi.md` | `@strapi/strapi` in `package.json` |
| `fastapi.md` | `fastapi` in `pyproject.toml` or `requirements.txt` |
| `react.md` | `react` in `package.json` |
| `angular.md` | `angular.json` |
| `dotnet.md` | A `*.sln` or `*.csproj` at the root |
| `flutter.md` | A `flutter` SDK dependency in `pubspec.yaml` |
| `default.md` | Anything else — not a near fit |

With no readable template, use these sections: Overview, Stack, Project Structure, Conventions (naming, formatting, error handling, testing), Build and Run, Baselines, Overrides.

## Decisions

| Situation | Decision |
|---|---|
| No established conventions | Start from the baselines; note "inferred — no established pattern found". |
| Polyglot repo | One CLAUDE.md at the root, a section per stack. |
| Monorepo | One per project root, plus one at the root for shared conventions. |
| The user disagrees with an inferred convention | The user wins. |

See [failure-modes.md](failure-modes.md) and [worked-example.md](worked-example.md).
