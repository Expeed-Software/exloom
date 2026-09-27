---
name: auditing-plan-fidelity
description: Use after plan execution and before code review — compares the actual diff to the plan and produces a drift audit report.
---

# Auditing Plan Fidelity

## Overview

Given a plan and the diff that claims to implement it, answer: was the plan followed, what deviated, and was every deviation justified and recorded? The output is a structured audit report — the first thing a code reviewer sees.

Runs between execution and code review. Code review asks "is this code good?"; this audit asks "is this the code we planned?" A high-deviation audit routes to `exloom:capturing-learnings` — it is a learning mechanism, not a punishment.

## Process

### Inputs

Gather all four. If any is missing, stop and obtain it.

**Spec file path.** The `F-nnn-*.md` the plan was built from. The spec *defines* the acceptance criteria; the plan only cites them. Audit against the spec — a criterion the spec states and the plan never picked up is absent from the plan by definition.

**Plan file path.** The executed plan, usually in `.claude/plans/` or similar. If unknown, check recent commits or ask the PR author. It must contain:
- A "Files to Touch" section listing every file to create, modify, or delete
- Criteria refs (`F-012/R-3/AC-2`) on its tasks, citing the spec
- A Deviation Log section (filled during `exloom:executing-handoff-plans`)

If a section is missing, proceed with what exists and flag the gap in the report. No "Files to Touch" makes Step 1 impossible. Tasks citing no criteria means you can audit spec criteria against the diff but not against the plan.

**Diff range.** The git range covering the full executed work. (Snippets here are bash — `sed`, `comm`, three-dot diff. On Windows run them in Git Bash; `comm` and `sed` do not exist in PowerShell.)

Detect the default branch — do not assume `main`:
```bash
# The default branch this repo's origin points at:
git symbolic-ref refs/remotes/origin/HEAD | sed 's@^refs/remotes/origin/@@'
```
If it fails with "not a symbolic ref" (fresh clones, most CI checkouts), populate it and retry:
```bash
git remote set-head origin --auto   # queries the remote and sets origin/HEAD
```
If the remote is unreachable, ask the PR author or read the PR's target (`gh pr view <N> --json baseRefName -q .baseRefName`). Substitute the resolved name for `<base>` below.

Typical commands:
```bash
git diff <base>...HEAD          # local branch vs base
gh pr diff <PR-number>          # PR diff via GitHub CLI (base is the PR's target)
git diff --stat <base>...HEAD   # summary view for initial orientation
```

Use three-dot (`...`), not two-dot (`..`) — two-dot pulls in base changes made after the branch was created. Three-dot stays correct after a rebase. If the branch has merge commits from the base, or is stacked on another feature branch, use `git diff $(git merge-base <base> HEAD)..HEAD`, with `<base>` set to the actual parent branch for a stacked branch.

**Deviation Log.** Inside the plan, populated during `exloom:executing-handoff-plans`. An empty log on a non-trivial plan is itself a signal — deviations more likely went unrecorded than never happened.

### Step 1: File Audit

Compare the plan's "Files to Touch" against the files changed:
```bash
git diff --name-only <base>...HEAD
```

Put every file in one bucket:

- **Planned + Changed (expected).** Verify the change type matches (modify vs. create vs. delete). A planned "modify" that was deleted and recreated is a deviation; a planned "create" of a file that already existed means the plan was stale — note it.
- **Planned + Unchanged (potentially missed).** Must have a Deviation Log entry explaining the skip; if not, flag it.
- **Unplanned + Changed (drift).** Logged with justification → note it. Not logged → flag as silent drift.

Record all three buckets, including expected. Watch path mismatches: `src/services/auth.ts` and `src/service/auth.ts` are different files — verify the real path.

Mechanize the comparison rather than eyeballing it. Put the plan's paths in a file, one per line:

```bash
# Save planned files (one path per line) to planned.txt, then:
git diff --name-only <base>...HEAD | sort > actual.txt
sort planned.txt > planned-sorted.txt

# Planned + Changed (expected) — appear in both:
comm -12 planned-sorted.txt actual.txt

# Planned + Unchanged (potentially missed) — in plan, not in diff:
comm -23 planned-sorted.txt actual.txt

# Unplanned + Changed (drift) — in diff, not in plan:
comm -13 planned-sorted.txt actual.txt
```

