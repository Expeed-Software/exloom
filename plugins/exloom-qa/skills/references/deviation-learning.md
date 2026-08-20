# Deviation Learning

QA's corrections to generated cases are information about an application the model cannot see. Capture them, or every story restarts from the same ignorance.

Capture runs at approval, inside `reviewing-test-coverage`. Knowledge lives in `.claude/qa/app-knowledge.md`.

## Classify before capturing

| Kind | Example | Durable? |
|---|---|---|
| **App knowledge** | `Customers > Opportunities` is actually `Sales > Opportunities > New Opportunity` | Yes — true for every future story in this app |
| **Convention** | This team writes preconditions as a single sentence; steps are split more finely | Yes — per team |
| **Coverage judgment** | "Tenant isolation is always P0 here"; "we never test export in this product" | Yes — per product |
| **Story-specific** | A correction true only for this story's data or rule | **No — discard** |

Misclassifying a story-specific edit as durable poisons every later generation. When unsure, classify as story-specific and discard — a missed lesson costs one correction later; a wrong lesson costs many.

## Confirmation is mandatory

Propose each candidate entry to QA, one at a time, with its classification. Only confirmed entries are written. Never capture silently.

## Confidence

| Marker | Meaning | Use |
|---|---|---|
| `seen once` | Observed in one story | Treat as a suggestion; propose it, flag it as unconfirmed |
| `confirmed` | Corroborated by a later story, or explicitly confirmed by QA | Treat as fact |

Promote `seen once` → `confirmed` when a second story corroborates it.

## File structure

Six sections. Every entry carries a date and a confidence marker.

```markdown
## Navigation
- Create Opportunity: Sales > Opportunities > New Opportunity — confirmed, 2026-08-14

## Vocabulary
- The list screen is titled "Opportunity Pipeline", not "Opportunities" — confirmed, 2026-08-14
- The save control reads "Save & Close" — seen once, 2026-08-20

## Error messages
- Close date validation: "Close date must be on or after the created date" — confirmed, 2026-08-14
- Expired subscription: "Your subscription has expired. Contact your administrator." — seen once, 2026-08-20

## Roles
- "Manager" can approve discounts; "Sales" cannot — confirmed, 2026-08-14

## Conventions
- Tenant isolation cases are always P0 in this product — confirmed, 2026-08-14

## Dependencies
- Opportunity creation always requires an active subscription — confirmed, 2026-08-14
```

## Staleness

Applications change and learned facts go wrong.

- Correcting an existing entry **updates it in place** with a new date. Never append a contradicting entry.
- An entry corrected more than twice is marked `volatile` and treated as a suggestion regardless of confidence.
- Entries not confirmed in a long while are still usable, but a correction to one is expected rather than surprising.

## Never record

- Passwords, tokens, API keys, connection strings
- Real customer names, emails, account numbers, or any personal data
- Anything specific to one test account that will not generalize

The file may be shared or committed. Treat it as readable by the whole team.

## Consumers

| Skill | Uses it for |
|---|---|
| `capturing-story-context` | Proposing navigation and dependencies that are usually right, so QA confirms instead of correcting |
| `generating-test-cases` | Real UI vocabulary, and real error strings for negative-case expected results |

An absent file is a normal first run, not an error.
