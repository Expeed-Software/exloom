---
name: requesting-review
description: Use when opening a pull request or marking work ready for review — produces a standard PR body with plan link, deviations, and test evidence.
---

# Requesting Review

## Overview

A pull request body tells the reviewer four things: what changed, why it changed, how it works, and how you know it is correct. The diff shows what lines moved — it cannot show intent, tradeoffs, or the alternatives you considered and rejected. Front-load that context so the reviewer evaluates the change instead of reconstructing it.

This skill defines the six-section PR body, when to split large PRs, when to use drafts, and the author's responsibilities after opening.

---

## Process

### Prerequisites

Before opening a PR, every one of these must be true. If any is false, fix it first — do not open the PR and plan to fix it later.

- **`exloom:proving-done` has run.** The verification output exists and contains test evidence. This is not optional. The test evidence in the PR body comes directly from verification output — you do not re-run or reconstruct it.
- **All tests pass.** The test suite is green. If tests fail for reasons unrelated to this change, that context belongs in the PR body explicitly — but the default expectation is a clean run.
- **Plan updated with deviations (if a plan existed).** The plan file reflects what was actually built, not what was originally proposed. The PR body links to the plan and summarizes deviations, but the plan itself is the canonical record.
- **Code committed and pushed.** The branch is up to date with the target branch. Merge conflicts that a reviewer discovers during review are unnecessary friction. Resolve them before requesting review. If the target branch has moved significantly since you branched, rebase or merge and re-run verification.
- **No known issues left unaddressed.** If you are aware of a limitation or follow-up needed, document it in the PR body under the Summary. Do not rely on "I'll file a ticket later."

### Writing the PR Body

Every PR body at your org has six sections. Do not omit any section. If a section does not apply, write "N/A" or the appropriate null statement — this makes it clear the section was considered, not forgotten. Consistent structure means reviewers always know where to find each piece of information, regardless of who authored the PR.

This skill defines the format below. If your team already has its own PR-body convention, follow that instead — consistency within your team beats this default.

#### 1. Summary

The summary answers three questions: **what** changed, **why** it changed, and **how** it works. Two to three sentences per question.

Write for someone who knows the codebase but does not know this ticket. They should understand the change without reading the diff first. This is your target audience for every PR in your org.

**Bad summary:**
> Updated order service.

What about it? Why? This tells the reviewer nothing they could not see from the file list.

**Good summary:**
> Orders with multiple discount codes applied only the first code. Root cause: the discount-application loop issued a `break` after the first match instead of `continue`. Fix: changed `break` to `continue` and accumulate the discount total across all matching codes. Added a guard to cap total discount at 100% of order value.

The good summary tells the reviewer the symptom, the root cause, the fix, and the edge case handling — before they read a single line of code.

Technique: do not describe what the diff shows. The reviewer can see that the method signature changed. They cannot see that the reason it changed was because the existing signature made the new behavior impossible to test. Write that.

**Sizing guidance:** Most summaries run a few sentences for each of what/why/how. If the change is one coherent thing but genuinely needs more explanation (a non-obvious algorithm, a tricky migration), add a "Design Context" subsection rather than inflating the summary — length from depth on a single change is fine. But if the summary balloons because you are describing *several unrelated changes*, that is not a summary problem, it is a PR-scope problem: split the PR (see "Splitting Large PRs"). The distinction: more detail about one change → Design Context subsection; more changes → split.

#### 2. Plan Link

If the work had a plan, link it:
> **Plan:** `docs/exloom/plans/PROJ-234-csv-export.md`

If no plan existed, state the scope:
> **Plan:** No plan — scope was a single-file bug fix in the discount calculation module.

Do not leave this blank.

#### 3. Deviations from Plan

If any step deviated from the plan, explain what changed and why. Format as a table:

| Plan Step | Expected | Actual | Justification |
|-----------|----------|--------|---------------|
| Step 3: Use in-memory cache | Redis cache | Switched to local Caffeine cache | Redis added latency for sub-1ms lookups; Caffeine measured at 50x faster for this access pattern |
| Step 5: Skip monitoring | — | Added Micrometer counter for cache misses | Discovered during testing that cache eviction rate was higher than expected; counter needed for production visibility |

If no deviations: "No deviations from plan." Write this explicitly. Do not omit the section. The explicit statement tells the reviewer "I checked, and the implementation matches" — omitting the section tells them nothing.

