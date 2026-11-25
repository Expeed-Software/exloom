---
name: review-complete
description: Used by /exloom at its review and push steps; do not start it directly. Checks that the checklist holds real evidence for everything the tier requires, dispatches missing reviewers, and names each gap.
---

# /review-complete

Verify that `.claude/reviews/<branch>.md` holds real evidence for everything the tier requires. A reviewer counts only by its receipt, `.claude/reviews/<branch>.verdicts/<agent>.json`, which the reviewer records itself; never write one by hand.

## 1. Tier and lane

No checklist: refuse and point the user to `/exloom`. The tier is `exloom_derive_tier HEAD`, never declared or lowered. The lane is `**Lane:**`, else the committed `.claude/exloom-lane`, else `standard`.

- **Sprint** requires only the Tier 1 set; mark the adversarial, cross-layer and runbook sections `N/A — Sprint lane`. It does not waive the proof or a security review the diff's surface demands. At Tier 3 it is refused: offer `/harden`.
- **Certified**: anything under `## Escape hatches used` blocks the push, and the checklist commit is signed. A recorded round-cap answer is not an escape hatch.

If the repository has architecture, data-model, DB or API docs, follow `exloom:maintaining-reference-docs`, or record `- Doc impact: none — <reason>` under `## Rulings`. The gate only warns here.

## 2. What each tier requires

| Tier | Required |
|---|---|
| 0 | `l1-reviewer` receipt; each Critical and Important resolved |
| 1 | Tier 0 + smoke test (boot command, user action, expected and observed result with evidence) + proof |
| 2 | Tier 1 + `adversarial-reviewer` receipt, with the cross-layer grep output and each orphan resolved |
| 3 | Tier 2 + `security-auditor` receipt with tool output; a runbook path that exists; **What reverting does not fix** (`nothing` is valid); **What would recover it** (`NOT RECOVERABLE` with a reason is valid) |

`l1-reviewer` must cover the shipped commit; the others need only have approved somewhere on the branch. At Tier 3, do not ask whether recovery was tested or who verifies at deploy: a deferral names a ticket.

**Proof**, unless `.claude/exloom-proof.disabled` is committed: a `proof.json` covering the reviewed commit, written only by

```bash
XL_ROOT='${CLAUDE_PLUGIN_ROOT}';XL_FILE="$XL_ROOT/scripts/prove-change-is-tested.sh";[[ $XL_ROOT =~ ^(/|[A-Za-z]:/) && -f $XL_FILE ]]||{ echo "exloom: $XL_FILE missing; reinstall exloom or update Claude Code">&2;exit 1;};bash "$XL_FILE"
```

`PROVED`, `PROVED_BY_MUTATION`, `NOT_APPLICABLE`, `NOT_TESTABLE` and `TESTS_ONLY` pass. `NO_NEW_BEHAVIOUR` at Tier 2–3 needs `- Proof: deletion only — <reason>` from the user; `NO_TEST_CHANGED` needs `- Proof: refactor — <reason>` from the user. `NOT_PROVED` blocks: strengthen the test, never re-run unchanged.

A section is missing if it is empty or still holds a template placeholder such as `<exact command>` or `<paste output / screenshot link>`.

## 3. Fill the gaps

Print `Cannot mark complete. Missing or placeholder sections:` with one line per gap. A missing or stale reviewer receipt: dispatch that reviewer now, without asking, with `model` set to `exloom_reviewer_model <agent>`. Smoke test: the smoke step of `/exloom`. Runbook: ask the user for the path. Do not accept "I'll do that later".

**Order.** `l1-reviewer` alone, first, once over the whole branch. Then `adversarial-reviewer` and `security-auditor` in parallel, once, with the L1 findings.

**The dispatch prompt — send exactly this:**

```
Review branch <branch> at <sha>. Diff: git diff <merge-base>...<sha>
<one line naming what the change is for — the ticket title is enough>
```

For the second-stage reviewers, add only:

```
L1 already reported and these are being handled, so do not re-report them:
  <file:line> — <one line each>
```

After a fix, re-dispatch in verify mode. `<last-reviewed-sha>` is the `"head"` of that reviewer's last receipt line:

```
Verify fixes on branch <branch>. Fix range: <last-reviewed-sha>..<sha>
Previous findings:
<the finding lines of its last report, verbatim>
```

Do not steer a reviewer: say nothing about what to look for, what to ignore, a severity, what you changed, or what you verified.

**Budget, enforced at dispatch.** Each reviewer gets one whole-branch review and one verify pass; each plan task gets `.claude/exloom-max-rounds` fix rounds (default 3). A refused dispatch means: ask the user about the open findings. The last fix always gets one verify. If the user wants another round, record `- Extra round — "<their words>"` under `## Rulings` and commit it.

## 4. When the loop is over

When every required receipt reads `"verdict":"APPROVED"` and `"round_needed":"NO"`, ship. No extra round to be thorough.

Minor, out-of-scope and pre-existing findings go to `.claude/reviews/<branch>.ledger.md` automatically: no ruling, no round, no fixing during the loop. After the final review, tick each item with the user — fixed, ticket id, or dropped — and commit it.

## 5. A rejected review

**The fix is made by `exloom:fixer`, not this session**, which makes no code edits or commits while a finding is open. Dispatch it with exactly:

```
Fix these review findings on branch <branch>, round <n>. Findings, verbatim:
<the blocking finding lines from the reviewer's report>
Rulings that allow more than a minimal fix:
<lines from '## Rulings', or "none">
```

Round 3 gets a fresh fixer with `model` set to `opus`. A `NEEDS RULING` line it returns goes to the user. Then verify.

For each finding the verify leaves NOT ADDRESSED, ask the user with AskUserQuestion, showing the reviewer's reason:

- **"Fix again"** — fixer, then verify.
- **"Not a real problem, ignore (PARKED)"** — `- src/x.go:12 — PARKED: why` under `## Rulings`.
- **"Fix later, with a ticket (DEFERRED)"** — `- src/x.go:30 — DEFERRED ABC-123: why`.

At Tier 3 and on Certified, a ruling on a Critical quotes the user's words in double quotes. A REJECTED review with no recorded findings cannot be ruled on: re-dispatch that reviewer.

A finding is a defect report, not a work order. A proposed design — a new check, abstraction, helper or class-wide fix — goes to a ticket as `DEFERRED <ticket>`.

## 6. Record it

Rebuild the evidence block from the receipts, never by hand, then commit the checklist with its receipts:

```bash
exloom_render_report "$(git rev-parse --abbrev-ref HEAD)"
git add .claude/reviews/<branch>.md ".claude/reviews/<branch>.verdicts" ".claude/reviews/<branch>.ledger.md"
git commit -m "chore(review): record the review of <branch-name>"
```

On Certified, or with `.claude/exloom-provenance-signed.enabled` or `.claude/exloom-strict`, sign it with `git commit -S`; never fall back to unsigned.

Then tell the user: review complete for Tier <N>, checklist committed, the branch may be pushed.

**Bypass.** Only the user may set `EXLOOM_REVIEW_SKIP=1` in their `settings.json` `env`; never set it yourself. It writes `.claude/reviews/<branch>.bypass.json`: commit that file and write the reason under `## Escape hatches used`.
