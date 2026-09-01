---
name: brainstorming
description: Use before any creative work — creating features, building components, adding functionality, or modifying behavior. Explores intent, requirements, and design before implementation. Brownfield-aware.
---

# Brainstorming

## Overview

Brainstorming explores intent, requirements, and design before implementation.
It runs before any code exists — the depth scales with complexity (see the table
below; minutes for a simple change, not a fixed quota).

This is brownfield-aware brainstorming. Generic brainstorming asks "what should
we build?" This skill asks "what already exists, and what is the minimum we need
to add?" Every proposal starts from the existing codebase, not from a blank
slate. New code earns its place by solving a problem that existing code cannot.
The output is a written spec that `exloom:planning-for-handoff` consumes to produce
an execution plan.

## Scaling Effort to Complexity

Not every feature needs 90 minutes of brainstorming. The process is the same — the depth scales.

| Complexity | Examples | Time | What scales down |
|---|---|---|---|
| **Simple** | CRUD endpoint, config change, add a column | 15-20 min | Design is 3-4 sentences. Steps 5-7 collapse into one message. Spec is half a page. |
| **Medium** | New API with integrations, new UI page, add auth to a flow | 30-45 min | Full process, but 2-3 approaches is enough. Spec is 1-2 pages. |
| **Complex** | New subsystem, cross-cutting concern, multi-service feature | 60-90 min | Full process, all steps at full depth. Spec is 2-4 pages. |

These durations are rough guides, not targets. A change that genuinely needs only five minutes of thought should take five minutes — do not pad it to hit a number. The point is to scale effort to complexity, not to spend a prescribed amount of time. If brainstorming exceeds 90 minutes, that is a signal the scope is too large — decompose into sub-projects and brainstorm the first one.

Simple work moves through all 8 steps faster. It doesn't skip them. A simple CRUD endpoint still checks for existing implementations (Step 1), still confirms the problem (Step 2), and still produces a spec (Step 6) — the spec is just shorter.

## Process

### Step 1: Explore Project Context

**What to do:** Before asking the user anything, read the codebase. Understand
what exists before proposing what should exist.

**How to do it well:** Read CLAUDE.md and README for conventions. Scan recent
git history (20-30 commits) for team patterns. Identify tech stack and
architecture. Search for features similar to the request — by name, concept,
and problem. If the codebase is unfamiliar, read it before proposing anything.
Check the test suite for testing patterns and coverage expectations.

**What bad looks like:** Asking "what framework are you using?" when the answer
is in `package.json`. Starting design without reading existing code — producing
a design that contradicts every convention in the project.

### Step 2: Understand the Problem, Not the Solution

**What to do:** Ask "what problem does this solve?" before "what should we
build?" Users arrive with solutions. Your job is to find the problem underneath
and verify the solution addresses it.

**How to do it well:** When a user says "I need a caching layer," the problem
might be "page load takes 4 seconds because we query the database on every
request." Maybe the answer is query optimization, not caching. Three key
questions: Who has this problem? How do they solve it today? What happens if we
don't build this? The answers reveal whether the proposed solution addresses the
root cause or whether the problem suggests a different approach entirely.

**What bad looks like:** Accepting "I need a caching layer" and immediately
designing one. Skipping problem exploration because the user seems confident —
confidence about solutions and correctness about problems are unrelated.

### Step 3: Ask Clarifying Questions One at a Time

**What to do:** Ask one question per message. Prefer multiple choice. Focus on
constraints over preferences.

**How to do it well:** Most important question first. Wait for the answer before
the next. Frame as multiple choice — "Should this handle (a) only logged-in
users, (b) all users including anonymous, or (c) only admin users?" beats "who
should have access?" Multiple choice reveals assumptions and gives the user
something concrete to react to. Focus on constraints (performance, backwards
compatibility, deployment) because constraints eliminate options. Stop asking
when you can predict the user's answer — you've internalized their model.

