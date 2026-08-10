---
name: switching-projects
description: Use when a developer is moving from one project to another — loads the new project's conventions, auto-detects differences from the previous project, produces a delta report with concrete trip-up warnings.
---

# Switching Projects

## Overview

Every project has its own conventions, stack quirks, and gotchas; applying the previous project's conventions is a common source of avoidable review comments. This skill is lighter than onboarding — it assumes you can already write code and focuses on one thing: the delta between the project you were on and the new one.

The output is a delta report — a table that puts old and new side by side, with explicit "watch out for" notes for the gaps most likely to trip you up.

## Process

### Step 1: Load the new project's CLAUDE.md and config

Read the new project's `CLAUDE.md` (Stack, Conventions, Overrides, Test Approach, Build/Run commands) and `README.md` (purpose, local setup, known caveats).

If `CLAUDE.md` is missing, suggest running `exloom:authoring-claude-md` first — working without one means Claude invents conventions, a real risk on a shared codebase. If the developer proceeds anyway, fall back to the README and the config files below, and note the gap in the report.

Also scan the project root for the ground-truth config — these are what the tools actually read, where `CLAUDE.md` only summarizes:
- **Linter/formatter:** `.eslintrc*`, `.prettierrc*`, `checkstyle.xml`, `.editorconfig`, `biome.json`
- **Build:** `package.json`, `build.gradle`, `pom.xml`, `Makefile`, `Cargo.toml`
- **Types:** `tsconfig.json`, `mypy.ini`
- **Environment:** `.env.example`, `docker-compose.yml`, `.tool-versions`, `.nvmrc`, `.java-version`
- **Git hooks:** `.husky/`, `.pre-commit-config.yaml`

If the README and CLAUDE.md disagree, flag it — one is stale. Ask the team which is current, then run `exloom:capturing-learnings` to resolve it.

### Step 2: Load the previous project's context

Ask: "What project are you switching from?" You need it to produce a meaningful delta. If the developer has no previous project (first project), redirect to `exloom:exploring-codebase` instead.

Get the previous context in this priority order — earlier sources are more reliable:

1. **Its CLAUDE.md, locally** — best source. Ask for the path to the checkout.
2. **Its repo, accessible** — read CLAUDE.md, README, and root config from the remote or another checkout.
3. **Auto-detect from its build/config files** — if there's a path but no CLAUDE.md, extract language/version, framework, test framework, linter, and build commands directly from `package.json`/`build.gradle`/config files.
4. **Developer's memory** — last resort. Ask targeted questions (language+framework, test framework + run command, linter setup, build/run command, gotchas, env/Docker setup), and mark any row sourced this way "(from memory — verify)".

### Step 3: Produce the delta report

