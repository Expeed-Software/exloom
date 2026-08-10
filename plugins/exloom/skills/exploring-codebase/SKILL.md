---
name: exploring-codebase
description: Use when joining an unfamiliar repo or before making non-trivial changes in one — produces a structured mental model of entry points, components, data flow, and tests.
---

# Exploring Codebase

## Overview

This skill produces a structured mental model before any code changes begin.

The output is a Markdown document — saved to `.claude/project-notes.md` — that gives you and your Claude Code sessions a working map of the repo, so future sessions start from it instead of re-exploring from scratch. Team-level facts that belong to everyone (architecture, conventions, gotchas) get promoted into the repo's committed `CLAUDE.md`; the personal notes file is your own working memory. See the Save Location section for how to split the two.

This skill is not about reading every file. It is about tracing the shape of the system: where things start, where they go, how they are tested, and what the gotchas are.

## Process

Work through these steps in order. Each step builds on the previous.

### Step 1: Read README and CLAUDE.md First

Before looking at any source code:

1. Read `README.md` — understand the project's stated purpose, setup instructions, and any known caveats.
2. Read `CLAUDE.md` — this is the fastest path to conventions. If it's thorough, steps 3-5 may be quick confirmations rather than discoveries.
3. Note any sections marked as "Overrides" in CLAUDE.md — these are intentional departures from defaults that you'll need to respect.

If CLAUDE.md doesn't exist, note this as a gap and suggest running `exloom:authoring-claude-md` after the exploration is complete.

### Step 2: Identify Entry Points

Find where the system starts. Entry points vary by type:

| Application Type | Where to Look |
|-----------------|---------------|
| Spring Boot | `@SpringBootApplication` class, `main()` method |
| Micronaut | `Application.main()`, `Application.run()` |
| Express / Node.js | `index.ts`, `server.ts`, `app.ts` |
| FastAPI | `main.py`, `app = FastAPI()` |
| React | `index.tsx`, `App.tsx` |
| Angular | `main.ts`, `app.module.ts`, `app.component.ts` |
| CLI tool | `main()`, `cli.py`, `bin/` directory |
| Background job | Scheduler configuration, cron setup, queue consumer |

For each entry point found:
- Note its file path
- Note what it initializes or wires up
- Note what it hands off to

### Step 3: Map Top-Level Structure

Do not read every directory. Map the shape:

```
src/
  controllers/    — HTTP layer, routing
  services/       — business logic
  repositories/   — data access
  models/         — domain entities
  config/         — wiring and configuration
  util/           — shared utilities
```

For each top-level directory, write one sentence: what lives here and what it's responsible for. If a directory's purpose is unclear from its name alone, sample 2-3 files to infer it.

Flag any directories that look like tech debt: `legacy/`, `deprecated/`, `old/`, or directories that seem to duplicate another.

### Step 4: Trace One Representative Operation End-to-End

Pick one representative operation — a common API endpoint, a page load, a background job — and trace it from entry to exit through every layer it touches.

For a web API, trace: HTTP request → controller → service → repository → database → response.
For a background job, trace: trigger → handler → business logic → side effects → completion.
For a UI component, trace: user action → event handler → state change → render.

Document the full path with file names at each hop. This trace reveals:
- How layers communicate (interfaces, direct calls, events)
- Where cross-cutting concerns live (auth, logging, error handling)
- Whether the architecture matches what the README claims

### Step 5: Locate Tests and Note Conventions

Find the test root(s) and characterize the test suite:

- **Test framework:** JUnit 5, Jest, pytest, Jasmine, etc.
- **Test locations:** Same directory as source? Separate `test/` tree? Both?
- **Test naming:** `*Test.java`, `*.spec.ts`, `test_*.py`?
- **Integration vs unit split:** Are they separated by directory, annotation, or file name prefix?
- **How to run:** The exact command (e.g., `./gradlew test`, `npm test`, `pytest`)
- **Test coverage:** Is a threshold configured? Where?

Sample 2-3 test files to understand what "a good test" looks like in this codebase. Note any unusual helpers, fixtures, or base classes that tests rely on.

### Step 6: Locate Configuration and Environment Setup

Find how the application is configured:

- **Local config:** `application.yml`, `.env`, `config.js`, etc.
- **Secrets management:** Environment variables, vault, config server?
- **Profile/environment switching:** How does local differ from staging/production?
- **Required env vars:** What must be set for the app to start?

Note any `*.example` or `*.template` config files — these are the documented baseline for local setup.

### Step 7: Locate Deploy Configuration

Find how the application gets to production:

- **CI/CD:** `.github/workflows/`, `Jenkinsfile`, `gitlab-ci.yml`, `bitbucket-pipelines.yml`
- **Containerization:** `Dockerfile`, `docker-compose.yml`
- **Infrastructure:** Kubernetes manifests (`k8s/`, `helm/`), Terraform, CloudFormation
- **Deploy scripts:** `Makefile`, shell scripts in `scripts/`

Note what triggers a deployment, what environments exist, and whether there are manual steps.

### Step 8: Produce Mental Model Document

Compile everything into `.claude/project-notes.md` using the structure below. Then split it by audience: the team-level sections — **Stack, Core Components, Data Flow, Tests, Configuration, Deploy, Gotchas** — are durable facts every developer on this repo needs, so promote them into the repo's committed `CLAUDE.md` (run `exloom:authoring-claude-md` if it's missing or thin). Keep only your personal working notes — open questions, "look at X next," tentative impressions — in the gitignored `project-notes.md`.

Structure:

```markdown
# [Project Name] — Mental Model

_Last updated: [date] | Explored by: [author]_

## Overview
[1-2 sentences: what this system does and why it exists]

## Stack
- Language: [language and version]
- Framework: [framework and version]
- Database: [database type and how it's accessed]
- Key dependencies: [3-5 most significant libraries]

## Entry Points
- [file path]: [what it does]
- [file path]: [what it does]

## Core Components
| Component | Path | Responsibility |
|-----------|------|----------------|
| [name] | [path] | [one sentence] |

## Data Flow
[Trace from Step 4, written as prose or a numbered sequence]

## Tests
- Framework: [name]
- Location: [path]
- Run with: `[command]`
- Coverage threshold: [N%] or "none configured"
- Conventions: [key observations]

## Configuration
- Local config: [path]
- Required env vars: [list or "see .env.example"]
- Profile switching: [how]

## Deploy
- CI/CD: [system and trigger]
- Environments: [list]
- Containerized: [yes/no, tool]

## Gotchas Discovered
- [Anything surprising, inconsistent, or worth warning a new developer about]
```

## Save Location

Write the document to `.claude/project-notes.md` in the repo root. Create the `.claude/` directory if it doesn't exist.

The two destinations serve different purposes:

- **Durable, team-level facts** — architecture, conventions, entry points, gotchas that every developer on this repo needs — belong in `CLAUDE.md`, committed and shared. If `CLAUDE.md` is thin or missing, run `exloom:authoring-claude-md` and route these findings there.
- **Personal working memory** — your own scratch notes, half-formed questions, "I should look at X next" reminders — belong in `.claude/project-notes.md`, gitignored, because they are yours and would be noise to others.

Add `.claude/project-notes.md` to `.gitignore` if the repo has one.

Exception: if the team explicitly wants a committed exploration document distinct from `CLAUDE.md` (for example, a longer architecture walkthrough), save to `docs/project-notes.md` and commit it.

## Failure Modes

### 1. "Let me read every file to really understand it"

**The thought pattern:** Thoroughness means completeness. To understand the codebase, you read all of it.

**Why it feels right:** Reading more feels like understanding more. Skipping files feels like cutting corners.

**What actually happens:** You spend two days reading 200 files, retain a vague impression of all of them and a clear model of none. You read infrastructure plumbing and generated code as carefully as the core domain logic, wasting your attention budget on code you will never touch. By the time you finish, you have forgotten the first half.

**The correction:** Exploration is tracing the shape, not reading the contents. Follow the 8 steps. Trace ONE operation end-to-end (Step 4) rather than reading every operation. Sample 2-3 files per directory, not all of them. You build a map, not a memorized transcript.

### 2. "I'll start coding now and figure out the structure as I go"

**The thought pattern:** Exploration is overhead. I'll learn the codebase by working in it.

**Why it feels right:** Writing code feels productive. Reading code feels passive. You want to show progress.

**What actually happens:** You put your change in the wrong layer because you didn't know the layering. You duplicate a utility that already existed because you never saw it. You violate a convention nobody told you about, and it surfaces in code review. Each of these costs more than the exploration would have.

**The correction:** Twenty minutes of structured exploration prevents hours of misplaced work. The map tells you where your change belongs before you write it.

### 3. "The README explains everything, I don't need to trace the code"

**The thought pattern:** The documentation describes the architecture. Reading it is enough.

**Why it feels right:** The README is the team's own description of their system. Who would know better?

**What actually happens:** The README describes the architecture the team intended two years ago. The code drifted. The README says "all data access goes through the repository layer," but three services query the database directly because of a deadline. You trust the README, put your code in the wrong place, and match a pattern that no longer exists.

**The correction:** The README tells you the intent. Step 4 (trace one operation end-to-end) tells you the reality. When they conflict, the code wins — and note the drift in your Gotchas section so the next person knows.