**What bad looks like:** Five questions in a single message — user answers easy
ones, skips hard ones. Open-ended questions ("what do you think about the
architecture?") that produce vague answers. Asking preferences ("Redux or
MobX?") instead of constraints ("does this need to work offline?").

### Step 4: Explore the Solution Space

**What to do:** Present 2-3 approaches with trade-offs. Lead with your
recommendation and explain why.

**How to do it well:** Start with "I recommend Approach B because..." — the user
wants judgment, not a menu. Then present alternatives with what you rejected and
why. Each approach: two-sentence summary, 1-2 pros/cons, one-sentence
"recommended when." Ground in the existing codebase — "extends the existing
EventBus pattern" beats "uses event-driven architecture." If one is clearly
superior, say so. Don't manufacture false equivalence.

**What bad looks like:** Three equally weighted options with "which do you
prefer?" — abdicating your role. Strawman options to make the recommendation
look better. Approaches disconnected from this codebase's patterns.

### Step 5: Present the Design in Sections

**What to do:** Walk through the design section by section, scaling depth to
complexity. Pause after each major section for feedback.

**How to do it well:** Simple sections: 2-3 sentences. Complex: detailed data
flow and failure modes. Sections: **Overview** (what, why, fit — one paragraph),
**Components** (name every file, class, function, endpoint, table), **Data flow**
(happy path and primary failure), **Error handling** (what fails, detection,
recovery), **Edge cases** (null, concurrent, network, scale — with handling),
**Non-goals** (what this does not do). Present overview first, get approval,
then components, then the rest. Course correction at overview is free; after
full design it costs everything.

**What bad looks like:** Wall of text for the entire design. Vague components
("a service layer that handles the logic"). No error handling. No non-goals —
scope creep starts immediately.

### Step 6: Write the Spec

**What to do:** Copy `templates/spec-template.md` to where this repo keeps specs —
if the repo's CLAUDE.md (or the user) specifies a location, use it; otherwise
`docs/exloom/specs/F-<nnn>-<slug>.md`. Allocate `<nnn>` as one past the highest
`F-` already in that directory. Commit if the user permits.

**How to do it well:** The spec must be readable by someone not in the session.
The template carries the canonical shape: problem, chosen approach with
rationale, rejected approaches with rationale, numbered requirements each
carrying at least one acceptance criterion, edge cases, non-goals, open
questions. Reference code by file path. Record contentious decisions with both
perspectives. Mark ambiguity as open questions rather than papering over it.

**The requirements section is the part that makes this a spec rather than a
memo.** Each requirement is one behaviour, in one of the five EARS shapes, with
at least one acceptance criterion written as Given/When/Then. Two rules do most
of the work:

- **Say what the system does, never how it is built.** `SHALL store the job in
  Postgres` is an architecture decision wearing a requirement's clothes; `SHALL
  persist the job so it survives a restart` is the requirement.
- **Anything touching money, permissions, or data loss needs an `unwanted`
  requirement** — `IF <bad thing> THEN THE SYSTEM SHALL <response>`. Most defects
  live in the negative space and most specs never go there.

**Refs are permanent once the spec is approved.** `F-012/R-3/AC-2` is cited by
plans, by tests, and by review checklists; a ref that quietly changes meaning
invalidates all three. While the spec is still `draft`, renumber freely. After
approval, changing what a criterion means creates a new one and marks the old
`superseded`.

**What bad looks like:** A spec that only makes sense to someone in the
conversation. No rejected alternatives — three months later, someone proposes the
same rejected idea because the reasoning was never recorded. Requirements nobody
can check: "the feature works correctly", "performance is acceptable". A
requirement with no criterion under it, which is the same thing said more
formally.

### Step 7: Lint the Spec

**What to do:** Run the linter. Fix the errors.

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/lint-spec.sh" docs/exloom/specs/F-012-slug.md
```

Errors are things a machine can be certain about — gapless refs, a criterion under
every requirement, a body under every criterion, no placeholders, no missing
sections. Warnings are two it can only guess at: an implementation named inside a
requirement, and money, permissions or deletion with no `unwanted` requirement
anywhere. **Fix the errors. Judge the warnings** — one you disagree with is a
warning to ignore, not a document to contort.

**This step used to be five prose checks and a linter.** The prose checks were
"scan for placeholders", "check internal consistency", "check for ambiguity" —
things a model does unprompted, so instructing them again spends tokens without
changing the spec. What was left is the part that is not self-review: a script
that either exits 0 or does not.

### Step 8: User Reviews, Then Transition

**What to do:** Ask the user to review the written spec. Once they explicitly
approve, transition to `exloom:planning-for-handoff`.

**How to do it well:** Ask for a full read, not a skim. Prompt: "Does the problem
statement match? Are non-goals acceptable? Edge cases missing?" Changes here
cost minutes; during implementation, hours. Once approved, invoke
`exloom:planning-for-handoff`. Never transition without explicit approval. "Looks
good" after thirty seconds is not approval.

**What bad looks like:** Accepting "yeah" without engagement. Skipping
`exloom:planning-for-handoff` and going straight to implementation.

## Brownfield Discipline

This is what makes exloom brainstorming different from generic brainstorming.
Before proposing any new code, pattern, or component, you must first understand
what already exists. The default assumption is that the codebase already has an
opinion about how to solve your problem. You are looking for that opinion before
forming your own.

1. **Search for existing implementations.** Before designing a notification
   system, search for "notification", "alert", "event", "message", "publish",
   "subscribe." Search by concept, not just name — `AlertDispatcher` is a
   notification system even if nobody called it that. Something probably exists.
   Prove that it doesn't before proposing something new. This is not optional
   due diligence — it is the first step of every design.

2. **Read the surrounding code.** Before adding a new service, read existing
   services in the same layer. How are they structured? What base classes, error
   handling patterns, logging conventions, and DI approaches do they use? Your
   new code should look like it belongs. Code that "looks different" creates
   cognitive overhead for every developer who touches it afterward.

3. **Check for shared libraries.** Check the codebase and the repo's CLAUDE.md
   — is there an existing internal library or approved third-party dependency that covers
   this use case? Adding a new dependency when an existing one suffices is a
   maintenance cost the whole team pays in version conflicts, security audits,
   and learning curves.

4. **Match existing patterns, then justify deviation.** If existing code uses
   Repository pattern and you want Active Record, justify it in the spec.
   "Active Record is simpler" is not a justification — it ignores the cost of
   two patterns in one codebase. "The ORM we're integrating only supports Active
   Record" is a justification. The bar: the existing pattern cannot solve the
   problem, and the new pattern's total cost (learning, maintenance, cognitive
   overhead) is lower than working within the existing one.

