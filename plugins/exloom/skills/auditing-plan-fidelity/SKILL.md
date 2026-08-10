---
name: auditing-plan-fidelity
description: Use after plan execution and before code review — compares the actual diff to the plan and produces a drift audit report.
---

# Auditing Plan Fidelity

## Overview

Given a plan and the git diff of the work that claims to implement it, this skill answers: was the plan followed? What deviated? Was every deviation justified and recorded? The output is a structured audit report that becomes the first artifact a code reviewer sees before reading a single line of code.

This skill runs between execution and code review. It separates "is this code good?" (code review) from "is this the code we planned?" (this audit). A high-deviation audit is a signal to route to `exloom:capturing-learnings` — it is a learning mechanism, not a punishment mechanism.

## Process

### Inputs

Before running the audit, gather three artifacts. All three are required. If any is missing, stop and obtain it before proceeding — an audit with incomplete inputs produces incomplete results.

**Plan file path.** The `.md` plan file as approved by `exloom:reviewing-plans`. Usually in `.claude/plans/` or a similar location. If the path is unknown, check recent commits for the plan file or ask the PR author. The plan must contain at minimum:
- A "Files to Touch" section listing every file expected to be created, modified, or deleted
- Acceptance criteria — the testable conditions that define "done"
- A Deviation Log section (filled during `exloom:executing-handoff-plans`)

If the plan lacks any of these sections, note it in the audit report. A plan without a "Files to Touch" section makes Step 1 impossible. A plan without acceptance criteria makes Step 2 impossible. Proceed with whatever sections exist and flag the gaps.

**Diff range.** The git range covering the full scope of the executed work. (The shell snippets in this skill are bash — `sed`, `comm`, three-dot diff. On Windows, run them in Git Bash, which ships with Git; `comm` and `sed` do not exist in PowerShell. The git commands themselves are identical in any shell.)

First, determine the repository's default branch — do not assume it is `main`. It may be `master`, `develop`, or something else. Detect it:
```bash
# The default branch this repo's origin points at:
git symbolic-ref refs/remotes/origin/HEAD | sed 's@^refs/remotes/origin/@@'
```
This fails with "not a symbolic ref" on fresh clones and most CI checkouts, where `origin/HEAD` is not set. If it does, populate it first, then retry:
```bash
git remote set-head origin --auto   # queries the remote and sets origin/HEAD
```
If you cannot reach the remote (offline, restricted CI), fall back to asking the PR author or reading the target branch from the PR metadata (`gh pr view <N> --json baseRefName -q .baseRefName`). In the commands below, substitute the resolved name wherever `<base>` appears — do not just assume `main`.

Typical commands:
```bash
git diff <base>...HEAD          # local branch vs base
gh pr diff <PR-number>          # PR diff via GitHub CLI (base is the PR's target)
git diff --stat <base>...HEAD   # summary view for initial orientation
```

Use the three-dot (`...`) syntax, not two-dot (`..`). Three-dot shows changes since the branch diverged from the base, which is what the plan covers. Two-dot includes changes to the base that happened after the branch was created, which pollutes the audit with unrelated files.

If the branch has been rebased onto the base recently, the three-dot diff is still correct — it shows only the branch's own changes. If the branch has merge commits from the base, or is stacked on another feature branch rather than the default branch, use `git diff $(git merge-base <base> HEAD)..HEAD` to isolate branch-only changes — and set `<base>` to the actual parent branch, not the repo default, for a stacked branch.

**Deviation Log.** Located inside the plan file, populated by the executor during `exloom:executing-handoff-plans`. If the Deviation Log section is empty, that is itself an audit signal — either execution was perfectly on-plan (rare) or deviations went unrecorded (common). An empty log on a non-trivial plan should raise your suspicion, not lower it.

### Step 1: File Audit

Compare the plan's "Files to Touch" list against the files actually changed in the diff.

