---
name: requesting-review
description: Use when opening a pull request or marking work ready for review — produces a standard PR body with plan link, deviations, and test evidence.
---

# Requesting Review

## Overview

A pull request is a communication artifact, not a code dump. Its purpose is to tell the reviewer four things: what changed, why it changed, how it works, and how you know it is correct. If the reviewer has to reconstruct any of those from the diff alone, the PR body has failed its job. The diff shows what lines moved — it cannot show intent, tradeoffs, or the alternatives you considered and rejected.

Reviewer time is the scarcest resource in any engineering team. A PR body that says "fixed the bug" forces the reviewer to spend 30 minutes rebuilding context that the author already had. That is not a review — it is archaeology. A well-prepared PR body front-loads the context so the reviewer can spend their time evaluating the change, not deciphering it.

The team-level failure mode is predictable: poor PR descriptions lead to surface-level reviews. The reviewer skims because there is no context to anchor deep review. They check formatting, maybe naming, and approve. Issues that should be caught — wrong assumptions, missed edge cases, architectural drift — pass through. Over time, the team learns that reviews do not catch real problems, so they invest less in reviewing. The feedback loop degrades until code review is pure ceremony. The PR body is not bureaucracy. It is the mechanism that makes code review actually work.

---

## Process

### Prerequisites

Before opening a PR, every one of these must be true. If any is false, fix it first — do not open the PR and plan to fix it later. A PR opened before it is ready trains reviewers to delay looking at your PRs.

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

Large PRs get worse reviews. After ~400 lines, reviewer fatigue sets in — attention drops, critical issues pass through, and approval becomes "I skimmed it and nothing jumped out." Splitting is not about making reviewers happy. It is about getting reviews that actually catch problems.

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

These are the patterns that consistently produce bad PRs. Each one feels reasonable in the moment — that is why they persist.


### 1. "The diff speaks for itself"

**Thought pattern:** The code is clean and well-named. A good reviewer can understand the change by reading it.

**Why it feels right:** You just spent hours making the code clear. Of course it communicates the intent — you can see it plainly.

**What actually happens:** The reviewer sees what changed but not why. They cannot evaluate whether the approach is correct without understanding the problem. They review surface-level concerns — formatting, naming, style — because that is all they have context for. The architectural question (should this have been a queue instead of synchronous?) never gets asked because the reviewer does not know the constraints.

**Correction:** Code shows what changed. The PR body explains why and what alternatives were considered. Both are necessary. Neither substitutes for the other. A two-sentence "Why" and a two-sentence "How" would have given the reviewer enough to ask the right question.

### 2. "Tests pass"

**Thought pattern:** The tests are green. That is proof the change works. Writing the exact command output is just ceremony.

**Why it feels right:** You ran the tests. They passed. What more is there to say?

**What actually happens:** The reviewer has no way to verify what was tested, how much coverage exists, or whether the right tests ran. "Tests pass" after a database migration change could mean the unit tests passed (which do not touch the database) while the integration tests were never run. Without the actual command and output, the reviewer cannot distinguish thorough verification from shallow verification.

**Correction:** Paste the command, exit code, and result counts. `./mvnw verify` exiting 0 with "142 passed, 0 failed" is evidence. "Tests pass" is an assertion. Reviewers should evaluate evidence, not trust assertions. The verification step already produced this output — copying it into the PR body takes seconds.

### 3. "I deviated but it's obviously better"

**Thought pattern:** The plan said to use approach X, but approach Y is clearly superior. The improvement is self-evident, so documenting the deviation would be pedantic.

**Why it feels right:** You are the person closest to the implementation. You discovered something during development that the planner did not foresee. The change is obviously an improvement.

**What actually happens:** The reviewer who read the plan expects approach X. They find approach Y and do not know if the deviation was intentional (a deliberate improvement), accidental (you forgot the plan said X), or a sign of deeper confusion about the requirements. They now have to ask, adding a review cycle. Worse — if they do not notice the deviation, the plan and the code silently diverge, and future work based on the plan will be wrong.

**Correction:** Document every deviation with the justification. If the improvement is truly obvious, the documentation takes one sentence. The cost of documenting is trivial. The cost of not documenting is a reviewer who cannot trust the implementation matches the plan.

### 4. "I'll fill in the PR body later"

**Thought pattern:** The code is ready. Get the PR open so the reviewer can start. Fill in the details after.

**Why it feels right:** Speed. The reviewer can begin looking at the diff while you write up the body. Parallel work.

**What actually happens:** The reviewer opens the PR, sees an empty or placeholder body, and does one of two things: waits (adding delay) or starts without context (producing a shallow review). Most commonly, "later" never comes — the PR gets approved based on the diff alone, and the body stays empty. The next person who needs to understand this change (during an incident, during onboarding, during a related feature) finds nothing.

