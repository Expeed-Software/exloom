---
name: using-exloom
description: Use when starting any conversation — establishes how to find and use exloom skills, requires invoking the right skill before any action.
---

# Using exloom

## Overview

exloom is a team-oriented development workflow for Claude Code. It brings handoff discipline, brownfield awareness, an enforced evidence-based review gate, and shared knowledge capture — so a team ships work that's provable and handoff-safe, and a solo developer gets that same rigor with a review panel behind them. It scales from one developer to a whole org.

Most of exloom is *discipline* — skills the model reads and chooses to follow. One part is *enforcement*: the `review-gate` hooks, when a repo turns them on, physically block "done" and `git push` until the review evidence exists. That gate is exloom's core guarantee; the rest is strong defaults.

This skill is the meta-skill. Load it at the start of any conversation to understand which skills apply and in what order. Every other skill in exloom encodes a team process — finding the right one before acting is the first and most important discipline.

## Is the gate on in this repo?

The gate is **opt-in per repo** and **off by default** — exloom never blocks a repo that did not ask for it. It is on only when this marker file exists:

```
.claude/exloom-gate.enabled
```

Without it, `review-gate` is a (strong) recommendation and nothing is enforced. With it, the hooks physically block done-claims and `git push` on feature branches until `.claude/reviews/<branch>.md` is complete and bound to the reviewed commit.

**Tell the user how to turn it on** when they ask about enforcing review, wonder why nothing is blocking, or say they want the gate — it is one line, committed once, and the whole team inherits it:

```bash
mkdir -p .claude && touch .claude/exloom-gate.enabled
```

**Do not create that marker on your own initiative.** It is committed to the repo and changes how the gate behaves for every developer on it — that is the user's decision to make, not a side effect of you reading this skill. Offer it; let them choose.

## Quick Start

New to exloom? Find your situation and start with the named skill — it will pull in the others as needed.

| Your situation | Start with |
|---|---|
| Building a new feature or changing behavior | `brainstorming` → it leads to `planning-for-handoff` → `isolating-execution` → `executing-handoff-plans` |
| Fixing a bug | `systematic-debugging` → diagnose root cause before any fix |
| Handed a written plan to implement | `isolating-execution` first, then `executing-handoff-plans` (or `orchestrating-execution` for multi-agent, review-per-task execution) |
| About to say "it's done" | `proving-done` |
| Closing work — about to mark done / ship / merge | `review-gate` (enforces the evidence gate) |
| Opening a PR | `requesting-review` |
| Reviewing someone's PR | `reviewing-code` (run `auditing-plan-fidelity` first if a plan existed) |
| Joining an unfamiliar codebase | `exploring-codebase` |
| Moving from one project to another | `switching-projects` |
| Learned something worth keeping | `capturing-learnings` |
| Want review actually enforced — or wondering why nothing is blocking | The gate is off unless `.claude/exloom-gate.enabled` exists — see *Is the gate on in this repo?* above |

The single most common flow: **`brainstorming` → `planning-for-handoff` → `isolating-execution` → `executing-handoff-plans` → `proving-done` → `requesting-review`.** When in doubt, start at `brainstorming` — it's the front door for any new work.

**Review commands — invoke these, don't reproduce them.** The gate runs on three commands, and *you* call them with the Skill tool; they are not instructions for the user to type:

```
/review-init   (when work starts on the branch)
    → /smoke-test   (before claiming done)
        → /review-complete   (before push / PR)
```

`/review-init` declares the tier **before** the diff is finished, which is the point of it — the gate derives the tier from the diff and blocks a checklist that declares less. `/review-complete` dispatches the reviewer subagents the tier requires, and each real dispatch writes a receipt the gate demands and no one can write by hand. Reading these commands and doing the steps yourself produces the checklist but none of the receipts, so the push is blocked. Having the text in context is not running it.

## When Skills Apply

Default rule: if a skill plausibly applies to the work in front of you, invoke it before acting. When genuinely unsure whether a skill applies, lean toward invoking it — the asymmetry favors it.

The reason is asymmetric cost. Invoking a skill that turns out not to apply costs a little context and a few seconds — real, but small. Skipping a skill that did apply costs a poorly executed task, a missed handoff, or a plan nobody else can follow — much larger. When the downside of skipping dwarfs the downside of invoking, default to invoking.

The decisive line, so the marginal case isn't ambiguous:

- **Does the request create, change, or review code or a plan?** → A skill applies. Invoke before acting.
- **Is it a conversational reply, a factual answer, or a trivial mechanical edit (rename a variable, fix a typo, bump a version)?** → No process skill needed. Just answer or do it.

When a request sits on the line, decide by that test, not by how it feels. The frontmatter's "use when starting any conversation" refers to loading *this* meta-skill to orient yourself — it does not mean loading a process skill before every sentence you say.

## Skill Catalog

### Core Discipline

These skills cover the primary development loop — the work itself.

| Skill | Trigger |
|---|---|
| `exloom:brainstorming` | Any creative work: new features, components, behavior changes. Explores intent before implementation. |
| `exloom:planning-for-handoff` | When you have a spec or requirements and need a handoff-ready execution plan. |
| `exloom:executing-handoff-plans` | When you have a written plan to run — step-by-step, no improvising. |
| `exloom:orchestrating-execution` | When executing a plan task-by-task by dispatching a fresh subagent per task, with the review gate run between tasks (multi-agent execution). |
| `exloom:isolating-execution` | Before executing a plan — isolates the workspace onto a gated feature branch (or a worktree) so the review gate applies and the base branch stays clean. |
| `exloom:systematic-debugging` | Any bug, test failure, or unexpected behavior. Diagnose before fixing. |
| `exloom:proving-done` | Before claiming any work is done, fixed, or passing. |
| `exloom:review-gate` | When closing work — claiming done, shipping, or opening a PR — runs the tier-scaled review gate (L1 + smoke test + cross-layer + adversarial) and refuses to mark complete without evidence. |
| `exloom:requesting-review` | When implementation is complete and needs a human reviewer. |
| `exloom:reviewing-code` | When reviewing someone else's code — PR review, pairing, or audit. |
| `exloom:security-review` | When a change touches user input, auth, secrets, deserialization, external calls, or dependencies — runs scanners plus a category review for AI-code security flaws. Evidence-based first pass, not a guarantee. |
| `exloom:test-driven-development` | When implementing any feature or bugfix — write failing test first, minimal code, refactor. |

