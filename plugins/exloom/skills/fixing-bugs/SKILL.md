---
name: fixing-bugs
description: Use when the work is a bug fix rather than a new feature — reproduces the bug first, commits the failing test with the fix, and records the root cause in one line.
---

# Fixing bugs

A bug fix needs no spec: the behaviour is already agreed. It needs a test that fails for the bug's own reason, written before the fix. Not for a new feature (`exloom:brainstorming`), a refactor, or a review finding (the fix step of `/exloom`).

1. **Reproduce it.** Make the bug happen and say what you did, what you expected and what occurred. If it will not reproduce, stop and report what you tried; never write a fix against a guess.
2. **Write the failing test and run it.** It must fail on the bug's symptom, not on a missing symbol or import. If it passes on the unfixed code it tests the wrong thing: fix the test.
3. **Name the root cause** in the checklist, in one line: `Root cause: <what the code does, and why that produces the symptom>`. Not the fix and not the symptom. If you cannot name it, you are about to suppress the symptom: say so and ask.
4. **Fix it with the smallest change that makes the test pass**, and commit the test and the fix together, so the proof sees a test that fails at the base and passes at the tip. Tidying nearby code belongs in a separate commit.
5. **Carry on through `/exloom`.** Proof and review are unchanged.

In the PR, say how you reproduced it so a reviewer can repeat it.
