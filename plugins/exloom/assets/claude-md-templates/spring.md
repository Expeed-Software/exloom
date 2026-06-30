# CLAUDE.md — Spring Boot

## Project Overview

[TBD — fill in: what this service does, who uses it, and where it fits in the system.]

- **Service name:** [TBD]
- **Team owner:** [TBD]
- **Port (local):** [TBD, default 8080]
- **Database:** [TBD — e.g., PostgreSQL 15]

## Stack

- **Language:** Java 21+
- **Framework:** Spring Boot 3.x
- **Build tool:** Maven (`./mvnw`) or Gradle (`./gradlew`) — detect from project root
- **Persistence:** Spring Data JPA + Hibernate
- **Security:** Spring Security 6.x
- **HTTP client:** Spring WebClient (reactive) or RestTemplate (avoid new usage)
- **Migrations:** Flyway or Liquibase — detect from dependencies

## Conventions

Follow this repo's existing conventions, plus these Spring-specific rules:

### Dependency Injection
- **Constructor injection only.** Never use `@Autowired` on fields or setters.
- For single-constructor classes, omit `@Autowired` entirely (Spring infers it).
- Lombok `@RequiredArgsConstructor` is acceptable if the project already uses Lombok.

### DTOs and Records
- Prefer Java records for immutable DTOs (request/response bodies, projections).
- Use records for value objects; use classes only when mutability is genuinely required.

### Error Handling
- Implement your org's error envelope via `@RestControllerAdvice`.
- All unhandled exceptions must produce a structured JSON error body — no stack traces to clients.
- Map domain exceptions to HTTP status codes in one central advice class.

### Controllers
- Keep controllers thin: validate input, delegate to service, return response.
- Use `@Valid` / `@Validated` on request bodies; let the advice handle `MethodArgumentNotValidException`.
- No business logic inside `@RestController` classes.

### Transactions
- `@Transactional` belongs on service methods, not controllers or repositories.
- Default propagation is fine for most cases; document deviations.

### Configuration
- Externalize all tunable values via `application.yml` (not `.properties`).
- Use `@ConfigurationProperties` records for typed config binding.
- Never hardcode URLs, credentials, timeouts, or port numbers in source.

### Naming
- Packages: `com.example.<service>.<layer>` (controller, service, repository, domain, config).
- Classes: `UserService`, `UserController`, `UserRepository` — no `Impl` suffix unless unavoidable.

## Testing

- **Principle:** test against real implementations of what you own; fake only what you don't. Don't mock your own repositories or services — a test that mocks the repository passes while the query is broken.
- **Integration tests (the default here):** `@SpringBootTest` + Testcontainers for the real database/infrastructure; exercise the real persistence and HTTP layers.
- **Unit tests:** JUnit 5 for pure logic with no I/O (calculations, mappers, domain rules) — not for wiring.
- **External boundaries:** fake only third-party services (payment, email, external APIs) and the clock — prefer a wire-level fake (e.g. WireMock / MockWebServer) over a mock object.
- **Test naming:** `<ClassUnderTest>Test` for units, `<ClassUnderTest>IT` for integration.

## Running Locally

```bash
# Maven
./mvnw spring-boot:run

# Gradle
./gradlew bootRun
```

Ensure required environment variables are set (see `.env.example` or `application-local.yml`).

## Common Commands

```bash
# Run tests (Maven)
./mvnw test

# Run tests + integration tests (Maven)
./mvnw verify

# Apply code formatting (Maven + Spotless)
./mvnw spotless:apply

# Run tests (Gradle)
./gradlew test

# Run all checks (Gradle)
./gradlew check

# Apply code formatting (Gradle + Spotless)
./gradlew spotlessApply

# Build artifact
./mvnw package -DskipTests   # Maven
./gradlew build -x test      # Gradle
```

## Baselines

Document this project's own conventions for error handling, logging, and security here (or link the team's standards). New code follows them; existing code is not refactored to match.

## Overrides

_(Empty by default — use this section to explicitly override any default with a justification)_