If no plan existed: "No plan existed for this change — scope was [one sentence description]."

Deviations are not failures. They are normal. An unlisted deviation, however, is a trust violation — the reviewer who knows a plan existed will go looking for alignment, and undocumented differences erode confidence in the entire change.

#### 4. Test Evidence

Copy directly from verification output. Command, exit code, quantitative result. Do not paraphrase.

**Bad:**
> Tests pass.

This is a claim, not evidence. "Tests pass" is like "trust me" — it communicates confidence but proves nothing.

**Good:**
```
Command: ./mvnw test
Exit code: 0
Result: 87 passed, 0 failed, 0 skipped

Command: ./mvnw checkstyle:check
Exit code: 0
Result: 0 violations
```

If multiple commands were run during verification, include all of them. This section cannot be filled with prose. The command, exit code, and output are the evidence.

#### 5. Screenshots

Required if the change affects any user-visible UI — including admin interfaces, dashboards, and developer-facing web tools.

Include:
- **Before** screenshot (if the UI existed prior to this change)
- **After** screenshot
- Annotations if the change is subtle

If the change does not affect UI, write "N/A."

For API changes (new endpoints, changed response shapes, modified status codes), include request/response examples instead of screenshots:
```
POST /api/orders/export
Content-Type: application/json
{"format": "csv", "filters": {"status": "completed"}}

Response: 200 OK
Content-Type: text/csv
Content-Disposition: attachment; filename="orders-export.csv"
[streaming CSV body]
```

#### 6. Review Checklist Reference

End the PR body with:
> Review against the team's review checklist

This signals to the reviewer which checklist applies and confirms the author is aware of the review standard. Do not pre-check items on behalf of the reviewer. The review checklist is for the reviewer. The author's self-verification is covered by `exloom:proving-done`.

### After Opening

