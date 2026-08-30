# Failure Modes — reviewing-plans

Extracted from SKILL.md so the skill loads lean. This is the failure modes this skill exists to prevent — thought pattern, why it feels right, what actually happens, and the correction.


**1. "It's good enough"**

Thought pattern: The plan covers the main cases and the executor is experienced. The gaps are small.

Why it feels right: Most of the plan is solid, and filling small gaps feels like nitpicking. You don't want to slow down the team over minor issues.

What happens: The executor hits the first gap within hours. They guess. They guess wrong. By the time the mismatch surfaces in code review, three days of work sit on top of a wrong assumption. "Good enough" plans produce "close enough" execution, and close enough is how rework, scope creep, and wasted time enter the process.

Correction: Review every item with equal rigor. The small gaps are the dangerous ones — large gaps are obvious and get caught; small gaps hide and compound.

**2. "The author is senior, they know what they're doing"**

Thought pattern: This plan was written by someone with deep domain knowledge. If they left something out, they probably had a reason.

Why it feels right: Seniority correlates with competence, and questioning a senior engineer's plan can feel presumptuous. You trust their judgment.

What happens: Seniority does not prevent ambiguity. Senior developers write ambiguous plans too — often more ambiguous, because they have so much context that they forget what isn't obvious. The executor (who may be less senior) fills gaps with less experienced judgment. The plan review exists to catch exactly this asymmetry.

Correction: Review the plan, not the person. Apply the same 9-item checklist regardless of who wrote it. A senior author who writes clear plans will pass easily. A senior author who writes ambiguous plans needs the same feedback as anyone else.

**3. "I'll note this minor issue but approve anyway"**

Thought pattern: There's one small thing that could be clearer, but it's not worth a rejection cycle. I'll mention it as a comment and approve.

Why it feels right: Rejecting for one minor issue feels disproportionate. The author will be frustrated. The executor can probably figure it out.

What happens: Noted issues become forgotten issues. The author reads the approval, ignores the comment, and hands off the plan. The executor never sees the comment. The "minor" issue becomes a real problem during execution. Conditional approval is not a thing — it just moves the ambiguity from the plan to a comment that nobody reads.

Correction: If an issue is worth noting, it is worth fixing before handoff. Reject with specific feedback. The 10-minute fix cycle is cheaper than the hours of confusion it prevents.

**4. "The executor can ask questions"**

Thought pattern: Not everything needs to be pre-answered. The executor is a professional — they'll ask when they're stuck.

Why it feels right: Asynchronous communication works. Teams ask questions all the time. Requiring every possible question to be pre-answered feels excessive.

What happens: Every question the executor asks is a plan failure. Each question creates a context switch for the author, a blocking wait for the executor, and a delay in the timeline. If the author is unavailable (different timezone, in meetings, on leave), the executor either guesses or stops. The plan's job is to pre-answer questions. An FAQ section that forces the author to think from the executor's perspective catches 80% of these interruptions.

Correction: Count the questions you'd ask as an executor. If the count is above zero on a multi-task plan, the FAQ needs work. Reject until it doesn't.

**5. "Reviewing plans takes too long"**

Thought pattern: This review process has 9 items. Working through all of them for every plan is overhead that slows down the team.

Why it feels right: Shipping matters. Process that delays shipping feels like bureaucracy. The team has been executing plans without formal review and things have mostly worked out.

What happens: "Mostly worked out" means the rework was absorbed silently — late nights, weekend fixes, scope reductions nobody tracked. The cost of unclear plans is real but invisible until you measure it. Twenty minutes of review prevents two days of confused execution. The 9-item checklist takes 15-25 minutes for a well-written plan. If it takes longer, that's a signal the plan has problems worth catching now rather than during execution.

Correction: Time the review. Track the time spent on rework from unclear plans. Compare the numbers. The case makes itself.
