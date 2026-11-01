---
name: using-exloom
description: Use when starting work that will produce a commit — the one entry point is /exloom, which runs every exloom step for the branch in order.
---

On a feature branch, run /exloom. Do not run the steps yourself.

# Using exloom

exloom produces **evidence** that transfers between people — spec, plan, proof receipt, review receipts — and gates it once, at push. `/exloom` does the next step for the branch and runs again until it can be pushed or a person has to decide. `/exloom status` prints one line.

## Quick start — what /exloom does, in order

| Step | What happens | What it produces |
|---|---|---|
| `branch` | protected branch — `exloom:isolating-execution` | a feature branch (the hooks skip protected ones) |
| `init` | `/review-init`, used by /exloom; asks once "Quick fix?" (yes = Sprint) | `.claude/reviews/<branch>.md` |
| `commit` | commit the review files on their own | checklist and receipts in history |
| `commit-work` | uncommitted changes outside `.claude/reviews` | your work committed first |
| `spec` | `exloom:brainstorming` (Standard and Certified only) | a spec — numbered requirements, one criterion each |
| `plan` | `exloom:planning-for-handoff` (Standard and Certified only) | a plan — exact files, tasks citing their criteria |
| `build` | `exloom:executing-handoff-plans`: one task at a time, each reviewed, until every task approved. No plan: make the change, commit | the code — not more, not less |
| `report` | the evidence block is regenerated from receipts | checklist bound to the reviewed commit |
| `review` | the whole-branch review, once, after the last task | receipts nobody can hand-write |
| `fix` | `exloom:fixer` applies the cited fix, then the same reviewer verifies | a fix commit and a verify receipt |
| `rulings` | each finding open after a verify: fix again, PARKED, or DEFERRED with a ticket | `## Rulings` |
| `proof` | `prove-change-is-tested.sh` runs the suite three times | `proof.json` — PROVED or why not |
| `smoke` | `/smoke-test`, used by /exloom — the real thing | smoke receipt or pasted result |
| `push` | ready | `git push` when you say so |

## Lanes

| Lane | What /exloom skips | Declared |
|---|---|---|
| **Sprint** | spec, plan, fidelity audit, reviewers above L1 | `**Lane:** sprint` |
| **Standard** | nothing | the default |
| **Certified** | nothing; plus no workflow-step escape hatches, signed commits | `**Lane:** certified` |

Asked once, at `init`. The repo default is a committed `.claude/exloom-lane`, else `standard`.

**Sprint skips ceremony, not evidence.** Same receipts, proof, smoke test, and the tier the hook derives from the diff. **Not available at Tier 3.** If a Sprint branch turns out to matter, `/harden` recovers the spec from the diff and flips the lane.

**On Certified, a skipped step written under `## Escape hatches used` blocks the push.**

## Review rounds

After a REJECTED review, `exloom:fixer` applies the smallest fix for what was cited; the same reviewer verifies the fix range. What it still reports open is yours to rule on. At the round cap (default 3, `.claude/exloom-max-rounds`) exloom refuses another dispatch and you rule on what is left.

Adversarial (Tier 2+) and security (Tier 3 or a security surface) run once, after L1 settles; a fix does not expire their approval.

**Fix what the reviewer cited.** A new file, class, or test class needs asking first.

`worked-example.md` takes one real change through /exloom.

## Skills /exloom calls

| Situation | Skill |
|---|---|
| No spec yet | `exloom:brainstorming` |
| Spec, no plan | `exloom:planning-for-handoff` |
| On a protected branch | `exloom:isolating-execution` |
| Executing a plan | `exloom:executing-handoff-plans` |
| Execution finished, before review | `exloom:auditing-plan-fidelity` |
| The gate itself | `exloom:review-gate` |
| Code behind an architecture, data-model, DB or API doc changed | `exloom:maintaining-reference-docs` |

Call yourself: `exloom:capturing-learnings`, `exloom:authoring-claude-md`. Skip skills for conversation or trivial edits.

## Commands

```
/exloom           the entry point — runs the next step until push
/exloom status    one line: tier, task, round, proof, rulings, next step
/exloom-setup     turn the gate on in a repo, once
/harden           when a Sprint branch turns out to matter
/review-cleanup   archive checklists of branches that no longer exist
```

`/review-init`, `/smoke-test` and `/review-complete` belong to /exloom, not to you. Doing their steps by hand leaves the push blocked; receipts exist only when a reviewer subagent completes.

## Is the gate on in this repo?

Where the branch's checklist is committed, or anywhere if `.claude/exloom-gate.enabled` is. Then `git push` on a feature branch is blocked until the checklist is complete and bound to the reviewed commit. **Never create that marker yourself** — it gates everyone, including people who did not choose exloom. `/exloom-setup` offers it; the user decides.