Every file `comm -13` prints needs a Deviation Log entry or it is silent drift.

### Step 2: Acceptance Criteria Verification

**First, run the coverage check in both directions.** It finds what is *absent*, which reading a list misses.

```bash
SPEC=docs/exloom/specs/F-012-slug.md
PLAN=docs/exloom/plans/....md
comm -23 <(grep -oE 'F-[0-9]+/R-[0-9]+/AC-[0-9]+' "$SPEC" | sort -u) \
         <(grep -oE 'F-[0-9]+/R-[0-9]+/AC-[0-9]+' "$PLAN" | sort -u)
```

- **Criteria in the spec that no task cites — forgotten scope.** Approved, never built, and invisible to every diff-based reviewer.
- **Refs in the plan that the spec does not define — a criterion invented at plan time.** Nobody approved it.
- **Tasks citing no ref at all — scope creep.** Work nobody asked for.

Report each as a finding with its ref.

**Then read what the test run actually proved:**

```bash
sed -n 's/.*"criteria":"\([^"]*\)".*/\1/p' .claude/reviews/<branch>.verdicts/proof.json | tail -1
```

`prove-change-is-tested.sh` writes that field from the runner's JUnit XML, counting only criteria whose test **passed with the change and did not pass without it**. A criterion the plan cites but this list omits has no test that notices it. The proof run also prints any criterion whose test passes against the base source — that test does not exercise the change, whatever its name says.

Then read each criterion from the **spec**, not the plan, and assign one status with cited evidence (file, function, test assertion, config):

- **Verified.** The diff shows code, test assertions, or config that meets it.
- **Unverified.** The diff alone cannot tell (performance, visual, runtime integration). State what manual test would resolve it.
- **Deviated.** The diff contradicts the criterion. Logged → note it; not logged → flag as silent drift on a criterion.

Unverified means missing information; Deviated means evidence of mismatch. Do not guess. "Verified" without evidence is not a finding.

Performance criteria are almost always Unverified — name the load test or monitoring check. Negative criteria ("does not expose internal IDs") are Unverified if multiple code paths could leak. Integration criteria: the call is verifiable, delivery needs runtime confirmation.

### Step 3: Deviation Log Review

For each logged deviation, evaluate:

- **Completeness.** Does it say what changed and why?
- **Justification quality.** "Existing codebase uses pattern X, so I followed it instead of Y" is justified. "It seemed better" is not.
- **Resolution.** Approved by the author, or left open for the reviewer?

Cross-reference Step 1: every Unplanned + Changed and every Planned + Unchanged file needs a log entry. Any gap is silent drift — the highest-severity finding, distinct from a logged deviation.

### Step 4: Produce Audit Report

Compile Steps 1-3 into the format below. Post it as the first PR comment, standalone (not in the PR description), before code review begins.

- Include every file and every criterion, not just flagged ones.
- Quote Deviation Log entries verbatim.
- State one verdict with a one-sentence justification. On Fail, list the blockers as actionable items.

## Audit Report Format

