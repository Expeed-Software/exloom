# Priority and Execution Tier

Two independent axes. Assign both on every case.

## Priority — how bad is it if this breaks?

Take the **highest** row that matches. Priority is never assigned by feel.

| Priority | Assign when any of these hold |
|---|---|
| **P0** | Blocks the primary user goal; data loss or corruption; authorization or tenant boundary; money or compliance impact |
| **P1** | A core acceptance criterion not already covered by a P0; failure of a declared upstream or downstream dependency; the primary negative paths |
| **P2** | Secondary validation; alternate paths; recoverable errors; UI-state correctness |
| **P3** | Cosmetic; rare edge cases with low impact; nice-to-have confirmations |

This rubric is what makes P1 mean the same thing on every board. Do not add local interpretations.

## Execution Tier — how often does it run?

| Tier | Meaning |
|---|---|
| **Acceptance** | Run to accept this story. May never run again. |
| **Regression** | Enters the permanent suite. Run whenever this area changes. |

## Why the two axes are separate

Conflating them rots the suite in both directions:

- A P2 data-integrity case may belong in permanent regression. Priority-only thinking drops it.
- A P0 case may be a one-off acceptance check that never needs rerunning. Priority-only thinking keeps it forever and bloats every cycle.

## Assignment guide

| Case kind | Typical Priority | Typical Tier |
|---|---|---|
| Primary happy path for the story's main goal | P0 | Regression |
| Authorization / tenant boundary | P0 | Regression |
| Core AC validation | P1 | Regression |
| Upstream dependency missing or invalid | P1 | Acceptance |
| Downstream regression check | P1–P2 | Regression |
| Field-level validation | P2 | Acceptance |
| Boundary values on a secondary field | P2 | Acceptance |
| Cosmetic or rare edge | P3 | Acceptance |

Typical, not automatic. A cosmetic defect on a payment confirmation screen is not P3.

## Worked calibration

| Case | Priority | Why |
|---|---|---|
| Sales user opens another tenant's opportunity by editing the URL | **P0** | Tenant boundary — highest matching row, regardless of how unlikely |
| Opportunity saves with valid data | **P0** | Blocks the primary user goal |
| Discount over 20% routes to Manager approval | **P1** | Core acceptance criterion |
| Saving with an expired subscription shows the correct message | **P1** | Declared upstream dependency failure |
| Close date before created date is rejected | **P2** | Field validation, recoverable |
| Currency symbol alignment in the totals column | **P3** | Cosmetic |

Note the first row: likelihood does not lower priority. The rubric asks how bad the failure is, not how often it happens.
