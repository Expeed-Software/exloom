# Handling Disagreements — reviewing-code

Extracted from SKILL.md so the skill loads lean.


Disagreements during code review are normal. Handle them as follows:

**Author pushes back on a Blocker** — A Blocker requires evidence, not authority. If the author disagrees that it is a production risk, discuss the specific scenario. Provide evidence: a reproduction path, a realistic input that triggers the issue, a code path that leads to the failure. If you cannot demonstrate the risk concretely, reconsider the severity — perhaps it is Major, not Blocker. If you still disagree after discussion, bring in a third person familiar with the system. Do not escalate to a stronger position out of frustration.

**Author pushes back on a Major** — Discuss. If you cannot reach agreement, get a third opinion from someone familiar with the system. Do not let disagreement on a Major stall the PR for days. Timebox the discussion.

**Author pushes back on a Minor or Nit** — Accept. Minor and Nit are explicitly defined as "author's call." If you find yourself arguing for a Minor, you have mis-calibrated the severity. Either upgrade it to Major with a concrete justification, or let it go.

**Convention conflict (your org's default vs. existing repo pattern)** — Flag the conflict explicitly. Do not silently enforce one over the other. Brownfield code wins by default — existing repo conventions take precedence over your org's defaults unless there is a specific reason to migrate. Ask which convention should win for THIS repository. Document the decision in the repo's `CLAUDE.md` under a conventions section so the same conflict is not re-litigated in every future PR. This is especially important for error handling patterns, logging conventions, test structure, and API response formats.

**Philosophical disagreement** — A PR comment thread is not the place to debate whether the team should use Result types instead of exceptions. If the review surfaces a genuine architectural question, take it to a team discussion. Do not hold the PR hostage to a design philosophy debate. The author should not be penalized for following the current convention while the team decides on the next one.

**Tone** — Review comments are written communication, which lacks vocal tone and facial expression. What you intend as helpful can read as condescending. Write observations, not judgments. "This does not handle the timeout case" is an observation. "You forgot to handle timeouts" implies carelessness. The difference matters over hundreds of reviews.
