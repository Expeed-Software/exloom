---
name: test-driven-development
description: Use when implementing any feature or bugfix — write the failing test first, then the minimal code to pass it, then refactor. Enforces design-through-testing discipline.
---

# Test-Driven Development

## Overview

TDD is a design technique, not a testing technique. When you write the test first, you are forced to think about the interface before the implementation. You design the API by consuming it before building it. The test becomes the first client of your code, and that client's needs shape the public surface. If the test is awkward to write, the API is awkward to use — and you discover this before you've committed to an implementation, not after. This is why TDD produces better APIs than implementation-first development: the feedback loop is immediate and the cost of change is zero.

Why teams resist: it feels slower. And it IS slower for the first 30 minutes. You're writing code that doesn't exist yet, watching it fail, writing the minimum to pass, watching it go green, then cleaning up. It feels like busywork compared to just writing the function. Then you hit the 30-hour mark — the part where non-TDD teams are debugging, reworking, guessing what the code should do, and manually testing in a browser. The TDD team is shipping. The upfront cost pays for itself many times over, and the payoff starts earlier than most people expect.

The inconsistency problem is what kills organizations at scale. Some teams do TDD, some don't. TDD teams produce code that is testable by design — small functions, injected dependencies, clear interfaces. Non-TDD teams produce code that is hard to test after the fact because testability was never a design constraint. This creates a quality gap that widens with every sprint. The untested code becomes the code nobody wants to touch, which becomes the code that breaks in production, which becomes the code that gets a "rewrite" ticket that sits in the backlog for two years.

This skill makes the case AND teaches the practice. It walks through the full Red-Green-Refactor cycle with real examples, addresses the situations where TDD genuinely doesn't apply, and covers the hardest scenario: applying TDD to brownfield code where nothing is tested yet. Not dogmatic — see Decision Points for when to skip it. But the default is: test first. You need a reason not to, not a reason to start. The goal is not 100% TDD adoption — it's making test-first the natural way of working, so that writing code without a test feels as uncomfortable as deploying without a review.

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

**Test these things:** Business logic and domain rules — the core of what your application does. Data transformations and calculations — anywhere numbers, strings, or objects change shape. State transitions and workflow steps — anything with a lifecycle. Error handling and validation — both expected errors and edge cases. Boundary values — empty inputs, single items, maximum sizes, off-by-one scenarios. Integration points where your code meets external systems — verify your side of the contract.

**Don't test these things:** Framework internals — Spring's dependency injection works, you don't need to verify it. Library functions — if `Math.max` is broken, you have bigger problems. Trivial getters and setters with no logic — they're just field access. Configuration loading — test it at the integration level, not by unit-testing a YAML parser. UI layout and CSS styling — use visual review, snapshot tests, and Storybook instead.

**Gray areas that need judgment:** Database queries — test via integration test with a real database or testcontainers, not by mocking the ORM. Mocking the ORM tests your mock setup, not your actual query. API endpoints — test via HTTP requests to the running app, not by calling the controller method directly. The HTTP layer (serialization, status codes, content negotiation, headers) is part of the contract and should be exercised.

**The decision rule:** if the logic could be wrong, test it. If it's just wiring that connects already-tested components, test it at a higher level (integration) not at the unit level. If testing something requires more fake/stub setup than actual assertions, you're testing the wrong thing at the wrong level. Step back and ask: "What am I actually trying to verify here?"

**Wire-level fakes vs mock frameworks — know the difference.**

This distinction matters because many teams (and some project-level rules) ban mock frameworks entirely. Understanding why clarifies what's allowed and what isn't.

- **Wire-level fakes (allowed everywhere):** These simulate the protocol boundary — an actual HTTP server, a WebSocket server, a fake SMTP endpoint. Examples: MSW (intercepts HTTP at the network level), WireMock, `MockWebServer` (OkHttp), embedded test servers, Testcontainers with real databases. They exercise your real serialization, real HTTP client, real error handling. Your code doesn't know it's talking to a fake.