Compare the two projects and produce a table. Cover these concerns where they differ (omit or mark "Same" where they don't): language, framework, build tool, test framework, coverage threshold, naming, module structure, database/ORM, linter/formatter, editor/IDE config, environment setup, git hooks, code-review norms, deployment, and project-specific gotchas.

The "Watch Out For" column is where the value lives — it's not about the technology, it's about *this team's conventions with the technology*.

```markdown
## Project Switch: [Previous] → [New]

| Concern | Previous | New | Watch Out For |
|---------|----------|-----|---------------|
| Language | Java 17 | TypeScript 5 | Strict mode on — null checks enforced |
| Framework | Spring Boot 3 | Express 4 | No DI container — wiring is manual, see src/container.ts |
| Build | Gradle | pnpm | NOT npm — `npm install` creates a conflicting lockfile |
| Linter | Checkstyle (CI only) | ESLint + Prettier (pre-commit) | Code that fails lint won't commit — run `pnpm lint:fix` |
| Environment | Docker Compose | `.env.local` + local Node | Copy `.env.example`; Redis not used here |
| Deployment | Jenkins (staged) | Vercel (auto on merge to main) | Every merge to main goes live — use feature branches |
```

After the table, distill the **top 3-5 trip-ups** — pull the rows from the "Watch Out For" column where the gap is widest or the consequence most immediate (broken build > review comment > style nit). Keep it to a tight list; don't re-explain what the table already said.

### Step 4: Offer a deeper walkthrough

Ask: "Is the delta enough to start, or do you want a deeper walkthrough?" If deeper → invoke `exloom:exploring-codebase` on the new repo. If sufficient → hand over the report and suggest a starter ticket to apply the new conventions under low pressure first.

## First Day on the New Project

Before writing any code, in order:

1. **Set up the environment and editor.** Follow the README setup exactly. If the delta flagged a linter/formatter change or the project ships `.vscode/settings.json` or `.editorconfig`, configure your editor now — wrong formatting on every file you touch is noise in the PR.
2. **Build locally, end to end.** If the build fails, fix it before writing code — never work in a broken environment.
3. **Run the tests.** A passing suite is your baseline. If tests already fail when you arrive, note which and why before touching anything, so you know later failures are yours.
4. **Read one existing implementation** similar to your task. Match real code in this project, not the style you inferred from the delta.
5. **Skim open PRs and the most recent merged PR.** Open PRs prevent collisions; the merged PR shows you the team's review bar and conventions in action.

**Gate before your first commit:** build passes, tests pass, editor configured to match the project, CLAUDE.md read, and at least one existing implementation read as a pattern reference. If git hooks exist, confirm they run (a throwaway commit, then revert).

## Worked Example

**Context:** A developer has been on `inventory-service` (Java 21, Spring Boot 3, Gradle, Postgres, JUnit 5 + Testcontainers) for six months. They're moving to `customer-portal` (TypeScript 5, Next.js 14, pnpm, Prisma, Vitest + Playwright).

**Step 1-2:** New project's CLAUDE.md read — App Router, Server Components by default, Prisma with migrations owned by a separate `db-migrations` repo, Husky pre-commit running lint-staged. Previous project checked out locally, CLAUDE.md read — layered architecture, Flyway auto-migrate, Checkstyle in CI only, no local hooks.

**Step 3 — delta report.** Built in the format shown above; abridged here to the three rows that became the top trip-ups (the full report covered ~10 rows):

```markdown
## Project Switch: inventory-service → customer-portal

| Concern | inventory-service | customer-portal | Watch Out For |
|---------|------------------|-----------------|---------------|
| Build | Gradle | pnpm | `npm install` creates a conflicting lockfile — use `pnpm` |
| Framework | Spring Boot 3 | Next.js 14 App Router | Server Components by default — no useState/onClick without `'use client'` |
| Database | JPA + Flyway (auto-migrate) | Prisma, migrations in separate repo | You cannot migrate from this repo — PR the db-migrations repo first |
```

Those three "Watch Out For" cells are the top trip-ups — wrong package manager corrupts the lockfile, the backend-developer instinct to add interactivity everywhere fails under Server Components, and there's no Flyway-style auto-migrate here.

**Step 4:** Developer chose a deeper walkthrough → invoked `exloom:exploring-codebase`.

## Failure Modes

### "I'll figure out the differences as I go"

You're experienced, so a delta report feels like hand-holding. But your first PR collects a dozen trivial review comments — wrong package manager, wrong directory convention, hardcoded value where a token exists — each minor, together signaling "didn't read the setup." Your next PR gets extra scrutiny. Twenty minutes on the delta is cheaper than the trust you spend recovering. **Read the delta.**

### "The previous project did it better — I'll bring that pattern here"

You've seen a better way, and improving the project feels helpful. But you reintroduce something the team deliberately removed (they dropped Testcontainers because CI was too slow; they chose their test framework for a reason). Your "improvement" becomes a maintenance burden and confuses the next switcher. **Match existing patterns for your first month; propose changes through the normal process afterward.**

### "I'll fix the tooling later"

Setting up editor extensions feels like yak-shaving you can defer. But every file you touch gets mis-formatted, your diff becomes 400 lines of whitespace around 20 lines of real change, and pre-commit hooks reject the commit anyway. **Set up the editor and tooling first — the delta tells you exactly what to install.**

### "I know this stack, I don't need the delta"

You know Next.js, so the report seems redundant. But the report isn't about Next.js — it's about *this team's* conventions with Next.js: Server Components by default, migrations in a separate repo, Vercel deploying on push. Those break your first week, not the framework. **The "Watch Out For" column is project-specific, not technology-specific — that's where the value is.**

## When NOT to Use This Skill

- **The new project is a totally different stack** (e.g., Java → Python for the first time) — the delta is too large to be useful. Run `exloom:exploring-codebase` from scratch.
- **The developer has never worked on any project** — run `exloom:exploring-codebase` instead.
- **No CLAUDE.md and no README** — no meaningful delta is possible. Run `exloom:authoring-claude-md` first.

## Related Skills

- `exloom:exploring-codebase` — deeper walkthrough when the delta isn't enough, or when the new stack is unfamiliar
- `exloom:authoring-claude-md` — use if the new project's CLAUDE.md is missing or thin
- `exloom:capturing-learnings` — use when the delta reveals a gotcha worth documenting for future switchers