**Correction:** The PR body IS the review request. An empty body says "I don't respect your time enough to explain what I did." Write the body before opening the PR. If you cannot explain the change in writing, you may not fully understand it yet — and that is valuable information. The act of writing the summary often surfaces gaps in your own understanding — which is exactly the point.

---

## Worked Example

**Scenario:** You completed the CSV export feature for the orders module. The stack is Angular (frontend) + FastAPI (backend). A plan existed. One deviation occurred during implementation. Verification has already been run.

Here is the complete PR body as it would appear when the PR is opened:

---

**Title:** `feat(orders): add CSV export with streaming for large result sets`

### Summary

**What:** Adds a CSV export feature to the orders list page. Users can export filtered order data as a CSV file directly from the orders table toolbar.

**Why:** Operations team currently copies data manually from the UI into spreadsheets for monthly reconciliation. This takes 2-3 hours per report and is error-prone. CSV export eliminates the manual step entirely.

**How:** The backend uses a streaming response (`StreamingResponse` in FastAPI) to generate CSV rows on the fly, avoiding loading the full result set into memory. This handles exports up to 500k rows without memory pressure. The Angular frontend triggers the download via a hidden anchor element with a blob URL, which avoids browser popup blockers. Column selection matches the current table configuration — whatever columns the user has visible are the columns that export.

### Plan

`docs/exloom/plans/PROJ-234-csv-export.md`

### Deviations from Plan

| Plan Step | Expected | Actual | Justification |
|-----------|----------|--------|---------------|
| Step 6: No progress indicator | Export starts and completes silently | Added progress indicator for exports >10k rows | User testing showed exports over 10k rows took 4-8 seconds. Without feedback, users clicked the export button repeatedly, generating duplicate requests. Progress indicator prevents this. |

### Test Evidence

```
Command: pytest tests/ -v
Exit code: 0
Result: 12 passed, 0 failed, 0 skipped

Command: ng test --watch=false
Exit code: 0
Result: 8 specs, 0 failures

Command: ruff check src/
Exit code: 0
Result: All checks passed

Command: ng lint
Exit code: 0
Result: All files pass linting
```

### Screenshots

**Before:** Orders page without export capability
![Orders page before — no export button in toolbar](before-orders-page.png)

**After:** Orders page with export button and progress indicator
![Orders page after — export button in toolbar, progress bar shown during export](after-orders-export.png)

### Review Checklist

Review against the team's review checklist

---

**What this PR body accomplishes:** The reviewer knows the feature, the business justification, the technical approach (and why streaming was chosen over buffering), the one deviation and its rationale, the exact test results, and what the UI looks like. They can begin reviewing the code with full context immediately.

**What it does not do:** It does not restate the diff. It does not say "updated orders.component.ts" — the reviewer can see that in the file list. Every sentence in the body adds context that the diff alone cannot provide.

**For a trivial change,** the same structure applies but compressed. A typo fix PR body might be:

> **Summary:** Fixed typo in error message shown to users during checkout timeout — "timout" → "timeout".
> **Plan:** No plan — trivial fix.
> **Deviations:** N/A.
> **Test evidence:** `ng test --watch=false` exited 0 — 247 specs, 0 failures.
> **Screenshots:** N/A.
> **Review checklist:** Review against the team's review checklist

Five lines. Still structured. Still verifiable. The structure scales down gracefully — it does not require padding for small changes.

---

## Integration

This skill sits between verification and review in your org's development workflow.

**Upstream — where you come from:**
- `exloom:proving-done` — the verification output provides the test evidence that feeds directly into the Test Evidence section of the PR body. Do not re-run tests or reconstruct output. Copy from verification.
- `exloom:executing-handoff-plans` — if the work followed a plan, the plan file and any deviations recorded during execution feed into the Plan Link and Deviations sections.

**Downstream — what happens next:**
- `exloom:reviewing-code` — the PR body you produce here is the input the reviewer works from. A complete PR body enables a thorough review. An incomplete one guarantees a shallow one.

**Related:**
- `exloom:reviewing-code` — defines the review categories the reviewer applies to the PR you open here.

**If no plan existed:** This skill still applies in full. The PR body structure is the same — the Plan and Deviations sections simply state that no plan existed and give a one-sentence scope description. The absence of a plan does not mean the absence of structure. Every PR gets the same six sections regardless of whether a plan existed.

**Key principle:** The PR body is a gift to your reviewer. The five minutes you spend writing it saves them thirty minutes of context reconstruction — and produces a review that actually catches problems.