5. **Propose extending before building new.** If an existing feature does 60%+
   of what's needed, the default is to extend it. Only propose building new when
   extending would produce a worse long-term outcome — and "worse" means worse
   for team maintenance and clarity, not worse for your creative freedom.
   Extension preserves existing tests, documentation, and team knowledge.

**Red flags that brownfield discipline was skipped:**

- "I didn't look at existing code because I already know the best approach" —
  general knowledge and codebase-specific knowledge are different things. You
  don't know the best approach for this codebase until you've read it.
- "This is a greenfield module" — inside a brownfield codebase, nothing is truly
  greenfield. Even a new module inherits conventions, shared libraries,
  deployment patterns, and team norms from the rest of the system.
- "The existing implementation is bad, let's start fresh" — without a specific,
  documented technical justification. "Bad" is an opinion. "Uses synchronous I/O
  causing thread starvation under 200 concurrent requests" is an engineering
  assessment that can be evaluated and debated.

## Decision Points

| Situation | Decision |
|---|---|
| User arrives with a solution, not a problem | Ask "what problem does this solve?" Explore the problem space first. The solution may be right, but verify it addresses the root cause. |
| Scope too large for one spec | Decompose into sub-projects. Brainstorm the first one fully. Reference others as future work in non-goals. |
| User wants to skip brainstorming | "If you already know, a quick pass just confirms it. If assumptions are wrong, this catches it before code. Minutes here versus days in code." |
| Existing feature does 80% of what's needed | Propose extending. Document the gap and the extension approach. Brownfield wins unless extension compromises the existing feature. |
| User disagrees with your recommendation | Present reasoning, accept their choice, note both perspectives in the spec. You advise; they decide. |
| Multiple valid approaches, no clear winner | Recommend the simplest. YAGNI. Less complexity wins because complexity compounds over time and across team members. |
| Problem unclear even after questions | That ambiguity is valuable information. Document what's known, unknown, and assumed. Don't paper over uncertainty with false precision. |

## Failure Modes

See [failure-modes.md](failure-modes.md).
## Worked Example

See [worked-example.md](worked-example.md).
## Integration

- **You arrive here from:** a user request, a ticket, an idea, a product
  requirement, or mid-execution when a task turns out to need design
  work not anticipated in the original plan.
- **You leave here toward:** `exloom:planning-for-handoff` — always. Never directly
  to implementation. The spec is an input to a plan, not an execution artifact.
  Skipping plans breaks the handoff chain and makes execution unauditable.
- **During Step 1:** If the project is unfamiliar, invoke
  read the surrounding code to build a mental model before brainstorming.
- **During any step:** If brainstorming reveals a learning about the codebase or
  team conventions, route through `exloom:capturing-learnings` so knowledge
  persists beyond this session.
