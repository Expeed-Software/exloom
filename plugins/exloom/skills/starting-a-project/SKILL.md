---
name: starting-a-project
description: Use when the user asks to start, create, scaffold or set up a new project, app or service from scratch, in an empty or near-empty folder. Agrees what the product is and what it is built on, writes the first project docs, and scaffolds a minimal app whose commands all pass. Not for adding a feature to existing code; that is /exloom.
---

# Starting a project

A team's first feature goes wrong when nobody wrote down what the product is or what it is built on, and each developer guesses differently. This skill settles both once, in files the whole team reads, and leaves a skeleton that runs. It builds no feature: features go through `/exloom` afterwards.

## 1. Check that it is new

Look for source code and manifests (`package.json`, `pom.xml`, `build.gradle*`, `*.csproj`, `pyproject.toml`, `go.mod`, `src/`). If real code exists, say this skill is for new projects, point to `/exloom`, and stop. A folder with only a README, a LICENSE, a `.gitignore` or `docs/` is new: read what is there and use what it already settles.

## 2. Agree the product

Ask one question at a time, most important first, offering two to four options with your recommendation first where the answer is a choice. Ask only about gaps:

- what the product is and the difference it makes;
- who uses it, and what each comes to do;
- the problems it solves, and what they cost today;
- what it covers and what it deliberately does not;
- the limits every feature must respect: devices and browsers, accessibility, privacy and compliance, scale, languages;
- the domain terms, so later specs name things the same way.

Keep this non-technical: a framework or database is settled in the next step. Do not ask for a feature list. If the idea itself is unclear, run `exloom:brainstorming` first.

Write `docs/product.md` from [product-template.md](product-template.md). Fill in every section; write "None" where there is nothing.

## 3. Settle the stack

Work out what the product needs from step 2: every constraint in `docs/product.md` must be met by something in the stack. Then settle, one question at a time, skipping what the user already decided: the kind of application, language and runtime, framework, storage, test framework, lint and format tools, and package manager. Prefer mainstream, well-supported choices, and say which constraint drove a recommendation. Check current versions and the official way to create a project in the library's documentation, not from memory.

Write `docs/architecture/overview.md` from [architecture-template.md](architecture-template.md), with a row for every constraint and every decision with the alternatives rejected.

## 4. Scaffold a skeleton that runs

If the folder is not a git repository, run `git init` and say so. Then create the smallest app that runs, with nothing in it that belongs to a feature:

- Use the framework's official generator with non-interactive flags, into the repository root, without losing existing files.
- Remove demo content that could be mistaken for a feature. Keep one page, endpoint or command that shows the app runs.
- Add one trivial test that passes, the lint and format configuration, a `.gitignore` for the stack that does not ignore `.claude/reviews/` or `.claude/exloom-*`, and a `.gitattributes` with `* text=auto eol=lf`. Make the formatter and the linter skip `.claude/`, so exloom's review files never fail a check.
- Tests that need a browser run in the test runner's own bundled browser (Playwright's Chromium, for example), headless, never in the browser installed on the developer's machine: that one differs per machine and opens on their screen.
- Install the dependencies.

Write `README.md` with a Commands table (build, lint, type check, tests, run the app; "none" where there is none) and links to the two docs. Then run `exloom:authoring-claude-md` in its new-project mode for `CLAUDE.md`.

If the product has a user interface, run `exloom:defining-a-design-system` now and tell it this skill is running it. It settles the look, writes `docs/design-system.md`, and themes the skeleton. Skip it for an API, a command-line tool, a library or a background service.

## 5. Prove every command

Run each command in the README's table yourself and record its exit code; stop any process you start. If one fails, fix the skeleton and run them all again, at most three times. After the third failure, stop, show the results, and ask whether to retry with the user's guidance, change a stack choice, or stop.

When the test command passes, write it to `.claude/exloom-test-command`, so the first feature's proof has it. The proof runs this command in a throwaway copy of the repository with nothing installed, so it must install what it needs first: for npm, `{ [ -d node_modules ] || npm ci; } && npm test`. Run it once in a temporary copy of the project without the installed dependencies before pinning it.

## 6. Hand over

Show the user the docs written (the design system too, if there is one), the stack in one line, the files created, and each command with its result. Ask them to read the docs, and apply their corrections. Propose one commit on the default branch, `chore: start <project>`, and wait for their yes.

Then propose two to four first features from the users and problems in `docs/product.md`, your recommendation first: usually the core flow the others depend on. For the one they pick, create a feature branch and run `/exloom`.
