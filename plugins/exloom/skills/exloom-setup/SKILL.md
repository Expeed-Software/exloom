---
name: exloom-setup
description: Set up exloom in this repository once — choose optional or mandatory mode, pin and dry-run the test command, check that review files can be committed, choose strict mode, and show the configuration. Commits only after the user confirms.
---

# /exloom-setup

Run once per repository. Everything it writes is committed — exloom honours only committed settings — on this setup branch, reaching main through review and a pull request, never a direct commit.

## Step 1 — Load the library

```bash
XL_ROOT='${CLAUDE_PLUGIN_ROOT}';XL_FILE="$XL_ROOT/hooks/lib.sh";[[ $XL_ROOT =~ ^(/|[A-Za-z]:/) && -f $XL_FILE ]]||{ echo "exloom: $XL_FILE missing; reinstall exloom or update Claude Code">&2;exit 1;};. "$XL_FILE"
```

## Step 2 — Optional or mandatory

Ask once with AskUserQuestion: "Optional or mandatory here?"

**Optional (recommended).** Write no gate switch: each developer is asked once per branch, and only a branch that said yes is checked. Right where some of the team use exloom and some do not.

**Mandatory.** Create `.claude/exloom-gate.enabled` (empty): every branch is checked, including developers who never chose exloom.

Everything below may be committed either way; on an ungated branch it does nothing.

## Step 3 — Pin the test command

Detect the stack and propose:

| Found | Command |
|---|---|
| `angular.json` | `./node_modules/.bin/ng test --watch=false --browsers=ChromeHeadless` |
| `package.json` with `vitest` | `./node_modules/.bin/vitest run` |
| `package.json` with `jest` or `react-scripts` | `CI=true npm test` |
| `package.json` with `@strapi/strapi` | `npm test`, if a `test` script exists; else ask |
| one `*.sln` (or one `*.csproj`) | `dotnet test <that file>` |
| `pubspec.yaml` | `flutter test` |
| `gradlew` / `mvnw` | `./gradlew test --rerun-tasks` / `./mvnw -q test` |
| `pyproject.toml` / `pytest.ini` | `pytest -q` |
| `go.mod` / `Cargo.toml` | `go test ./... -count=1` / `cargo test` |

Dry-run it once, non-interactively, with a timeout. It must exit 0 without waiting for input or a browser. If it hangs or fails, show the last lines and ask for the right one; never pin one that has not passed. Then write `.claude/exloom-test-command`.

If the suite needs local secrets or untracked state, the proof cannot run here: with the user's agreement write `.claude/exloom-proof.disabled` instead.

## Step 3b — Running only some tests

Work out this repo's "run only these tests" form, with `{tests}` where the paths or class names go — `./gradlew test --continue --tests {tests}`, `pytest {tests}` — from the build file and test layout, not just the language.

Dry-run it with one existing test file in `{tests}`. It must exit 0 **and** show that test ran. Only then write `.claude/exloom-test-select`.

If it fails or runs no tests, write nothing and say so: the built-in adapters and whole-suite fallback apply.

It goes on this setup branch and reaches main through review and a pull request, never a direct commit. Once merged, everyone gets fast proofs.

## Step 4 — Review files must be committable

```bash
exloom_ignored_settings "$(git rev-parse --abbrev-ref HEAD)"
```

Every path it prints is git-ignored, and exloom ignores uncommitted settings and receipts. If any are listed, propose this `.gitignore` change, which keeps local files such as `settings.local.json` ignored:

```
.claude/*
!.claude/reviews/
!.claude/exloom-*
```

Apply it only when the user agrees.

## Step 4b — Reference docs

The defaults are `docs/db/`, `docs/api/`, `docs/data-model/` and `docs/architecture/`. If those docs live elsewhere, write `.claude/exloom-docs` with one `<doc-dir>: <code globs>` line per doc (format in `exloom:maintaining-reference-docs`); otherwise write nothing.

If the repository has migrations, an API or ORM models but no matching docs, ask once: "Create the database, API and data-model docs from the code now?" On yes, write them as that skill describes and commit separately; on no, create nothing. Never create architecture docs or diagrams.

## Step 5 — Strict mode

Ask once: "Strict mode — every branch on the Certified lane (no escape hatches, signed review commits)?" Recommend **No** unless the repository is regulated. On yes, create `.claude/exloom-strict`.

## Step 5b — Who owns the full suite

Ask once with AskUserQuestion: "Does this repository run CI on pull requests?" Propose a value from `.github/workflows/*.yml` or `azure-pipelines.yml`. Write `github`, `azure` or `none` to `.claude/exloom-ci`.

On `github` or `azure`, say the full suite leaves the gate and **branch protection must require the CI check before merge** — exloom cannot enforce it. On `none`, the gate requires a `record-full-suite.sh` receipt before every push.

## Step 5c — A minimum tier (ask, never assume)

Only when the user raises it; never offer it unprompted.

Ask in plain words: "Set a minimum tier? Below it exloom asks for no review and no proof, so such a branch can be pushed unchecked. Tier 3 is never skippable, and every skip records your name and the commit that set the floor."

On yes, cap the value at 2 and write `.claude/exloom-min-tier` **on its own branch**: changing any `.claude/exloom-*` setting derives Tier 3. Say so when you write it.

## Step 5d — Line endings on the hooks

```bash
exloom_hooks_are_crlf && echo CRLF || echo LF
```

On CRLF, say this and stop:

> exloom's hooks have Windows line endings, so `bash` outside Git Bash stops at the first `\r` and the gate reports errors instead of evidence. Run `git config --global core.autocrlf input`, then reinstall.

On LF, say nothing.

## Step 6 — The effective configuration

```bash
exloom_policy_load; echo "rc=$?"; exloom_policy_error; exloom_policy_fingerprint
```

A non-zero rc means `.exloom.yml` is invalid and the gate blocks every push: print the error and stop. Else print:

```
Gate:            per branch | repo-wide
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

With a diff on the branch, add `exloom_derive_tier HEAD; exloom_tier_reasons`. Repository rules only raise a tier.

## Step 7 — Commit after the user confirms

List the files you wrote, ask for confirmation, then commit only those:

```
chore(exloom): set up the review gate
```

Then: `/exloom` on any feature branch. Full gate messages instead of one line is the plugin's `verbose` setting in `/plugin`.
