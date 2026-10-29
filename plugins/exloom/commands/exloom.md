---
name: exloom
description: Use when starting or continuing any work on a feature branch. Runs the next step, from checklist to push, until a person has to decide. `/exloom status` prints one line.
---

# /exloom

Load the library:

```bash
XL_ROOT='${CLAUDE_PLUGIN_ROOT}';XL_FILE="$XL_ROOT/hooks/lib.sh";[[ $XL_ROOT =~ ^(/|[A-Za-z]:/) && -f $XL_FILE ]]||{ echo "exloom: $XL_FILE missing; reinstall exloom or update Claude Code">&2;exit 1;};. "$XL_FILE"
B="$(git rev-parse --abbrev-ref HEAD)"
```

**`/exloom status`:** run `exloom_status_line "$B"`, print it, and stop.

Otherwise run `exloom_next_step "$B"`, do what it says, and run it again. Stop at `push`, at a question only the user can answer, or when a step repeats unchanged. Then print `exloom_status_line "$B"`.

| Step | Do |
|---|---|
| `setup` | Run `/exloom-setup`. |
| `branch` | Protected branch: run `exloom:isolating-execution` to move the work onto a feature branch. |
| `init` | Follow `/review-init`; the tier is pending until code exists. Ask once, "Quick fix?" — yes means `**Lane:** sprint`, never at derived tier 3. Then ask once what kind of work this is: **a new feature**, **a bug fix**, or **a change to existing code**. Record the answer in the checklist as `**Work type:** new feature` / `bug fix` / `change to existing code`, spelled exactly so — `exloom_next_step` reads it. A new feature takes the full flow. A bug fix runs `exloom:fixing-bugs` and is never sent to the spec or plan step. A change to existing code runs `exloom:brainstorming` in its change-note mode: the note goes in `**Spec:**`, and a single task records `**Plan:** none`. |
| `commit` | Commit `.claude/reviews/` on its own. |
| `commit-work` | Commit the changes outside `.claude/reviews/` first. |
| `spec` | Run `exloom:brainstorming`; put its path in `**Spec:**`. A change to existing code writes a change note there instead. Then, on the Standard and Certified lanes only, dispatch `exloom:spec-reviewer` once with that path: show the user its findings and append them under `## Spec review` in the checklist. It never blocks and is not a review round — carry on to `plan` whatever it says — and it is never resumed; a materially changed spec gets a fresh dispatch. |
| `plan` | Run `exloom:planning-for-handoff`; put its path in `**Plan:**`. |
| `build` | With a plan, run `exloom:executing-handoff-plans`, one reviewed task at a time, until every task is approved. Without one, make the change and commit. After each task run `${CLAUDE_PLUGIN_ROOT}/scripts/fast-check.sh`; it is advisory, so report a warning and carry on. |
| `report` | Run `exloom_render_report "$B"`; commit it. |
| `review` | Dispatch the reviewers `/review-complete` names: the whole-branch review once, verify mode after a fix. |
| `fix` | Dispatch `exloom:fixer` with the findings verbatim (prompt in `/review-complete`), then the reviewer in verify mode. |
| `rulings` | Per finding the verify left NOT ADDRESSED, one AskUserQuestion with the reviewer's reason and exactly: "Fix again" (go to `fix`), "Not a real problem, ignore (PARKED)" (`PARKED: <why>`), "Fix later, with a ticket (DEFERRED)" (`DEFERRED <ticket>: <why>`). For a proof ruling, ask whether the change is a refactor; record `- Proof: refactor — <their reason>`. Write the answer under the section the message names (`## Rulings` by default). Never write a ruling they did not give. |
| `proof` | Run the block below; commit its receipt. NOT PROVED needs a test that fails without the change. NO_TEST_CHANGED goes to `rulings`. |
| `smoke` | Follow `/smoke-test`. If the user cannot run it, ask once: "No smoke result — proceed anyway?" On yes, write `- Smoke test waived: <their reason> — <git user.name> at <short sha>` under `## Escape hatches used` and carry on. Never ask under Certified or in strict mode; there the smoke test is what the lane was chosen for. |
| `push` | When committed `.claude/exloom-ci` says `none`, run `${CLAUDE_PLUGIN_ROOT}/scripts/record-full-suite.sh` once and commit `full-suite.json` with the checklist; with any other value the suite belongs to CI and branch protection, and a CI run reference is not evidence here. Then print `exloom_branch_summary "$B"`; the branch is ready. Do not push unless asked. |
| `blocked` | Show the user the verbose line below; ask what to do. |

```bash
XL_ROOT='${CLAUDE_PLUGIN_ROOT}';XL_FILE="$XL_ROOT/scripts/prove-change-is-tested.sh";[[ $XL_ROOT =~ ^(/|[A-Za-z]:/) && -f $XL_FILE ]]||{ echo "exloom: $XL_FILE missing; reinstall exloom or update Claude Code">&2;exit 1;};bash "$XL_FILE"
```

The full reason behind any step: `EXLOOM_VERBOSE=1 exloom_validate_checklist ".claude/reviews/$B.md" HEAD 1 check`.

This session coordinates: it neither fixes findings nor invents steps.
