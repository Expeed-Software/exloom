# Complexity and Volume

Assess complexity **before** generating. State the tier and the reason in the artifact. The tier sets the case-count band.

## Tiers

| Tier | Signals | Band |
|---|---|---|
| **Trivial** | Label, text, or config change; single field; no business rule; no dependency; 1–2 AC | **3–8** |
| **Simple** | One screen; ≤3 AC; no integration; at most one dependency | **12–20** |
| **Typical** | Multi-field form or a workflow; some dependencies; one or two roles | **25–40** |
| **Complex** | Multiple roles, integrations, or a state machine; cross-module effects | **40–60** |

When signals straddle two tiers, take the lower one and say so. QA can override the assessment; the override stands for the rest of the run.

## The rules

**Exceeding the band** requires a written reason in the artifact naming what forced it — a third role, an extra integration, a state machine that was not obvious from the story. "Thoroughness" is not a reason.

**Falling below the band** is acceptable whenever `coverage-checklist.md` still passes. A short set with full acceptance-criteria coverage beats a padded one.

**Never pad to reach a number.** The band is a ceiling that reflects what a human will review and run, not a target to hit.

## Why the ceiling exists

A set of 100 cases is reviewed for the first ten and skimmed thereafter, then never executed in full. A reviewed set of 30 is worth more than an unreviewed set of 100. Volume is not coverage — `coverage-checklist.md` measures coverage.

## For Trivial and Simple stories

Prefer an exploratory charter over additional scripted cases. Five sharp cases plus a 30-minute charter finds more than twenty scripted variations of the same interaction.

## Worked examples

| Story | Tier | Reason | Count |
|---|---|---|---|
| "Change the Submit button label to Save" | Trivial | Text only; no rule, no dependency | 3 |
| "Add an optional Notes field to the customer form" | Simple | One screen, one field, persistence to check | 14 |
| "Create Opportunity with discount approval routing" | Typical | Multi-field form, one business rule, two roles, one downstream effect | 32 |
| "Bulk import customers with validation and rollback" | Complex | File handling, partial failure, integration, audit trail, two roles | 52 |

## Anti-pattern

The failure mode this file exists to prevent: taking a Trivial story, running every coverage area and combination axis against it, and producing forty cases for a label change. That output is not thorough — it is unusable, and it teaches QA to stop reading the tool's output.