- **Mock frameworks (project policy decides):** Mockito, jest.mock, unittest.mock, gomock, jasmine.createSpyObj, hand-rolled stub classes. These replace your own application code with fake implementations. They verify that you called a method with the right arguments — not that your system actually works. When the real implementation changes, mock-based tests keep passing because the mock doesn't know about the change.

- **Why wire-level fakes are better:** They test the same code path that runs in production. A wire-level fake for Stripe returns real HTTP responses — your error handling, retry logic, and deserialization all execute. A Mockito mock of `StripeClient` tests none of those things. It tests that you called `stripeClient.charge()` with certain arguments, which proves nothing about whether the charge actually works.

- **When in doubt:** Check the project's CLAUDE.md for its test policy. Some projects ban all mocks. Some allow mocks at external boundaries only. Some have no policy. This skill's guidance works with any policy — the TDD cycle is the same regardless. What changes is how you fake external dependencies: wire-level fake (always safe) vs mock framework (check project rules).

**Test granularity by layer:**
- **Domain/business logic:** Fine-grained unit tests. Every rule, every edge case. These are fast, isolated, and the highest-value tests you'll write.
- **Service/application layer:** Coarser tests that verify orchestration. Does the service call the right domain methods in the right order? Does it handle transactions correctly?
- **API/controller layer:** Integration tests via HTTP. Verify status codes, response shapes, error formats, authentication. Don't duplicate business logic tests here.
- **Database/repository layer:** Integration tests with a real database (testcontainers). Verify queries return correct data, constraints are enforced, migrations work.

The pyramid still holds: many unit tests, fewer integration tests, even fewer end-to-end tests. But "unit" doesn't mean "one class" — it means "one behavior." A unit test can span multiple classes if they form a cohesive unit of behavior.

**Test naming conventions that work across teams:**
- `test_<behavior>_<scenario>_<expected_result>` — e.g., `test_calculate_total_with_expired_coupon_ignores_discount`
- Avoid generic names: `test_discount_service` tells you nothing. `test_percentage_discount_rounds_to_two_decimal_places` tells you the exact behavior and the edge case.
- Each test name should be a readable sentence. If you can't name it clearly, you don't understand the behavior you're testing. Back up and clarify the requirement before writing the test.

## TDD in Brownfield Codebases

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

**1. "I'll write tests after."**
The thought pattern: you'll come back and add tests once the code works. It feels responsible — ship first, test later, like proofreading after the draft. Why it feels right: you want momentum, and tests feel like they slow you down. What happens: tests written after the fact test the implementation, not the behavior. They pass by definition because you wrote them to match what the code already does. They catch nothing you didn't already know about. And "later" rarely arrives because there's always another feature waiting. The correction: write the test first, every time. If you genuinely can't (spike, prototype), delete the code and rewrite it with TDD. Never retrofit tests onto implementation-first code and pretend that's the same thing.

**2. "TDD is too slow."**
The thought pattern: "I could have this feature done already if I wasn't writing tests first." Why it feels right: for the first test, it's literally true — you're writing test code instead of production code. What happens: by the third test, you're faster because you're not debugging with print statements, not alt-tabbing to a browser to click through flows, not running the entire app manually to check one behavior, not fixing bugs that a test would have caught. The slowness is frontloaded and visible. The speed is distributed and invisible. The correction: track actual time-to-done (including debugging and rework), not time-to-first-working-line. TDD wins on total time for anything non-trivial.

**3. "My code is too hard to test."**
The thought pattern: testability is a property of the code — something inherited, not chosen. Why it feels right: when you're staring at a 500-line method with twelve dependencies, testing it feels impossible. What happens: you skip tests, add more untestable code, and the problem gets worse. The correction: code that's hard to test has too many dependencies, too much coupling, too many side effects. TDD forces testable design because you literally cannot proceed without writing a test first. If you can't test it, you can't maintain it either. The difficulty is the design feedback, not an obstacle to work around.

