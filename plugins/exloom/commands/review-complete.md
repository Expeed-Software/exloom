---
name: review-complete
description: Run the final gate for the current branch. Verifies every required checklist section for the declared tier is populated with real evidence, dispatches any missing reviewer agents, and marks the checklist ready to ship. Refuses to mark complete if sections are missing, naming each gap.
---

# /review-complete

You are the terminal gate. Read `.claude/reviews/<branch>.md` and verify every tier-required section holds real evidence; do not take the operator's word. A reviewer counts only by its receipt, `.claude/reviews/<branch>.verdicts/<agent>.json`, written when the subagent completes and never by hand.

## Step 1 — Open and parse

Open `.claude/reviews/<current-branch>.md`. If absent, refuse and tell the user to run `/review-init`.

Parse the Tier field. If missing or not `0`, `1`, `2`, or `3`, refuse.

Check the tier against the diff (docs-only → 0; migrations or auth/tenancy/secrets/crypto → 3; deployment surface, API/route surface, or ≥5 files → 2; else 1). If the declared tier is lower, say so and raise it; the gate blocks otherwise.

## Step 1b — Read the lane

Read `**Lane:**`. Absent, use the committed `.claude/exloom-lane`, else `standard`.

**Sprint caps the required set at Tier 1**: L1 review, smoke test, proof. Mark adversarial, cross-layer and runbook sections `N/A — Sprint lane`. Sprint does **not** waive the proof receipt, the derived tier, or the security auditor when the diff's *surface* demands it (a dependency manifest, a deserialization entry point). **Sprint at Tier 3 is refused by the gate**: do not lower the tier; offer `/harden`.

**Certified**: anything under `## Escape hatches used` blocks the push, and the checklist commit must be signed. A recorded round-cap answer is not an escape hatch.

## Step 2 — Check required sections for the tier

Dispatch is answered by receipts, never the checklist:

```bash
ls .claude/reviews/<branch>.verdicts/
```

**`l1-reviewer` must cover the shipped commit**; if code changed after its review, it runs again. **Every other reviewer needs only to have run and approved somewhere on this branch.** Commit receipts alongside the checklist.

### When to stop reviewing

Each receipt carries `"round_needed"`, from the `ROUND NEEDED AFTER FIX:` line. **The loop is over when every required receipt reads `"verdict":"APPROVED"` and `"round_needed":"NO"`:**

```bash
grep -h '"round_needed"' .claude/reviews/<branch>.verdicts/*.json
```

If that holds, ship. Do not run another round to be thorough.

`"round_needed":"UNKNOWN"` counts as `YES`. Re-dispatch that one reviewer, not the whole set.

**Minor, out-of-scope and pre-existing findings go to the ledger**, `.claude/reviews/<branch>.ledger.md`, written by the hook: no ruling, no round, no fixing during the loop. After the final review, tick each item with the user — fixed, ticket id, or dropped — and commit it with the checklist. After a compaction, read the ledger and receipts to resume.

**A REJECTED review is closed by rulings, not another round.** For each recorded finding, add one line under `## Rulings`:

```
- src/x.go:12 — PARKED: why it can wait
- src/x.go:30 — DEFERRED ABC-123: why, and the ticket that tracks it
- src/x.go:44 — FIXED: the smallest change, at the cited line
```

The gate accepts the REJECTED receipt once every in-scope finding has a ruling. At Tier 3 and on Certified, a ruling on a Critical quotes the user's words in double quotes — ask them. An UNKNOWN verdict, or a REJECTED review with no recorded findings, cannot be ruled on: re-dispatch that reviewer.

### Tier 0 required
- L1: `l1-reviewer.json` receipt, findings listed (or "no findings"), resolution for each Critical/Important.
- Other sections marked `N/A - Tier 0` or left at defaults are fine.

