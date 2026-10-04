---
name: authoring-claude-md
description: Use when scaffolding or updating a repo's CLAUDE.md — auto-detects stack, infers existing conventions for brownfield repos, merges with the baselines.
---

# Authoring CLAUDE.md

## Overview

Three modes: **greenfield** (new repo, template-based), **brownfield** (existing repo, inference-based), **update** (CLAUDE.md exists — never overwrite; propose an annotated diff). Document what the code *does*, never what it *should* do. Baselines apply only where compatible with the codebase. **Existing code wins**: if the repo uses tabs and the org says spaces, the CLAUDE.md says tabs; every conflict goes in Overrides. Never auto-commit.

## Process

### Brownfield Mode (existing repo)

Use when the repo has code and either no CLAUDE.md or a thin one.

**Step 1: Detect stack.** Scan the repo root and common subdirectories for `package.json`, `pom.xml`, `build.gradle`, `build.gradle.kts`, `pyproject.toml`, `setup.py`, `Cargo.toml`, `go.mod`, `composer.json`. Identify language and version, framework, test framework, and package manager from each; polyglot repos need every stack.

**Step 2: Scan file structure.** Map the top two levels: source roots, test roots, configuration directories, generated or vendor directories to exclude (`node_modules/`, `build/`, `dist/`, `target/`), and monorepo indicators (multiple `package.json` files, `modules/`, `packages/`).

**Step 3: Sample existing conventions.** Read 3-5 source files from different layers (controller, service, model, utility). Record naming, indentation, error handling, import ordering, comment style and test naming. If inconsistent, say so and let the user decide.

**Step 4: Choose template.** Select from `../../assets/claude-md-templates/` by detected stack. No match (e.g. Quarkus): `default.md`, not a near fit. Polyglot: primary backend template plus a section per additional stack.

**Step 5: Draft CLAUDE.md.** Fill the template with conventions OBSERVED in steps 1-3, never aspirational ones (JUnit 4 in the code means JUnit 4 in the doc). Include:
- Stack details (language, framework, versions, package manager)
- Project structure (directory map with one-line descriptions)
- Naming conventions, error handling patterns, test approach (framework, locations, naming, how to run)
- Build and run commands — run one only after reading it; if it mutates state or reaches external systems, document it from config without executing
- Notable architectural patterns (DDD, hexagonal, layered, event-driven)

**Step 6: Annotate with the baselines.** Add the Baselines section:
- Planning: use `exloom:planning-for-handoff` for non-trivial changes (3+ steps or architectural decisions)
- Review: run `/review-complete` before opening a PR
- New code follows your org's naming standards; existing code is not refactored to match
- Test coverage: 80% line coverage for new code (not retroactive)
- Secrets: environment variables only, never committed to source control
- Logging: structured logging with correlation IDs for services

Every baseline conflicting with what exists goes in Overrides with its reason.

**Step 7: Present to user for review.** Show the full draft first. Ask:
1. "Does this accurately reflect your project's conventions?"
2. "Any baselines that should go in Overrides?"

Apply feedback.

### Greenfield Mode (new project)

Use when the repo has no code yet or only scaffolding.

1. **Ask for stack.** One question: "What stack is this project using?" If ambiguous ("Java"), ask one follow-up about the framework.
2. **Pick template** from `../../assets/claude-md-templates/`; `default.md` if none matches.
3. **Fill template.** Add project name, description, team context and all baselines. Leave the Overrides section in place but empty, with: `_(Empty by default — record here any baseline this repo deliberately departs from, with the reason.)_`
4. **Commit with permission.** Propose `docs: add CLAUDE.md for [project name]` and wait for approval.

### Update Mode (CLAUDE.md exists)

Do not overwrite.

