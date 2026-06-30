---
name: authoring-claude-md
description: Use when scaffolding or updating a repo's CLAUDE.md — auto-detects stack, infers existing conventions for brownfield repos, merges with the baselines.
---

# Authoring CLAUDE.md

## Overview

CLAUDE.md is the single most impactful file for AI-assisted development. It tells Claude what the project is, how it builds and runs, what conventions the team follows, and what patterns to use. Without it, Claude guesses — and guesses inconsistently across sessions, across developers, across tasks. With a well-authored CLAUDE.md, every developer on the team gets Claude that matches their project's actual patterns from the first prompt.

This skill operates in two primary modes: **greenfield** (new repo, template-based, fast) and **brownfield** (existing repo, inference-based, respects what's already there). A third mode, **update**, handles repos that already have a CLAUDE.md. In all three modes, the baselines are layered in — but only where they are compatible with what the codebase already does.

The brownfield principle is non-negotiable: **existing code wins**. If the repo uses tabs and your org's coding conventions say spaces, the CLAUDE.md says tabs. If the repo uses a stricter error handling pattern than your org recommends, keep the stricter pattern. Baselines exist for new code in repos with no established convention — they are defaults, not mandates.

Update mode deserves special emphasis: if a CLAUDE.md already exists, you never overwrite it. You read it, propose changes as an annotated diff, and let the user review. The existing file represents decisions the team already made.

**At a glance** (the rest of this skill is the detail behind these five steps):
1. Detect the stack and read 3-5 real source files to learn the *actual* conventions.
2. Pick a stack template from `../../assets/claude-md-templates/` (all are populated — `spring`, `angular`, `nodejs`, `fastapi`, etc.), or use the inline "CLAUDE.md Structure" below if none fits.
3. Draft the file documenting what the code *does*, never what it *should* do.
4. Add the Baselines, and put every conflict-with-reality in an Overrides section.
5. Present for review — never auto-commit. Existing code always wins over baselines.

## Process

### Brownfield Mode (existing repo)

Use this when the repo has code and either no CLAUDE.md or a thin one that needs expansion.

**Step 1: Detect stack.**

Scan for build and config files at the repo root and common subdirectories: `package.json`, `pom.xml`, `build.gradle`, `build.gradle.kts`, `pyproject.toml`, `setup.py`, `Cargo.toml`, `go.mod`, `composer.json`.

Read the contents of each found file to identify:
- Primary language and version
- Framework (Spring Boot, Micronaut, Express, FastAPI, React, Angular, etc.)
- Test framework (JUnit, Jest, pytest, etc.)
- Build tooling and package manager

Technique: check for multiple build files — some repos are polyglot. A single repo can have a `pom.xml` and a `package.json` and those are two different stacks that both need to be documented.

Bad pattern: stopping at the first build file found. A `package.json` in a Java project might just be for frontend tooling or linting configuration.

**Step 2: Scan file structure.**

List the top two directory levels. Map what you find:
- Source roots (`src/main/java`, `src/`, `app/`, `lib/`)
- Test roots (`src/test/java`, `__tests__/`, `tests/`, `spec/`)
- Configuration directories (`config/`, `resources/`, `.env*`)
- Generated or vendor directories to exclude (`node_modules/`, `build/`, `dist/`, `target/`)
- Any monorepo indicators (multiple `package.json` files, `modules/`, `packages/`)

Technique: folder names reveal the framework. `src/main/java` means Maven/Gradle Java. `app/` suggests Rails, Django, or FastAPI. `pages/` or `app/` with `next.config` means Next.js. `prisma/` at root means Prisma ORM.

Bad pattern: assuming a flat `src/` directory is always Node.js. Read the files inside it — it could be a Go project, a Rust project, or a C++ project.

**Step 3: Sample existing conventions.**

Read 3-5 representative source files from different parts of the codebase. Choose files from different layers (controller, service, model, utility) to get a cross-section. Document what you observe:
- Naming style: camelCase, snake_case, PascalCase, kebab-case for files
- Indentation: tabs vs spaces, indent width (2 or 4)
- Error handling: thrown exceptions, Result types, error codes, callback patterns
- Import ordering: stdlib first? grouped by type? sorted alphabetically?
- Comment style: JSDoc, Javadoc, docstrings, inline comments, none
- Test naming: `*Test.java`, `*.spec.ts`, `test_*.py`, `*_test.go`

If the codebase is inconsistent across files, note the inconsistency explicitly. Do not pick a winner — document that conventions vary and let the user decide which to standardize on.

Bad pattern: reading only one file and assuming the whole codebase follows its style. One file might be legacy, refactored, or written by a different team.

**Step 4: Choose template.**

Select from `../../assets/claude-md-templates/` based on the detected stack. If the stack does not match any available template, use `default.md`. If the repo is polyglot, use the primary backend template as the base and add sections for each additional stack.

Bad pattern: forcing a template that almost-but-not-quite fits. If it is a Quarkus project, use `default.md` and fill it manually rather than stretching `spring.md`. If it is a Hono project, use `nodejs.md` but note the differences from Express conventions.

**Step 5: Draft CLAUDE.md.**

Fill the template with conventions OBSERVED in steps 1-3. The draft should include:
- Stack details (language, framework, versions, package manager)
- Project structure (directory map with one-line descriptions)
- Naming conventions (exactly what the code uses, not what it "should" use)
- Error handling patterns (documented from actual code, not from a style guide)
- Test approach (framework, locations, naming, how to run)
- Build and run commands (prefer to verify by running them — but be cautious: an unfamiliar repo's build, test, or start scripts can have side effects like network calls, database migrations, code generation, or writing files. Read the script first; if it looks like it mutates state or reaches external systems, document the command from the config without executing it rather than running an unknown script blind)
- Notable architectural patterns (DDD, hexagonal, layered, event-driven)

Bad pattern: writing aspirational conventions. If the tests use JUnit 4, document JUnit 4 — do not write JUnit 5 because it is "better." If the code has no integration tests, say so — do not add a section on integration testing conventions.

**Step 6: Annotate with the baselines.**

Add the Baselines section. Standard baselines to include:
- Planning: use `exloom:planning-for-handoff` for non-trivial changes (3+ steps or architectural decisions)
- Review: run `exloom:auditing-plan-fidelity` before `exloom:reviewing-code`
- New code follows your org's naming standards; existing code is not refactored to match
- Test coverage: 80% line coverage for new code (not retroactive)
- Secrets: environment variables only, never committed to source control
- Logging: structured logging with correlation IDs for services

For each baseline, check if it conflicts with what exists. Conflicts go in the Overrides section with a clear explanation. Example: if the repo already has 60% coverage with no test infrastructure for legacy modules, do not write "80% coverage required" without an Override entry explaining the gap.

Bad pattern: silently overriding an existing convention with a baseline. The Overrides section exists precisely for these situations — use it.

**Step 7: Present to user for review.**

Show the complete draft to the user. Ask two questions:
1. "Does this accurately reflect your project's conventions?"
2. "Any baselines that should go in Overrides?"

Apply their feedback. Never auto-commit a CLAUDE.md. The user has final say on the document that governs how Claude operates in their repo.

Bad pattern: writing the file to disk without presenting it first. Even if you are confident in the output, the user may know details that a file scan cannot reveal.

### Greenfield Mode (new project)

Use this when the repo has no code yet or only scaffolding.

1. **Ask for stack.** One question: "What stack is this project using?" Do not present a multi-field form or a comparison menu. If the answer is ambiguous ("Java"), follow up with one clarifying question about the framework.

2. **Pick template.** Select the matching template from `../../assets/claude-md-templates/`. If no template matches the stated stack, use `default.md` and fill it in manually.

3. **Fill template.** Add the project name, description, and team context. Apply all the baselines — there are no existing conventions to conflict with. Include an empty Overrides section with a comment: `<!-- Add project-specific exceptions to the baselines here -->`.

4. **Commit with permission.** Propose the commit message `docs: add CLAUDE.md for [project name]` and wait for user approval before committing.

### Update Mode (CLAUDE.md exists)

When a CLAUDE.md is already present, the operating principle is: do not overwrite.

1. **Read the existing file completely.** Understand its structure, what it covers, and what decisions it encodes. Note any Overrides already documented — these are deliberate.

2. **Identify what needs changing.** Compare the existing CLAUDE.md against:
   - Current codebase state (did the build tool change? new modules added?)
   - The baselines (is the Baselines section present? complete?)
   - Accuracy (does it reference files that no longer exist? wrong commands?)

3. **Propose changes as an annotated diff.** For each proposed change, state what it is and why. Examples:
   - "Build command: changed from `mvn clean install` to `./gradlew build` — project migrated to Gradle"
   - "Adding the Baselines section — none of these conflict with existing conventions"
   - "Removing reference to `src/legacy/` — directory was deleted in commit abc123"

4. **Let the user review.** Apply only approved changes. If the user rejects a change, respect the decision without argument.

5. **Preserve existing structure.** If the existing CLAUDE.md does not follow your org's template structure, do not restructure it. Add the Baselines section at the end and leave the rest of the organization untouched.

If the existing CLAUDE.md contradicts a baseline, the existing file wins. Note the conflict in an Overrides section but do not change what the team already documented. Never remove an Override entry without explicit user confirmation — Overrides exist for a reason the original author understood.

## CLAUDE.md Structure (works without a template)

The templates are a convenience, not a dependency. If the template directory is missing, a template fails to load, or no template fits the stack, you can author a complete CLAUDE.md from this canonical structure alone. Every CLAUDE.md, template-derived or not, should contain these sections:

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

The two sections most often treated as "defined elsewhere" are spelled out here on purpose: **the Baselines** is the list in Step 6, and **Overrides** is where every baseline-vs-reality conflict is recorded with its justification. A reader with no template files can produce a correct CLAUDE.md from this skeleton.

## Templates Reference

Templates live at `../../assets/claude-md-templates/`. Each is a Markdown file with placeholder sections that get filled during the authoring process. If a listed template is absent or unreadable, fall back to the inline structure above and fill it from the conventions you detected — never block on a missing template.

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

If no template matches, use `default.md` and fill in detected conventions manually. Do not create new template files — extend the default.

## Decision Points

| Situation | Decision |
|---|---|
| Repo uses conventions that conflict with the baselines | Existing code wins. Document the conflict in Overrides with justification. |
| Repo has no established conventions (inconsistent, chaotic) | Use the baselines as the starting point. Note "inferred — no established pattern found." |
| Polyglot repo (e.g., Java backend + React frontend) | One CLAUDE.md at the repo root covering both stacks. Section headers per stack. |
| Monorepo with multiple projects | One CLAUDE.md per project root for project-specific conventions, plus one at the monorepo root for shared conventions. |
| User disagrees with an inferred convention | User wins. Update the CLAUDE.md to match their stated intent immediately. |
| Existing CLAUDE.md is comprehensive but not in your org's structure | Do not restructure it. Add the Baselines section at the end. Respect existing organization. |
| No build file found (scripts, notebooks, plain files) | Use `default.md` template. Ask the user to describe the stack and tooling. |

## Failure Modes

**1. "I know what conventions this project should use."**

Thought pattern: you have opinions about best practices — modern frameworks, clean architecture, certain naming styles — and you write the CLAUDE.md based on those opinions rather than what the code shows.

Why it feels right: best practices are best practices. The project would benefit from following them.

What happens: the CLAUDE.md documents a codebase that does not exist. Claude follows the CLAUDE.md, produces code that clashes with the actual codebase style, and every developer has to manually fix the mismatch on every task.

Correction: the codebase tells you what conventions it uses. Read the code. Document what is there, not what you wish were there.

**2. "The existing CLAUDE.md is wrong, let me fix it."**

Thought pattern: you see something in the existing CLAUDE.md that contradicts your understanding of the project or what you consider technically correct.

Why it feels right: accuracy matters. Wrong documentation is arguably worse than no documentation.

What happens: you overwrite decisions the team made deliberately. The "wrong" entry might be an intentional workaround, a team preference, or context you lack entirely.

Correction: propose changes with explanations. Let the user decide. The existing file represents team decisions you were not part of making.

**3. "Baselines should always apply."**

Thought pattern: baselines exist for a reason. Consistency across your org's projects reduces cognitive load when switching between them.

Why it feels right: standardization is valuable, and exceptions dilute the standard.

What happens: you override a working convention with a baseline that does not fit the project's reality. A repo with 60% coverage and no test infrastructure for legacy modules gets "80% required" — creating a mandate nobody can meet without a multi-sprint investment.

Correction: baselines are defaults for new code in the absence of existing conventions. Existing code that works differently is not wrong — it is context that the baseline did not anticipate.

**4. "I'll just use the Spring template — it's close enough."**

Thought pattern: the project is Java, and Spring is the most common Java framework in your org. The template covers most of what is needed.

Why it feels right: the templates are similar enough that it will work. Java is Java.

What happens: a Micronaut project gets Spring conventions — wrong annotation style (`@Inject` vs `@Autowired`), wrong testing approach (Micronaut Test vs Spring Test), wrong build plugin configuration. Developers follow the CLAUDE.md and produce code that fails to compile.

Correction: confirm the exact framework before choosing a template. Read the build file dependencies. A `pom.xml` with `spring-boot-starter-web` and a `build.gradle` with `io.micronaut:micronaut-http-server-netty` are fundamentally different projects that need different templates.

**5. "The CLAUDE.md is done, I'll move on."**

Thought pattern: you have written a thorough document and are confident it accurately reflects the codebase based on your analysis.

Why it feels right: the document matches what you observed across multiple files.

What happens: you commit without user review. The user discovers it contains a subtle error — the wrong test command, a misidentified framework version, or a convention from one module presented as a project-wide standard. The CLAUDE.md now actively misleads Claude on every task.

Correction: always present the draft for review before writing it to disk. The user knows their project better than a scan of 5 files can reveal. A two-minute review catches errors that would cost hours across the team.

## Worked Example

**Scenario:** Brownfield mode on an existing Node.js Express API with TypeScript. The developer just joined this project and ran `exloom:exploring-codebase`, which flagged the absence of a CLAUDE.md.

**Step 1 — Detect stack.**

Found `package.json` at the repo root. Reading its contents:
- `engines.node`: `">=20"`
- `devDependencies`: `typescript` 5.3, `jest` 29, `ts-jest`, `@types/express`
- `dependencies`: `express` 4.18, `@prisma/client` 5.x, `pino` 8.x, `zod` 3.x
- `scripts.start`: `"node dist/app.js"`, `scripts.dev`: `"tsx watch src/app.ts"`

Also found `.nvmrc` specifying `20.11.0` and a `Dockerfile` with `FROM node:20-alpine`.

No other build files at root. Checked subdirectories — no `pom.xml`, no `build.gradle`. This is a single-stack Node.js TypeScript project.

**Step 2 — Scan structure.**

Top two directory levels:
```
src/
  controllers/    -- route handlers
  services/       -- business logic
  middleware/     -- auth, error handling, logging
  prisma/         -- Prisma client setup
  types/          -- shared TypeScript types
  config.ts       -- environment config with zod validation
  app.ts          -- Express app setup and middleware chain
__tests__/
  controllers/    -- unit tests for controllers
  services/       -- unit tests for services
  integration/    -- API integration tests with supertest
prisma/
  schema.prisma   -- database schema
  migrations/     -- migration history
.env.example
tsconfig.json
jest.config.ts
package.json
```

Pattern: layered architecture (controllers call services, services call Prisma). Tests mirror the source structure in a separate `__tests__/` root. Integration tests are separated from unit tests. Prisma schema and migrations live at the repo root, not inside `src/`.

**Step 3 — Sample conventions.**

Read five files: `src/controllers/userController.ts`, `src/services/orderService.ts`, `src/middleware/authMiddleware.ts`, `__tests__/services/orderService.test.ts`, `src/config.ts`.

Observations:
- **Naming:** camelCase for variables and functions, PascalCase for types, interfaces, and classes. Files use camelCase (`userController.ts`, not `user-controller.ts`).
- **Indentation:** 2 spaces, no tabs. Consistent across all sampled files.
- **Error handling:** Services return `Result<T, AppError>` — a discriminated union. Services never throw. Controllers unwrap the Result and map `AppError` to HTTP status codes. This is stricter than thrown exceptions.
- **Imports:** Grouped in three blocks separated by blank lines — Node stdlib, then npm packages, then internal modules. Sorted alphabetically within each block.
- **Tests:** `describe`/`it` blocks. Test files named `*.test.ts`. Each test file mirrors one source file. Integration tests use `supertest` against the Express app.

**Step 4 — Choose template.**

`nodejs.md` matches — Node.js with TypeScript. Express is a standard Node.js framework covered by this template.

**Step 5 — Draft CLAUDE.md.**

Fill the `nodejs.md` template with observed patterns. Key decision point: the `Result<T, AppError>` pattern is stricter than your org's error handling baseline, which allows thrown domain errors caught by Express error middleware. The codebase's pattern is better for this project — it makes error handling explicit at every call site and prevents unhandled exceptions. Document the `Result` pattern as the project's error handling convention, not your org's default.

Also noted: `zod` is used for runtime validation of environment config and request bodies. This is an established pattern worth documenting — new endpoints should use zod schemas for input validation.

**Step 6 — Annotate baselines.**

Add the Baselines section:
- **Planning workflow:** added, no conflict with existing patterns
- **Review workflow:** added, no conflict
- **Error envelope:** added — compatible with the Result pattern. The controller layer already maps `AppError` variants to a consistent `{ error: string, code: string, details?: unknown }` JSON envelope.
- **Logging:** added — project already uses `pino` structured logging, which aligns with the baseline. Noted `pino` specifically in the conventions.
- **Security:** added — `.env.example` demonstrates the env-vars-only pattern. No secrets found in source.
- **Test coverage 80% for new code:** added to baselines. Existing coverage is 73%. Added an Override: "Legacy service modules (`orderService`, `inventoryService`) are below 80% — coverage target applies to new code and new modules only."

**Step 7 — Present to user.**

Showed the complete draft. User feedback:
- "We use pnpm, not npm — all build commands should reference pnpm." Fixed `npm run` to `pnpm` in the Build and Run section.
- "The Result pattern was introduced by our tech lead — good that you caught it. Keep it prominent."

User approved. File written with `docs: add CLAUDE.md for order-api`.

**Key moment:** The codebase uses a stricter error handling pattern than the baseline recommends. Brownfield wins — document what is there, do not downgrade it to match the baseline. The CLAUDE.md reflects the project's actual `Result<T, AppError>` pattern, and your org's error baseline is noted as compatible rather than authoritative.

## Integration

- **You arrive here from:** starting work on a new-to-you repo, or `exloom:exploring-codebase` discovers no CLAUDE.md exists and recommends creating one.
- **You leave here toward:** the CLAUDE.md is committed and becomes the project's working constitution. Future skills read it for project context — every other skill benefits from a well-authored CLAUDE.md.
- **If the CLAUDE.md reveals a baseline conflict worth standardizing:** route to `exloom:capturing-learnings` so the conflict, its context, and its resolution are preserved for future projects facing the same situation.
- **Related skill:** `exloom:switching-projects` reads CLAUDE.md as its primary input. A thorough CLAUDE.md directly improves how fast a developer can switch into a project with full Claude assistance.
- **Templates reference:** `../../assets/claude-md-templates/`
