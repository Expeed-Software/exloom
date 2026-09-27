---
name: brainstorming
description: Use when the user asks for a new feature, or when what to build is unclear or disputed. Not for bug fixes, refactors, review findings or changes whose requirements are already stated. Explores intent, requirements and design before implementation. Brownfield-aware.
---

# Brainstorming

## Overview

Explore intent, requirements and design before any code exists, starting from "what already exists, and what is the minimum we need to add?" The output is a written spec that `exloom:planning-for-handoff` consumes.

## Scaling Effort to Complexity

The process is the same; the depth scales.

| Complexity | Examples | Time | What scales down |
|---|---|---|---|
| **Simple** | CRUD endpoint, config change, add a column | 15-20 min | Design is 3-4 sentences. Steps 5-7 collapse into one message. Spec is half a page. |
| **Medium** | New API with integrations, new UI page, add auth to a flow | 30-45 min | Full process, but 2-3 approaches is enough. Spec is 1-2 pages. |
| **Complex** | New subsystem, cross-cutting concern, multi-service feature | 60-90 min | Full process, all steps at full depth. Spec is 2-4 pages. |

Durations are guides, not targets. Beyond 90 minutes, decompose into sub-projects and brainstorm the first. Simple work moves through all 8 steps faster; it doesn't skip them.

## Process

### Step 1: Explore Project Context

Before asking the user anything, read CLAUDE.md and README, the last 20-30 commits, the stack and architecture, similar features (by name, concept and problem), and the test suite's patterns. Never ask what the code already answers.

### Step 2: Understand the Problem, Not the Solution

Users arrive with solutions; find the problem underneath ("I need a caching layer" may be a slow query). Ask: Who has this problem? How do they solve it today? What happens if we don't build this?

### Step 3: Ask Clarifying Questions One at a Time

One question per message, most important first, wait for the answer. Prefer multiple choice: "Should this handle (a) only logged-in users, (b) all users including anonymous, or (c) only admin users?" Ask about constraints (performance, backwards compatibility, deployment, offline), not preferences ("Redux or MobX?"). Stop when you can predict the user's answer.

### Step 4: Explore the Solution Space

Present 2-3 approaches, leading with your recommendation: "I recommend Approach B because..." Each approach: two-sentence summary, 1-2 pros/cons, one-sentence "recommended when," grounded in this codebase ("extends the existing EventBus pattern"). No strawmen, no unweighted menu.

### Step 5: Present the Design in Sections

Scale depth to complexity; pause for feedback after each major section. Sections: **Overview** (what, why, fit — one paragraph), **Components** (name every file, class, function, endpoint, table), **Data flow** (happy path and primary failure), **Error handling** (what fails, detection, recovery), **Edge cases** (null, concurrent, network, scale — with handling), **Non-goals** (what this does not do). Present the overview first and get approval before the rest.

### Step 6: Write the Spec

Copy `templates/spec-template.md` to where this repo keeps specs — if the repo's CLAUDE.md (or the user) specifies a location, use it; otherwise `docs/exloom/specs/F-<nnn>-<slug>.md`. Allocate `<nnn>` as one past the highest `F-` already in that directory. Commit if the user permits.

The spec must be readable by someone not in the session. The template carries the canonical shape: problem, chosen approach with rationale, rejected approaches with rationale, numbered requirements each carrying at least one acceptance criterion, edge cases, non-goals, open questions. Reference code by file path. Record contentious decisions with both perspectives. Mark ambiguity as open questions.

**Requirements.** Each requirement (`R-<n> · <type>`) is one behaviour, in one of the five EARS shapes, with at least one acceptance criterion (`AC-<n> · <level>`) written as Given/When/Then. Unverifiable requirements ("works correctly", "performance is acceptable") are not requirements.

- **Say what the system does, never how it is built.** `SHALL store the job in Postgres` is an architecture decision; `SHALL persist the job so it survives a restart` is the requirement.
- **Anything touching money, permissions, or data loss needs an `unwanted` requirement** — `IF <bad thing> THEN THE SYSTEM SHALL <response>`.

**Refs are permanent once the spec is approved.** `F-012/R-3/AC-2` is cited by plans, tests and review checklists. While the spec is `draft`, renumber freely. After approval, changing what a criterion means creates a new one and marks the old `superseded`.

### Step 7: Lint the Spec

Run the linter. Fix the errors.

```bash
LINT="$(find ~/.claude/plugins -path '*exloom*/scripts/lint-spec.sh' | sort -V | tail -1)"
bash "$LINT" docs/exloom/specs/F-012-slug.md
```

**Fix the errors. Judge the warnings** — warnings are heuristics (an implementation named in a requirement; money, permissions or deletion with no `unwanted` requirement), and one you disagree with is ignored. This step is the linter and nothing else.

### Step 8: User Reviews, Then Transition

Ask the user for a full read of the written spec: "Does the problem statement match? Are non-goals acceptable? Edge cases missing?" Never transition without explicit approval — "looks good" after thirty seconds is not approval. Once approved, invoke `exloom:planning-for-handoff`; never go straight to implementation.

## Brownfield Discipline

Assume the codebase already has an opinion about how to solve the problem. Find it before forming your own.

1. **Search for existing implementations** by concept, not just name — for notifications, search "notification", "alert", "event", "message", "publish", "subscribe"; `AlertDispatcher` counts. Prove nothing exists before proposing something new.
2. **Read the surrounding code.** Match the base classes, error handling, logging and DI of existing code in the same layer.
3. **Check for shared libraries** in the codebase and the repo's CLAUDE.md before adding a dependency.
4. **Match existing patterns, then justify deviation** in the spec. The bar: the existing pattern cannot solve the problem, and the new pattern's total cost is lower. "Simpler" is not a justification; "the ORM we're integrating only supports Active Record" is.
5. **Propose extending before building new.** If an existing feature does 60%+ of what's needed, extend it unless that produces a worse outcome for team maintenance and clarity.

"The existing implementation is bad" needs a specific technical assessment, not an opinion.

## Decision Points

| Situation | Decision |
|---|---|
| User arrives with a solution, not a problem | Ask "what problem does this solve?" Verify the solution addresses the root cause. |
| Scope too large for one spec | Decompose into sub-projects. Brainstorm the first one fully. Reference others as future work in non-goals. |
| User wants to skip brainstorming | "If you already know, a quick pass just confirms it. If assumptions are wrong, this catches it before code. Minutes here versus days in code." |
| Existing feature does 80% of what's needed | Propose extending. Document the gap and the extension approach, unless extension compromises the existing feature. |
| User disagrees with your recommendation | Accept their choice, note both perspectives in the spec. You advise; they decide. |
| Multiple valid approaches, no clear winner | Recommend the simplest. YAGNI. |
| Problem unclear even after questions | Document what's known, unknown, and assumed. No false precision. |

## Failure Modes

See [failure-modes.md](failure-modes.md).

## Worked Example

See [worked-example.md](worked-example.md).

## Integration

- **You arrive here from:** a user request, a ticket, an idea, a product requirement, or mid-execution when a task needs design work the plan did not anticipate.
- **You leave here toward:** `exloom:planning-for-handoff` — always. Never directly to implementation.
- **During any step:** route a learning about the codebase or team conventions through `exloom:capturing-learnings`.
