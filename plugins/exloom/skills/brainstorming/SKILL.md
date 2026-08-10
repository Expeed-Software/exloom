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
and problem. If the codebase is unfamiliar, invoke `exloom:exploring-codebase`.
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

**What to do:** Save the agreed design where this repo keeps specs — if the repo's CLAUDE.md (or the user) specifies a docs location, use it; otherwise default to `docs/exloom/specs/YYYY-MM-DD-<topic>.md`. Commit if user permits.

**How to do it well:** The spec must be readable by someone not in the session.
Canonical format: problem statement, constraints, chosen approach with rationale,
rejected approaches with rationale, components, data flow, error handling, edge
cases, non-goals, open questions. Filename: date + topic in kebab-case.
Reference code by file path. Record contentious decisions with both perspectives.
Mark ambiguity as open questions — don't paper over it.

**What bad looks like:** Spec only makes sense to someone in the conversation.
No rejected alternatives — three months later, someone proposes the same
rejected idea because the reasoning was never recorded.

### Step 7: Self-Review the Spec

**What to do:** Before handing the spec to the user, review it against five
systematic checks. Fix problems inline without announcing them.

**How to do it well:** Five checks. **Placeholder scan:** resolve TODO/TBD or
mark as open questions with owners. **Internal consistency:** components match
data flow? Error handling covers edge cases? Non-goals contradict goals?
**Scope check:** more than one feature? Split it. **Ambiguity check:** could
two developers build different things? Tighten until they couldn't. **Brownfield
check:** existing patterns referenced, deviations justified? Fix issues directly
— don't send a message cataloging problems, just fix them.

**What bad looks like:** TODO placeholders in the final spec. "Handles
validation" without specifying rules. Overview contradicts detail sections.

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

### 1. "This is too simple for brainstorming"

**Thought pattern:** "It's just a CRUD endpoint. I've built hundreds of these."

**Why it feels right:** Simple tasks have obvious solutions. The gap between
understanding and implementation seems nonexistent.

**What actually happens:** The "simple" endpoint needs an authorization model you
didn't check. Or an existing endpoint does something similar, and now the API
has two inconsistent paths. Simple projects are where unexamined assumptions
cause the most damage — nobody builds in checkpoints for "trivial" work.

**The correction:** If it's truly simple, brainstorming takes five minutes. Run
the process — it finishes fast or reveals something you didn't know.

### 2. "I already know the best approach"

**Thought pattern:** "I solved this exact problem at my last company. I know
the architecture."

**Why it feels right:** Experience is valuable. Pattern recognition makes senior
engineers effective. Ignoring experience feels wasteful.

**What actually happens:** That approach was shaped by a different codebase, team,
and constraints. Transplanting it without adaptation creates a foreign body the
team works around for years.

**The correction:** Experience informs brainstorming — it doesn't replace it.
Let the codebase have a vote. Fast when you're right, catches mistakes when
you're wrong.

### 3. "Let me just explore the code first"

**Thought pattern:** "I'll read the codebase thoroughly, understand everything,
then I'll know what to build."

**Why it feels right:** Understanding code seems like a prerequisite to good
design. More information leads to better decisions.

**What actually happens:** You read fifty files, trace middleware, and three hours
later you know a lot but haven't made a single decision. Exploration without
guiding questions is tourism, not engineering.

**The correction:** Structure exploration around questions: What similar features
exist? What patterns apply? What libraries are available? Exploration is a step
within brainstorming, not a substitute for it.

### 4. "The user seems impatient, I'll skip questions"

**Thought pattern:** "They want me to start building. Asking questions will
frustrate them."

**Why it feels right:** Responsiveness feels like good service. Starting work
immediately shows initiative and competence.

**What actually happens:** You infer wrong. Build, discover mismatch, rebuild —
3-5x longer than questions would have taken. Five minutes of questions saves
five hours of rework.

**The correction:** Frame questions as acceleration: "I want to get this right
the first time. One quick question..." Users respond well when questions serve
speed, not ceremony.

### 5. "I'll design as I code"

**Thought pattern:** "Design docs get stale. Real design happens in code. I'll
figure out the architecture as I implement."

**Why it feels right:** Agile culture valorizes working software over
documentation. Iterating in code feels more productive than iterating in prose.

**What actually happens:** At every architectural fork mid-implementation, you
take the path requiring the least rework — not the best path. Sunk cost warps
every decision. Architecture ends up shaped by build order, not by the problem.

**The correction:** Fifteen minutes of design in prose is worth two hours of
design-by-implementation. The spec forces decisions into the open before they're
embedded in expensive-to-change code.

## Worked Example

**Scenario:** Developer says "I need to add real-time notifications to our
dashboard."

### Step 1: Explore Project Context