**4. "I'm testing implementation details."**
The thought pattern: tests break every time you refactor, even when behavior doesn't change. "TDD is fragile and creates maintenance overhead." Why it feels right: you ARE spending time fixing tests that shouldn't need fixing. What happens: you lose trust in TDD and stop doing it. The correction: you tested HOW the code works, not WHAT it does. Test through the public interface. Assert on outputs and observable side effects, not on internal method calls or data structures. If you can refactor the internals freely and all tests still pass, your tests are at the right abstraction level. Rewrite the brittle tests — the investment pays off immediately.

**5. "100% coverage means quality."**
The thought pattern: coverage is a concrete, measurable metric, and higher is better. "We have 95% coverage, our code is solid." Why it feels right: numbers feel objective, and stakeholders love dashboards. What happens: teams write tests that execute code without verifying behavior. A test that calls a function without assertions. A test that checks `result is not None` instead of `result == expected_value`. Coverage goes up. Quality stays flat. The correction: aim for meaningful assertions on every behavior, not a coverage percentage. Coverage is a useful tool for finding untested code, not a measure of test quality. A codebase with 70% coverage and strong assertions is more reliable than one with 95% coverage and weak assertions.

## Worked Example

**Scenario:** TDD a discount calculation service. Backend in FastAPI (Python), frontend hook in React. We'll walk through five Red-Green-Refactor cycles that progressively build up the service from nothing. Pay attention to how each cycle adds exactly one behavior and how design decisions emerge from the refactor steps rather than being planned upfront.

### Cycle 1: No discount — baseline total

**Red.** Write the first test. The `DiscountService` class doesn't exist yet.

```python
def test_order_total_no_discount():
    service = DiscountService()
    items = [{"name": "Widget", "price": 25.00}, {"name": "Gadget", "price": 15.00}]
    total = service.calculate_total(items)
    assert total == 40.00
```

Run it. Fails: `NameError: name 'DiscountService' is not defined`. This is the right failure — we're testing behavior that doesn't exist yet.

**Green.** Create the class with the minimum implementation.

```python
class DiscountService:
    def calculate_total(self, items):
        return sum(item["price"] for item in items)
```

Test passes.

**Refactor.** Nothing to clean up — one class, one method, one line of logic. Resist the urge to "prepare" the class for future features. Moving on.

### Cycle 2: Flat discount

**Red.** New test for a flat dollar-amount discount.

```python
def test_order_total_with_flat_discount():
    service = DiscountService()
    items = [{"name": "Widget", "price": 50.00}]
    total = service.calculate_total(items, discounts=[{"type": "flat", "value": 10.00}])
    assert total == 40.00
```

Fails: `calculate_total() got an unexpected keyword argument 'discounts'`. Right failure — the API doesn't accept discounts yet.

**Green.** Add the parameter and handle flat discounts.

```python
def calculate_total(self, items, discounts=None):
    total = sum(item["price"] for item in items)
    for d in (discounts or []):
        if d["type"] == "flat":
            total -= d["value"]
    return total
```

Both tests pass.

**Refactor.** The discount loop is already pulling weight — extract it into a private `_apply_discounts()` method so `calculate_total` stays focused on orchestration. Run both tests — still green. The extraction didn't change behavior, just improved structure.

### Cycle 3: Percentage discount

**Red.** Test a percentage-based discount.

```python
def test_order_total_with_percentage_discount():
    service = DiscountService()
    items = [{"name": "Widget", "price": 100.00}]
    total = service.calculate_total(items, discounts=[{"type": "percentage", "value": 10}])
    assert total == 90.00
```

Fails: percentage type not handled — the discount loop only knows about "flat." Right failure.

**Green.** Add percentage handling in `_apply_discounts()`:

```python
if d["type"] == "percentage":
    total -= total * (d["value"] / 100)
```

All three tests pass.

**Refactor.** The discount dict is getting passed around everywhere, and the `if/elif` chain is growing. Introduce a `Discount` dataclass:

```python
@dataclass
class Discount:
    type: str  # "flat" or "percentage"
    value: float
```

