---
name: using-exloom
description: Use when starting work that will produce a commit — the one entry point is /exloom, which runs every exloom step for the branch in order.
---

On a feature branch, run /exloom. Do not run the steps yourself.

# Using exloom

exloom produces evidence that transfers between people — a spec, a plan, a proof receipt, review receipts — and gates it once, at push. `/exloom` does the next step for the branch and runs again until the branch can be pushed or a person has to decide.

## What /exloom does

In order: `branch`, `init`, `spec`, `plan`, `build`, `review`, `fix`, `rulings`, `proof`, `smoke`, `push`. The `/exloom` skill says what each step does; Sprint skips `spec` and `plan`.

## Lanes

| Lane | What /exloom skips |
|---|---|
| **Sprint** (`**Lane:** sprint`) | spec, plan, reviewers above L1. Not available at Tier 3 |
| **Standard** | nothing; the default |
| **Certified** | nothing, and a skipped step under `## Escape hatches used` blocks the push |

Sprint skips ceremony, not evidence: same receipts, proof, smoke test and derived tier. If a Sprint branch turns out to matter, `/harden` recovers the spec from the diff and changes the lane.

## Review rounds

After a REJECTED review, the fixer applies the smallest fix for what was cited and the same reviewer verifies it. At the round cap (default 3) exloom refuses another dispatch and the user rules on what is left. Adversarial (Tier 2+) and security (Tier 3 or a security surface) run once, after L1 settles; a later fix does not expire their approval.

## Commands

```
/exloom           runs the next step until push
/exloom status    one line: tier, task, round, proof, rulings, next step
/exloom-setup     set a repository up, once
/harden           when a Sprint branch turns out to matter
/review-cleanup   archive checklists of branches that no longer exist
```

`/review-init`, `/smoke-test` and `/review-complete` belong to /exloom. Doing their steps by hand leaves the push blocked: receipts exist only when a reviewer records one.

Call yourself when needed: `exloom:starting-a-project` (a new project, before any feature), `exloom:defining-a-design-system` (the look of a product with screens), `exloom:capturing-learnings`, `exloom:authoring-claude-md`, `exloom:auditing-plan-fidelity`, `exloom:maintaining-reference-docs`. `exloom:review-gate` describes the gate.

## Is the gate on here?

Where the branch's checklist is committed, or everywhere if `.claude/exloom-gate.enabled` is. **Never create that marker yourself**: it gates everyone. `/exloom-setup` offers it and the user decides.
