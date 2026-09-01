---
ref: F-001
name: <short noun phrase — what this feature is>
status: draft          # draft | approved | superseded | built
created: YYYY-MM-DD
supersedes: []         # refs of specs this replaces, e.g. [F-014]
---

# F-001 · <name>

## Problem

What is wrong today, for whom, and what it costs. Two or three sentences. Not the
solution — the problem the solution has to answer to.

## Chosen approach

What we are going to do, and why this rather than something else. Reference
existing code by path: what already exists, what this extends, what convention it
follows.

## Rejected approaches

- **<approach>** — <why not>. One line each.

This is the section people skip and the one that stops the same idea being
re-proposed in three months.

## Requirements

Each requirement is one behaviour, stated so it can be checked without asking the
author what they meant. Say what the system does, never how it is built — the
storage engine is an architecture decision, not a requirement.

Five shapes cover almost everything (EARS, Mavin et al.). Use the keywords; they
make "one requirement, one behaviour" visible:

| Type | Shape |
|---|---|
| `ubiquitous` | THE SYSTEM SHALL *[response]* |
| `event` | WHEN *[trigger]* THE SYSTEM SHALL *[response]* |
| `state` | WHILE *[state]* THE SYSTEM SHALL *[response]* |
| `optional` | WHERE *[feature is present]* THE SYSTEM SHALL *[response]* |
| `unwanted` | IF *[condition]* THEN THE SYSTEM SHALL *[response]* |

**`unwanted` requirements are mandatory for anything touching money, permissions,
or data loss.** Most defects live in the negative space, and most specs never go
there.

**The test covering a criterion carries its ref in the test's name** — e.g.
`@DisplayName("F-001/R-1/AC-1 — rejects an over-large discount")` or
`def test_F001_R1_AC1_rejects_over_large_discount():`. `prove-change-is-tested.sh`
reads the runner's own JUnit XML and records which criteria actually passed, so
coverage is measured from the test run rather than claimed. A name works in every
framework; an annotation needs a reader for each one.

R-1 · event
WHEN a discount larger than the line total is submitted THE SYSTEM SHALL reject
the request and return the line total unchanged.

  AC-1 · unit
  ```gherkin
  Given a line with unit price 1 and quantity 1
  When a discount of 99 is applied
  Then the request is rejected
  And the stored total is unchanged
  ```

R-2 · unwanted
IF a discount is applied twice to the same line THEN THE SYSTEM SHALL apply it
once and record the duplicate.

  AC-1 · integration
  ```gherkin
  Given a line that already carries a 5.00 discount
  When the same discount is submitted again
  Then the line total is unchanged
  And a duplicate-discount event is recorded
  ```

## Edge cases

Each with a disposition — handled (how), out of scope (why), or the caller's
responsibility (which system).

## Non-goals

What this deliberately does not do. Specific enough that an executor recognises
the boundary while implementing.

## Open questions

Unknowns that are still unknown. Better here than papered over with false
precision.

## Identity

`F-001` · `F-001/R-3` · `F-001/R-3/AC-2`. Refs are sequential and gapless. Once the spec is `approved` they are permanent: changing what a criterion means creates a new one and marks the old `superseded`.
