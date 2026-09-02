# Failure Modes — capturing-learnings

The failure modes this skill exists to prevent.

### 1. "I'll remember this, no need to capture it"

**The thought pattern:** The lesson was painful enough that you'll never forget it. Writing it down feels unnecessary.

**Why it feels right:** The frustration is vivid right now. Of course you'll remember.

**What actually happens:** You remember for two weeks. Then a new project pushes it out. Six months later, a teammate hits the exact same gotcha — or you hit it again yourself — and the three hours are lost a second time. Worse, the knowledge never reaches everyone else on the team who would have benefited.

**The correction:** If the trigger phrase "I wish someone had told me that" applies, capture it now. The capture takes two minutes. The re-learning costs hours, multiplied by everyone who hits it.

### 2. "This is too small to capture"

**The thought pattern:** It's a tiny detail. Not worth a CLAUDE.md edit or a PR.

**Why it feels right:** Small things feel below the threshold of "documentation."

**What actually happens:** Small gotchas are exactly the ones that aren't obvious and aren't discoverable. A one-line note ("the test DB needs `RATE_LIMIT_ENABLED=false` or integration tests hang") saves the next person an afternoon. Big architectural facts are usually discoverable from the code; small operational gotchas are not.

**The correction:** Small and non-obvious is the sweet spot for capture. If it cost you time and wasn't findable, it belongs in CLAUDE.md.

### 3. "I'll batch up my learnings and capture them later"

**The thought pattern:** You'll collect everything you learned this sprint and write it up at the end.

**Why it feels right:** Batching feels efficient. One writing session instead of many interruptions.

**What actually happens:** "Later" arrives with the details fuzzy. You remember there was a gotcha but not the exact env var. You capture a vague, low-value version — or you skip it because reconstructing the detail is too much work. The batch never happens.

**The correction:** Capture at the moment of learning, when the detail is exact. Route it immediately through the decision tree. The whole point of the four destinations is that routing takes seconds.

### 4. "I'll add my learning next to the existing one"

**The thought pattern:** The reference already covers this topic, so you append your note below the existing content.

**Why it feels right:** Adding is safer than changing. You don't want to delete someone else's work.

**What actually happens:** The file now has two instructions on the same topic. A reader follows the first one they find, which may be the outdated one. The contradiction propagates until someone notices the file disagrees with itself.

**The correction:** Follow the "When a Learning Contradicts Existing Content" section above. Update in place, quote the before/after in the PR, never leave both versions.
