---
name: fixing-bugs
description: Use when the work is a bug fix rather than a new feature — reproduces the bug first, commits the failing test with the fix, and records the root cause in one line.
---

# Fixing bugs

A bug fix needs no spec: the behaviour is already agreed, and the only open
question is why the code does something else. What it does need is a test that
fails for the bug's own reason, written before the fix exists.

**Announce at start:** "I'm using the exloom:fixing-bugs skill."

Do not run this for a new feature, a refactor, or a review finding. New
behaviour goes through `exloom:brainstorming`; a review finding is handled by
the fix step of `/exloom`.

## Step 1: Reproduce it

Before writing anything, make the bug happen and say exactly what you observed:
the command or the user action, what you expected, what occurred. A bug you
cannot reproduce is a bug you cannot prove you fixed.

If it will not reproduce, stop and report that. Do not write a speculative fix
against a guess at the cause — report what you tried and hand the question back.

## Step 2: Write the failing test

Write the test that the bug breaks, and run it. It must fail, and the failure
must name the bug's symptom rather than a missing symbol or an import error.

If the test passes on the unfixed code, it is testing the wrong thing. Fix the
test, not the code, and run it again.

## Step 3: Find the root cause

State it in one line, in the checklist:

```
Root cause: <what the code does, and why that produces the symptom>
```

Not a description of the fix, and not a restatement of the symptom. If you
cannot name the cause, you are about to suppress the symptom instead of fixing
it — say so and ask.

## Step 4: Fix it, and commit both together

Commit the failing test and the fix in one commit. The proof then sees a test
that fails at the base and passes at the tip, which is what it exists to check,
and reports `PROVED` through the ordinary path.

Keep the fix the smallest change that makes the test pass. A bug fix that also
tidies the surrounding code hides the fix inside the tidying, and the reviewer
has to separate them.

## Step 5: Carry on through the gate

Proof and review are unchanged. `/exloom` runs them; nothing here replaces the
gate or lowers what it asks for.

## What to record

| In | What |
|---|---|
| The checklist | `Root cause:` — one line |
| The commit | the failing test and the fix together |
| The PR | how you reproduced it, so a reviewer can repeat it |

## Common mistakes

**Fixing the symptom.** A null check where the null should never have arrived
moves the bug rather than removing it. Name the cause first.

**Testing after fixing.** A test written against fixed code tends to assert what
the code now does, which is not the same as what it should do.

**Widening the fix.** "While I was in here" belongs in a separate commit, and
usually in a separate branch.
