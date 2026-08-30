# Worked Example — exploring-codebase

Extracted from SKILL.md so the skill loads lean. This is a full worked example.


**Scenario:** A developer joins a project to fix a bug in order processing. They've never seen this repo. It's a Spring Boot service. Rather than diving straight into the order code, they run a 25-minute exploration first.

### Step 1: README and CLAUDE.md

README says: "Order management service. Handles order lifecycle from creation to fulfillment. PostgreSQL for persistence, Kafka for events." CLAUDE.md exists and has an Overrides section: "We use constructor injection only — no field `@Autowired`. All money values use `BigDecimal`, never `double`."

That Overrides note is gold — it's exactly the kind of convention that causes review rejections if violated.

### Step 2: Entry Points

`OrderServiceApplication.java` with `@SpringBootApplication`. Also finds a Kafka consumer entry point: `OrderEventConsumer.java` with `@KafkaListener`. So there are two ways into this system: HTTP (REST controllers) and events (Kafka). Important — a bug in order processing could be triggered by either path.

### Step 3: Top-Level Structure

```
src/main/java/com/example/orders/
  controller/   — REST endpoints (OrderController, FulfillmentController)
  service/      — business logic (OrderService, PricingService, FulfillmentService)
  repository/   — Spring Data JPA repositories
  domain/       — JPA entities (Order, OrderLine, Customer)
  events/       — Kafka producers and consumers
  config/       — Spring configuration
```

No legacy/ or deprecated/ directories. Clean structure.

### Step 4: Trace One Operation — "Create Order"

Traced `POST /api/orders` end-to-end:

`OrderController.createOrder()` → validates request DTO → `OrderService.create()` → `PricingService.calculateTotal()` (uses BigDecimal, matches the CLAUDE.md convention) → `OrderRepository.save()` → publishes `OrderCreatedEvent` via `OrderEventProducer` → returns 201 with order ID.

Key discovery: order creation publishes a Kafka event. Anything that consumes `OrderCreatedEvent` is part of the order flow. The bug being investigated involves order totals — `PricingService` is the prime suspect, and it's the layer to focus on.

### Step 5: Tests

JUnit 5 + Testcontainers (real Postgres in tests, no mocks). Tests in `src/test/java`, mirroring the source package structure. Naming: `*Test.java` for unit, `*IT.java` for integration. Run with `./gradlew test` (unit) and `./gradlew integrationTest` (integration). Coverage threshold: 80% configured in `build.gradle`. Sampled `PricingServiceTest.java` — good example of how the team structures arithmetic tests.

### Step 6: Configuration

`application.yml` with profiles for local, staging, prod. `.env.example` present. Required env vars: `DB_URL`, `KAFKA_BROKERS`, `DB_PASSWORD`. Local uses Docker Compose for Postgres and Kafka.

### Step 7: Deploy

`.github/workflows/deploy.yml` — deploys on merge to main, through staging then prod with a manual approval gate. Containerized via `Dockerfile`.

### Step 8: Mental Model Document

Compiled all findings into `.claude/project-notes.md`. Added to the Gotchas section: "Order creation publishes Kafka events — changes to order flow must consider event consumers. Money is always BigDecimal (enforced by convention, not the type system). Two entry points: REST and Kafka."

**The payoff:** The developer now knows the bug in order totals lives in `PricingService`, that it's tested with real Postgres via Testcontainers, that they must use BigDecimal, and that their fix might affect Kafka event consumers. They spent 25 minutes and avoided: putting the fix in the wrong layer, using `double` and failing review, and missing the event-consumer side effect. The bug fix itself is now a focused, well-targeted change.
