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

The lane is your choice; the **tier** is derived from the diff and decides how deep the review goes. They are different axes: a migration is Tier 3 whatever lane you are on, and **Sprint is refused at Tier 3** — those are the stakes that earn the full flow. Changing any `.claude/exloom-*` setting is itself Tier 3, so the rules cannot be relaxed and used in the same push.

`/exloom` asks two questions when a branch starts. "Quick fix?" — a yes is Sprint, never offered at Tier 3. Then what kind of work this is, recorded as `**Work type:**`:

| Work type | What changes |
|---|---|
| **new feature** | the full flow below |
| **bug fix** | `exloom:fixing-bugs` — reproduce it, commit the failing test with the fix. Never sent to the spec or plan step |
| **change to existing code** | `exloom:brainstorming` in change-note mode: a numbered change note stands in for the spec, and a single task records `**Plan:** none` |

Certified is not a per-branch choice: `/exloom-setup` asks once whether the repository runs in strict mode. A committed `.claude/exloom-lane` still sets a repo default.

A Sprint branch that turns out to matter gets `/harden`: it recovers the spec from the diff that now exists, raises the lane, and names what the higher bar requires. Nothing is regenerated.

A repository may also commit `.claude/exloom-min-tier`, a floor below which the gate asks for nothing. It is capped at 2 so Tier 3 is never skippable, ignored under Certified and strict mode, and every skip writes `.claude/reviews/<branch>.skip.json` naming the tier, the floor, and who set it in which commit.

## Optional, or mandatory

A repository runs the gate one of two ways, and `/exloom-setup` asks which.

**Optional (per branch, the default).** No gate switch is committed. The first `/exloom` on a branch asks "Use exloom on this branch?" A yes commits the branch's checklist, and that committed checklist is what every hook reads, so the answer holds for every later session on the branch. A branch that said no is never checked, and nor is a developer who never answered — which is the point: a committed switch would gate the whole team, including the people who chose not to use exloom. Deleting the checklist from the working tree does not revoke the yes; only a commit does.

**Mandatory (repo-wide).** A **committed** `.claude/exloom-gate.enabled` checks every branch, for everyone, and overrides any per-branch answer. Everything else — strict mode, the minimum tier, the pinned test command — behaves the same in both modes; on an ungated branch those settings simply do nothing.

**Personal always-on.** The gate switch is read from the working tree, not from the index, so a developer who keeps an uncommitted `.claude/exloom-gate.enabled` is gated on every branch in that clone and nobody else is. Committing it is what makes it the repository's rule; leaving it uncommitted makes it one person's habit. Add it to `.git/info/exclude` so it stays out of commits and off everyone else's radar.

Neither mode is enforcement. Both are hooks in the developer's own session, and `EXLOOM_REVIEW_SKIP=1` turns them off. What actually stops an unreviewed change from merging is CI and branch protection; the gate's job is to produce evidence those checks can read.

In optional mode the proof uses its own auto-detected test command. Pinning one per branch would make ordinary work a Tier 3 change, because every `.claude/exloom-*` setting does; a repository that needs a custom command has its lead commit it once through `/exloom-setup`.

## The loop

`/exloom` runs the next step that is not done, then stops when a person has to decide. It is a priority order, not a pipeline — the same command does the right next thing whatever state the branch is in.

| Step | What it means | Run |
|---|---|---|
| `branch` | you are on a protected branch | `exloom:isolating-execution` |
| `init` | no checklist yet; asks the lane and the work type | `/review-init` |
| `commit` | `.claude/reviews/` has uncommitted changes | commit it alone |
| `commit-work` | real work is uncommitted. Untracked tool scratch — `node_modules/`, `.gradle/`, `.playwright-mcp/` and a dozen more — is passed over and named, never committed for you | commit it |
| `spec` | a feature or a change needs one | `exloom:brainstorming`, then `exloom:spec-reviewer` once on Standard and Certified. Its verdict is advice: it gates nothing and counts as no review round |
| `plan` | a multi-task change needs one | `exloom:planning-for-handoff` |
| `build` | tasks remain | `exloom:executing-handoff-plans`, then `scripts/fast-check.sh` after each task — compile, lint and the tests it touched, under a minute, warning only |
| `review` | a reviewer has not covered this commit | `/review-complete` dispatches them. A reviewer is always a fresh dispatch; resuming one is refused |
| `fix` | a reviewer rejected | `exloom:fixer`, on the findings verbatim |
| `rulings` | findings are open and only you can dispose of them | fix again, `PARKED`, or `DEFERRED <ticket>` |
| `report` | the review is stale against the tip | re-run the reviewer |
| `smoke` | no evidence the thing runs | `/smoke-test`, or a waiver naming who waived it and where — never on Certified or in strict mode |
| `proof` | no proof the tests notice the change | `scripts/prove-change-is-tested.sh` |
| `push` | the tier's evidence is in | the gate lets it through |
| `blocked` | the gate cannot name a next step | read what it printed |

## The proof, and what it costs

`prove-change-is-tested.sh` runs your tests at the base commit, then at the base with your tests added, then with change and tests together. If your tests pass without your change, they do not test it.

It runs **only the tests your diff touches**, which is why it takes seconds. The selection comes from the diff, or from a committed `.claude/exloom-test-select` that `/exloom-setup` derives and proves for the repository. If a narrowed command will not run — a layout the built-in adapters guessed wrong — the whole suite is retried before anything is concluded, and the receipt records `selection_source: fallback`. Certified and strict mode keep the wide proof.

The **full suite** is not the gate's job. With CI, branch protection carries it. Without CI — a committed `.claude/exloom-ci` of `none` — the gate asks for a `record-full-suite.sh` receipt before the push.

**A small change starts at `init`.** The spec, plan and drift steps need a plan to work against, and the Sprint lane and the bug-fix route skip them.
