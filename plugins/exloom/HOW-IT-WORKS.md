# How exloom works

The README's quick start is two commands. This page is what `/exloom` does underneath, for when you want to run a step yourself.

## Pick a lane before you pick a step

Rigour is earned by stakes. Running the full flow on a null check is how a one-line fix becomes a feature, so the ceremony scales separately from the review.

| Lane | Before the code | After it | Declared |
|---|---|---|---|
| **Sprint** | nothing | L1, smoke test, proof | `**Lane:** sprint` |
| **Standard** | a spec and a plan | whatever the tier requires | the default |
| **Certified** | a spec and a plan | tier's requirements, no workflow-step escape hatches, signed commit | strict mode: a committed `.claude/exloom-strict` |

"No workflow-step escape hatches" means the gate refuses a Certified checklist that records a skipped step under `## Escape hatches used` — a step you chose not to do is not a step you may write your way past. It does not mean the branch cannot be pushed: `EXLOOM_REVIEW_SKIP=1` still bypasses the hooks on any lane, and always writes a bypass receipt. One is a workflow decision the gate reads; the other is an out-of-band override that leaves a trace.

The lane is your choice; the **tier** is derived from the diff and decides how deep the review goes. They are different axes: a migration is Tier 3 whatever lane you are on, and **Sprint is refused at Tier 3** — those are the stakes that earn the full flow.

`/exloom` asks one question when a branch starts — "Quick fix?" — and a yes is Sprint; it never offers Sprint at Tier 3. Certified is not a per-branch choice: `/exloom-setup` asks once whether the repository runs in strict mode. A committed `.claude/exloom-lane` still sets a repo default.

A Sprint branch that turns out to matter gets `/harden`: it recovers the spec from the diff that now exists, raises the lane, and names what the higher bar requires. Nothing is regenerated.

## The loop

| # | Step | Run | Produces |
|---|---|---|---|
| 1 | Decide what to build | `exloom:brainstorming` | a spec — problem, approach, numbered requirements, a criterion each |
| 2 | Turn it into a plan | `exloom:planning-for-handoff` | a plan — exact files, tasks citing the criteria they serve |
| 3 | Get on a branch | `exloom:isolating-execution` | a feature branch, because the gate skips protected ones |
| 4 | Start the record | `/review-init` | `.claude/reviews/<branch>.md`: base branch, lane, rulings, and an evidence block exloom generates |
| 5 | Build it | `exloom:executing-handoff-plans` | the code — not more, not less; deviations logged |
| 6 | Prove the tests notice it | `scripts/prove-change-is-tested.sh` | `proof.json` — PROVED, or the reason it is not |
| 7 | Check for drift | `exloom:auditing-plan-fidelity` | criteria with no task, tasks with no criterion, files no task called for |
| 8 | Run it | `/smoke-test` | real output from the real thing |
| 9 | Review | `/review-complete` | reviewer receipts, findings, dispositions |
| 10 | Ship | `git push` | the gate lets it through |

**A small change starts at step 3.** Steps 1, 2, 5 and 7 need a plan to work against, and the Sprint lane skips them.

