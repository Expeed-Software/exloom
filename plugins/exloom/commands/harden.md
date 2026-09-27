# /harden

Promote the current branch from Sprint to Standard (or Standard to Certified) when a spike turned out to matter. Nothing is regenerated: code, receipts and history stay. The steps Sprint skipped now get done against working software.

## Step 1 — Read the current lane

Open `.claude/reviews/<current-branch>.md` and read `**Lane:**`. If absent, the repo default applies — a committed `.claude/exloom-lane`, else `standard`.

- Already `certified` → nothing to promote. Say so and stop.
- `sprint` → the target is `standard`.
- `standard` → the target is `certified`. Confirm with the user first: Certified means a skipped step recorded in the checklist blocks the push, and signed commits are mandatory, which needs git signing configured. It does not disable `EXLOOM_REVIEW_SKIP=1`; that overrides the hooks on every lane and leaves a bypass receipt.

## Step 2 — Write the spec that was never written

Read the diff (`git diff <merge-base>...HEAD`), then invoke `exloom:brainstorming` in recovery mode: write down what *was* built — problem, approach taken, edge cases handled, and those not handled. Save it where the repo keeps specs.

- **Do not describe intentions the code does not have.** If the diff handles no empty-input case, the spec says it is unhandled.
- **Do not change the code while writing it.** Gaps become findings for the review that follows, or tickets.

## Step 3 — Flip the lane

Set `**Lane:**` to the target lane. Commit it on its own:

```
chore(review): harden <branch> from <old-lane> to <new-lane>
```

## Step 4 — Name what is now required, then do it

Run `/review-complete`; it names every section the new lane leaves unfilled. Expect, for sprint → standard:

- **Adversarial review** at Tier 2+ — a real dispatch, so a real receipt.
- **Cross-layer contract check** at Tier 2+.
- **Security review** at Tier 3, or wherever the diff's surface demands it.
- **Fidelity** — `exloom:auditing-plan-fidelity` against the recovered spec.

For standard → certified, additionally: every recorded escape hatch must be resolved rather than justified, and the checklist commit must be signed (`git commit -S`).

## Step 5 — Say what changed

> Hardened `<branch>`: `<old-lane>` → `<new-lane>`. Spec recovered at `<path>`. Now required and not yet present: `<list>`.

## Rules

- **Never demote.** `/harden` only raises. Moving a branch to a lighter lane is a decision the user states and records in the checklist.
- **Never promote to skip a block.** Hardening raises the bar. Fix the finding.
- The tier is untouched; it is derived from the diff.
