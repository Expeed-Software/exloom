# Worked Example — test-driven-development

Extracted from SKILL.md so the skill loads lean. This is a full worked example.


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