### Handoff

These skills manage the transition of work between people.

| Skill | Trigger |
|---|---|
| `exloom:reviewing-plans` | When a plan needs review before execution — especially cross-person handoffs. |
| `exloom:auditing-plan-fidelity` | After execution completes — verifies what was built matches what was planned. |

### Supporting

These skills handle setup, context, and organizational knowledge.

| Skill | Trigger |
|---|---|
| `exloom:authoring-claude-md` | When creating or updating a CLAUDE.md for a repo or team. |
| `exloom:exploring-codebase` | When starting work on an unfamiliar codebase or module. |
| `exloom:capturing-learnings` | After a significant bug, incident, or successful pattern — document it. |
| `exloom:switching-projects` | When context-switching between projects — save and restore mental state. |

### UI

| Skill | Trigger |
|---|---|
| `exloom:designing-ui` | When designing or building UI components — visual, accessible, on-brand. |

If a skill listed here is not available when you try to invoke it, it may not be installed in this build of the plugin, or it may have been renamed. Check the plugin's `skills/` directory or your client's skill list rather than guessing — do not fabricate behavior for a skill that is not present.

## Priority Order

When multiple skills could apply, use this priority:

1. **Process skills** — if there is a bug or open-ended creative problem, start here.
   - `systematic-debugging` (bug present) → `brainstorming` (creative problem)
2. **Workflow skills** — if the work is defined, plan it or execute the plan.
   - `planning-for-handoff` (need a plan) → `isolating-execution` (isolate onto a gated branch) → `executing-handoff-plans` *or* `orchestrating-execution` (multi-agent, review-per-task) → `test-driven-development` (during implementation)
3. **Review skills** — whenever work crosses a boundary (person-to-person, stage-to-stage).
   - `reviewing-plans` → `reviewing-code` / `security-review` → `review-gate` (enforced gate at completion) → `auditing-plan-fidelity`
4. **Supporting skills** — context, setup, and organizational hygiene.
   - Any of the supporting skills as needed.

If two skills at the same priority level both apply, invoke the one that gates the other. Example: you have a plan to review AND code to write — review the plan first; don't write code against an unreviewed plan.

## Solo vs. Team Flow

### Solo path (one person owns the full cycle)

```
brainstorming → planning-for-handoff → isolating-execution → executing-handoff-plans (with TDD) → proving-done → review-gate → requesting-review
```

For higher throughput, `orchestrating-execution` replaces `executing-handoff-plans` — it dispatches a fresh subagent per task and runs the review gate between tasks. Even solo work produces handoff-ready plans. Future-you is a different person. Use `test-driven-development` during execution for any task with business logic. Code review still happens at the end — the reviewer is the team.

### Team path (work crosses person boundaries)

```
brainstorming → planning-for-handoff → reviewing-plans → [assign to executor] → isolating-execution → executing-handoff-plans or orchestrating-execution (with TDD) → auditing-plan-fidelity → reviewing-code → review-gate
```

The handoff point is between `reviewing-plans` and `executing-handoff-plans`. The plan is the contract. The executor does not modify the plan without logging a deviation and getting approval from the author.

### How to decide which path

- Is execution happening in the same session by the same person who wrote the plan? → Solo path.
- Will the plan be picked up by a different person, or in a future session? → Team path. Use `reviewing-plans` before any handoff.
- Is the task exploratory with no spec yet? → Start with `brainstorming` regardless of path.

**When it is not obvious, ask — do not guess silently.** If you cannot tell from the request whether the same person will execute the plan in this session or it will be handed off, ask the user: *"Are you executing this yourself now, or will someone else (or a later session) pick it up?"* State which path you are taking and why, so the choice is visible. When the answer is genuinely unknowable, default to the **team path** and run `reviewing-plans` — a plan that passed a second review is never wrong, and a handoff-ready plan costs little even when you end up executing it yourself.

## Red Flags

These are thoughts that indicate rationalizing away a skill. Recognize them and respond correctly.

**"This is simple, no skill needed."**
Simplicity is not an exemption. Simple tasks go wrong in simple ways. Invoke the skill and move fast — it does not slow you down.

**"I'll just do it first and document later."**
This is how plans that nobody can follow get created, and how brownfield context gets lost. Write the plan before executing, not after.

**"I need more context first before I can use a skill."**
`exploring-codebase` is a skill. `brainstorming` starts with exploration. Context-gathering is itself a structured activity.

**"This doesn't need a formal skill — it's just a quick fix."**
Quick fixes that skip `systematic-debugging` produce fixes that mask root causes. Quick fixes that skip `proving-done` introduce regressions. No fix is too small for the checklist.

**"The skill will slow me down."**
Skills encode exactly the steps an experienced engineer would take anyway. Invoking a skill does not add overhead — it prevents the expensive rework that comes from skipping steps.

**"I already know the best approach."**
That certainty is the smell. If you already know, the skill runs quickly. If you're wrong, the skill catches it cheaply. Invoke it.
