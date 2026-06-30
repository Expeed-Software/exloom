# CLAUDE.md — Micronaut

## Project Overview

[TBD — fill in: what this service does, who uses it, and where it fits in the system.]

- **Service name:** [TBD]
- **Team owner:** [TBD]
- **Port (local):** [TBD, default 8080]
- **Database:** [TBD — e.g., PostgreSQL 15]

## Stack

- **Language:** Java 21+
- **Framework:** Micronaut 4.x
- **Build tool:** Gradle (`./gradlew`)
- **Persistence:** Micronaut Data (JPA or JDBC — detect from project)
- **HTTP client:** Micronaut declarative `@Client`
- **Migrations:** Flyway (Micronaut default)
- **GraalVM native:** optional — check `build.gradle` for `graalvmNative` plugin

## Conventions

Follow this repo's existing conventions, plus these Micronaut-specific rules:

### Dependency Injection
- Use Micronaut's compile-time DI — annotations are processed at build time, not runtime.
- `@Singleton`, `@Prototype`, `@RequestScope` for bean scopes; choose deliberately.
- Constructor injection is preferred; Micronaut supports it natively.
- No Spring annotations (`@Autowired`, `@Component`, `@Service`) — use Micronaut equivalents.

### Controllers and Clients
- Use `@Controller("/path")` for HTTP endpoints.
- Use `@Client("service-id")` or `@Client("${service.url}")` for declarative HTTP clients.
- Keep controllers thin: validate, delegate to `@Singleton` service, return response.

### DTOs and Records
- Prefer Java records for immutable request/response DTOs.
- Annotate with `@Introspected` when used with Micronaut serialization (Jackson or Serde).

### Error Handling
- Implement your org's error envelope via `@Error(global = true)` handlers or
  `ExceptionHandler<T>` implementations.
- All unhandled exceptions must produce a structured JSON error body.
- Centralize exception-to-status mapping; do not scatter `@Error` across controllers.

### Configuration
- Externalize all tunable values via `application.yml`.
- Use `@ConfigurationProperties` for typed config; pair with `@Requires` for conditional beans.
- Never hardcode URLs, credentials, timeouts, or port numbers in source.

### Naming
- Packages: `com.example.<service>.<layer>` (controller, service, repository, domain, config).
- No `-Impl` suffix unless the interface/implementation split is genuinely necessary.

## Testing

- **Principle:** test against real implementations of what you own; fake only what you don't. Don't mock your own beans or repositories — those tests validate the mock, not the system.
- **Integration tests (the default here):** `@MicronautTest` + Testcontainers for the real database/infrastructure, with the embedded server + `@Client` injection for real HTTP.
- **Unit tests:** JUnit 5 for pure logic with no I/O.
- **External boundaries:** fake only third-party services and the clock — prefer a wire-level fake (e.g. MockWebServer / an embedded stub server) over a mock object.
- **Test naming:** `<ClassUnderTest>Test` for units, `<ClassUnderTest>IT` for integration.

## Running Locally

```bash
./gradlew run
```

For continuous development with auto-reload:
```bash
./gradlew -t run   # continuous build + restart
```

Ensure required environment variables are set (see `.env.example` or `application-local.yml`).

## Common Commands

```bash
# Run unit tests
./gradlew test

# Run all checks (test + lint + static analysis)
./gradlew check

# Build shadow/fat JAR
./gradlew shadowJar

# Build native binary (if GraalVM configured)
./gradlew nativeCompile

# Apply code formatting (if Spotless configured)
./gradlew spotlessApply
```

## Baselines

Document this project's own conventions for error handling, logging, and security here (or link the team's standards). New code follows them; existing code is not refactored to match.

## Overrides

_(Empty by default — use this section to explicitly override any default with a justification)_
