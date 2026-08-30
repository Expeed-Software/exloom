# Worked Example — systematic-debugging

Extracted from SKILL.md so the skill loads lean. This is a full worked example.


This example walks through all 7 steps including a wrong first hypothesis. The messy middle — the hypothesis that looked right but was not — is where real debugging happens. Pay attention to how the wrong hypothesis still produced useful evidence that narrowed the search.

**Scenario:** A Spring Boot payments API. The QA report states: "Order with items priced at $1.15, $0.70, and $0.25 shows an invoice total of $2.10, but the customer's card is charged $2.09 — a cent short."

The temptation: glance at the code, see a `double` somewhere, change it to `BigDecimal`, and call it done. That might even work. But you would not know whether it is the only cause, why the invoice total and the charged amount disagree, or whether some other money path has the same flaw. Follow the process.

### Step 1: Reproduce

Write the reproduction case before anything else:

```
POST /api/orders
Body: { "items": [{"sku":"A","price":1.15},{"sku":"B","price":0.70},{"sku":"C","price":0.25}] }
Expected: invoice total 2.10, card charged 2.10 (210 cents)
Actual:   invoice total 2.10, card charged 2.09 (209 cents)
```

Run it three times against the local dev server. The charge is $2.09 every time — deterministic, not intermittent. Note the precise discrepancy: the invoice total is correct ($2.10); only the *charged* amount is short. That asymmetry is the most important clue in the report — write it down exactly, do not flatten it to "the total is wrong."

### Step 2: Isolate

Find the boundary:

- Order totaling $3.50 (items $1.00, $2.00, $0.50): invoice $3.50, charged $3.50. Correct.
- Order from the report, totaling $2.10 (items $1.15, $0.70, $0.25): invoice $2.10, charged $2.09. Wrong.
- A different order also totaling $2.10 (items $0.70, $0.70, $0.70): invoice $2.10, charged $2.09. Same symptom.

Two facts emerge. First, the invoice total is correct in every case — so the display/total path is not where the money is lost. Second, the charge breaks for the $2.10 total but not the $3.50 total, and it breaks regardless of which SKUs produce the $2.10. The bug is in the charge path and depends on the total's *value*, not the item count or specific prices. Smallest failing case: any order whose total is $2.10.

### Step 3: First hypothesis

The cent is lost somewhere in the charge path. Two candidates:

1. The payment gateway rounds the amount down on its side.
2. Our code computes the cents amount wrong before sending it.

Start with hypothesis 1: "We send 210 cents and the gateway truncates to 209."

Falsifiable prediction: if the gateway is at fault, the cents value we compute and send should be 210; only the gateway's recorded charge would be 209.

### Step 4: Test first hypothesis

Add a log line where the charge request is built, before it leaves our service:

```java
log.debug("Charging {} cents for order {}", amountInCents, order.getId());
```

Result: the log shows `Charging 209 cents`. We are sending 209, not 210. Hypothesis refuted — the gateway is faithfully charging exactly what we send. The bug is upstream of the gateway, in our own cents conversion.

This is not a failure — refuting a hypothesis is progress. We have eliminated the gateway, the network, and their rounding policy from consideration and localized the bug to one line of our own code: wherever `amountInCents` is computed.

### Step 3 again: Second hypothesis

With the gateway eliminated, the bug is in our cents conversion.

"The order total is held as a `double`, and converting it to an integer number of cents truncates the fractional part instead of rounding."

Falsifiable prediction: the conversion will look like `(long)(total * 100)` with `total` a `double` holding a value microscopically below 2.10. Reproduce in a REPL: sum `1.15 + 0.70 + 0.25` as doubles (→ `2.0999999999999996`), multiply by 100 (→ `209.99999999999997`), cast to `long` (→ `209`).

### Step 4 again: Test second hypothesis

Search `PaymentService.java` for the cents conversion:

```java
double total = order.getItems().stream()
    .mapToDouble(i -> i.getPrice().doubleValue())
    .sum();                                  // 2.0999999999999996
long amountInCents = (long) (total * 100);   // (long) 209.99999999999997 = 209
```

Confirmed. Prices are summed as `double` (producing `2.0999999999999996`, a hair below 2.10), and the cast to cents truncates: `total * 100` is `209.99999999999997`, and `(long)` drops the fraction to `209`. The invoice total looked correct only because the display formatter rounds `2.0999999999999996` to `2.10` for presentation — but the charge path *truncates* instead of rounding, so it loses the cent. Root cause: money held and converted as `double`. Mechanism identified down to the line.

### Step 5: Fix at root cause

Extract the cents conversion into a method that computes the total as `BigDecimal` and converts exactly (this is the `amountInCents` the regression test in Step 7 calls):

```java
long amountInCents(Order order) {
    BigDecimal total = order.getItems().stream()
        .map(Item::getPrice)
        .reduce(BigDecimal.ZERO, BigDecimal::add);     // exactly 2.10
    return total.movePointRight(2).longValueExact();   // exactly 210
}
```

This removes `double` from the money path entirely. The root cause — representing currency as binary floating point — is made impossible, not patched with a rounding heuristic.

Note what we did NOT do:
- We did NOT change `(long)(total * 100)` to `Math.round(total * 100)`. That hides this case but still routes money through `double`, and rounding can bite the other direction (over-charging) on different inputs.
- We did NOT keep the `double` sum and fix only the cast. The sum is already imprecise; fixing only the conversion leaves a latent fault.
- We did NOT add a "+0.001 then truncate" fudge factor. Financial code does not tolerate fudge.

The fix eliminates the entire category of floating-point money error for this path, not just the specific instance in the QA report.

### Step 6: Verify

Run the full verification stack — all three layers:

**Layer 1 — Isolated case:** Order totaling $2.10 ($1.15 + $0.70 + $0.25): `amountInCents` is now 210, card charged $2.10. Correct. (Was 209 before fix.)

**Layer 2 — Original scenario:** The exact reproduction from the QA report — invoice $2.10 and card charged $2.10 (210 cents). The $0.70 × 3 variant also charges 210. The clean $3.50 order still charges 350. No regression.

**Layer 3 — Regression sweep:** Full test suite passes, zero failures, zero skipped.

All three layers are green. The fix can be committed with confidence that it resolves the reported bug without introducing regressions.

### Step 7: Regression test

```java
@Test
void test_order_charged_in_exact_cents() {
    Order order = new Order(List.of(
        new Item("A", new BigDecimal("1.15")),
        new Item("B", new BigDecimal("0.70")),
        new Item("C", new BigDecimal("0.25"))
    ));

    long cents = paymentService.amountInCents(order);

    assertThat(cents).isEqualTo(210L);   // not 209
}
```

Revert the fix temporarily and run the test: it fails with `expected 210 but was 209`. Re-apply the fix: test passes. This confirms the regression test actually catches the bug — a regression test that passes regardless of the fix is worthless.

The test is named after the behavior (the order is charged the exact cents), not the implementation detail (uses BigDecimal). If someone later swaps in a money library, the test still validates correctness because it asserts on the charged amount, not the mechanism.

**Key takeaway from this example:** The wrong first hypothesis (the gateway) was not wasted time — it conclusively eliminated everything outside our service and localized the bug to one line, fast. That is the value of falsifiable hypotheses: even when wrong, they narrow the search. And note where the cent actually hid — the invoice total *looked* correct because display rounding masked an already-imprecise `double`; only the truncating charge path exposed it. A guess-and-patch that "saw a double and switched to BigDecimal" might have landed the same fix, but without isolation it could have missed that the display path relied on the same bad value, and without the regression test it would ship with no guard against recurrence.
