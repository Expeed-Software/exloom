# Worked example — one feature, end to end

A Micronaut service. Ticket: **orders API should reject a discount larger than the line total.** Today it returns a negative amount.

This is a small change — two files. It starts at step 3, not step 1. The spec-and-plan steps are shown after, for when the work is bigger.

---

## 3. Get on a branch

```
exloom:isolating-execution
```

Creates `fix/24391-negative-discount` off `dev`. This matters more than it looks: the hooks skip protected branches, so work left on `dev` or `main` is never gated at all.

## 4. Start the review record

```
/review-init
```

Reads the diff (empty so far) and the ticket, proposes a tier, writes `.claude/reviews/fix/24391-negative-discount.md`, commits it.

> Tier 1 — two files, one module, no API surface change, internal only.

Tier is declared **now**, before the diff exists, on purpose. The gate derives the same tier at push time from the actual diff and refuses a checklist that declares less, so declaring early is the honest version.

## 5. Build it

```
exloom:executing-handoff-plans
```

Two files:

```java
// OrderTotal.java
int gross = unitPrice * qty;
return Math.max(0, gross - discount);
```

```java
// OrderTotalTest.java
assertThat(total(10, 3, 5)).isEqualTo(25);
assertThat(total(1, 1, 99)).isEqualTo(0);   // the bug
```

Nothing else. No `DiscountPolicy` interface, no refactor of the caller, no second test class. If the fix genuinely needs one of those, **stop and ask** — that is a scope decision, not an implementation detail.

## 6. Prove the tests notice it

```
bash scripts/prove-change-is-tested.sh
```

```
run 1/3: base source + base tests (control)     PASS
run 2/3: base source + YOUR tests               FAIL  ← the point
run 3/3: your change + your tests               PASS
PROVED — without the source change, the tests fail.
```

If run 2 had **passed**, the test does not test the change — the usual cause is asserting on something true either way. Fix the test, not the script.

Costs no model tokens. It is a shell script running your suite three times.

## 7. Check for drift

```
exloom:auditing-plan-fidelity
```

With no plan, this is a short pass: does the diff contain anything the ticket did not ask for? Two files, both named in the ticket. Clean.

On planned work this is the step that catches "I improved it while I was in there."

## 8. Run it

```
/smoke-test
```

Not the unit test — the real thing:

```
$ ./gradlew :orders:bootRun
$ curl -s -XPOST localhost:8080/orders/quote -d '{"unitPrice":1,"qty":1,"discount":99}'
{"total":0}
```

Pasted into the checklist verbatim. **For a library or CLI there is still a smoke test** — call the public entry point an adopter would call, from outside the test sources, and show the output. `N/A — library` is not an answer.

## 9. Review

```
/review-complete
```

Dispatches `l1-reviewer` at low effort. It comes back:

> **Critical** — `OrderTotal.java:12` — `Math.max(0, …)` silently swallows a discount larger than the total. The caller cannot distinguish "discount applied" from "discount clamped", and the receipt line will show a discount that was never given.
>
> VERDICT: REJECTED (1 items)

That is a real finding. The fix is to return the clamp as a signal, not to redesign discounting:

```java
if (discount > gross) throw new InvalidDiscountException(gross, discount);
```

Re-run `/review-complete`. **L1 only** — adversarial and security do not re-run, and their approval does not expire because you fixed something.

> No further findings. VERDICT: APPROVED · ROUND NEEDED AFTER FIX: NO

Two rounds. Not nine.

## 10. Ship

```
git push -u origin fix/24391-negative-discount
```

The gate checks: checklist complete, no placeholder text, tier not under-declared, `proof.json` says PROVED, L1 approved the commit being shipped. All true — the push goes.

Had this branch reached **three** review passes, the push would have blocked and you would have been asked to choose: fix the open Criticals by name and re-review, merge as-is, or see the findings first — with the recommended option first, derived from whether any Critical is still open. Note the wording of the fix option: another *review* pass on unchanged code returns the same findings, so what the cap asks for is a fix.

---

## When it's bigger: steps 1 and 2

For a feature rather than a bug fix, start earlier.

**1. `exloom:brainstorming`** — explores what exists before proposing anything new. Searches for the current implementation by concept as well as by name, reads neighbouring code for the conventions, and writes a spec: problem, chosen approach, **rejected approaches and why**, edge cases, non-goals. The rejected list is the part people skip and the part that stops the same idea being re-proposed in three months.

**2. `exloom:planning-for-handoff`** — turns the spec into a plan a different person could execute: exact file paths, one task per atomic change, a validation step per task, acceptance criteria that are observable without asking the author what they meant. Then steps 3–10 are the same, except step 5 follows the plan task by task and logs every deviation, and step 7 has a plan to audit against.

---

## What goes wrong, and where

| Symptom | Step | What is actually happening |
|---|---|---|
| Review round 4, 5, 6… | 9 | Findings are being treated as design briefs. Fix what is cited; a fix needing new architecture is a ticket, not this branch. |
| `PROOF VOID` | 6 | The suite could not run in the throwaway worktree — usually gitignored deps. Pin a self-contained command in `.claude/exloom-test-command` and commit it. |
| Push blocked on a branch you thought was done | 10 | Run `/review-complete`; it names the exact section that is missing. |
| Nothing blocks at all | — | The gate is opt-in. It is on only when `.claude/exloom-gate.enabled` exists in the repo. |
| Gate demands a reviewer that already ran | 9 | Its receipt covers an older commit. Only L1 must cover the commit you ship — re-run that one. |
