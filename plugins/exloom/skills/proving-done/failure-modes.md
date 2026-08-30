# Failure Modes — proving-done

Extracted from SKILL.md so the skill loads lean. This is the failure modes this skill exists to prevent — thought pattern, why it feels right, what actually happens, and the correction.


### 1. "Tests pass, ship it"

**Thought pattern:** The test suite is green. That means the code works correctly. Time to open the PR and move on.

**Why it feels right:** Tests are the automated verification system. Green means go. That is literally what CI is designed to tell you.

**What actually happens:** Tests verify code correctness against the specific scenarios someone wrote into the test suite. They do not verify feature correctness against what the user actually needs. They do not verify operational readiness — timeouts, retries, concurrent access, infrastructure failures. A passing test suite and a broken feature coexist regularly. The tests check what was coded, not what was intended.

**The correction:** Tests are one item on an eight-item checklist, not the entire checklist. A green suite is necessary but nowhere near sufficient. Run all eight items.

### 2. "I checked everything in my head"

**Thought pattern:** I have been working on this for hours. I know every line. I do not need to re-read it — I can see the code in my mind.

**Why it feels right:** You have deep context. You just wrote every line. You can picture every file and function. Reading it again feels redundant.

**What actually happens:** You see what you intended to write, not what you actually wrote. The variable you meant to rename still has the old name in one place. The error handler you planned to add is still a TODO comment. The debug log you meant to remove is still printing user emails to stdout. Your brain autocompletes the copy-paste block with what should be there, not what is there. Heads forget. Especially tired heads.

**The correction:** The checklist exists because memory is unreliable under fatigue. Run the checklist. Read the actual files on disk. Do not trust your mental model.

### 3. "It is just a small change"

**Thought pattern:** This is a three-line fix. It cannot break anything. Full verification is overkill.

**Why it feels right:** The effort seems disproportionate to the size of the change. Eight items for three lines feels like bureaucracy.

**What actually happens:** Small changes that skip verification cause production incidents at a rate disproportionate to their size — precisely because people skip verification on them. A one-line config change can take down a service. A three-line fix can regress a code path you did not consider. A renamed constant can break ten consumers you did not know existed. The size of the change does not determine the size of the blast radius.

**The correction:** Abbreviated checklist for genuinely trivial changes (typo, config value, comment). Full checklist for anything touching logic, control flow, or runtime behavior — regardless of line count. When in doubt, full checklist. The cost is minutes. Getting it wrong costs hours.

### 4. "The reviewer will catch it"

**Thought pattern:** Code review exists for this purpose. The reviewer will find anything I missed.

**Why it feels right:** Code review is a genuine safety net. Two sets of eyes are better than one. The system is designed for this.

**What actually happens:** The reviewer's job is to find issues you could not find — design concerns, architectural implications, edge cases in unfamiliar code paths. When you send a PR with debug statements, hardcoded values, and missing error handling, the reviewer wastes their expertise on janitorial cleanup. The review takes longer, the feedback is noisier, and the real architectural concerns get buried under trivial findings that you should have caught in five minutes.

**The correction:** Your job: catch everything you can. Reviewer's job: catch what you genuinely could not see from your vantage point. Do your job completely so the reviewer can do theirs.

### 5. "I am too tired to re-read"

**Thought pattern:** I have been at this for hours. I am exhausted. I just want to be done. I will look at it fresh tomorrow.

**Why it feels right:** Fatigue is real. Pushing through produces diminishing returns. Stopping makes sense.

**What actually happens:** You open the PR tired. The reviewer finds three issues you would have caught in a five-minute re-read. You context-switch back tomorrow, reload the mental model, fix the issues, push again, wait for re-review. The "time saved" costs three times as much in round-trip delay. Or worse: nobody catches it and it ships broken.

**The correction:** If you are too tired to re-read, you are too tired to claim done. Either run the checklist now — fifteen minutes, and the structure carries you through fatigue — or stop and run it tomorrow before claiming completion. The checklist does not get tired.
