# Severity Calibration — reviewing-code

Extracted from SKILL.md so the skill loads lean.


Every review comment must include a severity. This is a requirement of your org's review process, not a suggestion — untagged comments force authors to guess whether they need to act.

### Blocker

**Definition:** Merging this will cause a production incident, data loss, security vulnerability, or break existing functionality for users.

**Examples:**
- SQL injection via unsanitized user input in a query
- Authentication bypass — endpoint missing auth middleware
- Infinite loop triggered by a common input
- Data corruption — writing to the wrong table or overwriting existing records
- Breaking change to a public API with no migration path

**Action:** Request Changes. Author MUST fix before merge. No exceptions.

**Not a Blocker:** A style disagreement is never a blocker. An alternative approach that is equally correct is not a blocker. A missing optimization for a code path that handles 10 requests per day is not a blocker. A convention violation, even an important one, is Major at most — conventions are about consistency, not about preventing outages.

### Major

**Definition:** Significant quality issue that will cause real problems — not immediately catastrophic, but bad enough that it should not ship as-is.

**Examples:**
- Missing error handling for a failure mode that will realistically occur (e.g., network timeout on an external call)
- Untested critical path — a new payment flow with no test coverage
- N+1 query pattern in a code path that handles realistic production load
- Convention violation that will actively confuse future developers (e.g., error responses that don't match the standard envelope)
- Missing database migration for a schema change

**Action:** Request Changes. Author should fix.

**Not a Major:** An unlikely edge case that would require adversarial input is not a major unless it is a security vector. A style preference is not a major. A slightly unclear variable name is not a major — that is Minor at most.

### Minor

**Definition:** Worth fixing if easy, but not worth blocking the PR. The code works correctly; this is about making it better.

**Examples:**
- Variable name that is technically accurate but could be clearer
- Missing test for an unlikely edge case
- Style inconsistency with the rest of the file
- A comment that would help future readers understand non-obvious logic
- Missed opportunity to use an existing shared utility

**Action:** Approve with comment. Author decides whether to address it. Respect their judgment.

### Nit

**Definition:** Optional. Author's call entirely. Purely stylistic or preference-level.

**Examples:**
- Formatting preference within the bounds of the style guide
- Synonym preference in a variable name ("fetch" vs. "retrieve")
- Removing a blank line or reordering imports
- An alternative approach that is equally valid

**Action:** Approve with comment. Prefix with "Nit:" so the author knows immediately. Never request changes for a Nit.

**Not a Nit:** If the alternative approach would prevent a real problem, it is Minor or Major, not Nit. Nit is reserved for genuinely equivalent alternatives.

### Calibration Rule

If you are about to mark something Major and the author pushes back, ask yourself honestly: "Would I block this PR over this single item?" If the answer is no, it is Minor, not Major. Severity is about merge decisions, not about how strongly you feel. If you would not actually block the merge, do not use a severity that blocks the merge.

A second calibration check: count your Blockers and Majors. If a 200-line PR has more than 2-3 blocking items, either the code has fundamental problems that warrant a conversation (not 15 inline comments), or you are over-calibrating severity. Step back and ask whether a higher-level comment would be more effective than annotating every line.
