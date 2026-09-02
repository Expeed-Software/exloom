---
name: capturing-learnings
description: Use whenever a team learns something new — a gotcha, a convention, an incident, a pattern — and route it to the right durable location automatically.
---

# Capturing Learnings

## Overview

Every real-world learning — a gotcha in a specific framework, an incident that revealed a missing convention, a pattern that turned out to work well — gets routed to the right durable location.

The skill's job is not to write documentation. It is to ask: "Where does this belong so that it helps the right people at the right time?"

## When to Use

Run this skill when you encounter:

- **A gotcha:** "I wasted 3 hours because I didn't know X" — this should never happen to the next developer.
- **A new convention:** The team agreed on a pattern that isn't written down anywhere yet.
- **An incident post-mortem:** Root cause identified — the fix is code, but the learning is knowledge.
- **A retro output:** "We should always do X" or "never do Y" emerged from a retrospective.
- **A workflow improvement:** A step was missing from a skill or reference that would have saved time.
- **A false positive in a shared doc:** Something in a team or shared reference doc turned out to be wrong for this project.

The trigger phrase: "I wish someone had told me that."

## Decision Tree

Given a learning, route it to one of four destinations. Work through the questions in order.

### Question 1: Is this specific to one repo?

If the learning only applies to a single codebase and would confuse or mislead developers on other projects:

**Route to: Repo's CLAUDE.md**

Edit the repo's `CLAUDE.md` directly. Add it to the most specific applicable section. If no section fits, add a "Gotchas" section at the bottom.

See [gotchas.md](gotchas.md) for the entry shape.

## When a Learning Contradicts Existing Content

Sometimes the learning is not new information — it is a correction. A shared doc, CLAUDE.md, or skill already says something, and your learning shows it is wrong, outdated, or incomplete. Handle this as an update, not an addition. Adding a contradicting entry alongside the old one creates two conflicting instructions, and the reader cannot tell which is current.

**Step 1: Find the contradicting content.** Before adding anything, search the target file for the topic. If your conventions doc already has a section on error handling and your learning is about error handling, you are updating that section, not appending a new one.

**Step 2: Determine the nature of the conflict.**
- **The old content is simply wrong** → Replace it. In the PR, quote the old text and explain why it was wrong. "The convention said use HTTP 503 for rate limiting, but 429 is the RFC-correct code and what our gateway expects. Updating."
- **The old content was right but is now outdated** → Replace it and note when/why it changed. "We moved from Redis to Caffeine for caching in Q2; the convention referencing Redis is stale."
- **The old content is right in some cases, yours in others** → Do not replace. Add a condition that distinguishes the cases. "Use Redis when state must be shared across instances; use Caffeine for single-instance local caches."

**Step 3: Make the conflict explicit in the PR.** A PR that changes existing content must quote the before and after. Reviewers need to see what is being overturned to evaluate whether the change is correct. A silent overwrite of an established convention will (and should) get pushback.

**Step 4: Never leave both versions.** The failure mode is a reference file that says "do X" in one section and "do Y" in another because someone added a learning without removing the contradicted content. If you cannot reconcile the two into a single coherent instruction, that is a signal the convention is genuinely contested — take it to a team discussion before capturing either version.

## PR Generation

When routing to a PR (destination 2 or 3 above), use the template provided in the decision tree. Key principles:

- **Title format:** `learning: [topic]` for reference updates, `feat: new skill [skill-name]` for new skills
- **Body must include:** what was learned, where it was discovered, what the proposed change is, who it helps
- **Single learning per PR** — don't batch multiple unrelated learnings into one PR

Use your org's PR mechanism from the command line where possible — `gh pr create` for GitHub, `az repos pr create` for Azure DevOps, the Bitbucket CLI/API for Bitbucket. The `gh` examples here assume GitHub; substitute your platform's equivalent. The point is a reviewable, command-line-generated PR, not the specific tool.

## Review Expectations

PRs to the exloom plugin follow normal code review:

- At least one other developer must review and approve
- No auto-merge
- The plugin maintainer (or their delegate) has final say on new skills
- Reference file updates are lighter-weight; one approval from any team member is sufficient

Suggested turnaround (adjust to your team's actual cadence): roughly 1-2 business days for reference updates, 3-5 for new skills. These are defaults to set expectations, not a guaranteed SLA.

## Anti-Patterns

Do not capture these as learnings — they create noise:

- **Generic best practices** already covered by well-known resources: "Use meaningful variable names", "Don't commit secrets". These belong in external references, not org-specific files.
- **Ephemeral state:** "The staging environment was down on March 3rd." This is an incident, not a learning, unless the root cause reveals a missing convention.
- **Things already in CLAUDE.md** for the current repo. Duplicate captures create drift. Check before adding.
- **Speculation:** "I think maybe we should use X instead of Y." This is a proposal, not a learning. Take it to a team discussion first.
- **Too-specific procedure:** "How to reset my laptop." This belongs in an IT knowledge base, not a developer workflow skill.

## Failure Modes

See [failure-modes.md](failure-modes.md).

## Worked Example

**Scenario:** A developer spends an afternoon debugging why integration tests hang in CI but pass locally. Root cause: the rate limiter uses a real Redis connection in tests, and CI has no Redis, so the connection attempt blocks until timeout. The fix is a test config flag. Now they capture the learning.

### Trigger

"I wish someone had told me that integration tests need `RATE_LIMIT_BACKEND=memory` in CI." The trigger phrase applies — capture it.

### Decision Tree

**Question 1: Is this specific to one repo?** Yes — this is about the `payments-service` test configuration. It would mean nothing to a developer on a different project with a different rate limiter.

**Route: Repo's CLAUDE.md.**

### Check for contradicting content

Before adding, search `CLAUDE.md` for "Redis", "rate limit", and "test". There's an existing testing section that says "Integration tests use Testcontainers for Postgres." It doesn't mention the rate limiter at all — so this is an addition, not a contradiction. Add to the existing testing section rather than creating a new Gotchas section, since a testing section already exists.

### The edit

```markdown
## Testing

Integration tests use Testcontainers for Postgres. The rate limiter must
use the in-memory backend in tests — set `RATE_LIMIT_BACKEND=memory`.
Without it, tests attempt a real Redis connection and hang until timeout
(CI has no Redis). This is set in `src/test/resources/application-test.yml`.
```

### Commit

```bash
git commit -m "docs: note rate limiter test config gotcha in CLAUDE.md"
```

Since `payments-service` is a repo the team owns, no PR is needed for the CLAUDE.md update.

**The payoff:** The next developer who runs integration tests reads this in CLAUDE.md (surfaced automatically by Claude Code) before they hit the hang. The afternoon of debugging happens exactly once, to exactly one person, instead of recurring across the team.

## Related Skills

- `exloom:authoring-claude-md` — the primary destination for repo-specific learnings
- Debugging sessions often produce learnings worth capturing — reach for this skill when one resolves
