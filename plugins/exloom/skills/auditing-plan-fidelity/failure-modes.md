# Failure Modes — auditing-plan-fidelity

The failure modes this skill exists to prevent: thought pattern, why it feels right, what actually happens, and the correction.

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
