---
name: exloom
description: Run the next step of the review flow for the current branch — init, proof, review, fix, rulings, report — until it can be pushed or a person has to decide. `/exloom status` prints one line.
---

# /exloom

Load the library once:

```bash
LIB="$(find ~/.claude/plugins -path '*exloom*/hooks/lib.sh' | sort -V | tail -1)"; . "$LIB"
B="$(git rev-parse --abbrev-ref HEAD)"
```

**`/exloom status`:** run `exloom_status_line "$B"`, print it, and stop.

Otherwise run `exloom_next_step "$B"`, do what the step says, and run it again. Stop at `push`, at a question only the user can answer, or after the same step comes back twice with nothing changed. Print `exloom_status_line "$B"` when you stop.

| Step | Do |
|---|---|
| `setup` | Run `/exloom-setup`. |
| `branch` | This is a protected branch. Run `exloom:isolating-execution` to move the work onto a feature branch. |
| `init` | Follow `/review-init`. For the lane, ask once with AskUserQuestion: "Quick fix?" — yes means `**Lane:** sprint`. Never offer it when the derived tier is 3. |
| `commit` | Commit `.claude/reviews/` — the checklist, `<branch>.verdicts/` and `<branch>.ledger.md` — on their own. |
| `report` | Run `exloom_render_report "$B"`, then commit it. |
| `review` | Dispatch the reviewers `/review-complete` names: per-task review during a plan, the whole-branch review once, verify mode after a fix. |
| `fix` | Dispatch `exloom:fixer` with the findings verbatim (prompt in `/review-complete`), then the reviewer in verify mode. If exloom refuses the dispatch because a budget is spent, go to `rulings`. |
| `rulings` | Show the user the full gate message and ask them, one question per open item, with AskUserQuestion. Record their answer under `## Rulings` (or `## Remedy choices` / `## Re-finds` as the message says). Never write a ruling they did not give. |
| `proof` | Run `prove-change-is-tested.sh` (find it like the library, under `scripts/`) and commit its receipt. If it reports NOT PROVED, the fix is a test that fails without the change. |
| `push` | Tell the user the branch is ready and what the evidence block says. Do not push unless they ask. |
| `blocked` | Show the user `EXLOOM_VERBOSE=1 exloom_validate_checklist ".claude/reviews/$B.md" HEAD 1 check` and ask what to do. |

For the full reason behind any step, run that same `EXLOOM_VERBOSE=1 exloom_validate_checklist` line; gate messages are one line unless asked for more.

This session coordinates. It does not fix review findings itself, and it does not invent steps the table does not list.