### Tier 1 required
- L1, as Tier 0.
- Smoke test: boot command, user action, expected result, actual observed result with real evidence. "Test passed" ticked.
- **Proof that the change is tested — unless the repo has committed `.claude/exloom-proof.disabled`.** `proof.json` receipt covering the reviewed commit with `"result":"PROVED"` (or `NOT_APPLICABLE` at Tier 1 only, or `NO_NEW_BEHAVIOUR` with a `- Proof: deletion only — <reason>` line from the user at Tier 2–3). Written only by:

  ```bash
  PROVE="$(find ~/.claude/plugins -path '*exloom*/scripts/prove-change-is-tested.sh' | sort -V | tail -1)"
  bash "$PROVE"
  ```

  `PROVED_BY_MUTATION` (repo-pinned mutation command) and `NOT_APPLICABLE` (tests cannot compile without the change) also pass; the receipt's `method` field says which. `NOT_PROVED` blocks: fix the tests, do not re-run. Applies to **every tier from 1 up**.

### Tier 2 required (Tier 1 +)
- Adversarial review: `adversarial-reviewer.json` receipt, findings with category and resolution, and the cross-layer contract check's grep output with each orphan resolved.

### Tier 3 required (Tier 2 +)
- Security review: `security-auditor.json` receipt, tool output pasted, findings dispositioned.
- Runbook path filled and the file exists.
- **What reverting does not fix** filled; `nothing` is valid but must be written.
- **What would recover it** filled: a named mechanism, or `NOT RECOVERABLE` with a stated reason. Do not push back on it.
- The Tier 3 box ticked.

Do **not** ask whether recovery was tested, who verifies at deploy, or for a "rollback command". Every line must be answerable by the author, on this branch, before merge; a deferral names a ticket.

## Step 3 — Verify section content is real, not placeholder

A required section is missing if it is empty after the header or still contains:
- `<paste output / screenshot link>`
- `<exact command>`
- `<exact steps>`
- `<Critical / Important / Minor with file:line>`
- `<expected-result>`

## Step 4 — If sections are missing

Print `Cannot mark complete. Missing or placeholder sections:` and one line per gap. Then:
- Smoke test → run `/smoke-test`.
- Proof missing, stale, or `NOT_PROVED` → run `prove-change-is-tested.sh` (above); NOT PROVED needs a better test, not another run.
- L1 receipt missing or stale → dispatch `exloom:l1-reviewer` now.
- Adversarial receipt missing or stale → dispatch `exloom:adversarial-reviewer` now.
- Security receipt missing or stale → dispatch `exloom:security-auditor` now.
- Runbook → ask the user for the path.
- Reversal proof → ask which test exercises the rollback; if none, offer to write it rather than accepting prose.

Dispatch missing reviewers without asking, with the `Agent`/`Task` tool and the agent type above. **Dispatch without a name**, with `model` set to `exloom_reviewer_model <agent>` (Opus unless `.claude/exloom-reviewer-model` says otherwise). A receipt with no `"verdict"` field means it was named: dispatch again, unnamed. Reviewing it yourself produces no receipt.

### The dispatch prompt — use this, do not write your own

Copy this, fill the two blanks, send nothing else:

```
Review branch <branch> at <sha>. Diff: git diff <merge-base>...<sha>
<one line naming what the change is for — the ticket title is enough>
```

For the second-stage reviewers, add only:

```
L1 already reported and these are being handled, so do not re-report them:
  <file:line> — <one line each>
```

**From round 2, re-dispatch in verify mode:**

```
Verify fixes on branch <branch>. Fix range: <last-reviewed-sha>..<sha>
Previous findings:
<the finding lines of its last report, verbatim>
```

`<last-reviewed-sha>` is the `"head"` of that reviewer's last verdict line. A new finding outside the fix range is out of scope and needs no ruling.

**The budget is enforced at dispatch.** Each reviewer gets one whole-branch review and one verify pass; each plan task gets `.claude/exloom-max-rounds` fix rounds (default 3). Past that, or a whole-branch dispatch after the branch grew by more than max(100 lines, half its size) since the final review started, is refused: answer with rulings. If the user wants another round, record `- Extra round — "<their words>"` under `## Rulings`; each line allows one dispatch. A commit made while a reviewer runs is not covered by its approval.

**That is the whole prompt.** See "Do not steer the review".

**Dispatch order:**

