# Failure Modes — brainstorming

The failure modes this skill exists to prevent: thought pattern, why it feels right, what actually happens, and the correction.

### 1. "This is too simple for brainstorming"

**Thought pattern:** "It's just a CRUD endpoint. I've built hundreds of these."

**Why it feels right:** Simple tasks have obvious solutions. The gap between
understanding and implementation seems nonexistent.

**What actually happens:** The "simple" endpoint needs an authorization model you
didn't check. Or an existing endpoint does something similar, and now the API
has two inconsistent paths. Simple projects are where unexamined assumptions
cause the most damage — nobody builds in checkpoints for "trivial" work.

**The correction:** If it's truly simple, brainstorming takes five minutes. Run
the process — it finishes fast or reveals something you didn't know.

### 2. "I already know the best approach"

**Thought pattern:** "I solved this exact problem at my last company. I know
the architecture."

**Why it feels right:** Experience is valuable. Pattern recognition makes senior
engineers effective. Ignoring experience feels wasteful.

**What actually happens:** That approach was shaped by a different codebase, team,
and constraints. Transplanting it without adaptation creates a foreign body the
team works around for years.

**The correction:** Experience informs brainstorming — it doesn't replace it.
Let the codebase have a vote. Fast when you're right, catches mistakes when
you're wrong.

### 3. "Let me just explore the code first"

**Thought pattern:** "I'll read the codebase thoroughly, understand everything,
then I'll know what to build."

**Why it feels right:** Understanding code seems like a prerequisite to good
design. More information leads to better decisions.

**What actually happens:** You read fifty files, trace middleware, and three hours
later you know a lot but haven't made a single decision. Exploration without
guiding questions is tourism, not engineering.

**The correction:** Structure exploration around questions: What similar features
exist? What patterns apply? What libraries are available? Exploration is a step
within brainstorming, not a substitute for it.

### 4. "The user seems impatient, I'll skip questions"

**Thought pattern:** "They want me to start building. Asking questions will
frustrate them."

**Why it feels right:** Responsiveness feels like good service. Starting work
immediately shows initiative and competence.

**What actually happens:** You infer wrong. Build, discover mismatch, rebuild —
3-5x longer than questions would have taken. Five minutes of questions saves
five hours of rework.

**The correction:** Frame questions as acceleration: "I want to get this right
the first time. One quick question..." Users respond well when questions serve
speed, not ceremony.

### 5. "I'll design as I code"

**Thought pattern:** "Design docs get stale. Real design happens in code. I'll
figure out the architecture as I implement."

**Why it feels right:** Agile culture valorizes working software over
documentation. Iterating in code feels more productive than iterating in prose.

**What actually happens:** At every architectural fork mid-implementation, you
take the path requiring the least rework — not the best path. Sunk cost warps
every decision. Architecture ends up shaped by build order, not by the problem.

**The correction:** Fifteen minutes of design in prose is worth two hours of
design-by-implementation. The spec forces decisions into the open before they're
embedded in expensive-to-change code.
