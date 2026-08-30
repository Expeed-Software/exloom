---
name: test-driven-development
description: Use when implementing any feature or bugfix — write the failing test first, then the minimal code to pass it, then refactor. Enforces design-through-testing discipline.
---

# Test-Driven Development

## Overview

TDD is a design technique, not a testing technique. Writing the test first forces you to design the interface before the implementation: the test is your code's first client, and if the test is awkward to write, the API is awkward to use — you learn that before committing to an implementation, when the cost of change is still zero.

Default to test-first: you need a reason NOT to write the test first, not a reason to. This skill teaches the full Red-Green-Refactor cycle, the cases where TDD genuinely doesn't apply (see Decision Points), and the hardest case — applying it to brownfield code where nothing is tested yet.

## The Cycle

The TDD cycle has three phases. They repeat for every behavior you add. The discipline is in the repetition — each cycle is small (5-15 minutes), and you never skip a phase. The order matters: Red forces you to think about what you want, Green forces you to make it work, Refactor forces you to make it clean. Skipping any phase breaks the feedback loop.

### Red: Write a Failing Test

**What to do.** Write a test that describes the next behavior you want. Run it. Watch it fail. Confirm it fails for the right reason.

**How to do it well.** The test describes WHAT the code should do, not HOW it does it. Test behavior through the public interface. Name the test after the behavior: `test_order_total_includes_tax()`, not `test_calculate()`. The name should read like a specification — if someone reads only your test names, they should understand every behavior the system supports. Good test names eliminate the need for comments in production code.

**Technique.** Write the test as if the ideal API already exists. Import the class that doesn't exist yet. Call the method with the arguments you wish it took. Assert the return value you expect. The test IS the interface design. This is the most valuable moment in TDD — you're making design decisions with zero sunk cost. If you don't like how the test reads, change the API. You haven't built anything yet.

The test should fail for the RIGHT reason. A missing function or wrong return value means you're on track. A syntax error, import failure, or wrong test setup means you skipped a step — your test isn't even reaching the code under test. Fix the infrastructure before moving on. A test that fails for the wrong reason gives you no information.

**What bad looks like.** Writing a test that calls implementation details. If your test reaches into private methods, checks internal data structures, or breaks when you refactor code that doesn't change behavior — you tested HOW, not WHAT. These tests become a maintenance burden that punishes refactoring instead of enabling it.

Another anti-pattern: testing fake/stub behavior instead of real behavior. If your test only proves that you called a substitute with the right arguments, it proves nothing about whether your system actually works. Fake external boundaries (APIs, third-party services) with wire-level fakes that simulate real protocol behavior — not by replacing your own classes with stubs.

One more thing: only write ONE test at a time. The temptation is to write three tests you can see coming. Resist. Each test should change how you think about the implementation. If you write three tests before any green step, you're planning the implementation in your head — which defeats the purpose. One red, one green, one refactor. Then repeat.

### Green: Write Minimal Code to Pass

**What to do.** Write the smallest amount of production code that makes the failing test pass. Run all tests — not just the new one. They should all be green.

**How to do it well.** Minimal means minimal. Test expects `42`? Write `return 42`. Seriously. Don't implement the general solution yet. Each test forces exactly one new behavior into the system. Implementing more than the test requires is guessing about future needs — and guesses are usually wrong. If you write more code than the test demands, that extra code is untested by definition.

**Technique.** The "fake it till you make it" progression works like this: start with a constant (`return 42`), then a variable (`return self.total`), then a computation (`return sum(item.price for item in self.items)`), then an abstraction (extract a method, introduce a class). Each step is driven by a new failing test that the current implementation can't handle. The tests push you toward the general solution incrementally. You never jump ahead — the tests lead, and the code follows.

**What bad looks like.** Writing the full algorithm on the first green step. If you implement a complete discount engine when the first test only checks "no discount," you're not doing TDD — you're doing test-after with extra ceremony. You wrote more code than you can verify, and any bug in that code won't be caught until much later.

Another trap: "I know what the final code looks like, let me just write it." Then why TDD? You're guessing at correctness instead of proving it step by step. The whole point is that each test adds one provable behavior. If your intuition is right, TDD will get you there quickly. If your intuition is wrong, TDD will catch it on the next failing test instead of in production.

### Refactor: Clean Up Without Changing Behavior

**What to do.** Look at the code you just wrote — both production and test code. Clean it up. Run all tests after every change. They must still pass. If they don't, you changed behavior, not structure — undo and try again.

**How to do it well.** Look for: duplication between production code and test data, unclear variable or method names, functions doing more than one thing, conditionals that should be polymorphism, magic numbers that deserve named constants, test setup that could be extracted into helpers. This is where design emerges. The first green pass is ugly on purpose — you were focused on making the test pass, not on aesthetics. Refactor makes it clean.

**Technique.** Apply one refactoring at a time. Rename a variable, then run tests. Extract a method, then run tests. Inline a temporary, then run tests. Each refactoring is a tiny step with immediate verification. If you batch three refactorings and a test breaks, you don't know which one caused it. Small steps keep the feedback loop tight.

