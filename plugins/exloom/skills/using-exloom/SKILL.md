---
name: using-exloom
description: Use when starting work that will produce a commit — names the exloom skills and review commands and when each applies.
---

# Using exloom

exloom produces **evidence**, not discipline.

The model already plans, tests, and self-reviews without being told. What a team of many developers lacks is evidence that transfers between people: something the next person can read to know what was intended, whether the tests actually exercise the change, and who reviewed it at which commit. exloom produces four artifacts and gates them once, at push.

| Artifact | Produced by | Answers |
|---|---|---|
| Spec | `brainstorming` | what we decided to build, and what we rejected |
| Plan | `planning-for-handoff` | what to do, in what order, verifiable by someone else |
| Proof receipt | `scripts/prove-change-is-tested.sh` | do the tests actually fail without this change |
| Review checklist + receipts | `/review-init` → `/review-complete` | who reviewed, at which commit, with what verdict |

Nothing here instructs you how to think about code. If a skill would only tell you to be careful, it was removed.

## Skills

| Situation | Skill |
|---|---|
| New feature or behaviour change, no spec yet | `exloom:brainstorming` |
| Have a spec, need a plan someone else could execute | `exloom:planning-for-handoff` |
| Closing work — done, shipping, opening a PR | `exloom:review-gate` |
| Learned something worth keeping | `exloom:capturing-learnings` |
| Writing or updating a repo's CLAUDE.md | `exloom:authoring-claude-md` |

Invoke one when it applies. Do not invoke one for a conversational reply, a factual answer, or a trivial mechanical edit.

## Commands — invoke them, don't reproduce them

```
/review-init      when work starts on the branch
/smoke-test       before claiming done
/review-complete  before push / PR
```

`/review-complete` dispatches the reviewer subagents the tier requires. Each real dispatch writes a receipt that the gate demands and that nobody can write by hand. Reading the command and performing the steps yourself produces the checklist and none of the receipts, so the push stays blocked. Having the text in context is not running it.

## Cost shape

Three reviewers remain, and the effort levels are deliberate:

- `l1-reviewer` — **low** effort, cheap enough to run per commit.
- `adversarial-reviewer` — **medium**, once, before push. Carries the cross-layer contract check.
- `security-auditor` — **medium**, at Tier 3 or when the diff touches a security surface.

Run the cheap pass often and the expensive pass once. An earlier version ran the whole panel at full effort and re-ran all of it on every fix commit, because receipts bind to the tip — which turned one fix into three more reviews, and each extra round surfaced thinner findings that were then treated as work. If a reviewer's receipt says `"verdict":"APPROVED"` and `"round_needed":"NO"`, stop. Another round to be thorough is the specific way a two-round change becomes a nine-round one.

## Is the gate on in this repo?

Opt-in per repo, off by default. On only when this file exists:

```
.claude/exloom-gate.enabled
```

Without it the skills are recommendations and nothing blocks. With it, `git push` on a feature branch is blocked until `.claude/reviews/<branch>.md` is complete and bound to the reviewed commit.

Turn it on with:

```bash
mkdir -p .claude && touch .claude/exloom-gate.enabled
```

**Do not create that marker on your own initiative.** It is committed and changes the gate for everyone on the repo — the user's decision, not a side effect of reading this skill. Offer it; let them choose.
