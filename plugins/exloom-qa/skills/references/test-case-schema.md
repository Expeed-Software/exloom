# Test Case Schema

Ten fields. Every case populates all ten, or marks a field `None` explicitly. A blank field is a defect.

| # | Field | Rule |
|---|---|---|
| 1 | `Test Case ID` | `TC-001`, sequential. **Never renumbered** once assigned, even if earlier cases are removed. |
| 2 | `Objective` | One sentence naming what is validated. No two cases may share an objective. |
| 3 | `Covers` | The evidence link. See below. |
| 4 | `Test Type` | One or more from the enum below. |
| 5 | `Priority` | P0–P3. Assigned by rubric, never by feel — see `priority-rubric.md`. |
| 6 | `Execution Tier` | `Acceptance` or `Regression` — see `priority-rubric.md`. |
| 7 | `Preconditions` | Required state before step 1. Dependency states live here, never in steps. |
| 8 | `Test Data` | Values used, separated from steps so the case ports between environments. |
| 9 | `Test Steps` | Human-executable, one action per step — see `human-executability.md`. |
| 10 | `Expected Result` | Specific and observable. See below. |

## Covers — the evidence link

Every case names its source. One of:

| Form | Use when |
|---|---|
| `AC-3` | Derived from a numbered acceptance criterion |
| `Dependency: Subscription must be active` | Derived from a declared upstream/downstream dependency |
| `Inferred: <one-line reason>` | Reasonable functional inference from the story |
| `Security: IDOR` | From `manual-security-scope.md` |

A case that cannot name a source is deleted, not published. No orphan cases.

## Test Type enum

```
Functional      Positive        Negative        Boundary
Validation      Business Rule   Scenario        Workflow
State Transition  Authorization  Authentication  Security
Integration     Data            Regression      Error Handling
Concurrency     Session
```

`Accessibility` and `Performance` are deliberately absent — this methodology does not generate them, and an enum value with no method behind it gets misapplied.

## Objective — worked examples

| Verdict | Objective |
|---|---|
| Bad | `Test the create opportunity screen` — names a screen, not a behavior |
| Bad | `Verify AC-2` — restates the criterion instead of the check |
| Good | `Opportunity cannot be saved when the close date precedes the created date` |
| Good | `Manager role can reopen a closed opportunity; Sales role cannot` |

## Expected Result — the hard rule

A negative case must name the **actual message or observable behavior**. "Shows an error" is not executable — two testers will disagree on whether it passed.

| Verdict | Expected Result |
|---|---|
| Bad | `An error is displayed` |
| Bad | `The system handles it gracefully` |
| Bad | `Save fails` |
| Good | `Inline validation reads "Close date must be on or after the created date"; the record is not saved and the form retains entered values` |
| Good | `The Save button stays disabled and the Close Date field is outlined in red` |

If the real message is unknown, do **not** invent one. Either take it from `app-knowledge.md`, or raise it as a QA Question. Inventing an expected result produces a test that fails for the wrong reason.

## Preconditions vs Test Steps

Setup belongs in preconditions. Steps start at the action under test.

| Verdict | Example |
|---|---|
| Bad | Step 1: `Log in as Manager.` Step 2: `Create a customer.` Step 3: `Open Opportunities.` Step 4: `Click New.` |
| Good | Preconditions: `Logged in as Manager. An active customer exists with a configured billing address.` Steps: `1. Use the navigation flow to reach Create Opportunity. 2. …` |

The navigation flow is captured once in the story context. Do not repeat it in every case.
