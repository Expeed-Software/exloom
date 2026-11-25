---
name: auditing-plan-fidelity
description: Use after plan execution and before code review — compares the actual diff to the plan and produces a drift audit report.
---

# Auditing Plan Fidelity

Code review asks "is this code good?"; this audit asks "is this the code we planned?" The output is a report the code reviewer reads first.

## Inputs

Gather all four; if one is missing, stop and obtain it.

- **Spec** — the `F-nnn-*.md` that defines the acceptance criteria. Audit against the spec, not the plan's copy of it.
- **Plan** — with its "Files to Touch" list, its criteria refs (`F-012/R-3/AC-2`) and its Deviation Log. If a section is missing, proceed and flag the gap.
- **Diff range** — `git diff <base>...HEAD`, three dots. Find `<base>` with `git symbolic-ref refs/remotes/origin/HEAD`; never assume `main`. On a stacked branch, the base is the parent branch.
- **Deviation Log** — inside the plan. An empty log on a non-trivial plan is itself a signal.

## 1. Files

Put the plan's paths in `planned.txt`, one per line:

```bash
git diff --name-only <base>...HEAD | sort > actual.txt
sort planned.txt > planned-sorted.txt
comm -12 planned-sorted.txt actual.txt   # planned and changed
comm -23 planned-sorted.txt actual.txt   # planned, not changed
comm -13 planned-sorted.txt actual.txt   # changed, not planned
```

A planned file left unchanged, and a changed file that was not planned, each need a Deviation Log entry. Without one it is silent drift. Tests for planned source files are expected; an import reorder is noted, not flagged.

## 2. Acceptance criteria

Coverage, in both directions:

```bash
comm -23 <(grep -oE 'F-[0-9]+/R-[0-9]+/AC-[0-9]+' "$SPEC" | sort -u) \
         <(grep -oE 'F-[0-9]+/R-[0-9]+/AC-[0-9]+' "$PLAN" | sort -u)
```

A spec criterion no task cites is forgotten scope. A plan ref the spec does not define was invented. A task citing no ref is scope creep.

What the test run proved:

```bash
sed -n 's/.*"criteria":"\([^"]*\)".*/\1/p' .claude/reviews/<branch>.verdicts/proof.json | tail -1
```

That list holds only criteria whose test passed with the change and failed without it. A cited criterion missing from it has no test that notices it.

Then give each spec criterion one status, with evidence (file, function, assertion):

- **Verified** — the diff shows code or a test that meets it.
- **Unverified** — the diff cannot tell (performance, visual, runtime delivery). Name the test that would.
- **Deviated** — the diff contradicts it. Not logged means silent drift.

"Verified" without evidence is not a finding.

## 3. Deviation Log

For each entry: does it say what changed and why, is the reason one a teammate would accept in six months ("existing code uses pattern X", not "it seemed better"), and was it approved or left open? An executor's unlogged fix to a wrong plan is still silent improvisation.

## 4. Report

Post it as the first PR comment. Include every file and every criterion, quote log entries verbatim, and give one verdict.

```markdown
## Plan Fidelity Audit

**Spec:** <path> · **Plan:** <path> · **Diff range:** <range>

### File Audit
| File | Plan | Diff | Notes |
|---|---|---|---|

### Criteria coverage
| Direction | Result |
|---|---|
| Spec criteria with no task | |
| Plan refs not defined in the spec | |
| Tasks citing no criterion | |

### Acceptance Criteria
| Ref | Criterion | Status | Evidence |
|---|---|---|---|

### Deviation Log Review
| # | Deviation | Justification | Resolution |
|---|---|---|---|

### Verdict
```

- **Pass** — every planned file changed, nothing unlogged, every verifiable criterion confirmed.
- **Pass with notes** — some criteria Unverified or logged deviations worth attention; no blockers.
- **Fail** — any unlogged drift or a log entry without justification. List the blockers. Do not proceed to `/review-complete` on a Fail: the executor logs, reverts or completes, and the audit runs again from step 1.

A plan split across PRs: audit only the tasks this PR claims; the final PR is audited cumulatively. If the plan itself was wrong, route to `exloom:capturing-learnings`.

See [failure-modes.md](failure-modes.md) and [worked-example.md](worked-example.md).
