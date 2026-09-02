---
name: using-exloom-qa
description: Use when starting any QA test-case work — establishes which exloom-qa skill to use when, and the rules that hold across all of them.
---

# Using exloom-qa

Find the skill for your situation and invoke it. It pulls in the others in order.

| Situation | Skill |
|---|---|
| Starting from a user story | `capturing-story-context` |
| Context captured, need cases | `generating-test-cases` |
| Reviewing, changing, or approving cases | `reviewing-test-coverage` |
| Approved and ready for the board | `publishing-test-cases` |

Invoke them with the Skill tool, in that order. There are no slash commands for this workflow — the skills are the interface.

## Rules that hold everywhere

**Nothing is published without an approval record.** Before approval, the only permitted tracker call is reading the work item. A `PreToolUse` hook enforces this and fails closed.

**Every case must be runnable by a human** with the application open — no API calls, database queries, logs, devtools, or scripts. See `../references/human-executability.md`.

**Volume matches story complexity.** Assess first, then generate within the band. See `../references/complexity-and-volume.md`.

**The story is a delta, not a spec.** It will not describe navigation, prerequisites, or downstream effects. Capturing those from QA is mandatory, not optional.

**Evidence over speculation.** Every case names its source. Never generate cases for capabilities with no evidence they exist — SSO, LDAP, biometrics, social login, IP restrictions and similar are not tested unless the story or context shows they apply.

**Ask one question at a time.** Use `AskUserQuestion` with options and a recommendation. Never present a wall of questions, and never present a blank field where a proposal would do.

**Never invent expected behavior.** If it is unknown and material, raise a QA Question. Maximum five per story.

## Where things live

| Path | Contents |
|---|---|
| `.claude/qa/<story-id>.md` | Per-story artifact: context, cases, matrices, approval record, TC → work-item map |
| `.claude/qa/app-knowledge.md` | What QA's corrections taught about this application |

No git dependency. The working folder may be an ordinary directory; artifacts are keyed by story ID, never by branch.

## Setup

`az login --tenant <org-tenant>` and `az extension add --name azure-devops`. No MCP server, no personal access token.

If board calls behave strangely, check `az account show` first — a session on the wrong tenant returns a 302 sign-in redirect rather than a clear error.
