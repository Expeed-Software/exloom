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

```markdown
## Gotchas

- **[Topic]:** [Concise description of the gotcha and how to avoid it]
```

Commit the change: `docs: add [topic] gotcha to CLAUDE.md`.

No PR required for CLAUDE.md updates to a repo you own. If it's a shared or client repo, PR it with a one-line description.

---

### Question 2: Would every project benefit from this?

If the learning applies across multiple projects — regardless of stack or client:

**Route to: your team's shared conventions**

The concrete test that separates this from Question 1 (repo-specific): "If I deleted the repo this was discovered in, would the learning still be true and useful?" A gotcha about *this service's* Redis config dies with the repo — that's Question 1, route to the repo's CLAUDE.md. A learning like "our gateway rejects any non-RFC error code, so always return standard HTTP codes" is true for every service regardless of repo — that's Question 2. If you are unsure, ask: "Would a developer on a completely different team, different stack, hit this?" If yes → your team's shared docs. If it only bites people in this one codebase → Question 1. When genuinely on the fence, prefer Question 1 (repo CLAUDE.md) — it is cheaper to promote a repo learning to org-wide later than to pollute shared team docs with something that turned out to be repo-specific.

Add it wherever your org keeps cross-project standards — a shared conventions repo, a root or org-level CLAUDE.md, or a team wiki. Route by topic:

- **Coding pattern or convention** → your shared coding-conventions doc
- **New tool or access process** → your team's onboarding / tooling doc
- **Org-level process change** → your org's process doc
- **Stack-specific default** → your stack's shared config, or a CLAUDE.md template if your team maintains them

Propose the change through your team's normal review process (e.g. a PR to the shared-docs repo) so a second person signs off before it becomes a shared standard. A good proposal states: what was learned (1–2 sentences), where it was discovered (project, date, context), the exact change, and which teams or projects it helps.

---

### Question 3: Is this a recurring workflow that needs its own skill?

If the learning describes a multi-step process that Claude should be able to run on demand — and that process doesn't exist yet:

**Route to: New skill proposal**

A new skill is warranted when all three of these hold (the numbers are rules of thumb to gauge "is this a repeatable process worth encoding," not hard gates — use judgment at the margins):
- The workflow has several distinct steps (roughly 4+) — fewer than that is usually a reference note or a CLAUDE.md entry, not a skill
- It recurs often enough across the team to be worth maintaining (roughly weekly or more) — a once-a-quarter process is better documented than skillified
- It can be described as "Use when [trigger]..." — if you cannot name the trigger, it is not a skill

A learning that fails these is not lost — it routes to one of the other three destinations. The bar is deliberately high because every skill is a maintenance commitment for the whole team.

Propose a PR creating `plugins/exloom/skills/<new-skill-name>/SKILL.md`. The PR body should include:
- The trigger description (what situation invokes this skill)
- A sketch of the steps
- Which existing skill (if any) this extends or replaces

Tag the plugin maintainer for review. New skills require approval before merging.

---

### Question 4: Is this personal only?

If the learning is about your own workflow, preferences, or setup — and would not apply to other developers in your org:

**Route to: personal memory**

Save it to Claude Code's memory. Two ways:
- Start a message with `#` followed by the instruction — Claude Code prompts you to save it as a memory.
- Run `/memory` to open the memory files directly and add the entry yourself.

Phrase it as a concrete instruction, for example:
```
# Always run the full test suite before pushing, even for one-line changes.
```

Personal memory entries affect only your own sessions, not other developers'. (If the instruction would help the whole team, it is not personal — route it to the repo's CLAUDE.md or your team's shared docs instead.)

---

### If none of the above fit:

The learning may not be ready to capture. Ask: "Is this a one-time edge case, or a pattern?" If one-time, note it in a PR description or commit message. Do not capture ephemeral facts as durable knowledge.

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

### 1. "I'll remember this, no need to capture it"

**The thought pattern:** The lesson was painful enough that you'll never forget it. Writing it down feels unnecessary.

**Why it feels right:** The frustration is vivid right now. Of course you'll remember.

**What actually happens:** You remember for two weeks. Then a new project pushes it out. Six months later, a teammate hits the exact same gotcha — or you hit it again yourself — and the three hours are lost a second time. Worse, the knowledge never reaches everyone else on the team who would have benefited.

**The correction:** If the trigger phrase "I wish someone had told me that" applies, capture it now. The capture takes two minutes. The re-learning costs hours, multiplied by everyone who hits it.

### 2. "This is too small to capture"

**The thought pattern:** It's a tiny detail. Not worth a CLAUDE.md edit or a PR.

**Why it feels right:** Small things feel below the threshold of "documentation."

**What actually happens:** Small gotchas are exactly the ones that aren't obvious and aren't discoverable. A one-line note ("the test DB needs `RATE_LIMIT_ENABLED=false` or integration tests hang") saves the next person an afternoon. Big architectural facts are usually discoverable from the code; small operational gotchas are not.

**The correction:** Small and non-obvious is the sweet spot for capture. If it cost you time and wasn't findable, it belongs in CLAUDE.md.

### 3. "I'll batch up my learnings and capture them later"

**The thought pattern:** You'll collect everything you learned this sprint and write it up at the end.

**Why it feels right:** Batching feels efficient. One writing session instead of many interruptions.

**What actually happens:** "Later" arrives with the details fuzzy. You remember there was a gotcha but not the exact env var. You capture a vague, low-value version — or you skip it because reconstructing the detail is too much work. The batch never happens.

**The correction:** Capture at the moment of learning, when the detail is exact. Route it immediately through the decision tree. The whole point of the four destinations is that routing takes seconds.

### 4. "I'll add my learning next to the existing one"

**The thought pattern:** The reference already covers this topic, so you append your note below the existing content.

**Why it feels right:** Adding is safer than changing. You don't want to delete someone else's work.

**What actually happens:** The file now has two instructions on the same topic. A reader follows the first one they find, which may be the outdated one. The contradiction propagates until someone notices the file disagrees with itself.

**The correction:** Follow the "When a Learning Contradicts Existing Content" section above. Update in place, quote the before/after in the PR, never leave both versions.

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
- `exloom:systematic-debugging` — debugging sessions often produce learnings worth capturing
