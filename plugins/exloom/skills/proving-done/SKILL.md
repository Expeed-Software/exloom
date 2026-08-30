---
name: proving-done
description: Use before saying work is done, fixed, passing, or ready to ship (and before committing or opening a PR) — run exloom's eight-item evidence checklist and show real command output instead of asserting success.
---

# Proving Done

## Overview

"Done" is a claim that requires evidence: you ran the commands, read the output, and can show the receipts — not a feeling, not "I think tests pass," not "it worked on my machine."

This skill is an eight-item checklist to run before claiming work is complete, fixed, passing, or ready to ship. Each item specifies what to check, how to check it, and what bad looks like.

## The Checklist

Run all eight items before claiming completion. Each item specifies what to check, how to check it, and what bad looks like. For trivial changes, see the abbreviated process in the Decision Points section.

The examples below use Java/Spring commands (`./gradlew`, `checkstyle`, `application.yml`) because they are concrete, but the checklist is stack-agnostic — substitute your stack's equivalents (`npm test`/`eslint`, `pytest`/`ruff`, `go test`/`go vet`, `cargo test`/`clippy`). The eight items apply to backend, frontend, mobile, and infrastructure work alike.

Some items overlap with upstream skills by design — item 4 (plan deviations) revisits territory from `exloom:executing-handoff-plans`, and item 5 (edge cases) revisits `exloom:planning-for-handoff`. When the deviation log is already complete and the edge cases were already decided, these items are 30-second confirmations, not redo-work. They exist as a final net to catch what slipped through — work done without a plan, a deviation logged hastily, an edge case the plan never considered. If an item is genuinely already covered, confirm it and move on.

### 1. Re-read every modified file

**What to check:** Every file you created or modified in this session, read top to bottom.

**How to check it:** Read with fresh eyes. Pretend you are reviewing someone else's code — you did not write this, you do not know what it is supposed to do. Does it make sense on its own? Read each file sequentially. Look specifically for:

- Leftover debug statements (`console.log`, `System.out.println`, `print()`)
- Commented-out code from earlier experiments you forgot to remove
- Inconsistent naming between new code and existing conventions
- Copy-paste errors where you duplicated a block and forgot to update a variable name or string

**What bad looks like:** "I wrote it, so I know what is in there." That is exactly why you need fresh eyes. The author is the worst reviewer of their own code because they see what they intended to write, not what they actually wrote. A five-minute re-read catches things that would otherwise cost an entire review round-trip.

### 2. Hardcoded values audit

**What to check:** Every literal value in the changed code — numbers, strings, URLs, hostnames, ports, timeouts, sizes, counts, retry limits, file paths, feature flags.

**How to check it:** Scan every changed file for literals. For each one, make an explicit decision and state it:

- If the value is defined by a specification and unlikely to ever change (a protocol-defined buffer size, a mathematical constant, an HTTP status code), it is a genuine constant — give it a name.
- If the value could vary by environment, deployment, or operational tuning (a timeout, a URL, a port, a connection pool size, a retry count), it must be externalized to configuration.
- There is no third option. Every literal gets classified, and the classification is stated in your verification output.

**What bad looks like:** A hardcoded `localhost:5432` that works on your machine and breaks in staging. A timeout of `5000` buried in a service client that nobody can find when the downstream service starts responding slowly. A retry count of `3` that causes cascading failures under production load because retries amplify the problem instead of recovering from it.

### 3. Runtime environment assumptions

**What to check:** Every assumption the code makes about where it runs, what infrastructure is available, and how the deployment behaves.

**How to check it:** List what the code assumes explicitly:

- Single instance or multiple instances?
- Specific operating system or OS-agnostic?
- Local filesystem access or network/ephemeral storage?
- Database always available or potentially unreachable?
- Stable network topology or dynamic service discovery?
- Accurate system clock or potential skew between nodes?

Then ask three questions: Would this work in a container with an ephemeral filesystem? Would this work in CI where no external services are running? Would this work with three replicas behind a load balancer?

**What bad looks like:** Session stored in memory — works locally, breaks the moment a load balancer routes the next request to a different instance. File written to `/tmp` with a predictable name — works with one instance, silently corrupts data with two. A scheduled job that assumes one node — fires three times in production on a three-node cluster.

### 4. Plan deviations

**What to check:** Every difference between what you planned to do and what you actually did.

**How to check it:** Diff your changes against the plan's "files to modify" list:

- Any file you touched that was not in the plan is a deviation.
- Any file in the plan you did not touch is a deviation.
- Any approach that differs from what was specified — different algorithm, data structure, API contract — is a deviation.

List every one, no matter how small, with a one-line justification. Format: "Deviation: changed `UserDTO` to add a validation annotation — needed for the new endpoint but not in the original plan."

