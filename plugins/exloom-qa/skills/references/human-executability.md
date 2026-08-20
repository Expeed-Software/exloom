# Human Executability

The reader is a QA engineer with the application open and normal test-environment access. Not an agent. Not an engineer with a terminal.

## Rules

1. Steps reference only the application UI and access QA already has.
2. **No** API calls, database queries, log inspection, browser devtools, or scripts.
3. One action per step, phrased so a person follows it without interpreting.
4. Expected results are observable on screen, in a document, in an email, or in another surface QA can reach.
5. Preconditions must be things QA can arrange — or are flagged as needing dev/data support.
6. Anything verifiable only with engineering tooling becomes a **note to development**, never a test case.

## Rewrites

| Agent-shaped | Human-shaped |
|---|---|
| `Send a POST to /api/opportunities with an invalid closeDate` | `In the Close Date field enter a date before the created date, then click Save` |
| `Verify the opportunities table contains one row` | `Reopen the opportunity from the list and confirm the discount shows 25%` |
| `Check the application logs for a validation error` | `Confirm the inline message under Close Date reads "Close date must be on or after the created date"` |
| `Assert the response status is 403` | `Confirm the page shows "You do not have permission to view this record" and no opportunity data is visible` |
| `Inspect localStorage for the auth token` | `Close the tab, reopen the application, and confirm you are returned to the login screen` |
| `Simulate a network failure during submit` | *(not manually stageable — becomes a note to development)* |

## What a lone tester can actually stage

Feasible, so generate freely:

- Two roles at once — a second browser profile or an incognito window
- Double-click and repeated submission
- Refresh, browser Back, multiple tabs
- Session expiry — wait it out, or use an idle window
- Direct URL and ID manipulation in the address bar
- Leaving a form idle, then submitting

Usually **not** feasible alone — write as notes to development, not as cases:

- Precise race conditions between two simultaneous saves
- Network interruption at an exact moment mid-processing
- Forcing an integration timeout or a partial upstream response
- Database-level or storage-level corruption
- Load and concurrency beyond two sessions

## Notes to development

A scenario that matters but cannot be verified by hand is recorded in the artifact's **Notes to Development** section with the risk it represents.

This exists so real risks stay visible instead of sitting in the suite forever as cases marked *blocked*. A permanently blocked case is worse than no case — it looks like coverage and delivers none.

## Check before publishing

Read each case and ask: *could a QA engineer who has never seen this story execute this with only the application in front of them?*

If the answer needs a terminal, the case is wrong.