Opening the PR is not the end of the task. The PR lifecycle has three phases: preparation (this skill), review (the reviewer's responsibility), and resolution (responding to feedback and merging). The author is responsible for phases one and three.

The specific time windows below (the 24-hour response expectation, the 3-day draft limit) are recommended defaults, not a ratified org-wide SLA. Follow your team's actual agreed response time where it differs. What matters is the principle — do not let a PR or a review comment go stale — not the exact number of hours.

- **Assign reviewers.** Every PR needs at least one assigned reviewer. For changes to shared services or infrastructure, include the relevant team lead. Do not rely on passive notification — use the platform's reviewer assignment so the reviewer knows they are responsible. An unassigned PR is nobody's responsibility, and nobody's responsibility means it does not get done.
- **Link in the ticket system.** The PR must be linked to the ticket it addresses. If the system does not auto-link based on branch name or PR title, add the link manually. This traceability is required for sprint tracking, post-incident analysis, and audit.
- **Respond to comments within SLA.** Unanswered review comments are the most common cause of stalled PRs. If a comment requires more than a trivial response, acknowledge it ("Looking into this, will reply by EOD") so the reviewer knows it is not being ignored. Stale comment threads signal that the author has moved on — and the reviewer will too.
- **Never merge your own PR without explicit approval.** Even if you have merge permissions. Even if the change is one line. The review process exists for reasons beyond catching bugs — it maintains team awareness and prevents knowledge silos. If review is taking too long, escalate through the team, not around the process.
- **Resolve all comment threads before merging.** Every review comment should end in either a code change or an explicit agreement that no change is needed. Open threads at merge time mean unresolved concerns were bypassed.

---

## Decision Points

| Situation | Decision |
|-----------|----------|
| Trivial change (typo, config value, dependency bump) | Abbreviated PR body: one-line summary + "No plan — trivial fix" + test evidence. Mark screenshots and deviations `N/A` (don't drop the headings — `N/A` shows they were considered, matching the trivial example below). |
| Large PR (>400 lines changed) | Split it. See the "Splitting Large PRs" section below. If splitting is genuinely not feasible, add a "Reading Guide" section explaining the order to review files. |
| Reviewer requests changes you disagree with | Discuss in the PR comments. Do not silently ignore. If agreement cannot be reached, get a third opinion from a team lead or architect. Never merge with unresolved disagreements. |
| No plan existed for this work | State it explicitly: "No plan — this was a bug fix / small improvement / urgent production fix." The absence of a plan is information, not a problem. |
| Deviations from plan exist | The PR body MUST explain them. Every one. Unlisted deviations are trust violations — if a reviewer discovers a deviation you did not document, they will question what else is undocumented. |
| Reviewer has not responded in 24 hours | Ping politely in the PR or team channel. Do not merge without review. Do not let it sit silently for days. |
| PR was opened prematurely (tests failing, body incomplete) | Close or convert to draft. Fix the issues. Reopen when ready. A premature PR trains reviewers to ignore your notifications. |
| Multiple reviewers disagree with each other | Do not pick the answer you prefer. Escalate to the team lead or architect and let them make the call. Document the decision in the PR. |

---

## Splitting Large PRs

Split PRs larger than ~400 lines changed. Past that threshold, reviewer attention drops and critical issues pass through.

**How to split — in order of preference:**

1. **By vertical slice.** Each PR delivers one complete behavior end-to-end: database migration + backend endpoint + frontend component + tests. The reviewer sees a coherent feature, not disconnected layers. This is the default for feature work.

2. **By layer with a clear dependency order.** When vertical slices are not practical (e.g., a shared data model change that affects multiple features), split by layer and merge in dependency order: data model first, then backend, then frontend. Each PR must build and test independently. State the dependency in the PR body: "Depends on PR #234 (data model)."

3. **By preparatory refactoring vs. feature.** If the feature requires refactoring existing code first, split the refactoring into its own PR. The refactoring PR changes structure without changing behavior (all existing tests pass). The feature PR builds on the cleaned-up code. This makes both PRs easier to review — one is "did anything break?" and the other is "is the new feature correct?"

4. **By commit, as a last resort.** If the work is inherently a single cohesive change that cannot be split (a large migration, a framework upgrade), add a "Reading Guide" to the PR body that tells the reviewer which commits to read in which order: "Start with commit 3 (the core change), then commit 1 (the setup), then commit 2 (the tests)."

**Signs you should have split:**
- The PR touches more than 3 directories that are not closely related
- The summary has to describe several unrelated changes (not just explain one change in depth)
- You find yourself writing "also" in the summary — "Also updated the error handling in the auth module"
- The reviewer asks "can you break this up?" (by then you have already wasted their time and yours)

## Draft PRs — When to Use Them

A draft PR is a request for early feedback, not a request for review. Use it when:

- **Architectural direction check.** You are 30% into implementation and want to confirm the approach before investing the remaining 70%. The draft shows enough code to evaluate the pattern without being complete. State what you want feedback on: "Looking for feedback on the event-sourcing approach in `OrderAggregate.java` — is this the right pattern for our codebase?"

- **Cross-team coordination.** Your change affects another team's API contract or shared library. A draft PR lets them see the shape of the change early enough to raise concerns before you finish.

- **Complex or risky changes.** The change is large enough that discovering a fundamental problem at review time would waste days of work. A draft at the halfway point is insurance.

**Draft PR rules:**
- The title must start with `[DRAFT]` or use the platform's draft PR feature.
- The body must state what feedback you want — "review everything" is not a draft, it is a premature PR.
- Do not convert a draft to "ready for review" without running the full verification checklist. The draft may have been reviewed informally, but formal review requires the same evidence as any other PR.
- Do not leave drafts open for more than 3 days. Either convert to ready or close with a note on why.

## Failure Modes

See [failure-modes.md](failure-modes.md).
## Worked Example

See [worked-example.md](worked-example.md).
## Integration

This skill sits between verification and review in your org's development workflow.

**Upstream — where you come from:**
- `exloom:proving-done` — the verification output provides the test evidence that feeds directly into the Test Evidence section of the PR body. Do not re-run tests or reconstruct output. Copy from verification.
- `exloom:executing-handoff-plans` — if the work followed a plan, the plan file and any deviations recorded during execution feed into the Plan Link and Deviations sections.

**Downstream — what happens next:**
- `exloom:reviewing-code` — the PR body you produce here is the input the reviewer works from. A complete PR body enables a thorough review. An incomplete one guarantees a shallow one.

**Related:**
- `exloom:reviewing-code` — defines the review categories the reviewer applies to the PR you open here.

**If no plan existed:** This skill still applies in full. The PR body structure is the same — the Plan and Deviations sections simply state that no plan existed and give a one-sentence scope description. Every PR gets the same six sections regardless of whether a plan existed.
