# Coverage Checklist

The readiness bar for a generated set. Every item is checkable. A set failing any item is not presented to QA without the failures named.

## Definition of done

- [ ] Complexity tier assessed and stated; count within the band, or the excess justified in writing
- [ ] Every acceptance criterion has at least one covering case, and at least one at P0 or P1
- [ ] Every declared upstream dependency has a missing / invalid / wrong-state case
- [ ] Every declared downstream dependency has a regression case
- [ ] Every case's `Covers` field names a real source — no orphan cases
- [ ] Every negative case names a specific expected message or observable behavior
- [ ] Every case is executable by a human tester — no API, DB, log, devtools, or script steps
- [ ] No two cases share an objective
- [ ] Where a technique applies, the derived cases exist and the technique is named
- [ ] At least one authorization case wherever the story involves roles, records, or tenants
- [ ] QA Questions ≤ 5, each materially affecting expected behavior
- [ ] Real but manually unverifiable scenarios appear under Notes to Development, not as blocked cases

## Required outputs

Alongside the case set:

| Output | Required |
|---|---|
| Complexity assessment — tier, reason, band | Yes |
| AC → TC coverage matrix | Yes |
| Dependency coverage matrix | Yes |
| QA Questions (≤5) | Yes — `None` if genuinely none |
| Assumptions | Yes — `None` if genuinely none |
| Exploratory charter | Yes |
| Notes to Development | Yes — `None` if genuinely none |
| Coverage summary by type | Optional |

## AC → TC coverage matrix

| AC | Covered by | Highest priority |
|---|---|---|
| AC-1 Opportunity saves with valid data | TC-001, TC-004, TC-011 | P0 |
| AC-2 Discount over 20% requires approval | TC-006, TC-007, TC-008 | P1 |
| AC-3 Closed opportunities cannot be edited | *(none)* | — |

An empty row is a checklist failure. This matrix is the answer to "did we cover the acceptance criteria" — the type tally is not.

## Dependency coverage matrix

| Dependency | Direction | Covered by |
|---|---|---|
| Customer must exist | Upstream | TC-012, TC-013 |
| Subscription must be active | Upstream | TC-014 |
| Invoice generation | Downstream | TC-021 |
| Audit log | Downstream | *(none)* |

## Exploratory charter

One per story. Not published as a test case.

```
Mission:  Probe discount approval routing for states the scripted cases assume cannot occur
Areas:    Approval queue, role switching mid-flow, opportunities edited after approval
Duration: 30 minutes
```

For Trivial and Simple stories the charter often finds more than additional scripted cases would.

## Final question before presenting

> What important scenario would be missed if the team tested only the acceptance criteria?

Add those cases if meaningful. Do not invent business requirements to justify them.