Extract the planned file list from the plan. Then extract the actual changed files (`<base>` = the repo's default or parent branch detected above):
```bash
git diff --name-only <base>...HEAD
```

Compare the two lists line by line and categorize every file into one of three buckets:

- **Planned + Changed (expected).** The file appears in the plan and in the diff. This is the normal case. No flag needed, but verify the nature of the change matches the plan's intent (modify vs. create vs. delete).
- **Planned + Unchanged (potentially missed).** The file appears in the plan but not in the diff. This could mean the task was intentionally skipped (should be in the Deviation Log) or was accidentally missed. If not logged, flag it.
- **Unplanned + Changed (drift).** The file appears in the diff but not in the plan. This is what the audit exists to catch. Check the Deviation Log — if the change is logged with justification, note it. If not logged, flag it as silent drift.

Record all three categories for the audit report. Do not skip the "expected" category — it confirms the plan was substantively followed and gives the reviewer confidence in the audit's thoroughness.

For files in the "expected" category, also verify the type of change matches the plan. If the plan said "modify `src/config.ts`" but the diff shows the file was deleted and recreated, that is a deviation even though the file appears in both lists. Similarly, if the plan said "create" but the file already existed and was modified, the plan was based on stale assumptions — note it.

Pay attention to file paths. A plan that says `src/services/auth.ts` and a diff that shows `src/service/auth.ts` (singular) are different files. Path mismatches are easy to miss and indicate either a plan typo or a structural deviation. When in doubt, verify the actual filesystem path.

**Automating the three-bucket comparison.** Eyeballing two file lists is error-prone — auditors miss files, especially on large diffs. Mechanize it. Put the plan's "Files to Touch" paths in a file (one per line) and compare against the actual diff:

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

The third bucket — `comm -13` — is the drift list. Every file it prints must have a Deviation Log entry or it is silent drift. This three-command check catches what manual comparison misses and takes 30 seconds.

### Step 2: Acceptance Criteria Verification

Read each acceptance criterion from the plan. For every criterion, assign one of three statuses:

- **Verified.** You can see evidence in the diff that the criterion is met. This includes: code that directly implements the behavior, test assertions that validate it, configuration that enables it. Cite the specific file and change as evidence.
- **Unverified.** You cannot determine from the diff alone whether the criterion is met. This is common for performance criteria, visual requirements, or integration behaviors that require a running system. Note what needs to be manually tested and where.
- **Deviated.** The implementation does not match the specification. The criterion says one thing; the diff shows another. Check the Deviation Log — if the deviation is logged, note it. If not, flag it as silent drift on a criterion.

Do not conflate "Unverified" with "Deviated." Unverified means you lack information. Deviated means you have evidence of a mismatch. Do not guess — if you cannot tell, mark it Unverified and specify what manual test would resolve it.

For each criterion, cite specific evidence. "Verified" without evidence is an assertion, not an audit finding. Point to the file, the function, the test assertion, or the configuration change that demonstrates the criterion is met. This specificity is what makes the audit useful to the reviewer — they can go directly to the cited location instead of searching the entire diff.

Common acceptance criteria patterns and how to handle them:
- **Behavioral criteria** ("returns 404 when not found"): look for the response code in route handlers and test assertions. Usually verifiable.
- **Performance criteria** ("P95 latency under 200ms"): almost always Unverified from diff alone. Note what load test or monitoring check would confirm it.
- **Negative criteria** ("does not expose internal IDs"): look for the absence of the field in response serializers. Verifiable if you can confirm the serializer excludes it, but fragile — mark as Unverified if there are multiple code paths.
- **Integration criteria** ("sends email on signup"): look for the integration call in the diff. Verifiable if the call is present, but actual delivery needs runtime confirmation.

### Step 3: Deviation Log Review

Read the plan's Deviation Log section. This was populated by the executor during `exloom:executing-handoff-plans`. For each logged deviation, evaluate:

- **Completeness.** Does the entry describe what changed and why? An entry that says "used a different approach" without explaining the reason is incomplete.
- **Justification quality.** Was the deviation a justified response to a discovery during implementation? "Existing codebase uses pattern X, so I followed it instead of the planned pattern Y" is justified. "It seemed better" is not.
- **Resolution.** Was the deviation resolved (approved by the author as acceptable) or left open for reviewer decision?

Then look for unlisted deviations: files changed that are not in the plan AND not in the Deviation Log. These are silent improvisations — the most important finding an audit can produce. Silent drift means the executor changed scope without recording it, and the team's shared understanding of the work is now inaccurate.

Cross-reference Step 1's "Unplanned + Changed" files against the Deviation Log entries. Every unplanned file should have a corresponding log entry. Every "Planned + Unchanged" file should also have an entry explaining why it was skipped. Any gap between the file audit and the deviation log is a finding.

Silent drift is the highest-severity finding. This is different from a logged deviation, which is a deliberate, transparent decision.

### Step 4: Produce Audit Report

Compile all findings from Steps 1-3 into the structured format below. Post the report as a PR comment before code review begins — not inline in the PR description, but as a separate comment so it is distinguishable from author-provided context. The report is the reviewer's entry point into the PR.

When producing the report:
- Include every file from the file audit, not just the flagged ones. The "expected" entries demonstrate thoroughness.
- Include every acceptance criterion, not just the failed ones. A complete list lets the reviewer see scope at a glance.
- Quote deviation log entries verbatim. Do not paraphrase — the reviewer needs the executor's exact words to evaluate justification quality.
- State the verdict clearly with a one-sentence justification. If the verdict is Fail, list the specific blockers as actionable items.

## Audit Report Format

```markdown
## Plan Fidelity Audit

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

### Acceptance Criteria
| # | Criterion | Status | Evidence |
|---|---|---|---|
| 1 | Returns paginated results | Verified | Diff shows limit/offset in query |
| 2 | Total count in header | Deviated | Count is in response body, not header |
| 3 | Handles empty result set | Unverified | Needs runtime test with empty DB |

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

Use exactly one verdict line, not all three. The three options above are the possible values — pick the one that fits. Include a brief justification after the verdict explaining the deciding factors.

**Verdict definitions:**

- **Pass.** All planned files were changed. No unrecorded deviations exist. All verifiable acceptance criteria are confirmed. Every deviation log entry is complete and justified. The reviewer can proceed to code review immediately with full confidence that the plan was followed.

- **Pass with notes.** One or more acceptance criteria are "Unverified" (requiring manual testing), or deviation log entries exist that the reviewer should be aware of, but there are no blockers. Minor logged deviations that do not affect the plan's core intent fall here. The reviewer proceeds with specific items flagged for attention.

- **Fail.** One or more of the following conditions exist: files changed but not in plan AND not in Deviation Log; acceptance criteria deviated AND not in Deviation Log; Deviation Log entries incomplete (missing justification); files in plan not changed AND not in Deviation Log. A Fail means the PR author must update the Deviation Log, revert unplanned changes, or complete missing work before code review begins. Do not proceed to `exloom:reviewing-code` on a Fail verdict.

## Decision Points

| Situation | Decision |
|---|---|
| Small unplanned change (import reorder, formatting) | Note but do not flag as drift. Incidental changes are not deviations. They are mechanical consequences of touching nearby code. |
| Unplanned file changed with real logic changes | Flag as drift. This is what the audit exists to catch. Logic changes in unplanned files mean scope expanded without agreement. |
| Planned file not changed | Could be intentional (task was unnecessary) or missed. Check the Deviation Log. If not logged, flag it. |
| Acceptance criterion cannot be verified from diff alone | Mark as "Unverified — needs manual testing." Do not guess. Specify what test would resolve it. |
| Deviation log has a deviation but justification is weak | Flag it. "It seemed better" is not a justification. "Existing pattern required X because of Y" is. The bar is: would a teammate reading this in 6 months understand why? |
| Everything matches perfectly | Rare but possible. Verify you did not miss anything — re-check the file lists and criteria counts before issuing a Pass verdict. |
| Plan was clearly wrong but executor fixed it | Good judgment by the executor — but was it logged? Fixing a bad plan step without recording it is still silent improvisation. The deviation log exists for exactly this case. |
| Multiple small drifts that individually seem harmless | Evaluate in aggregate. Five "harmless" unlogged changes suggest a pattern of not logging, which is a process failure even if the code is fine. |
| Plan has no "Files to Touch" section | You cannot run Step 1. Note this in the report. Audit what you can (acceptance criteria, deviation log). Recommend the plan template be updated to require file lists. |
| Executor says "I updated the plan as I went" | Check git history of the plan file. If the plan was modified after execution started without going through `exloom:reviewing-plans` again, the plan no longer represents what the team agreed to. Flag it. |
| Test files were added that are not in the plan | Test files that directly correspond to planned source files are expected even if not explicitly listed. Test files for unplanned source files are drift — they indicate scope expansion. |
| Plan is split across a stack of PRs (PR 2 of 3) | Audit only the tasks the current PR claims to implement, not the whole plan. Use the diff range for THIS PR (`gh pr diff <N>`), not the cumulative branch diff. State in the report which plan tasks are in scope for this PR and which remain for later PRs. Acceptance criteria that span PRs are marked "Unverified — completes in PR 3." |
| Auditing the final PR of a multi-PR plan | Now audit cumulative fidelity. Use the full diff range across all merged PRs (`git diff <base-before-PR1>...HEAD`) to confirm every planned file was eventually touched and every acceptance criterion is met across the combined work. The last audit is where you catch a task that fell through the cracks between PRs. |

## Failure Modes

These are the most common ways auditors get the audit wrong. Each follows the same pattern: a plausible-sounding shortcut that undermines the audit's purpose.

**1. "The diff is small, the plan was followed."**
The thought pattern is: small diff means small scope means nothing could have drifted. This feels right because volume is a proxy for complexity. But small diffs can hide significant deviations. A one-line change in an unplanned file is drift. A missing file that was supposed to be created is an unmet criterion. Audit systematically by comparing lists, not by estimating risk from diff size. Correction: run every step regardless of diff size. The steps are fast on small diffs anyway.

**2. "The executor is experienced, I trust them."**
The thought pattern is: senior developers do not need auditing. This feels right because experienced developers generally make good decisions. But the audit does not exist because developers are untrustworthy — it exists because memory is unreliable and context is lossy. An experienced developer who improvised a better solution still needs to record it. Trust the process, not the person. Correction: apply the same audit steps regardless of who executed the plan.

**3. "These extra files were obviously necessary."**
The thought pattern is: the unplanned file changes are self-evidently required. This feels right because developers reading the diff can see why a utility file or config change was needed. But obvious to the auditor now is not obvious to the team later. If the changes were necessary, they should have been in the plan or the deviation log. Unlogged changes erode the plan-as-contract model even when the changes are correct. Correction: flag every unplanned+unlogged change. Let the executor add it to the deviation log — that takes 30 seconds and preserves the record.

**4. "The acceptance criteria are mostly met."**
The thought pattern is: 4 out of 5 criteria met is close enough. This feels right because partial credit is how most things work. But "mostly met" is a precise statement: it means at least one criterion is deviated. A deviated criterion that is not logged is silent drift on a requirement the team agreed to. Partial completion is fine — but it must be explicit. Correction: mark each criterion individually. If one is deviated, the verdict depends on whether it was logged, not on the percentage met.

**5. "Auditing takes too long for this small change."**
The thought pattern is: the overhead of a formal audit is not justified for a 3-file change. This feels right because process should be proportional to risk. But if the plan was small, the audit is fast — a 3-file plan audits in under 2 minutes. If the audit reveals drift even on a small change, that is exactly the kind of silent deviation that compounds across a codebase. Correction: run the audit. If it takes less than 5 minutes, the overhead argument does not hold. If the plan was so small it did not need a plan, the audit is moot — but that is a planning question, not an auditing one.

## Worked Example

**Scenario:** Auditing the plan for "Add rate limiting to the payments API" (Node.js Express backend) after execution. The plan was approved via `exloom:reviewing-plans`, specified 4 files in its "Files to Touch" section, listed 3 acceptance criteria, and was executed on the `feature/rate-limiting` branch. The executor ran `exloom:executing-handoff-plans` and populated the Deviation Log with 2 entries.

We will walk through all 4 audit steps and arrive at a verdict.

### Step 1: File Audit

Plan's "Files to Touch" listed:
- `src/middleware/rate-limiter.ts` [new]
- `src/routes/payments.ts` (modify — wire middleware)
- `src/config/app-config.ts` (modify — add rate limit settings)
- `tests/middleware/rate-limiter.test.ts` [new]

Actual files changed (`git diff --name-only <base>...HEAD`, where `<base>` resolved to `main` for this repo):
- `src/middleware/rate-limiter.ts` (new)
- `src/routes/payments.ts` (modified)
- `src/config/app-config.ts` (modified)
- `src/config/rate-limits.ts` (new) — NOT in plan
- `tests/middleware/rate-limiter.test.ts` (new)

Categorization:
- `src/middleware/rate-limiter.ts` — Planned [new] + Created = **expected**
- `src/routes/payments.ts` — Planned [modify] + Modified = **expected**
- `src/config/app-config.ts` — Planned [modify] + Modified = **expected**
- `tests/middleware/rate-limiter.test.ts` — Planned [new] + Created = **expected**
- `src/config/rate-limits.ts` — NOT in plan + Created = **drift**

Result: 4 files planned+changed (expected). 0 files planned+unchanged. 1 file unplanned+changed (drift). Check deviation log for the unplanned file: Deviation #1 says "Extracted rate limit constants to dedicated config file for reusability across future endpoints." Logged and justified — this drift is accounted for.

### Step 2: Acceptance Criteria Verification

Criterion 1: "Rate limiting returns HTTP 429 when threshold exceeded."
Status: **Verified.** Diff shows `rate-limiter.ts` returns `res.status(429).json({ error: 'Rate limit exceeded' })`. Test file includes assertion for 429 response.

Criterion 2: "Rate limit state uses Redis for multi-instance support."
Status: **Deviated.** Diff shows rate limiter uses an in-memory `Map` with TTL, not Redis. Check deviation log: not logged. This is silent drift on a core acceptance criterion.

Criterion 3: "Rate limit window resets after 60 seconds."
Status: **Unverified.** The diff shows a `windowMs: 60000` config value, which suggests 60-second windows, but actual reset behavior depends on runtime timing. Needs manual test with timed requests.

### Step 3: Deviation Log Review

The executor's deviation log contains 2 entries:
- Deviation #1: "Extracted rate limit config to `src/config/rate-limits.ts`." Justification: "Keeps rate limit constants separate for reuse when we add rate limiting to other endpoints." Complete and justified.
- Deviation #2: "Used TypeScript strict mode for new files." Justification: "Existing `tsconfig.json` has strict enabled; new files follow existing convention." Complete and justified.

Missing: the Redis-to-memory change is not in the deviation log. This is a significant unlogged deviation — it affects a core acceptance criterion (multi-instance support) and changes the operational characteristics of the feature.

### Step 4: Verdict

**FAIL.** One unlogged deviation: acceptance criterion #2 (Redis for multi-instance support) was silently changed to in-memory storage. This affects production behavior and was not recorded.

Blockers before code review can proceed:
1. The executor must add a deviation log entry explaining why Redis was dropped and what triggered the decision during implementation.
2. The team must confirm whether in-memory rate limiting is acceptable for the deployment topology (single instance vs. multi-instance).
3. If in-memory is not acceptable, the executor must implement Redis as originally planned.
4. Re-run this audit after the deviation log is updated or the implementation is corrected.

Note what a Pass would have looked like here: if the executor had logged "Dropped Redis in favor of in-memory Map because the staging environment has no Redis instance and the rate limiter needs to work in local dev. Will revisit for production multi-instance deployment," that would be a complete deviation log entry. The verdict would shift to Pass with notes, and the reviewer would know to evaluate the tradeoff rather than discovering it by accident in the diff.

## Integration

**Timing.** Run this audit after the executor marks execution complete and before any code review begins. The audit is a gate — it determines whether the PR is ready for review or needs corrections first.

**You arrive here from:** execution complete, before `exloom:reviewing-code`. The executor has finished implementing the plan and the branch is ready for review.

**Audit report placement:** post the report as the first comment on the PR, before any code review comments. This gives the reviewer full context before they read a single line of code. The report should be a standalone comment, not embedded in the PR description — the PR description belongs to the author, and the audit report belongs to the auditor. Keeping them separate preserves accountability.

**Who runs the audit:** ideally the PR author runs this before requesting review, so blockers are resolved proactively. If the author did not run it, the reviewer runs it as their first step. Either way, the audit must exist before code review comments begin.

**If audit fails:** the executor addresses the issues — either by updating the deviation log with justifications, reverting unplanned changes, or completing missed work. Then re-audit. Do not proceed to code review on a failed audit.

**If audit reveals the plan was wrong:** route to `exloom:capturing-learnings`. A plan that was correct at approval time but wrong at execution time means the planning process missed something — an unknown dependency, a misunderstood API, an incorrect assumption about the codebase. This is a learning opportunity, not a failure of execution. The learning should feed back into plan templates and estimation practices.

**Re-audit workflow:** when an audit fails and the executor makes corrections, run the full audit again from Step 1. Do not partially re-audit — the corrections may have introduced new changes that need evaluation. A re-audit is fast because most findings will now be resolved. If the re-audit also fails, the pattern suggests a deeper issue — the executor may not understand the audit expectations, or the plan may need revision. Escalate to the team lead or route to `exloom:capturing-learnings`.

**Related skills:**
- `exloom:reviewing-plans` — the upstream gate; plan must be approved before execution begins
- `exloom:executing-handoff-plans` — execution produces the Deviation Log this skill reviews
- `exloom:reviewing-code` — the downstream gate; runs after this skill passes
- `exloom:capturing-learnings` — destination when audit reveals systemic plan weaknesses

**Workflow sequence:**
```
reviewing-plans → executing-handoff-plans → auditing-plan-fidelity → reviewing-code
                                          ↓ (on fail)
                                    executor fixes → re-audit
                                          ↓ (if plan was wrong)
                                    capturing-learnings
```
