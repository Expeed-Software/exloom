---
name: exloom-setup
description: Set up exloom in this repository once — turn on the gate, pin and dry-run the test command, check that review files can be committed, choose strict mode, and show the effective configuration. Commits only after the user confirms.
---

# /exloom-setup

Run once per repository. Everything it writes is a committed file, because exloom honours its settings only when committed.

## Step 1 — Load the library

```bash
LIB="$(find ~/.claude/plugins -path '*exloom*/hooks/lib.sh' | sort -V | tail -1)"; . "$LIB"
```

`sort -V | tail -1` takes the highest installed version; `${CLAUDE_PLUGIN_ROOT}` is not set in your shell.

## Step 2 — Turn the gate on

Create `.claude/exloom-gate.enabled` (empty).

## Step 3 — Pin the test command

Detect the stack from the repository root and propose the command:

| Found | Command |
|---|---|
| `angular.json` | `npx ng test --watch=false --browsers=ChromeHeadless` |
| `package.json` with `vitest` | `npx vitest run` |
| `package.json` with `jest` or `react-scripts` | `CI=true npm test` |
| `package.json` with `@strapi/strapi` | `npm test`, only if a `test` script exists; otherwise ask the user for one |
| one `*.sln` (or one `*.csproj`) | `dotnet test <that file>` |
| `pubspec.yaml` | `flutter test` |
| `gradlew` / `mvnw` | `./gradlew test --rerun-tasks` / `./mvnw -q test` |
| `pyproject.toml` / `pytest.ini` | `pytest -q` |
| `go.mod` / `Cargo.toml` | `go test ./... -count=1` / `cargo test` |

Dry-run it once, non-interactively, with a timeout. It must exit 0 on the current tree without waiting for input or opening a browser. If it hangs, fails or asks for input, show the last lines and ask the user for the right command; do not pin one that has not passed. Then write it to `.claude/exloom-test-command`.

If the suite cannot run from tracked files alone (it needs local secrets or untracked state), the proof cannot run here. Ask the user, and with their agreement write `.claude/exloom-proof.disabled` instead.

## Step 4 — Check that review files can be committed

```bash
exloom_ignored_settings "$(git rev-parse --abbrev-ref HEAD)"
```

Every path it prints is git-ignored, and exloom ignores an uncommitted setting or receipt. If any are listed, show them and propose this `.gitignore` change, which keeps local files such as `settings.local.json` ignored:

```
.claude/*
!.claude/reviews/
!.claude/exloom-*
```

Apply it only when the user agrees.

## Step 4b — Reference docs

The defaults are `docs/db/`, `docs/api/`, `docs/data-model/` and `docs/architecture/`. If the repository keeps those docs elsewhere, write `.claude/exloom-docs` with one `<doc-dir>: <code globs>` line per doc (format in `exloom:maintaining-reference-docs`). If the defaults fit, or there are no docs, write nothing.

If the repository has migrations, an API or ORM models but none of the matching docs, ask once with AskUserQuestion: "Create the database, API and data-model docs from the code now?" On yes, write them from the code as that skill describes, on the current branch, and commit them as their own commit. On no, create nothing. Never create architecture docs or diagrams.

## Step 5 — Strict mode

Ask once with AskUserQuestion: "Strict mode — every branch on the Certified lane (no escape hatches, signed review commits)?" Recommend **No** unless the repository is regulated. On yes, create `.claude/exloom-strict`.

## Step 6 — Show the effective configuration

```bash
exloom_policy_load; echo "rc=$?"; exloom_policy_error; exloom_policy_fingerprint
```

A non-zero rc means `.exloom.yml` is invalid and the gate blocks every push: print the error and stop. Otherwise print:

```
Gate:            on
Test command:    <pinned>          | proof off (.claude/exloom-proof.disabled)
Strict mode:     yes | no
Max rounds:      <.claude/exloom-max-rounds, else 3> per plan task
Reviewer model:  <exloom_reviewer_model for each reviewer; opus unless set>
Policy:          .exloom.yml @ <fingerprint prefix> | none
Required reviewers by tier
  Tier 0, 1   l1-reviewer
  Tier 2      l1-reviewer, adversarial-reviewer
  Tier 3      l1-reviewer, adversarial-reviewer, security-auditor
```

If the branch already has a diff, add `exloom_derive_tier HEAD; exloom_tier_reasons`: the tier and the rule behind it. Repository rules in `.exloom.yml` only ever raise a tier or add a reviewer.

## Step 7 — Commit after the user confirms

List the files you wrote, ask the user to confirm, then commit only those:

```
chore(exloom): set up the review gate
```

Tell the user the next step: `/exloom` on any feature branch. A per-user preference — full gate messages instead of one line — is the plugin's `verbose` setting in `/plugin`.