If there was no plan (ad-hoc work, a quick fix, an exploratory change), say so explicitly — then do the same accounting against the task itself: list every file you changed and confirm each was necessary for the stated goal. No plan does not mean no accountability for scope; it means you justify scope here, against the task's intent, instead of against a plan document.

**What bad looks like:** "I changed an extra file but it was obvious why." Not to the reviewer. Not to the developer who picks up this code in six months. Every undocumented deviation is a mystery that someone will have to solve later without the context you have right now.

### 5. Unhandled edge cases

**What to check:** For every function or method you touched — null input, empty collection, single element, maximum size, concurrent access, external service failure, malformed data, timeout, permission denied.

**How to check it:** Walk through each changed function systematically:

- What happens if the input is null? Empty? A single element? Maximum size?
- What if two threads call this simultaneously with conflicting data?
- What if the external API returns a 500? A 429? Times out after 30 seconds?
- What if the database connection drops mid-transaction?

It is acceptable to leave edge cases unhandled if you declare them explicitly: "Concurrent updates to the same entity are not handled — no optimistic locking. Documented as a known gap for V1." It is not acceptable to leave them unhandled silently and hope nobody triggers them.

**What bad looks like:** "That will not happen in production." Famous last words that precede every production incident retrospective. The edge case you dismiss as impossible is the one that fires at 2 AM on a Saturday when the on-call engineer has no context on your code.

### 6. Run lint/build/test

**What to check:** The full project build pipeline — compilation, linting, formatting, and the entire test suite. Not just the tests you wrote or the files you changed.

**How to check it:** Run the full suite from the project root. Your change may have broken something in a completely different module through a shared dependency, a renamed class, or a test fixture that now needs a field you added. Run the canonical build command (`./gradlew build`, `npm test`, `cargo test`, `pytest`, `dotnet test`). Capture the output.

The required evidence format is: **command + exit code + quantitative output.**

- Good: "`./gradlew test` exited 0. 142 passed, 0 failed, 0 skipped."
- Bad: "Tests passed." Which tests? How many? What command produced that conclusion?

If a verification command cannot be run — no test suite exists, the linter is only configured in CI, the build requires credentials you do not have locally — state that explicitly as a gap. Do not pretend the gap does not exist by staying silent.

### 7. Staff engineer test

**What to check:** Whether the most senior engineer on your team would approve this without requesting changes.

**How to check it:** Read the implementation one final time and ask honestly: "Would a staff engineer approve this as-is?" Not "would they understand it" — would they approve it with no comments and no requested changes. If the answer is "probably, but they would leave some comments," then you already know what those comments are. Fix them now. You are not asking for permission. You are calibrating against the highest standard on your team, not the minimum bar for merging.

**Calibration examples — what staff engineers actually flag:**

Staff-level concerns (these block PRs):
- "This stores session state in memory — it works single-instance but breaks behind a load balancer."
- "This catches `Exception` broadly — a `NullPointerException` will return a misleading 404 instead of a 500."
- "This error handler logs and continues — the user gets a partial result with no indication data is missing."
- "This works for 10 users but the N+1 query will be a problem at 1000."
- "These two modules are now coupled through a shared DTO — changing one forces a change in the other."

Not staff-level concerns (these are style preferences, not quality gates):
- "I would name this variable differently."
- "I prefer early returns over nested ifs."
- "This could use a stream instead of a for loop."
- "The test name could be more descriptive."

The difference: staff-level concerns identify things that will break, corrupt data, degrade performance, or create maintenance burden. Style preferences are valid review feedback but do not block merging. If your self-review only finds style items, you probably passed. If you find anything from the first list, fix it before claiming done.

**What bad looks like:** "It is good enough." Good enough for whom? Good enough to merge without being rejected, or good enough that you would confidently defend every line in a live review discussion? Those are different standards. One is a floor. The other is a target. Aim for the target.

### 8. Production readiness rating

**What to check:** An honest 1-10 rating of how ready this change is for production use.

**How to check it:** Assign a number. Then list every specific item keeping the score below 10. The number itself is not the point — the gap analysis is what matters. A score of 7 with a clear list of three specific gaps is infinitely more useful than a vague 9 with no explanation.

| Score | Meaning |
|-------|---------|
| 9-10 | Shippable immediately. No known gaps. |
| 8 | Shippable. Minor items noted but do not block production use. |
| 6-7 | Notable gaps — document them, get explicit approval to ship. |
| Below 6 | Not shippable. Work is incomplete. Fix before reporting. |

If the rating is below 8, report the score and the specific gaps to the user before claiming done. The user decides whether to fix, defer, or accept — but they decide with accurate information, not false confidence.

