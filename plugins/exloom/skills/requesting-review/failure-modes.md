# Failure Modes — requesting-review

Extracted from SKILL.md so the skill loads lean. This is the failure modes this skill exists to prevent — thought pattern, why it feels right, what actually happens, and the correction.


These are the patterns that consistently produce bad PRs. Each one feels reasonable in the moment — that is why they persist.


### 1. "The diff speaks for itself"

**Thought pattern:** The code is clean and well-named. A good reviewer can understand the change by reading it.

**Why it feels right:** You just spent hours making the code clear. Of course it communicates the intent — you can see it plainly.

**What actually happens:** The reviewer sees what changed but not why. They cannot evaluate whether the approach is correct without understanding the problem. They review surface-level concerns — formatting, naming, style — because that is all they have context for. The architectural question (should this have been a queue instead of synchronous?) never gets asked because the reviewer does not know the constraints.

**Correction:** Code shows what changed. The PR body explains why and what alternatives were considered. Both are necessary. Neither substitutes for the other. A two-sentence "Why" and a two-sentence "How" would have given the reviewer enough to ask the right question.

### 2. "Tests pass"

**Thought pattern:** The tests are green. That is proof the change works. Writing the exact command output is just ceremony.

**Why it feels right:** You ran the tests. They passed. What more is there to say?

**What actually happens:** The reviewer has no way to verify what was tested, how much coverage exists, or whether the right tests ran. "Tests pass" after a database migration change could mean the unit tests passed (which do not touch the database) while the integration tests were never run. Without the actual command and output, the reviewer cannot distinguish thorough verification from shallow verification.

**Correction:** Paste the command, exit code, and result counts. `./mvnw verify` exiting 0 with "142 passed, 0 failed" is evidence. "Tests pass" is an assertion. Reviewers should evaluate evidence, not trust assertions. The verification step already produced this output — copying it into the PR body takes seconds.

### 3. "I deviated but it's obviously better"

**Thought pattern:** The plan said to use approach X, but approach Y is clearly superior. The improvement is self-evident, so documenting the deviation would be pedantic.

**Why it feels right:** You are the person closest to the implementation. You discovered something during development that the planner did not foresee. The change is obviously an improvement.

**What actually happens:** The reviewer who read the plan expects approach X. They find approach Y and do not know if the deviation was intentional (a deliberate improvement), accidental (you forgot the plan said X), or a sign of deeper confusion about the requirements. They now have to ask, adding a review cycle. Worse — if they do not notice the deviation, the plan and the code silently diverge, and future work based on the plan will be wrong.

**Correction:** Document every deviation with the justification. If the improvement is truly obvious, the documentation takes one sentence. The cost of documenting is trivial. The cost of not documenting is a reviewer who cannot trust the implementation matches the plan.

### 4. "I'll fill in the PR body later"

**Thought pattern:** The code is ready. Get the PR open so the reviewer can start. Fill in the details after.

**Why it feels right:** Speed. The reviewer can begin looking at the diff while you write up the body. Parallel work.

**What actually happens:** The reviewer opens the PR, sees an empty or placeholder body, and does one of two things: waits (adding delay) or starts without context (producing a shallow review). Most commonly, "later" never comes — the PR gets approved based on the diff alone, and the body stays empty. The next person who needs to understand this change (during an incident, during onboarding, during a related feature) finds nothing.

**Correction:** The PR body IS the review request. An empty body says "I don't respect your time enough to explain what I did." Write the body before opening the PR. If you cannot explain the change in writing, you may not fully understand it yet — and that is valuable information. The act of writing the summary often surfaces gaps in your own understanding — which is exactly the point.

---