Read the codebase. Angular 16 dashboard, Node.js/Express REST API, PostgreSQL.
Monorepo: `packages/frontend` and `packages/api`. Recent git activity in the
orders module. Search for notification-related code — find
`EmailNotificationService` in `packages/api/src/services/email-notification.service.ts`
with event detection logic, subscriber management, and template rendering. Also
find `SystemAlertService` that logs errors to an admin table (no push mechanism).

### Step 2: Understand the Problem

"Real-time notifications" is a solution, not a problem. The actual problem:
"Users miss events because they must manually refresh. Payments arrive, orders
change status, alerts fire — nobody knows until reload." This is a visibility
problem. The solution space is wider than "notifications."

### Step 3: Clarifying Questions

**Q1:** "What event types need notifications? (a) Order status changes,
(b) Payments, (c) System alerts, (d) All three?" **A:** "All three."

**Q2:** "How time-sensitive? (a) Within 1-2 seconds, (b) 30 seconds OK,
(c) Next refresh OK?" **A:** "30 seconds is fine."

**Q3:** "Concurrent dashboard users? (a) Under 20, (b) 20-100, (c) 100+?"
**A:** "Around 50."

**Q4:** "Per-user notification preferences, or everyone gets everything?"
**A:** "Everyone gets everything for now."

At this point, I can predict the answers to further questions — the scope is
contained. Stop asking and proceed.

### Step 4: Solution Space

**Recommended: SSE (Server-Sent Events).** One-directional server-to-client
push, matching the use case exactly. Standard HTTP, no new infrastructure,
Angular supports `EventSource` natively. Right-sized for ~50 users with
30-second latency tolerance. Pros: simple, proven, no bidirectional complexity.
Cons: one-directional only. Recommended when: server pushes events, client
displays them.

**Alternative A — WebSocket.** Bi-directional. More powerful than needed since
the client never sends events back. Requires connection lifecycle management.
Recommended when: client also needs to push real-time data to the server.

**Alternative B — Polling.** Simplest implementation. Client calls
`GET /api/notifications/recent` every 30 seconds. But 50 users polling = 100
requests/minute, mostly returning empty results. Recommended when: infrastructure
constraints prevent long-lived connections.

### Step 5: Design

**Overview:** Extend the existing `EmailNotificationService` to emit SSE events
alongside emails. Add an Angular service that subscribes to the SSE stream and
a notification badge component that displays unread counts with a dropdown.

**Components:** Modify `email-notification.service.ts` to publish events to a
new `NotificationEventEmitter`. New `packages/api/src/routes/sse.route.ts` for
the SSE endpoint. New `notification-stream.service.ts` in Angular wrapping
`EventSource`. New `notification-badge` component. Three event type handlers
(order status, payment, system alert).

**Data flow:** Event occurs -> `EmailNotificationService` detects it (existing
logic, no changes) -> emits to `NotificationEventEmitter` (new) -> SSE endpoint
pushes to all connected clients -> Angular `notification-stream.service`
receives the event -> `notification-badge` component updates count -> user
clicks badge -> dropdown renders event details.

**Error handling:** SSE disconnection — `EventSource` auto-reconnects (built-in).
Backend crash — clients reconnect when server returns. Slow client — events
dropped (acceptable given 30-second tolerance).

**Non-goals:** Notification preferences, persistent history, mobile push,
read/unread tracking beyond the current browser session.

### Steps 6-8: Write, Review, Transition

Write spec to `docs/exloom/specs/2026-04-12-dashboard-notifications.md`.
Self-review: placeholder scan finds none. Consistency check confirms component
list matches data flow. Brownfield check confirms the spec references existing
`EmailNotificationService` and justifies the only new pattern (SSE) as the
minimal addition to the existing event detection infrastructure. User reviews
spec, confirms non-goals are acceptable, approves. Transition to
`exloom:planning-for-handoff`.

**The brownfield payoff:** The existing `EmailNotificationService` already has
all event detection logic — it knows when orders change status, when payments
arrive, when system alerts fire. The new work is only the delivery mechanism
(SSE endpoint + Angular subscription) and the UI (badge + dropdown). Reuse saves
roughly 60% of the estimated effort. Without brownfield discipline, a developer
would likely have built parallel event detection from scratch — duplicating
tested, working logic that already exists.

## Integration

- **You arrive here from:** a user request, a ticket, an idea, a product
  requirement, or during `exloom:executing-handoff-plans` when a task needs design
  work not anticipated in the original plan.
- **You leave here toward:** `exloom:planning-for-handoff` — always. Never directly
  to implementation. The spec is an input to a plan, not an execution artifact.
  Skipping plans breaks the handoff chain and makes execution unauditable.
- **During Step 1:** If the project is unfamiliar, invoke
  `exloom:exploring-codebase` to build a mental model before brainstorming.
- **During any step:** If brainstorming reveals a learning about the codebase or
  team conventions, route through `exloom:capturing-learnings` so knowledge
  persists beyond this session.
