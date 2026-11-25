---
name: exloom-setup
description: Set up exloom in this repository once — choose optional or mandatory mode, pin and dry-run the test command, and check that review files can be committed. Commits only after the user confirms.
---

# /exloom-setup

Run once per repository. exloom honours only committed settings, so everything written here is committed on this setup branch and reaches main through review and a pull request, never a direct commit.

```bash
XL_ROOT='${CLAUDE_PLUGIN_ROOT}';XL_FILE="$XL_ROOT/hooks/lib.sh";[[ $XL_ROOT =~ ^(/|[A-Za-z]:/) && -f $XL_FILE ]]||{ echo "exloom: $XL_FILE missing; reinstall exloom or update Claude Code">&2;exit 1;};. "$XL_FILE"
exloom_hooks_are_crlf && echo CRLF || echo LF
```

On CRLF, say this and stop: exloom's hooks have Windows line endings, so `bash` outside Git Bash stops at the first `\r`. Run `git config --global core.autocrlf input`, then reinstall.

## 1. Optional or mandatory

Ask once with AskUserQuestion: "Optional or mandatory here?"

- **Optional (recommended).** Write no gate switch: each developer is asked once per branch, and only a branch that said yes is checked.
- **Mandatory.** Create `.claude/exloom-gate.enabled` (empty): every branch is checked, for every developer.

## 2. The test command

Detect the stack and propose:

| Found | Command |
|---|---|
| `angular.json` | `./node_modules/.bin/ng test --watch=false --browsers=ChromeHeadless` |
| `package.json` with `vitest` | `./node_modules/.bin/vitest run` |
| `package.json` with `jest` or `react-scripts` | `CI=true npm test` |
| `package.json` with `@strapi/strapi` | `npm test`, if a `test` script exists; else ask |
| one `*.sln` or `*.csproj` | `dotnet test <that file>` |
| `pubspec.yaml` | `flutter test` |
| `gradlew` / `mvnw` | `./gradlew test --rerun-tasks` / `./mvnw -q test` |
| `pyproject.toml` / `pytest.ini` | `pytest -q` |
| `go.mod` / `Cargo.toml` | `go test ./... -count=1` / `cargo test` |

Dry-run it once, non-interactively, with a timeout. It must exit 0 without waiting for input or a browser. If it hangs or fails, show the last lines and ask for the right one; never pin a command that has not passed. The proof runs this command in a throwaway copy of the repository with nothing installed, so it must install what it needs first: for npm, `{ [ -d node_modules ] || npm ci; } && npm test`. Run it once in a temporary copy of the project without the installed dependencies before pinning it. Then write `.claude/exloom-test-command`.

If the suite needs local secrets or untracked state, the proof cannot run here: with the user's agreement write `.claude/exloom-proof.disabled` instead.

**Running only some tests.** Work out this repo's form with `{tests}` where the paths or class names go — `./gradlew test --continue --tests {tests}`, `pytest {tests}`. Dry-run it with one existing test file: it must exit 0 and show that test ran. Only then write `.claude/exloom-test-select`. If it fails or runs no tests, write nothing: the built-in selection and the whole-suite fallback apply.

## 3. Review files must be committable

```bash
exloom_ignored_settings "$(git rev-parse --abbrev-ref HEAD)"
```

Every path it prints is git-ignored, and exloom ignores uncommitted settings and receipts. If any are listed, propose this `.gitignore` change and apply it only when the user agrees:

```
.claude/*
!.claude/reviews/
!.claude/exloom-*
```

## 4. Reference docs

If the docs live somewhere other than `docs/db/`, `docs/api/`, `docs/data-model/` and `docs/architecture/`, write `.claude/exloom-docs` (format in `exloom:maintaining-reference-docs`). If the repository has migrations, an API or ORM models but no matching docs, ask once whether to create them from the code now; that skill says how.

## 5. Only when it applies

- **No CI.** If the repository has neither `.github/workflows/` nor `azure-pipelines.yml`, ask once whether it runs CI on pull requests. On no, write `none` to `.claude/exloom-ci`: the gate then requires a `record-full-suite.sh` receipt before every push. With CI, write nothing and say that branch protection must require the CI check, which exloom cannot enforce.
- **Strict mode**, only when the user raises it: `.claude/exloom-strict` puts every branch on the Certified lane.
- **A minimum tier**, only when the user raises it: `.claude/exloom-min-tier`, capped at 2, on its own branch. Say that below it exloom asks for no review and no proof.

## 6. Show the configuration

```bash
exloom_policy_load; echo "rc=$?"; exloom_policy_error; exloom_policy_fingerprint
```

A non-zero rc means `.exloom.yml` is invalid and the gate blocks every push: print the error and stop. Otherwise print the gate mode (per branch or repo-wide), the test command or that the proof is off, the max rounds (default 3), each reviewer's model from `exloom_reviewer_model`, the policy fingerprint, and the reviewers each tier requires: Tier 0–1 `l1-reviewer`; Tier 2 adds `adversarial-reviewer`; Tier 3 adds `security-auditor`. With a diff on the branch, add `exloom_derive_tier HEAD; exloom_tier_reasons`.

## 7. Commit after the user confirms

List the files you wrote, ask for confirmation, then commit only those as `chore(exloom): set up the review gate`. Then open a pull request so the settings reach everyone. After that, `/exloom` on any feature branch.