Update the tests to construct `Discount` objects instead of raw dicts, and update `_apply_discounts` to use attribute access instead of dict keys:

```python
def _apply_discounts(self, total, discounts):
    for d in discounts:
        if d.type == "flat":
            total -= d.value
        elif d.type == "percentage":
            total -= total * (d.value / 100)
    return total
```

Run tests — still green. The interface is cleaner, IDE autocompletion works, and the type system helps catch mistakes at development time instead of runtime.

### Cycle 4: Combined discounts — percentage first, then flat

**Red.** Test that when both discount types are present, percentage applies before flat.

```python
def test_combined_discounts_apply_percentage_first():
    service = DiscountService()
    items = [{"name": "Widget", "price": 100.00}]
    # Caller passes flat FIRST, but percentage must still apply first
    discounts = [Discount("flat", 5.00), Discount("percentage", 10)]
    total = service.calculate_total(items, discounts=discounts)
    assert total == 85.00  # percentage first: 100 * 0.9 = 90, then 90 - 5 = 85
```

Fails: returns `85.50`, not `85.00`. The current code applies discounts in the order they appear in the list. With flat first, it computes `100 - 5 = 95`, then `95 * 0.9 = 85.50`. The business rule requires percentage to always apply before flat regardless of input order. We deliberately pass the discounts in the "wrong" order ([flat, percentage]) so the test actually fails without sorting — right failure, we need to enforce ordering in the service.

**Green.** Sort discounts so percentage types always apply before flat types, and call the sort from `_apply_discounts` before iterating:

```python
def _sort_by_priority(self, discounts):
    priority = {"percentage": 0, "flat": 1}
    return sorted(discounts, key=lambda d: priority.get(d.type, 99))

def _apply_discounts(self, total, discounts):
    for d in self._sort_by_priority(discounts):   # sort first
        if d.type == "flat":
            total -= d.value
        elif d.type == "percentage":
            total -= total * (d.value / 100)
    return total
```

All four tests pass — including the `[flat, percentage]` ordering test, because the sort now forces percentage first regardless of input order.

**Refactor.** The priority mapping makes the ordering rule explicit and easy to extend if new discount types are added later. The method name `_sort_by_priority` communicates intent clearly. No further cleanup needed.

### Cycle 5: Edge case — negative total floors at zero

**Red.** What happens when discounts exceed the item total?

```python
def test_discount_cannot_produce_negative_total():
    service = DiscountService()
    items = [{"name": "Widget", "price": 50.00}]
    discounts = [Discount("flat", 100.00)]
    total = service.calculate_total(items, discounts=discounts)
    assert total == 0.00  # Not -50.00
```

Fails: returns `-50.00`. The code doesn't guard against this. Right failure — a real business rule we need to enforce. Customers don't get paid to buy things.

**Green.** Add `return max(0, total)` at the end of `calculate_total`. Test passes. All five tests green.

**Refactor.** The code is clean and clear. Nothing structural to change. But this is a good time to review all five tests together — are they readable? Do the names tell a story? Could a new team member understand the discount rules by reading only the test file? If yes, the tests are serving as living documentation.

### Frontend: React hook — one cycle

**Red.** Test a `useDiscount` hook that calls the backend API, using React Testing Library and MSW (a wire-level fake — it intercepts HTTP, it does not replace your code). `Item` and `Discount` here are the project's shared TypeScript types mirroring the backend models, assumed already defined in a shared `types` module.

```tsx
test("useDiscount returns correct total after applying discount", async () => {
  server.use(
    http.post("/api/calculate", () => HttpResponse.json({ total: 85.0 }))
  );
  const { result } = renderHook(() => useDiscount());
  act(() => {
    result.current.calculate(
      [{ name: "Widget", price: 100 }],
      [{ type: "percentage", value: 10 }, { type: "flat", value: 5 }]
    );
  });
  await waitFor(() => expect(result.current.total).toBe(85.0));
});
```

Fails: `useDiscount` doesn't exist.

