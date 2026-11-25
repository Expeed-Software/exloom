---
name: harden
description: Promote the current branch to a stricter lane (Sprint to Standard, or Standard to Certified) when a spike turned out to matter. Recovers the spec from the diff and names what the higher bar requires; nothing is regenerated.
---

# /harden

Promote the branch one lane up when a spike turned out to matter. Code, receipts and history stay; the steps the lighter lane skipped are now done against working software. It only raises: never demote, and never promote to get past a block.

1. **Read `**Lane:**`** in `.claude/reviews/<branch>.md`, else the committed `.claude/exloom-lane`, else `standard`. `sprint` goes to `standard`; `standard` goes to `certified`; `certified` has nowhere to go. Before Certified, confirm with the user: a recorded escape hatch then blocks the push, and commits must be signed.
2. **Write the spec that was never written.** Read `git diff <merge-base>...HEAD` and invoke `exloom:brainstorming` to record what was built: the problem, the approach, the edge cases handled and those not. Do not describe intentions the code does not have, and do not change the code while writing it: gaps become review findings or tickets.
3. **Change the lane** and commit it alone: `chore(review): harden <branch> from <old-lane> to <new-lane>`.
4. **Run `/exloom`**, which names what the new lane still needs. From Sprint that is the adversarial review and cross-layer check at Tier 2+, the security review at Tier 3 or where the surface demands it, and `exloom:auditing-plan-fidelity` against the recovered spec. For Certified, every recorded escape hatch is resolved, not justified, and the checklist commit is signed.
5. **Tell the user** the old and new lane, where the spec is, and what is now required and missing.

The tier is untouched; it is derived from the diff.
