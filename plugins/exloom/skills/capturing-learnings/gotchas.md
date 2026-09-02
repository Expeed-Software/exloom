# Gotchas — capturing-learnings

The shape of a gotcha entry in a repo's CLAUDE.md.

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