1. **`l1-reviewer` alone, first, once over the whole branch** (tasks were reviewed during build, `exloom:executing-handoff-plans` step 7). Fix, then re-dispatch in verify mode.
2. **Then `adversarial-reviewer` and `security-auditor`**, in parallel, once, after L1 settles, with the L1 findings. The gate's `approved <sha> — 3 commit(s) have landed since` does not block; a large number means they ran too early.

**A finding is a defect report, not a work order.** Implement defects ("dereferences null when X"). A proposed design — a new check, abstraction, validator, helper, test infrastructure, or a class-wide fix — goes to the ticket owner. Do not build a guard unless you can point to the type, schema or contract behind its rule; if one was built and reverted, pin the case with a test.

**Cost discipline.** `l1-reviewer` runs at low effort, per commit. `adversarial-reviewer` and `security-auditor` run at medium effort, once, before push.

## How to respond to a finding

Deliver what was asked, at the scope intended; if it seems mistaken, say so in a sentence and continue as asked.

**The fix is made by `exloom:fixer`, not this session.** During the fix loop this session makes no code edits or code commits. Dispatch the fixer, unnamed, with exactly:

```
Fix these review findings on branch <branch>, round <n>. Findings, verbatim:
<the blocking finding lines from the reviewer's report>
Rulings that allow more than a minimal fix:
<lines from '## Rulings', or "none">
```

Round 3 gets a fresh fixer with `model` set to `opus`. Each `NEEDS RULING` line it returns goes to the user, never back to the fixer. Then re-dispatch the reviewer in verify mode.

- **Fix what is cited, at the line cited.**
- **Before adding a new file, class, method, or test class for a finding, stop and ask**, stating the minimal fix and what you would add.
- **The branch should stay roughly its size at review start.**
- **A finding that needs architecture goes to a ticket**: record `DEFERRED <ticket>` under `## Rulings` and move on.

## Do not steer the review

- **Do not tell a reviewer what to look for.**
- **Do not tell it what not to flag** ("ignore the docs changes", "pre-existing").
- **Do not pre-rate a severity.**
- **Do not summarise what you changed or why.**
- **Do not say what you already verified.** The proof receipt covers that.

**Do not invent process** — your own freeze, re-review trigger, or same-commit rule. Where you think exloom is wrong, say so and continue as written.

Wait for the user. Do NOT mark complete while anything is missing.

## Step 5 — If everything is present

Regenerate the evidence block from the receipts; do not write it by hand:

```bash
exloom_render_report "$(git rev-parse --abbrev-ref HEAD)"
```

It records HEAD as the reviewed code commit, so run it before committing.

Stage the checklist **and the verdict receipts** and commit them together:

```bash
git add .claude/reviews/<branch>.md ".claude/reviews/<branch>.verdicts" ".claude/reviews/<branch>.ledger.md"
```

If the repo has `.claude/exloom-provenance-signed.enabled` or strict mode (`.claude/exloom-strict`), the commit MUST be signed (`git commit -S`); never fall back to unsigned. Otherwise:

```
git commit -m "chore(review): record the review of <branch-name>"
```

A checklist from the old template (a `## Final verdict` section with tick boxes) still works: tick the boxes and write `Reviewed code commit:`.

## Step 6 — Tell the user what is now unblocked

Print:

> Review complete for Tier <N> — checklist committed (`chore(review): mark Tier <N> review complete`). You may now run `git push` or open a PR; the push gate will no longer block this branch.

## Rules

- All-or-nothing per the tier's required sections.
- Do NOT accept "I'll do that later".
- A skipped narrative step with written justification under "Escape hatches used" counts as addressed; an unjustified skip does not. **An under-declared tier and a missing reviewer receipt have no escape hatch.**
- Emergency bypass: `EXLOOM_REVIEW_SKIP=1` in the Claude Code session env (`settings.json` `env`), not inline. It works on every lane, verifies no justification, and writes `.claude/reviews/<branch>.bypass.json` — **commit that file with the change** and write the reason under "Escape hatches used". Do not tell the user the tooling enforces the reason.
