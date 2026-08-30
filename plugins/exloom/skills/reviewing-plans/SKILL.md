---
name: reviewing-plans
description: Use before handing off a plan to someone else — verifies the plan is unambiguous, complete, and executable by a non-author.
---

# Reviewing Plans

## Overview

This skill is the approval gate between plan authorship and plan execution. The central question it answers: "Can someone who doesn't know what the author was thinking execute this plan without ambiguity?" If the answer is anything other than an unqualified yes, the plan goes back to the author. There is no middle ground.

This skill also applies to self-review. Before you execute your own complex plan, run it through the full checklist — review it as if a stranger will execute it, because future-you (executing it next week without today's full context) is that stranger.

The review is deliberately not about whether the plan is a good idea. That question was settled during brainstorming and design. This review is strictly about executability: Is every section present? Is every criterion testable? Is every file path real? Can the executor finish the work without coming back to ask questions? That is the only bar. If you find yourself evaluating the technical approach rather than the plan's clarity, you have shifted into the wrong mode — refocus on executability.

## Process

### When to Use

**Always required:**
- Plan author and executor are different people. No exceptions. Run this before assigning the executor.
- Plan has been significantly revised after a previous rejection. Re-review from scratch — do not assume the fixes are correct.

**Strongly recommended:**
- Self-review of complex plans before solo execution (5+ tasks, external dependencies, or architectural decisions).
- Plans that cross team boundaries or affect shared infrastructure.
- Plans where the executor is less experienced with the relevant codebase or technology.

**Not needed:**
- Trivial changes with no written plan (single task, one file, obvious fix).
- Hotfixes with a clear rollback path where time pressure genuinely overrides thoroughness.
- Plans that were already reviewed and approved with no subsequent modifications.

If a written plan exists and work is about to start, this skill runs first. No exceptions.

### The Checklist

Work through all 9 items in order. Every item must pass for the plan to be approved. For each item below: what to check, how to check it, and what failure looks like.

**1. All required sections present**

Verify the plan contains every required section, in the template's order: Metadata, Goal, Acceptance Criteria, Files to Touch, Existing Patterns to Follow, Edge Cases, Non-Goals, Executor FAQ, **Tasks**, Review Checklist, and Deviation Log (empty at plan time). Compare section-by-section — do not skim. A missing section is an automatic reject. The Tasks section is the heart of the plan — a plan with no Tasks section has nothing to execute and fails item 1 immediately. Do not evaluate other checklist items until all sections are present.

How to check: Walk the section list above against the plan and confirm each section exists with substantive content — not just a heading with no body.

Failure looks like: The plan has no Edge Cases section, or the Executor FAQ heading exists but contains no questions.

**2. Acceptance criteria are observable and testable**

Each criterion must be independently verifiable by someone other than the author. Apply this test to every criterion: "Can I determine pass or fail without asking the author what they meant?"

How to check: Read each criterion and attempt to write a concrete verification step. If you cannot, the criterion is not testable.

Failure looks like: "The feature works correctly" (no observable condition). "Performance is acceptable" (no threshold). "Code is clean" (subjective). These all require the executor to interpret intent.

Passing looks like: "GET /api/products?page=2&size=20 returns items 21-40 with X-Total-Count header." "All existing tests pass with zero new failures." "Migration completes in under 30 seconds on a copy of production data."

**3. File paths are exact**

Every file in the "Files to Touch" section must be an exact relative path from the repository root. No directory names, no glob patterns, no placeholders. New files marked `[new]`, deleted files marked `[delete]`, everything else is a modification.

How to check: For each path, verify it looks like a real file path with a filename and extension. For existing files in a brownfield repo, confirm the path is plausible given the project structure. If possible, verify the files actually exist in the repository.

Failure looks like: "the auth module," "relevant service files," `src/services/**`, or any path containing "appropriate" or "relevant." Also reject paths that list only directories without specifying which files within them will change.

**4. Existing patterns referenced**

For brownfield work, the plan must cite which existing code to emulate. For each modified file, the plan should acknowledge the current pattern in that file and explain how the change fits it. If the plan introduces a new pattern, it must justify the deviation explicitly.

How to check: Look at the Existing Patterns to Follow section and the Files to Touch section. For each modification, ask: "Does the plan say what pattern currently exists and how this change continues it?"

Failure looks like: A brownfield repo where the Existing Patterns to Follow section describes the solution without mentioning any existing code. The plan proposes a repository pattern in a codebase that uses services — with no justification for the divergence.

**5. Edge cases enumerated**

Every non-happy-path scenario the executor might encounter must be listed. Each edge case must have a disposition: handled (with description), out of scope (with reason), or caller's responsibility (with upstream system named).

How to check: Read the edge cases section and mentally walk through failure modes. At minimum, probe for: null or empty inputs, concurrent execution, external service unavailability, large data sets, permission failures, partial failures, and rollback paths. If any obvious case is missing, that is a rejection item.

Failure looks like: No edge case section. An edge case section with only happy-path variations. Edge cases listed but with no handling disposition.

**6. Non-goals explicit**

The plan must state what it will NOT do. Non-goals prevent scope creep during execution and set clear boundaries for code review. Vague non-goals are insufficient — "other stuff is out of scope" tells the executor nothing.

How to check: Read the Non-Goals section. Each non-goal should be specific enough that the executor can recognize the boundary during implementation.

Failure looks like: "Out of scope" with no specifics. No Non-Goals section. Non-goals that are so broad they are meaningless ("We won't do anything not in this plan").

Passing looks like: "Cursor-based pagination is not included — only offset-based." "Mobile responsive layout is out of scope; desktop only." "Password reset flow is tracked in issue #214, not addressed here."

**7. Executor FAQ populated**

Read the plan as if you are the executor seeing it for the first time with zero prior context. Write down every question that comes to mind. Then check whether the FAQ section answers them.

How to check: Deliberately adopt the executor's perspective. Common questions to probe: "What if this file doesn't exist yet?" "Which environment do I target first?" "What's the expected behavior when this condition occurs?" "Is this dependency a blocker or can I proceed without it?" "Should I change the default configuration or leave it?"

Failure looks like: Empty FAQ section on any plan with more than one task. FAQ that only answers trivial questions while ignoring the hard ones. The executor would need to message the author within the first hour of work.

**8. Review checklist agreed**

The "Review Checklist" section defines what the code reviewer will verify after execution (in `exloom:reviewing-code`). It must be specific to this change, cover the acceptance criteria from item 2, name any security or performance concerns, and be short enough to actually use (5-10 items).

How to check: Cross-reference the review checklist against the acceptance criteria. Every criterion should map to at least one review checklist item. Generic items like "check for bugs" are not acceptable. The checklist should be actionable enough that a different reviewer could use it without additional context.

Failure looks like: No review checklist. A checklist with only "all tests pass." A checklist with 20 items (nobody will use it). A checklist that doesn't mention the acceptance criteria. A checklist that is copy-pasted from another plan without adaptation to this specific change.

**9. No TBDs or placeholders**

Search the entire plan text for placeholder markers: TBD, TODO, FIXME, ???, "fill in later," "to be determined." These are unambiguous — every occurrence is an automatic rejection item.

Then search for the soft-placeholder words: "later," "appropriate," "relevant," "as needed." These are NOT automatic rejections — they require in-context judgment. The word is a flag to inspect, not a verdict. "Call this hook later in the lifecycle" and "return the appropriate HTTP status (404 for missing, 409 for conflict)" are legitimate, specific prose — they pass. "Update the relevant service" and "add appropriate error handling" are placeholders for decisions the author did not make — they fail. Reject only when the word stands in for a specific name, value, or decision that is missing.

How to check: Search for the markers programmatically (the hard ones above are always rejections). For each soft-placeholder hit, read the surrounding sentence and ask: "Does this word hide a decision the executor will have to make?" If yes, reject. If the sentence is specific without the flagged word doing placeholder duty, it passes. Also check for softer placeholders: "we'll decide during implementation," "depends on what we find," or "the team will align on this" — these are always rejections.

Failure looks like: "Test file: TBD." "Approach: decide later whether to use Redis or Memcached." "Update the relevant configuration file." Each of these means the author deferred a decision that the executor will inherit as ambiguity. If a decision genuinely cannot be made yet, that is a blocker — execution should not start until the decision is resolved.

### Rejection and Approval

**Rejection:**

Any single checklist item failing means the plan is rejected. Partial approval does not exist — a plan is either executable or it is not.

**Why binary, and the one legitimate scoping.** The rigidity is deliberate: this is an approval *gate*, and a gate that says "mostly yes" is a gate that leaks ambiguity into execution. "Approve with reservations" reliably becomes "the executor hits the reservation and guesses." So the verdict is binary. The one thing that is *not* a violation of this rule is reviewing a **defined subset** of a plan — e.g., approving phase 1 of a 3-phase plan while phases 2-3 are still being written. That is not partial approval of a whole plan; it is full approval of a smaller, explicitly-scoped plan, with the out-of-scope tasks named in the approval note (see the mid-execution row in Decision Points). Scope can shrink; the bar within that scope cannot.

When rejecting, provide structured feedback:
1. State clearly: "Plan rejected — cannot proceed to execution."
2. List each failing item by number and name.
3. For each failure, quote the offending text and explain what is wrong.
4. Provide what "fixed" looks like — rewrite the failing element as a passing example.
5. Return to the author. Do not rewrite the plan yourself.

Rejection format:
```
Plan rejected — [N] items require attention before execution.

Item [#] ([Name]): "[quoted text from plan]" — [what's wrong].
Fixed: [concrete example of what passing looks like].
```

**Approval:**

When all 9 items pass:
1. Add an approval note in the plan: `<!-- Reviewed: [date] by [reviewer] — APPROVED -->`
2. Assign the executor and share the plan file path.
3. Executor confirms receipt and raises any final questions before starting — this is the last opportunity to catch ambiguity without writing code.

**Re-review after rejection:**

When a revised plan comes back, review all 9 items from scratch. Do not limit yourself to the items that previously failed. Revisions can introduce new problems — a rewritten acceptance criterion might be testable but no longer match the edge cases section. A new file path might invalidate the existing patterns section. Treat every re-review as a fresh review.

## Decision Points

| Situation | Decision |
|---|---|
| Plan is 90% good, one minor gap | Reject. The 10% gap is exactly where the executor will waste time. |
| Author says "they'll figure it out" | That is the definition of an unexecutable plan. Reject. |
| Plan references patterns you're unfamiliar with | Verify the referenced files exist. If they do, the pattern reference is valid even if you haven't read the files. |
| Edge case handling seems overkill | If the author documented it, it stays. You are reviewing executability, not scope. |
| Plan is for a tech stack you don't know | You can still review structure, completeness, and ambiguity. Stack expertise is not required for plan review. |
| Self-reviewing your own plan | Be harder on yourself than you would be on others. You have context they won't. Ask: "What would confuse someone reading this cold?" |
| Plan has been revised after rejection | Re-review from scratch. Do not assume the fixes are correct or that passing items still pass. |
| Disagreement about whether something is ambiguous | If you have to debate whether it's ambiguous, it's ambiguous. Reject and clarify. |
| Plan spans multiple repos or services | Verify interface contracts (API schemas, event formats, shared types) are explicitly documented. Each repo's changes must be independently deployable, or the plan must specify the exact deployment order. A cross-repo plan that does not name the contract between the repos is incomplete. |
| Plan depends on an external or third-party API | Verify the plan documents the API version, authentication method, rate limits, and fallback behavior when the service is unavailable. "Call the Stripe API" is insufficient — which endpoint, which version, what happens on timeout? |
| Reviewing a plan mid-execution (only some tasks done) | Scope the review to the subset of tasks being executed now. Mark the remaining tasks "not yet in scope for this review." State the scope boundary explicitly in the approval note so the next reviewer knows what was and was not covered. |

## Failure Modes

See [failure-modes.md](failure-modes.md).
## Worked Example

See [worked-example.md](worked-example.md).
## Integration

- You arrive here from: `exloom:planning-for-handoff` — the author requests review before handoff, or self-reviews before solo execution.
- You leave here toward: `exloom:executing-handoff-plans` — the executor picks up the approved plan and begins implementation.
- Plan structure: defined by `exloom:planning-for-handoff` (the skill that produces the plan); the section list in item 1 above is the standard every plan is measured against.
- If the plan needs fundamental rework (wrong approach, missing requirements, design-level issues): send back to `exloom:brainstorming`. That is a design problem, not a plan-writing problem.
- After execution completes: `exloom:auditing-plan-fidelity` checks whether the executor followed the approved plan or deviated.
- The review checklist agreed in item 8 feeds directly into `exloom:reviewing-code` — the code reviewer uses it as their primary verification list.