Don't forget to refactor the tests too. Test code is production code — it needs to be readable, maintainable, and free of duplication. Extract common setup into helper methods or fixtures. Use descriptive variable names that communicate intent (`expired_coupon`, not `c2`). If a test is hard to read, it's not documenting behavior effectively. A good test reads like a story: given this setup, when this happens, then expect this result.

Common refactorings during this phase, roughly in order of frequency:
- **Rename** — better names for methods, variables, classes. Costs nothing, improves everything.
- **Extract method** — when a function does two things, split it. Each function should have one reason to change.
- **Extract class** — when a method accumulates parameters or a data clump keeps appearing, it's asking to be its own type.
- **Replace conditional with polymorphism** — when you see `if type == "flat" ... elif type == "percentage"`, consider a discount strategy interface.
- **Remove duplication** — between production code and tests, between test methods, between similar production methods. DRY applies here too.

**What bad looks like.** Skipping refactor because "it works." Tech debt accumulates here, one skipped refactor at a time. The code gets messier with each feature until someone declares it needs a rewrite — a rewrite that wouldn't be necessary if refactoring had been continuous.

The other failure: refactoring AND adding behavior in the same step. These are separate activities with different goals. Refactor changes structure while preserving behavior. Green changes behavior by adding new functionality. Mixing them means you can't tell if a test failure is a bug in your new behavior or a mistake in your restructuring. Keep them separate. Always.

## What to Test and What Not to Test

See [what-to-test.md](what-to-test.md).
## TDD in Brownfield Codebases

See [tdd-brownfield.md](tdd-brownfield.md).
## Decision Points

| Situation | Decision |
|---|---|
| Prototyping or exploring | Skip TDD. Spike first to learn, throw away the spike, then TDD the real implementation with the knowledge you gained. Never keep spike code. |
| UI layout and CSS | TDD doesn't apply to visual layout. Use visual review, snapshot tests, and Storybook. Test interaction logic (click handlers, form validation) but not pixels. |
| Simple CRUD with no business logic | Light testing only — one integration test for the happy path, one for a common error case. Don't TDD pure boilerplate. |
| Complex business rules | TDD shines here. Tests document the rules better than comments ever could, and they stay accurate as the rules evolve. Each edge case gets its own test. |
| Bug fix | Write the failing test FIRST. It proves the bug exists and specifies the correct behavior. Fix the code. Test passes. You now have a regression test forever. This is the single best use of TDD. |
| Legacy code with no tests | Characterization test to document current behavior, then TDD the change you're making. See the Brownfield section above. |
| Time pressure or deadline | TDD saves time on anything complex — fewer bugs, less debugging, less rework. For truly trivial tasks (renaming a field, updating a config value), skip it. Be honest with yourself about what counts as "trivial." |
| Third-party integration | Test YOUR code's behavior when the third party returns various responses — success, error, timeout, malformed data. Use wire-level fakes (MSW, WireMock, MockWebServer) at the protocol boundary — they exercise your real HTTP client and error handling. |
| Concurrent or async code | TDD applies, but test at a higher level. Verify observable outcomes (final state, emitted events), not thread scheduling. Use deterministic test helpers for async — don't rely on `sleep`. |
| Data migrations | Write a test with sample data in the old format, run the migration, assert the new format. TDD works well here because the transformation is pure logic. |

## Failure Modes

See [failure-modes.md](failure-modes.md).
## Worked Example

See [worked-example.md](worked-example.md).
## Integration

- **Use TDD during plan execution:** `exloom:executing-handoff-plans` — for each implementation step in a plan, write the failing test before the production code. The plan says what to build; TDD ensures each piece works before you move to the next step. A plan step isn't complete until its tests pass.
- **Use TDD for bug fixes:** `exloom:systematic-debugging` identifies the root cause, then TDD verifies the fix. Write a failing test that reproduces the bug, fix the code, confirm the test passes. The failing test is proof the bug existed; the passing test is proof it's fixed. This test stays in the suite forever as a regression guard. Every bug fixed with TDD is a bug that can never come back undetected.
- **Tests from TDD feed into verification:** `exloom:proving-done` — the passing test suite is concrete evidence of correctness, not a verbal claim. When verification asks "does it work?", TDD answers with a green build and a list of tested behaviors, not "I think so" or "it worked when I tried it manually."
- **In brownfield codebases:** Write characterization tests first to document existing behavior, then TDD the change. This pairs with the brownfield-first principle across all projects — respect what exists, test what you're changing, and let coverage grow organically with active development. Don't block on achieving coverage targets before shipping — coverage follows development, not the other way around.
- **During brainstorming:** `exloom:brainstorming` may produce multiple design options. When evaluating them, consider testability as a design criterion. The option that's easier to test is usually the option with better separation of concerns. TDD makes this tradeoff visible early.
- **For new team members:** TDD is one of the best onboarding tools. Reading a well-named test suite teaches you what the system does faster than reading the production code. Writing tests forces you to understand the API before you can extend it. Pair a new developer with an experienced TDD practitioner for their first few stories.
