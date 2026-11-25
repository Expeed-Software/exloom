---
name: smoke-test
description: Used by /exloom at its smoke step; do not start it directly. Boot the system, perform the user action, capture the observed result; fills the Smoke Test section of .claude/reviews/<branch>.md with evidence, not assertions.
---

# /smoke-test

A smoke test is the system booted, the user action performed, and the result observed. Passing unit tests or a clean compile is not one. No checklist at `.claude/reviews/<branch>.md`: point the user to `/exloom` and stop.

## 1. The boot command

Propose `smoke_test_boot_command` from `.claude/exloom.local.md` if set; otherwise infer it (`./gradlew bootRun`, `npm start`, `docker compose up -d`). Ask the user to confirm it and to name the prerequisites: database, dependencies, env vars.

A library, SDK, CLI or parser still gets a smoke test; `N/A — library` is not one. Call the public entry point an adopter calls, from a scratch file outside the test sources, and show the returned value, the message, or stdout, stderr and the exit code.

## 2. The action and the expected result

Ask what user-facing action exercises the change, as clicks, API calls or commands, and what the user should observe. Require specifics: "the Widgets list includes a row named foo with status active", not "the widget appears".

## 3. Capture the evidence

**A CLI or API change at Tier 0–2 with no UI files in the diff** — run it through the recorder, which writes the gate's receipt:

```bash
XL_ROOT='${CLAUDE_PLUGIN_ROOT}';XL_FILE="$XL_ROOT/scripts/record-smoke.sh";[[ $XL_ROOT =~ ^(/|[A-Za-z]:/) && -f $XL_FILE ]]||{ echo "exloom: $XL_FILE missing; reinstall exloom or update Claude Code">&2;exit 1;};bash "$XL_FILE" -- <the command or curl call that exercises the change>
```

It writes `smoke.json` and `smoke.out` under `<branch>.verdicts/`. Read the output: a non-zero exit is a failed smoke test. Commit both files.

**A UI change, or Tier 3** — the gate does not accept an agent-run receipt. Ask the user to boot the system, perform the action, and paste back the log lines or response showing it completed and the evidence of the visible result (screenshot link, log excerpt, DB row, response body). "It worked" with nothing pasted is refused: help them get the output from the network tab, the logs, `psql` or `curl`.

If the spec has an approved UI mock, compare the result with it, list each difference, and ask the user to accept or reject each one. A rejected difference means the change is not ready.

## 4. Record it

For a pasted result, add a `## Smoke test` section above `## Rulings`, outside the generated evidence block: the boot command with prerequisites, the action as a numbered list, the expected result, the pasted evidence, and "Test passed" ticked only if the evidence shows it.

Commit as `chore(review): smoke test recorded for <branch-name>` and hand back to `/exloom`.

If the smoke test failed, record nothing as passed: the change is fixed first, then `/exloom` runs this step again.