1. **Read the existing file completely.**
2. **Identify what needs changing**: codebase drift, a missing or incomplete Baselines section, dead file references, wrong commands.
3. **Propose changes as an annotated diff**, each with what and why, e.g. "Build command: changed from `mvn clean install` to `./gradlew build` — project migrated to Gradle".
4. **Let the user review.** Apply only approved changes; accept rejections without argument.
5. **Preserve existing structure.** Do not restructure to the org template. Add the Baselines section at the end.

If the existing file contradicts a baseline, it wins; record the conflict in Overrides. Never remove an Override entry without explicit user confirmation.

## CLAUDE.md Structure (works without a template)

If no template loads or fits, use these sections:

```markdown
# [Project Name]

## Overview
[1-2 sentences: what this project is and does]

## Stack
- Language + version, framework + version, package manager, database

## Project Structure
[Directory map, one line per significant directory]

## Conventions
- Naming (files, classes, variables — exactly what the code uses)
- Formatting (indentation, import ordering)
- Error handling (the actual pattern: exceptions, Result types, error envelope)
- Testing (framework, location, naming, how to run, coverage expectation)

## Build and Run
- Install, build, test, run commands (verified against the repo)

## Baselines
[The defaults from Step 6 — planning/review workflow, new-code naming,
 coverage for new code, secrets via env vars, structured logging.
 These apply to NEW code only.]

## Overrides
[Each place this repo deliberately departs from a baseline,
 with a one-line reason. Empty section with a placeholder comment if none.]
```

## Templates Reference

Templates live at `../../assets/claude-md-templates/`; if one is unreadable, use the structure above.

| Template | Stack | When to Use |
|----------|-------|-------------|
| `default.md` | Any | Fallback when no specific framework is detected, or for uncommon stacks |
| `spring.md` | Java 21+ / Spring Boot 3.x | `pom.xml` or `build.gradle` with Spring Boot starter dependencies |
| `micronaut.md` | Java 21+ / Micronaut 4.x | `build.gradle` with Micronaut dependencies or `micronaut-cli.yml` present |
| `nodejs.md` | Node.js 20+ / TypeScript | `package.json` with Node.js runtime (Express, Koa, Fastify, NestJS, plain) |
| `strapi.md` | Strapi 4.x / 5.x | `package.json` with `@strapi/strapi` as a dependency |
| `fastapi.md` | Python 3.12+ / FastAPI | `pyproject.toml` or `requirements.txt` with `fastapi` |
| `react.md` | React 18+ / TypeScript | `package.json` with `react` — CRA, Vite, or Next.js frontend |
| `angular.md` | Angular 17+ | `angular.json` present, `package.json` with `@angular/core` |
| `dotnet.md` | C# 12+ / ASP.NET Core 8.x | a `*.sln` or `*.csproj` at the root |
| `flutter.md` | Dart 3.x / Flutter 3.x | `pubspec.yaml` with a `flutter` SDK dependency |

Do not create new template files — extend `default.md`.

## Decision Points

| Situation | Decision |
|---|---|
| Repo has no established conventions (inconsistent, chaotic) | Start from the baselines. Note "inferred — no established pattern found." |
| Polyglot repo (e.g., Java backend + React frontend) | One CLAUDE.md at the repo root covering both stacks. Section headers per stack. |
| Monorepo with multiple projects | One CLAUDE.md per project root for project-specific conventions, plus one at the monorepo root for shared conventions. |
| User disagrees with an inferred convention | User wins. Update the CLAUDE.md to match. |
| No build file found (scripts, notebooks, plain files) | Use `default.md` template. Ask the user to describe the stack and tooling. |

## Failure Modes

See [failure-modes.md](failure-modes.md).

## Worked Example

See [worked-example.md](worked-example.md).

## Integration

- **You arrive here from:** a repo new to you with no CLAUDE.md, or one whose CLAUDE.md has drifted from the code.
- **You leave here toward:** a committed CLAUDE.md that every other skill reads for project context.
- **If the CLAUDE.md reveals a baseline conflict worth standardizing:** route to `exloom:capturing-learnings`.
