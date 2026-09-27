---
name: smoke-test
description: Walk through a real smoke test for the current change — boot the system, perform the user action, capture the observed result. Fills the Smoke Test section of .claude/reviews/<branch>.md with evidence, not assertions.
---

# /smoke-test

Guide a real smoke test. Passing unit tests or a successful compile is not one. The operator boots the system, performs the user action, and observes the result; you capture the evidence.

## Step 1 — Open the checklist

Open `.claude/reviews/<current-branch>.md`. If it does not exist, tell the user to run `/review-init` first and stop.

## Step 2 — Establish the boot command

Check `.claude/exloom.local.md` frontmatter for `smoke_test_boot_command`. If present, propose it. Otherwise infer:

- Java/Gradle → `./gradlew :<main-module>:run` or `./gradlew bootRun`.
- Angular frontend → `npm start` or `ng serve`.
- Node service → `npm run dev` or `npm start`.
- Docker-composed stack → `docker compose up -d` plus service command.

**No app to boot — a library, SDK, CLI, or parser — still gets a smoke test.** `N/A — library` is not one. Exercise the change through the public entry point an adopter calls, from a scratch file outside the test sources, and show the observable result:

- Library / SDK → a scratch `main` or REPL snippet that imports the published artifact and calls the entry point, printing the returned value or thrown exception in full.
- Parser / validator → feed it the input the change is about; print the accept/reject and the message verbatim, escaping anything invisible.
- CLI → run the binary with real arguments; paste stdout, stderr and the exit code.

Ask the user to confirm or correct the boot command, and for prerequisites (DB running, dependencies installed, env vars set). Record them.

## Step 3 — Establish the user action

Ask the user, in order:

1. "What is the user-facing action that exercises this change? Describe it as a sequence of clicks / API calls / CLI commands."
2. "What should the user observe if this change is working? (specific UI element, specific API response field, specific log line, specific DB row)"

Require specifics: not "the widget should appear" but "the 'Widgets' list should include a row with name='foo' and status='active'".

## Step 4 — Capture the evidence

Tell the user:

> Run the boot command. When the system is up, perform the user action. Then paste back: (a) the log lines or API response showing the action completed, (b) the evidence of the user-visible result (UI screenshot link / log excerpt / DB row dump / API response body). If it failed, paste the failure output and we will stop the smoke test here — the change is not ready.

Wait for the paste. If they say "it worked, I don't have output to paste", refuse and guide them to grab it: browser devtools network tab, backend logs, `psql` query, `curl` response.

## Step 5 — Fill the section

Update the Smoke Test section with:

- The exact boot command used (including prerequisites).
- The exact user action, as a numbered list.
- The expected observable result (one sentence).
- The actual observed result — the pasted evidence.
- Tick "Test passed" if the evidence shows success; otherwise leave it unticked and add a note.

## Step 6 — Commit

Stage the checklist and commit:

```
chore(review): smoke test recorded for <branch-name>
```

## Step 7 — Tell the user

Say the evidence was recorded and committed (`chore(review): smoke test recorded`). Print what the declared tier still requires — the cross-layer contract check and adversarial review at Tier 2+, and at Tier 3 the security review, the runbook, and the two lines under "What a revert will not undo" — and suggest `/review-complete` when done.

## Refusals

- Refuse to fill the section without pasted evidence.
- Refuse if the smoke test failed — the operator fixes the change first, then re-runs `/smoke-test`.
