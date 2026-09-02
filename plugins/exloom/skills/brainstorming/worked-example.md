# Worked Example — brainstorming

One request taken through every step.

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
