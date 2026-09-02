# /harden

Promote the current branch from the Sprint lane to Standard (or Standard to Certified). Use it when something built as a spike turned out to matter.

This is the upgrade path that makes Sprint safe to offer. A branch that survives the weekend becomes a governed one **without regenerating anything** — the code stays, the receipts stay, the commit history stays. What changes is that the steps Sprint skipped now get done, against working software rather than against an intention.

## Step 1 — Read the current lane

Open `.claude/reviews/<current-branch>.md` and read `**Lane:**`. If it is absent, the repo default applies — check for a committed `.claude/exloom-lane`, else `standard`.

- Already `certified` → nothing to promote. Say so and stop.
- `sprint` → the target is `standard`.
- `standard` → the target is `certified`. Confirm with the user first; Certified means no workflow-step escape hatches — a skipped step recorded in the checklist blocks the push instead of being waved through — and mandatory signed commits, which needs git signing configured. It does not disable `EXLOOM_REVIEW_SKIP=1`; that overrides the hooks on every lane and leaves a bypass receipt.

## Step 2 — Write the spec that was never written

This is the part that makes hardening worth more than re-running gates, and it only works in this direction: **there is working code to describe.** A spec written before the code is a guess. A spec recovered from a diff that runs and passes its tests is a description of something real, and reviewing it is a better review than a cold read of a proposal.

Read the diff (`git diff <merge-base>...HEAD`), then invoke `exloom:brainstorming` in recovery mode: rather than exploring what to build, write down what *was* built — problem, approach taken, edge cases handled, and, honestly, the ones that were not. Save it where the repo keeps specs.

Two rules:

- **Do not describe intentions the code does not have.** If the diff handles no empty-input case, the spec says that is unhandled. A spec that flatters the code is worse than no spec, because the next person trusts it.
- **Do not change the code while writing it.** Gaps found here become findings for the review that follows, or tickets. Fixing them mid-hardening turns a promotion into a second feature, which is the thing exloom exists to prevent.

## Step 3 — Flip the lane

Set `**Lane:**` in the checklist to the target lane. Commit it on its own:

```
chore(review): harden <branch> from <old-lane> to <new-lane>
```

## Step 4 — Name what is now required, then do it

The lane change raises the bar, so the checklist that passed yesterday will not pass today. Run `/review-complete`; it names every section the new lane's requirements leave unfilled. Expect, for sprint → standard:

- **Adversarial review** at Tier 2+ — a real dispatch, so a real receipt.
- **Cross-layer contract check** at Tier 2+.
- **Security review** at Tier 3, or wherever the diff's surface demands it.
- **Fidelity** — with a spec now in hand, `exloom:auditing-plan-fidelity` has something to audit against.

For standard → certified, additionally: every recorded escape hatch has to be resolved rather than justified, and the checklist commit must be signed (`git commit -S`).

## Step 5 — Say what changed

> Hardened `<branch>`: `<old-lane>` → `<new-lane>`. Spec recovered at `<path>`. Now required and not yet present: `<list>`.

## Rules

- **Never demote.** `/harden` only raises. Going the other way would let a branch that failed a gate walk backwards until it passed one, which makes every lane meaningless. If a branch genuinely belongs on a lighter lane, that is a decision for the user to state and record in the checklist, not a command.
- **Never promote to skip a block.** If the branch is blocked, hardening it raises the bar rather than lowering it. Fix the finding.
- The tier is untouched. It is derived from the diff and hardening does not change the diff.
