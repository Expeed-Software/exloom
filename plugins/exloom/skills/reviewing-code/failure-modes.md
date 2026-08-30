# Failure Modes — reviewing-code

Extracted from SKILL.md so the skill loads lean. This is the failure modes this skill exists to prevent — thought pattern, why it feels right, what actually happens, and the correction.


These are the five most common ways reviews fail. Each one feels reasonable in the moment, which is exactly why they persist.

### 1. "Looks good to me" (LGTM without reading)

**Thought pattern:** "I trust this author. They know what they are doing. I will skim the diff and approve."

**Why it feels right:** The author has a good track record. The PR is from a senior engineer. You are busy with your own work.

**What happens:** The review catches nothing because it examined nothing. A subtle bug ships. When it surfaces in production, the review history shows an approval with no substantive comments, which undermines confidence in the entire review process.

**Correction:** Run every checklist category. If you genuinely cannot find issues after a thorough review, that is fine — approve and note what was done well. But "I looked and found nothing" is fundamentally different from "I did not look."

### 2. "Every comment is a blocker"

**Thought pattern:** "This code has problems and the author needs to fix all of them before merge."

**Why it feels right:** You care about quality. Every issue you found is real. Why would you not want them all fixed?

**What happens:** Authors stop taking your reviews seriously. When everything is critical, nothing is. The author cannot distinguish your actual blockers from your preferences, so they either fix everything resentfully or push back on everything defensively. Review cycles become adversarial.

**Correction:** Use severity ratings honestly. Ask yourself for each comment: "Would I block the merge over this alone?" If no, it is not a Blocker or Major. Your preferences are valid as Minor or Nit — they just should not block a merge.

### 3. "I would have done it differently"

**Thought pattern:** "This works, but I would have used a different pattern / library / structure. I should mention it."

**Why it feels right:** You have experience with an approach that you believe is better. Sharing knowledge is part of the review process.

**What happens:** The author receives feedback that amounts to "rewrite this my way" with no concrete problem identified. If the reviewer cannot articulate a specific issue (performance, correctness, maintainability, readability), the comment is a preference, not a finding.

**Correction:** Before commenting on an alternative approach, ask: "What concrete problem does the current approach cause?" If you cannot answer that, the comment is a Nit at best. Frame it as "Have you considered X? It might help with Y" rather than "This should be X."

### 4. "I will review the tests later"

**Thought pattern:** "Let me focus on the implementation first. I will circle back to the tests."

**Why it feels right:** The implementation is the "real" code. Tests are supporting artifacts. You want to understand the logic before evaluating the tests.

**What happens:** You never go back. Or you review the tests superficially because you have already spent your review energy on the implementation. The tests — which are the most important part of the review because they document intended behavior and catch regressions — get the least attention.

**Correction:** Review the tests as part of the same pass as the implementation, not as an afterthought — by default, before the implementation, so they frame your understanding. But scrutinize them rather than trusting them: confirm they assert real behavior, cover failure paths, and would actually catch a regression. The tests are the author's claim about correctness; your job is to verify the claim, not accept it.

### 5. "The PR is too big to review carefully"

**Thought pattern:** "This is 1500 lines. I will do my best to review it all."

**Why it feels right:** The author already wrote it. Asking them to split it feels like creating more work. You do not want to be the bottleneck.

**What happens:** You review the first 300 lines carefully and skim the rest. Critical issues in the later files are missed. The review provides a false sense of security — the approval suggests thorough review, but coverage was shallow.

**Correction:** Request a split. A 1500-line PR reviewed shallowly is worse than five 300-line PRs reviewed thoroughly. This is not about being difficult — it is about being honest that humans cannot maintain review quality over large diffs. The request to split is itself a valuable review comment. If the author says "it cannot be split," discuss it — most PRs can be split into a refactoring PR followed by a feature PR, or split by layer (data access, business logic, API surface).