**What bad looks like:** Rating yourself 9/10 because acknowledging gaps feels like admitting failure. It is not failure. It is accuracy. A dishonest 9 that hides two known issues is worse than an honest 6 that names them, because the honest 6 lets the team make a real shipping decision.

## Evidence Format

This skill requires proof, not claims. Claims without proof are not accepted, no matter how confident the claim sounds. The standard format for all verification evidence is:

```
<command> exited <exit code>. <quantitative summary>.
```

**Bad examples — claims without proof:**

| What was said | Why it is not evidence |
|---|---|
| "Tests passed." | Which tests? How many? What command was run? |
| "I ran the build and it worked." | What build command? What does "worked" mean? |
| "Looks good." | By what criteria? Compared to what standard? |
| "No lint errors." | What linter? What configuration? How many files checked? |

**Good examples — evidence with proof:**

| Evidence statement | Why it is evidence |
|---|---|
| `./gradlew test` exited 0. 142 passed, 0 failed, 0 skipped. | Command, exit code, full quantitative result. Reproducible. |
| `npm run lint` exited 0. 0 errors, 2 warnings (pre-existing in `utils.js`). | Distinguishes new issues from pre-existing ones. |
| `pytest -v tests/` exited 0. 67 passed in 4.31s. | Includes timing for performance baseline. |
| `cargo clippy -- -D warnings` exited 0. 0 warnings, 0 errors. | Shows strict mode was used. |

If a verification step cannot produce command-line evidence — the check was manual, the tool is not installed locally, the environment lacks access — state that explicitly and describe what you did instead. "Manual verification: tested the profile update flow by sending a PUT request via curl, confirmed the response includes the updated bio field and returns HTTP 200." That is honest. Silence about gaps in verification coverage is not.

When this evidence feeds into a PR description, paste the raw commands and output directly. Do not summarize into prose. The reviewer should be able to copy each command and reproduce the result.

## Decision Points

| Situation | Decision |
|---|---|
| Rating 9-10 | Ship it. Evidence is clean, no meaningful gaps. |
| Rating 7-8 | List gaps explicitly. Ask user: fix now or accept as documented debt? |
| Rating below 7 | Not done. Fix blocking gaps before reporting completion. |
| Trivial change (typo, comment, doc) | Abbreviated: run items 1, 6, 7, 8 (re-read, build/test, staff check, rating). Skip items 2-5 only when no logic and no config changed. |
| Config / value change (timeout, URL, port, flag, limit) | Run items 1, 2, 3, 6, 7, 8. A one-line config change is exactly where hardcoded-value (item 2) and runtime-assumption (item 3) bugs ship — those are not skippable here. |
| Tests pass but you feel uneasy | Trust the unease. Read through once more. Find what your subconscious noticed. |
| No test suite exists | State it as a gap. Do not claim "tests pass" when there are no tests. |
| One test fails but seems unrelated | Investigate. "Unrelated" is an assumption. Prove it or fix it. |
| Lint warnings you did not introduce | Note as pre-existing with file locations. Do not let them mask new violations. |

**The abbreviated-path boundary, stated once and authoritatively:** Items 1 (re-read), 6 (build/test), 7 (staff-engineer test), and 8 (rating) are *always* run — they are cheap and they are where most issues surface. The abbreviation only ever skips items 2-5 (hardcoded values, runtime assumptions, plan deviations, edge cases), and only when the change genuinely cannot involve them — i.e. no logic and no config changed. A config/value change always keeps items 2 and 3.

## Failure Modes

See [failure-modes.md](failure-modes.md).
## Worked Example

See [worked-example.md](worked-example.md).
## Integration

**Proving-done is your self-check, not the finish line.** Passing this checklist means *you* believe the work is done — it does not mean it has been independently reviewed. Independent review is what catches what you cannot see, and it still has to happen after this. Do not stop here.

- You arrive here from: `exloom:executing-handoff-plans` (or `exloom:orchestrating-execution`), or any implementation work ready to be called complete.
- You leave here toward, in order:
  1. `exloom:auditing-plan-fidelity` — if a plan existed, confirm what shipped matches it (before code review).
  2. `exloom:reviewing-code` — independent code review; or, if the repo runs the enforced gate, `exloom:review-gate` (L1 + smoke test + cross-layer + adversarial).
  3. `exloom:requesting-review` — package the change for a human reviewer with the verification evidence and gap documentation.
- Only after independent review passes is the work actually done.
- If verification reveals a bug you cannot quickly resolve: route to `exloom:systematic-debugging` to diagnose the root cause before retrying verification.
- Evidence produced by this skill feeds directly into the PR description for `exloom:requesting-review`. The reviewer should see raw verification output, not a prose summary.
- The production readiness rating and gap list become the "Known Limitations" section of the PR description, giving reviewers an honest starting point instead of forcing them to discover gaps themselves.
