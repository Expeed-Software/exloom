---
name: using-exloom
description: Use when starting work that will produce a commit — names the exloom skills and review commands and when each applies.
---

# Using exloom

exloom produces **evidence** that transfers between people — spec, plan, proof receipt, review receipts — and gates it once, at push.

## Quick start — a feature, start to finish

| # | Step | What you run | What it produces |
|---|---|---|---|
| 1 | Decide what to build | `exloom:brainstorming` | a spec — problem, approach, numbered requirements, one criterion each |
| 2 | Turn it into a plan | `exloom:planning-for-handoff` | a plan — exact files, tasks, each citing the criteria it serves |
| 3 | Get on a branch | `exloom:isolating-execution` | a feature branch (the gate skips protected branches) |
| 4 | Start the review record | `/review-init` | `.claude/reviews/<branch>.md` with a tier |
| 5 | Build it | `exloom:executing-handoff-plans` | the code — not more, not less; deviations logged |
| 6 | Prove the tests notice it | `bash scripts/prove-change-is-tested.sh` | `proof.json` — PROVED or the reason it isn't |
| 7 | Check for drift | `exloom:auditing-plan-fidelity` | files changed that no task called for |
| 8 | Run it | `/smoke-test` | real output from the real thing |
| 9 | Review | `/review-complete` | reviewer receipts, findings, fixes |
| 10 | Ship | `git push`, open the PR | the gate lets it through |

## Pick a lane before you pick a step

| Lane | Steps | What it costs you | Declared |
|---|---|---|---|
| **Sprint** | 3, 4, 5, 6, 8, 9, 10 | nothing before the code — L1, smoke and proof after it | `**Lane:** sprint` |
| **Standard** | all ten | a spec and a plan, and the reviewers the tier asks for | the default |
| **Certified** | all ten | standard, plus no workflow-step escape hatches and signed commits | `**Lane:** certified` |

`/review-init` asks. The repo default lives in a committed `.claude/exloom-lane`; absent, it is `standard`.

**Sprint skips ceremony, not evidence.** Same receipts, proof, smoke test and derived tier. It drops the spec, the plan, the fidelity audit, and reviewers above L1.

**Sprint is not available at Tier 3.** Migrations, auth, tenancy, secrets and crypto earn the full flow.

**If a Sprint branch turns out to matter, run `/harden`.** It recovers the spec from the diff, flips the lane, and names what the higher bar requires.

**Even on Standard, a small change starts at step 3.** Steps 5 and 7 apply only when there is a plan.

**Round 2 is L1 only.** Fix what it found, re-run `/review-complete`. Adversarial and security run once, after L1 has settled; their approval does not expire when you fix something.

**When a reviewer finds something, fix what it cited.** If the fix seems to need a new file, class, or test class, stop and ask first.

See `worked-example.md` in this skill for one real change taken through all ten steps.

## Skills

| Situation | Skill |
|---|---|
| New feature, or unclear requirements, no spec yet | `exloom:brainstorming` |
| Have a spec, need a plan someone else could execute | `exloom:planning-for-handoff` |
| About to start executing — before the first commit | `exloom:isolating-execution` |
| Executing a written plan | `exloom:executing-handoff-plans` |
| Execution finished, before review | `exloom:auditing-plan-fidelity` |
| Closing work — done, shipping, opening a PR | `exloom:review-gate` |
| Learned something worth keeping | `exloom:capturing-learnings` |
| Writing or updating a repo's CLAUDE.md | `exloom:authoring-claude-md` |

The three execution skills are the scope discipline: `executing-handoff-plans` writes what the plan describes and logs every deviation, `auditing-plan-fidelity` reports drift between diff and plan, and `isolating-execution` puts the work on a feature branch so the gate applies.

Do not invoke a skill for a conversational reply, a factual answer, or a trivial mechanical edit.

## Commands — invoke them, don't reproduce them

```
/review-init      when work starts on the branch — picks the lane
/smoke-test       before claiming done
/review-complete  before push / PR
/harden           when a Sprint branch turns out to matter
```

`/review-complete` dispatches the reviewer subagents the tier requires; each real dispatch writes a receipt the gate demands and nobody can write by hand. Performing its steps yourself produces no receipts, so the push stays blocked.

## Cost shape

- `l1-reviewer` — **low** effort, cheap enough to run per commit.
- `adversarial-reviewer` — **medium**, once, before push. Carries the cross-layer contract check.
- `security-auditor` — **medium**, at Tier 3 or when the diff touches a security surface.

When a receipt says `"verdict":"APPROVED"` and `"round_needed":"NO"`, stop. Do not run another round to be thorough.

## Is the gate on in this repo?

Opt-in per repo, off by default. On only when this file exists:

```
.claude/exloom-gate.enabled
```

With it, `git push` on a feature branch is blocked until `.claude/reviews/<branch>.md` is complete and bound to the reviewed commit.

Turn it on with:

```bash
mkdir -p .claude && touch .claude/exloom-gate.enabled
```

**Do not create that marker on your own initiative.** It is committed and changes the gate for everyone. Offer it; the user decides.
