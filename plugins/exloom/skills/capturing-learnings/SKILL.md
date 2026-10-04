---
name: capturing-learnings
description: Use whenever a team learns something new — a gotcha, a convention, an incident, a pattern — and route it to the right durable location automatically.
---

# Capturing Learnings

## Overview

Route each learning to the durable location where it helps the right people at the right time. The job is routing, not writing documentation.

## When to Use

- **A gotcha:** "I wasted 3 hours because I didn't know X."
- **A new convention** the team agreed on that is not written down.
- **An incident post-mortem:** the fix is code, the learning is knowledge.
- **A retro output:** "always do X" or "never do Y".
- **A workflow improvement:** a step missing from a skill or reference.
- **A false positive in a shared doc:** a team or shared reference turned out wrong for this project.

The trigger phrase: "I wish someone had told me that."

## Decision Tree

Route to one of four destinations. Work through the questions in order.

### Question 1: Is this specific to one repo?

If it applies to a single codebase and would mislead developers on other projects:

**Route to: Repo's CLAUDE.md**

Edit the repo's `CLAUDE.md` directly, in the most specific applicable section. If none fits, add a "Gotchas" section at the bottom.

See [gotchas.md](gotchas.md) for the entry shape, and for Questions 2 through 4 —
the org-wide, new-skill and personal-memory destinations.

## When a Learning Contradicts Existing Content

If the learning corrects something a shared doc, CLAUDE.md, or skill already says, update it; do not add a second entry.

**Step 1: Find the contradicting content.** Search the target file for the topic before adding anything.

**Step 2: Determine the nature of the conflict.**
- **Old content is wrong** → Replace it. In the PR, quote the old text and say why it was wrong.
- **Old content is outdated** → Replace it and note when and why it changed.
- **Old content is right in some cases, yours in others** → Do not replace. Add a condition that distinguishes the cases, e.g. "Use Redis when state must be shared across instances; use Caffeine for single-instance local caches."

**Step 3: Make the conflict explicit in the PR.** A PR that changes existing content quotes the before and after.

**Step 4: Never leave both versions.** If the two cannot be reconciled into one instruction, the convention is contested — take it to a team discussion before capturing either.

## PR Generation

When routing to a PR — Question 2 (shared conventions) or Question 3 (a new skill), both in [gotchas.md](gotchas.md) — follow the proposal shape given there.

- **Title format:** `learning: [topic]` for reference updates, `feat: new skill [skill-name]` for new skills
- **Body must include:** what was learned, where it was discovered, what the proposed change is, who it helps
- **Single learning per PR**

Create the PR from the command line with your platform's tool: `gh pr create` (GitHub), `az repos pr create` (Azure DevOps), or the Bitbucket CLI/API.

## Review Expectations

PRs to the exloom plugin:

- At least one other developer reviews and approves; no auto-merge.
- The plugin maintainer (or delegate) has final say on new skills.
- Reference file updates need one approval from any team member.

Suggested turnaround: 1-2 business days for reference updates, 3-5 for new skills. Defaults, not an SLA.

## Anti-Patterns

Do not capture:

- **Generic best practices** covered by well-known resources ("Don't commit secrets").
- **Ephemeral state** ("staging was down on March 3rd"), unless the root cause reveals a missing convention.
- **Things already in CLAUDE.md** for the current repo. Check before adding.
- **Speculation** ("maybe we should use X"). Take it to a team discussion first.
- **Too-specific procedure** ("how to reset my laptop"). That belongs in an IT knowledge base.

## Failure Modes

See [failure-modes.md](failure-modes.md).

## Worked Example

Integration tests hang in CI but pass locally: the rate limiter uses a real Redis connection in tests and CI has no Redis.

**Question 1:** Yes, repo-specific to `payments-service`. **Route: Repo's CLAUDE.md.**

Search `CLAUDE.md` for "Redis", "rate limit", "test". An existing testing section mentions Testcontainers but not the rate limiter — an addition, not a contradiction. Add to that section rather than creating Gotchas:

```markdown
## Testing

Integration tests use Testcontainers for Postgres. The rate limiter must
use the in-memory backend in tests — set `RATE_LIMIT_BACKEND=memory`.
Without it, tests attempt a real Redis connection and hang until timeout
(CI has no Redis). This is set in `src/test/resources/application-test.yml`.
```

```bash
git commit -m "docs: note rate limiter test config gotcha in CLAUDE.md"
```

The team owns the repo, so no PR is needed for the CLAUDE.md update.

## Related Skills

- `exloom:authoring-claude-md` — the primary destination for repo-specific learnings.
- When a debugging session resolves, check whether it produced a learning worth capturing.
