# Technique Catalog

When a situation below applies, derive the cases with the named technique and record the technique name on the case. Techniques bound the case count; unguided generation does not.

| Situation | Technique |
|---|---|
| A field with a range, length, or format | Equivalence Partitioning + Boundary Value Analysis |
| Two or more business rules that interact | Decision table |
| A record with statuses, or a multi-step workflow | State-transition table |
| Several independent variables (role × state × dependency) | Pairwise |
| A dependency with lifecycle states | Dependency state matrix |
| A user journey | Scenario path analysis |

---

## Equivalence Partitioning + Boundary Value Analysis

Partition into classes that behave identically; take one value per class plus the values either side of each boundary.

**Field:** Discount percent, valid 0–100, integers only.

| Case | Value | Class |
|---|---|---|
| 1 | `-1` | Below minimum |
| 2 | `0` | Minimum boundary |
| 3 | `45` | Valid interior |
| 4 | `100` | Maximum boundary |
| 5 | `101` | Above maximum |
| 6 | `12.5` | Invalid type |
| 7 | *(empty)* | Missing |

Seven cases, not twenty. Do **not** generate boundary cases for fields where boundaries are meaningless — a dropdown with three options has no boundary.

---

## Decision table

Use when the outcome depends on a combination of conditions. One case per rule that produces a distinct outcome.

**Rules:** A discount over 20% requires Manager approval. Approval is not required for internal accounts.

| Rule | Discount > 20% | Internal account | Outcome |
|---|---|---|---|
| 1 | No | No | Saves immediately |
| 2 | Yes | No | Routed for Manager approval |
| 3 | Yes | Yes | Saves immediately |
| 4 | No | Yes | Saves immediately |

Rules 1 and 4 share an outcome and a path — merge them into one case. Three cases, full rule coverage.

---

## State-transition table

Rows are states, columns are actions. Test every legal transition, plus a representative sample of illegal ones.

**States:** Draft → Submitted → Approved → Closed

| From \ Action | Submit | Approve | Reopen |
|---|---|---|---|
| Draft | → Submitted | **illegal** | **illegal** |
| Submitted | **illegal** | → Approved | → Draft |
| Approved | **illegal** | **illegal** | → Submitted |
| Closed | **illegal** | **illegal** | **illegal** |

Legal transitions each get a case. Illegal transitions get cases only where a user could realistically attempt one — a stale browser tab, a bookmarked URL, browser Back. Do not write a case for a transition no interface exposes.

---

## Pairwise

Use instead of the full cross-product when three or more independent variables combine. Cover every *pair* of values.

**Variables:** Role (Manager, Sales) × Account state (Active, Suspended) × Discount (≤20%, >20%)

Full cross-product is 8. Pairwise covers all pairs in 4:

| Case | Role | Account | Discount |
|---|---|---|---|
| 1 | Manager | Active | ≤20% |
| 2 | Manager | Suspended | >20% |
| 3 | Sales | Active | >20% |
| 4 | Sales | Suspended | ≤20% |

Add a specific combination back only when it carries independent business risk — the pairwise set is the floor, not a cap.

---

## Dependency state matrix

For each declared upstream dependency, walk its lifecycle. Generate only the states the system can actually reach.

| State | Case |
|---|---|
| Available | Baseline positive path |
| Missing | Never created |
| Inactive | Exists, disabled |
| Expired | Was valid, no longer |
| Deleted | Removed after the record referenced it |
| Foreign tenant | Belongs to another account — see `manual-security-scope.md` |

For each declared **downstream** dependency, generate one regression case confirming it still receives correct data.

---

## Scenario path analysis

One case per realistic path through the journey.

| Path | Case |
|---|---|
| Normal | Completes the flow with valid data |
| Alternate | Reaches the same outcome by a different legal route |
| Interrupted | Refresh or navigate away mid-flow, then return |
| Abandoned | Cancel partway; confirm nothing partial was saved |
| Retried | Fail once, correct the input, resubmit |

Include double-submit and duplicate-action cases **only** where a real duplicate could result — see `human-executability.md` for what a lone tester can actually stage.