**Green.** Implement the hook: `useState` for the total, a `calculate` function that POSTs to the API and updates state with the response.

```tsx
export function useDiscount() {
  const [total, setTotal] = useState<number | null>(null);
  const calculate = async (items: Item[], discounts: Discount[]) => {
    const res = await fetch("/api/calculate", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ items, discounts }),
    });
    const data = await res.json();
    setTotal(data.total);
  };
  return { total, calculate };
}
```

Test passes. **Refactor.** Extract the API call into a separate `discountApi` module so the hook handles state and the API module handles transport. Add error state handling. Tests still pass.

**What the five cycles demonstrate:** The progression went from constant behavior (sum prices), to one parameter (flat discount), to two types (percentage), to ordering rules (percentage first), to an edge case (floor at zero). Each test added exactly one new requirement. The design emerged from the tests — we didn't plan the `Discount` dataclass or the `_sort_by_priority` method upfront. The tests told us when those abstractions were needed, and we introduced them during refactor phases. That's TDD working as a design tool.

Notice what we DIDN'T do: we didn't write all five tests first. We didn't design the `Discount` dataclass before we needed it. We didn't add the zero-floor logic until a test demanded it. Every line of production code was written in response to a specific failing test. If you removed any test, the corresponding production code would have no reason to exist. That's the level of coupling between tests and behavior you want — not between tests and implementation.

Also notice the test ordering strategy. We started with the simplest possible case (no discount), then added complexity one axis at a time. This is deliberate. If you start with the most complex case, you'll write too much code in the first green step and lose the incremental design benefit. Start simple, add one dimension of complexity per cycle, and let the design reveal itself.

When you're unsure which test to write next, ask: "What's the simplest behavior that my current code doesn't support?" That's your next test. A useful heuristic for ordering:

1. **Happy path, simplest case** — the degenerate case or empty case. Establishes the basic structure.
2. **Happy path, one input** — the single simplest valid input. Gets the core logic working.
3. **Happy path, multiple inputs** — adds iteration or aggregation.
4. **Variations** — different types, modes, or configurations of the same feature.
5. **Combinations** — multiple variations interacting with each other.
6. **Edge cases** — boundaries, empty inputs, overflow, invalid states.
7. **Error cases** — what happens when things go wrong.

Each test in the sequence builds on the last. By the time you hit edge cases, the core design is solid and you're just hardening it.

## Integration

- **Use TDD during plan execution:** `exloom:executing-handoff-plans` — for each implementation step in a plan, write the failing test before the production code. The plan says what to build; TDD ensures each piece works before you move to the next step. A plan step isn't complete until its tests pass.
- **Use TDD for bug fixes:** `exloom:systematic-debugging` identifies the root cause, then TDD verifies the fix. Write a failing test that reproduces the bug, fix the code, confirm the test passes. The failing test is proof the bug existed; the passing test is proof it's fixed. This test stays in the suite forever as a regression guard. Every bug fixed with TDD is a bug that can never come back undetected.
- **Tests from TDD feed into verification:** `exloom:proving-done` — the passing test suite is concrete evidence of correctness, not a verbal claim. When verification asks "does it work?", TDD answers with a green build and a list of tested behaviors, not "I think so" or "it worked when I tried it manually."
- **In brownfield codebases:** Write characterization tests first to document existing behavior, then TDD the change. This pairs with the brownfield-first principle across all projects — respect what exists, test what you're changing, and let coverage grow organically with active development. Don't block on achieving coverage targets before shipping — coverage follows development, not the other way around.
- **During brainstorming:** `exloom:brainstorming` may produce multiple design options. When evaluating them, consider testability as a design criterion. The option that's easier to test is usually the option with better separation of concerns. TDD makes this tradeoff visible early.
- **For new team members:** TDD is one of the best onboarding tools. Reading a well-named test suite teaches you what the system does faster than reading the production code. Writing tests forces you to understand the API before you can extend it. Pair a new developer with an experienced TDD practitioner for their first few stories.
