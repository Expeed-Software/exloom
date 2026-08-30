# TDD in Brownfield Codebases — test-driven-development

Extracted from SKILL.md so the skill loads lean.


Most real-world work is brownfield. TDD in brownfield is fundamentally different from TDD in greenfield, and pretending otherwise leads to frustration and abandonment. Greenfield TDD is easy — you control everything. Brownfield TDD requires strategy because you're working with code that wasn't designed for testability. The strategies below are ordered by when you'd use them in a typical brownfield change.

**1. Characterization tests first.** Before changing existing code, write a test that documents the current behavior — inputs, outputs, side effects, error cases. This test passes RIGHT NOW. Its job is not to verify correctness (the current behavior might be wrong); it's to catch unintended changes. When your modification breaks a characterization test, you know you changed something you didn't mean to. This is your safety net. Write it before you touch anything. Name it clearly: `test_existing_behavior_order_total_rounds_down()` so future developers know it documents legacy behavior, not a specification.

**2. Don't rewrite to add tests.** The temptation is strong: "this code is untestable, let me refactor it first so I can test it." Resist. Refactoring without tests is walking a tightrope without a net. You might make it across, but you're taking an unnecessary risk. Instead, add tests to the code you're actually changing. Your goal is confidence in YOUR changes, not 100% coverage of the legacy codebase. Coverage will grow naturally as you touch more code.

**3. Seam-based testing.** When code is genuinely untestable — hardcoded dependencies, global state, static method calls, `new` operators buried in business logic — find a "seam." A seam is a point where you can substitute behavior without modifying the calling code. Common seam techniques:
- **Extract interface:** The class depends on a concrete `EmailSender`? Extract an `EmailSender` interface, make the existing class implement it, and inject the interface instead. Now you can substitute a fake in tests.
- **Constructor injection:** The class creates its own dependencies with `new`? Add a constructor parameter. Default it to the real implementation so existing callers don't break. Pass a test double in your test.
- **Wrap and override:** A method calls a static utility directly? Wrap the static call in a protected instance method. In your test, subclass and override that method. Ugly, but it works as a first step toward proper injection.

Make the smallest change needed for testability, verify the change didn't break anything with a characterization test, then proceed with TDD for your new behavior.

**4. Test at the boundary.** For legacy code, integration tests at the API or service boundary give the best return on investment. They test real behavior through real code paths without requiring you to understand every internal class. A single integration test that hits your REST endpoint with realistic data covers more ground than a dozen unit tests of deeply coupled internal classes. Don't try to unit-test tightly coupled internal code — you'll spend more time on test setup than on actual assertions.

**5. The strangler fig pattern for tests.** New code gets full TDD from day one — no exceptions. Old code gets characterization tests when touched. Over time, the tested surface area grows naturally, following the areas of active development. In six months, the code that changes frequently is well-tested and well-designed. The code that never changes remains untested — and that's fine, because stability is its own form of reliability. Don't chase coverage numbers on code nobody touches.

A practical brownfield workflow looks like this: (1) identify the code you need to change, (2) write characterization tests around that code, (3) find or create a seam if the code is untestable, (4) write a failing test for your new behavior using TDD, (5) make it pass, (6) refactor, (7) verify characterization tests still pass. Steps 4-6 are standard TDD. Steps 1-3 are the brownfield tax — it gets smaller every time because previous developers already paid it for the code they touched.
