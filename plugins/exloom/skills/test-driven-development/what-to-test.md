# What to Test and What Not to Test — test-driven-development

Extracted from SKILL.md so the skill loads lean.


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
