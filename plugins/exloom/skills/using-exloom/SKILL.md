---
name: using-exloom
description: Use when starting work that will produce a commit — names the exloom skills and review commands and when each applies.
---

# Using exloom

exloom produces **evidence**, not discipline.

The model already plans, tests, and self-reviews without being told. What a team of many developers lacks is evidence that transfers between people: something the next person can read to know what was intended, whether the tests actually exercise the change, and who reviewed it at which commit. exloom produces four artifacts and gates them once, at push.

| Artifact | Produced by | Answers |
|---|---|---|
| Spec | `brainstorming` | what we decided to build, and what we rejected |
| Plan | `planning-for-handoff` | what to do, in what order, verifiable by someone else |
| Proof receipt | `scripts/prove-change-is-tested.sh` | do the tests actually fail without this change |
| Review checklist + receipts | `/review-init` → `/review-complete` | who reviewed, at which commit, with what verdict |

Nothing here instructs you how to think about code. If a skill would only tell you to be careful, it was removed.

## Quick start — a feature, start to finish

This is the sequence. The table below is for looking up a single step; this is what you actually do.

| # | Step | What you run | What it produces |
|---|---|---|---|
| 1 | Decide what to build | `exloom:brainstorming` | a spec — the problem, the approach, what's out of scope |
| 2 | Turn it into a plan | `exloom:planning-for-handoff` | a plan — exact files, tasks, acceptance criteria |
| 3 | Get on a branch | `exloom:isolating-execution` | a feature branch (the gate skips protected branches) |
| 4 | Start the review record | `/review-init` | `.claude/reviews/<branch>.md` with a tier |
| 5 | Build it | `exloom:executing-handoff-plans` | the code — not more, not less; deviations logged |
| 6 | Prove the tests notice it | `bash scripts/prove-change-is-tested.sh` | `proof.json` — PROVED or the reason it isn't |
| 7 | Check for drift | `exloom:auditing-plan-fidelity` | files changed that no task called for |
| 8 | Run it | `/smoke-test` | real output from the real thing |
| 9 | Review | `/review-complete` | reviewer receipts, findings, fixes |
| 10 | Ship | `git push`, open the PR | the gate lets it through |

**A small change starts at step 3.** A one-line bug fix does not need a spec or a plan — branch, fix, prove, smoke, review, push. Steps 5 and 7 need a plan to work against, so they only apply when there is one.

**Round 2 is L1 only.** Fix what it found, re-run `/review-complete`. Adversarial and security run once, after L1 has settled, and their approval does not expire when you fix something.

**When a reviewer finds something, fix what it cited.** A finding is a defect report, not a design brief. If the fix seems to need a new file, class, or test class — stop and ask first. That is the single behaviour that turns a one-line change into a feature.

See `worked-example.md` in this skill for one real change taken through all ten steps.

## Skills

| Situation | Skill |
|---|---|
| New feature or behaviour change, no spec yet | `exloom:brainstorming` |
| Have a spec, need a plan someone else could execute | `exloom:planning-for-handoff` |
| About to start executing — before the first commit | `exloom:isolating-execution` |
| Executing a written plan | `exloom:executing-handoff-plans` |
| Execution finished, before review | `exloom:auditing-plan-fidelity` |
| Closing work — done, shipping, opening a PR | `exloom:review-gate` |
| Learned something worth keeping | `exloom:capturing-learnings` |
| Writing or updating a repo's CLAUDE.md | `exloom:authoring-claude-md` |

**The three execution skills are the scope discipline.** `executing-handoff-plans` says write what the plan describes — *not more, not less, not differently* — and log every deviation instead of improvising. `auditing-plan-fidelity` then compares the shipped diff against the plan and reports drift: files changed that no task called for, acceptance criteria quietly altered. `isolating-execution` puts the work on a feature branch, which is what makes the gate apply at all — the hooks skip protected branches.

They were cut in 4.0.0 as "technique the model already does" and restored in 4.4.0. That was a misjudgement: a check that compares work against an artifact is not technique, because the model is the thing being checked. Their absence is a large part of how one-line changes grew into features.

Invoke one when it applies. Do not invoke one for a conversational reply, a factual answer, or a trivial mechanical edit.

## Commands — invoke them, don't reproduce them

```
/review-init      when work starts on the branch
/smoke-test       before claiming done
/review-complete  before push / PR
```

`/review-complete` dispatches the reviewer subagents the tier requires. Each real dispatch writes a receipt that the gate demands and that nobody can write by hand. Reading the command and performing the steps yourself produces the checklist and none of the receipts, so the push stays blocked. Having the text in context is not running it.

## Cost shape

Three reviewers remain, and the effort levels are deliberate:

- `l1-reviewer` — **low** effort, cheap enough to run per commit.
- `adversarial-reviewer` — **medium**, once, before push. Carries the cross-layer contract check.
- `security-auditor` — **medium**, at Tier 3 or when the diff touches a security surface.

Run the cheap pass often and the expensive pass once. When a receipt says `"verdict":"APPROVED"` and `"round_needed":"NO"`, stop — running another round to be thorough is how a two-round change becomes a nine-round one.

## Is the gate on in this repo?

Opt-in per repo, off by default. On only when this file exists:

```
.claude/exloom-gate.enabled
```

Without it the skills are recommendations and nothing blocks. With it, `git push` on a feature branch is blocked until `.claude/reviews/<branch>.md` is complete and bound to the reviewed commit.

Turn it on with:

```bash
mkdir -p .claude && touch .claude/exloom-gate.enabled
```

**Do not create that marker on your own initiative.** It is committed and changes the gate for everyone on the repo — the user's decision, not a side effect of reading this skill. Offer it; let them choose.
