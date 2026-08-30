# Failure Modes — exploring-codebase

Extracted from SKILL.md so the skill loads lean. This is the failure modes this skill exists to prevent — thought pattern, why it feels right, what actually happens, and the correction.


### 1. "Let me read every file to really understand it"

**The thought pattern:** Thoroughness means completeness. To understand the codebase, you read all of it.

**Why it feels right:** Reading more feels like understanding more. Skipping files feels like cutting corners.

**What actually happens:** You spend two days reading 200 files, retain a vague impression of all of them and a clear model of none. You read infrastructure plumbing and generated code as carefully as the core domain logic, wasting your attention budget on code you will never touch. By the time you finish, you have forgotten the first half.

**The correction:** Exploration is tracing the shape, not reading the contents. Follow the 8 steps. Trace ONE operation end-to-end (Step 4) rather than reading every operation. Sample 2-3 files per directory, not all of them. You build a map, not a memorized transcript.

### 2. "I'll start coding now and figure out the structure as I go"

**The thought pattern:** Exploration is overhead. I'll learn the codebase by working in it.

**Why it feels right:** Writing code feels productive. Reading code feels passive. You want to show progress.

**What actually happens:** You put your change in the wrong layer because you didn't know the layering. You duplicate a utility that already existed because you never saw it. You violate a convention nobody told you about, and it surfaces in code review. Each of these costs more than the exploration would have.

**The correction:** Twenty minutes of structured exploration prevents hours of misplaced work. The map tells you where your change belongs before you write it.

### 3. "The README explains everything, I don't need to trace the code"

**The thought pattern:** The documentation describes the architecture. Reading it is enough.

**Why it feels right:** The README is the team's own description of their system. Who would know better?

**What actually happens:** The README describes the architecture the team intended two years ago. The code drifted. The README says "all data access goes through the repository layer," but three services query the database directly because of a deadline. You trust the README, put your code in the wrong place, and match a pattern that no longer exists.

**The correction:** The README tells you the intent. Step 4 (trace one operation end-to-end) tells you the reality. When they conflict, the code wins — and note the drift in your Gotchas section so the next person knows.

### 4. "I explored it last quarter, I still know it"

**The thought pattern:** I've worked in this repo before. I don't need to re-explore.

**Why it feels right:** You have real memory of the codebase. Re-exploring feels redundant.

**What actually happens:** The repo changed. A refactor moved the entry points. A framework upgrade relocated config. Three new services appeared. Your stale mental model leads you to look for things where they used to be, and you waste time discovering they moved — or worse, you act on the old model.

**The correction:** Read `.claude/project-notes.md` first. If it's more than a few months old on an active repo, skim the recent git history and update the notes. A 5-minute refresh beats acting on a stale map.