```markdown
## Plan Fidelity Audit

**Spec:** [path to spec file]
**Plan:** [path to plan file]
**Diff range:** [git diff range]
**Auditor:** [who ran this audit]
**Date:** [date]

### File Audit
| File | Plan Status | Diff Status | Notes |
|---|---|---|---|
| src/services/order.ts | Modify | Modified | As planned |
| src/services/payment.ts | — | Modified | NOT in plan — drift |
| tests/order.test.ts | Create | Created | As planned |
| src/utils/format.ts | Modify | Not changed | Planned but not touched |

### Criteria coverage
| Direction | Result |
|---|---|
| Spec criteria with no task | `F-012/R-4/AC-1` — forgotten scope |
| Plan refs not defined in the spec | none |
| Tasks citing no criterion | Task 7 (added a caching layer) — scope creep |

### Acceptance Criteria
| Ref | Criterion | Status | Evidence |
|---|---|---|---|
| F-012/R-1/AC-1 | Returns paginated results | Verified | Diff shows limit/offset in query |
| F-012/R-1/AC-2 | Total count in header | Deviated | Count is in response body, not header |
| F-012/R-2/AC-1 | Handles empty result set | Unverified | Needs runtime test with empty DB |
| F-012/R-4/AC-1 | Rejects a negative page size | **Not built** | No task cited it |

### Deviation Log Review
| # | Deviation | Justification | Resolution |
|---|---|---|---|
| 1 | Used .ts instead of .js | Existing codebase pattern | Resolved — approved |
| 2 | (unlisted) payment.ts changed | Not in deviation log | FLAGGED — silent drift |

### Verdict
- **Pass** — plan followed, all deviations logged and justified
- **Pass with notes** — minor drift, logged, acceptable
- **Fail** — significant unlogged deviations or unmet acceptance criteria
```

Use exactly one verdict line, followed by the deciding factors.

**Verdict definitions:**

- **Pass.** All planned files changed, no unrecorded deviations, all verifiable criteria confirmed, every log entry complete and justified.
- **Pass with notes.** Some criteria Unverified, or logged deviations worth attention, but no blockers.
- **Fail.** Any unlogged drift (unplanned file, deviated criterion, or skipped planned file), or a log entry missing justification. The author must update the log, revert unplanned changes, or finish missing work. Do not proceed to `/review-complete` on a Fail.

## Decision Points

| Situation | Decision |
|---|---|
| Small unplanned change (import reorder, formatting) | Note, do not flag as drift. Incidental changes are not deviations. |
| Deviation log justification is weak | Flag it. The bar: would a teammate reading it in 6 months understand why? |
| Everything matches perfectly | Re-check file lists and criteria counts before issuing Pass. |
| Plan was clearly wrong but executor fixed it | Was it logged? An unrecorded fix is still silent improvisation. |
| Multiple small drifts that individually seem harmless | Evaluate in aggregate. Several unlogged changes are a process failure even if the code is fine. |
| Plan has no "Files to Touch" section | Skip Step 1, note it, audit criteria and log. Recommend the plan template require file lists. |
| Executor says "I updated the plan as I went" | Check the plan file's git history. Edits after execution started, without the author's agreement, mean the plan no longer reflects what was approved. Flag it. |
| Test files were added that are not in the plan | Tests for planned source files are expected. Tests for unplanned source files are drift. |
| Plan is split across a stack of PRs (PR 2 of 3) | Audit only the tasks this PR claims, using this PR's diff (`gh pr diff <N>`). State which tasks are in scope and which remain. Cross-PR criteria are "Unverified — completes in PR 3." |
| Auditing the final PR of a multi-PR plan | Audit cumulatively (`git diff <base-before-PR1>...HEAD`): every planned file touched, every criterion met across the combined work. |

## Failure Modes

See [failure-modes.md](failure-modes.md).

## Worked Example

See [worked-example.md](worked-example.md).

## Integration

**Timing.** A gate: after execution is marked complete, before `/review-complete` dispatches the reviewers. Ideally the PR author runs it before requesting review; otherwise the reviewer, first.

**On Fail.** The executor updates the log, reverts unplanned changes, or completes missed work, then re-audits from Step 1 — never partially. A second Fail: escalate to the team lead or route to `exloom:capturing-learnings`.

**If the plan was wrong.** Route to `exloom:capturing-learnings` so the gap feeds back into plan templates and estimation.

**Related skills:**
- `exloom:planning-for-handoff` — produces the plan this skill audits against
- `exloom:executing-handoff-plans` — execution produces the Deviation Log this skill reviews
- `exloom:review-gate` — the downstream gate; runs after this skill passes
- `exloom:capturing-learnings` — destination when audit reveals systemic plan weaknesses

**Workflow sequence:**
```
planning-for-handoff → executing-handoff-plans → auditing-plan-fidelity → /review-complete
                                               ↓ (on fail)
                                         executor fixes → re-audit
                                               ↓ (if the plan was wrong)
                                         capturing-learnings
```
