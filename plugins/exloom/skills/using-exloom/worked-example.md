# Worked example — one change, start to push

A Micronaut service. Ticket: **orders API should reject a discount larger than the line total.** Today it returns a negative amount.

You are on `dev`. You run `/exloom`. Everything below is what it does, in the order `exloom_next_step` returns.

---

## `branch`

`dev` is protected, so `exloom:isolating-execution` creates `fix/1042-negative-discount` off it. The hooks skip protected branches, so work left on `dev` or `main` is never gated at all.

## `init`

`/review-init` (used by /exloom) writes `.claude/reviews/fix/1042-negative-discount.md` and asks once:

> Quick fix? — **yes** means the Sprint lane.

You say no: small, but it changes the API's behaviour. `**Lane:** standard`. No diff yet, so the tier is pending; the hook derives it from the real diff at push.

## `commit`

The checklist is committed on its own: `chore(review): initialize review report for fix/1042-negative-discount`.

## `spec`

Standard lane, `**Spec:** none` — so `exloom:brainstorming`. For a stated bug it is short: current behaviour, chosen approach, one rejected approach (clamp to zero — hides the bad input), one criterion:

> F-1042 / R-1 / AC-1 — a discount larger than the gross returns 400 with `InvalidDiscount`, not a clamped total.

The spec path goes into `**Spec:**` and is committed.

## `plan`

`**Plan:** none` — so `exloom:planning-for-handoff`. Two tasks, exact files, each citing AC-1:

```
### Task 1 — OrderTotal.java: throw InvalidDiscountException when discount > gross
### Task 2 — OrderController.java: map it to 400; OrderTotalTest covers both
```

The plan path goes into `**Plan:**` and is committed.

## `build`

`exloom:executing-handoff-plans`, one task at a time. Task 1:

```java
// OrderTotal.java
int gross = unitPrice * qty;
if (discount > gross) throw new InvalidDiscountException(gross, discount);
return gross - discount;
```

Commit. The task review dispatches `l1-reviewer` on that commit; it approves. Task 2 the same way. Nothing else: no `DiscountPolicy` interface, no refactor of the caller. If the fix genuinely needs one, **stop and ask** — that is a scope decision.

`/exloom status` while this runs: `Tier 1 · task 1/2 · round 0/3 · proof ✗ · 0 rulings · next: build`.

When both tasks' reviews have approved, `build` is finished. An edit left uncommitted sends you to `commit-work` first.

## `report`, then `review`

The evidence block is regenerated and committed. Then the whole-branch review runs once — `l1-reviewer`, plus `adversarial-reviewer` at Tier 2 and `security-auditor` at Tier 3 or on a security surface. Here: Tier 1, L1 only. It comes back:

> **Critical** — `OrderTotal.java:12` — the exception carries `gross` and `discount` but the controller's 400 body omits both, so the client cannot tell which line was rejected.
>
> VERDICT: REJECTED (1 items)

## `fix`

`exloom:fixer` gets that finding verbatim and makes the smallest fix: the two numbers in the response body. Commit. Then `l1-reviewer` runs again in **verify** mode over the fix range only.

> ## Previous findings
> - OrderTotal.java:12 — NOT ADDRESSED: the body names the numbers but not the line id, which is what the client keys on.

Adversarial and security would not re-run here; a fix does not expire their approval.

## `rulings`

What is still open after a verify is yours. /exloom asks, with the reviewer's reason:

- Fix again
- Not a real problem, ignore (PARKED)
- Fix later, with a ticket (DEFERRED)

The ticket is about the amount, not the line id: DEFERRED. Written under `## Rulings`:

```
- OrderTotal.java:12 — DEFERRED ORD-1050: line id in the error body is a separate change
```

Nothing is recorded that you did not say. At the round cap exloom refuses another dispatch and asks for rulings on what is left.

## `proof`

```
run 1/3: base source + base tests (control)     PASS
run 2/3: base source + YOUR tests               FAIL  ← the point
run 3/3: your change + your tests               PASS
PROVED — without the source change, the tests fail.
```

If run 2 had **passed**, the test does not test the change — usually it asserts something true either way. The fix is a better test, not another run.

## `smoke`

`/smoke-test` (used by /exloom) — not the unit test, the real thing:

```
$ ./gradlew :orders:bootRun
$ curl -s -XPOST localhost:8080/orders/quote -d '{"unitPrice":1,"qty":1,"discount":99}'
{"error":"InvalidDiscount","gross":1,"discount":99}
```

For a CLI or API change `record-smoke.sh` records the receipt; a UI change needs the result pasted under `## Smoke test`. **A library still has a smoke test** — call the public entry point an adopter would call. `N/A — library` is not an answer.

## `push`

```
12 min · 2 review rounds · 1/1 criteria proved · 1 ruling
```

The gate checks: checklist bound to the reviewed commit, tier not under the derived one, `proof.json` PROVED, L1 approved the shipped commit, a ruling per open finding. All true — `git push -u origin fix/1042-negative-discount` goes.

---

## The same ticket on the Sprint lane

Answer **yes** to "Quick fix?" at `init`. `spec` and `plan` never appear; `build` is "make the change, commit". Reviewers are capped at L1; proof, smoke and the derived tier are unchanged. If it turns out to matter, `/harden` moves the branch to Standard.

---

## What goes wrong, and where

| Symptom | Step | What is actually happening |
|---|---|---|
| Review round 4, 5, 6… | `fix` | Findings are being treated as design briefs. Fix what is cited; a fix needing new architecture is a ticket, not this branch. |
| `PROOF VOID` | `proof` | The suite did not pass at the base commit. Either the throwaway worktree lacks gitignored deps, or the pinned test command names test classes that do not exist at the base. Pin one valid at any base. |
| Push blocked on a branch you thought was done | `push` | Run `/exloom`; it names the missing step. `EXLOOM_VERBOSE=1` prints the full reason. |
| Nothing blocks at all | — | The gate is opt-in: on where the checklist is committed, else only with `.claude/exloom-gate.enabled`. |
| Gate demands a reviewer that already ran | `review` | Its receipt covers an older commit. Only L1 must cover the commit you ship; /exloom re-dispatches that one. |