### 4. "I explored it last quarter, I still know it"

**The thought pattern:** I've worked in this repo before. I don't need to re-explore.

**Why it feels right:** You have real memory of the codebase. Re-exploring feels redundant.

**What actually happens:** The repo changed. A refactor moved the entry points. A framework upgrade relocated config. Three new services appeared. Your stale mental model leads you to look for things where they used to be, and you waste time discovering they moved — or worse, you act on the old model.

**The correction:** Read `.claude/project-notes.md` first. If it's more than a few months old on an active repo, skim the recent git history and update the notes. A 5-minute refresh beats acting on a stale map.

## Worked Example

**Scenario:** A developer joins a project to fix a bug in order processing. They've never seen this repo. It's a Spring Boot service. Rather than diving straight into the order code, they run a 25-minute exploration first.

### Step 1: README and CLAUDE.md

README says: "Order management service. Handles order lifecycle from creation to fulfillment. PostgreSQL for persistence, Kafka for events." CLAUDE.md exists and has an Overrides section: "We use constructor injection only — no field `@Autowired`. All money values use `BigDecimal`, never `double`."

That Overrides note is gold — it's exactly the kind of convention that causes review rejections if violated.

### Step 2: Entry Points

`OrderServiceApplication.java` with `@SpringBootApplication`. Also finds a Kafka consumer entry point: `OrderEventConsumer.java` with `@KafkaListener`. So there are two ways into this system: HTTP (REST controllers) and events (Kafka). Important — a bug in order processing could be triggered by either path.

### Step 3: Top-Level Structure

```
src/main/java/com/example/orders/
  controller/   — REST endpoints (OrderController, FulfillmentController)
  service/      — business logic (OrderService, PricingService, FulfillmentService)
  repository/   — Spring Data JPA repositories
  domain/       — JPA entities (Order, OrderLine, Customer)
  events/       — Kafka producers and consumers
  config/       — Spring configuration
```

No legacy/ or deprecated/ directories. Clean structure.

### Step 4: Trace One Operation — "Create Order"

Traced `POST /api/orders` end-to-end:

`OrderController.createOrder()` → validates request DTO → `OrderService.create()` → `PricingService.calculateTotal()` (uses BigDecimal, matches the CLAUDE.md convention) → `OrderRepository.save()` → publishes `OrderCreatedEvent` via `OrderEventProducer` → returns 201 with order ID.

Key discovery: order creation publishes a Kafka event. Anything that consumes `OrderCreatedEvent` is part of the order flow. The bug being investigated involves order totals — `PricingService` is the prime suspect, and it's the layer to focus on.

### Step 5: Tests

JUnit 5 + Testcontainers (real Postgres in tests, no mocks). Tests in `src/test/java`, mirroring the source package structure. Naming: `*Test.java` for unit, `*IT.java` for integration. Run with `./gradlew test` (unit) and `./gradlew integrationTest` (integration). Coverage threshold: 80% configured in `build.gradle`. Sampled `PricingServiceTest.java` — good example of how the team structures arithmetic tests.

### Step 6: Configuration

`application.yml` with profiles for local, staging, prod. `.env.example` present. Required env vars: `DB_URL`, `KAFKA_BROKERS`, `DB_PASSWORD`. Local uses Docker Compose for Postgres and Kafka.

### Step 7: Deploy

`.github/workflows/deploy.yml` — deploys on merge to main, through staging then prod with a manual approval gate. Containerized via `Dockerfile`.

### Step 8: Mental Model Document

Compiled all findings into `.claude/project-notes.md`. Added to the Gotchas section: "Order creation publishes Kafka events — changes to order flow must consider event consumers. Money is always BigDecimal (enforced by convention, not the type system). Two entry points: REST and Kafka."

**The payoff:** The developer now knows the bug in order totals lives in `PricingService`, that it's tested with real Postgres via Testcontainers, that they must use BigDecimal, and that their fix might affect Kafka event consumers. They spent 25 minutes and avoided: putting the fix in the wrong layer, using `double` and failing review, and missing the event-consumer side effect. The bug fix itself is now a focused, well-targeted change.

## When to Re-Run

Re-run this skill (or update the notes manually) when:

- A major refactor changes the layer structure or entry points
- The team has been away from the repo for 3+ months
- A framework upgrade changes where things live
- A new team member joins who hasn't explored the repo yet

Stale project notes are worse than no notes — they mislead. If notes are more than 6 months old and the repo is active, re-run.

## Related Skills

- `exloom:authoring-claude-md` — run after this skill if CLAUDE.md is missing or thin; exploration findings directly populate it
- `exloom:switching-projects` — uses this skill for deep walkthroughs when switching to a very different stack
