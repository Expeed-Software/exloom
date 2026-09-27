# CLAUDE.md — .NET

## Project Overview

[TBD — fill in: what this service does, who uses it, and where it fits in the system.]

- **Service name:** [TBD]
- **Team owner:** [TBD]
- **Port (local):** [TBD, see `Properties/launchSettings.json`]
- **Database:** [TBD — e.g., SQL Server 2022]

## Stack

- **Language:** C# 12+
- **Framework:** ASP.NET Core 8.x
- **Build tool:** `dotnet` CLI — the solution file at the root is the build entry point
- **Persistence:** Entity Framework Core — detect from package references
- **Migrations:** EF Core migrations under `Migrations/`
- **Package versions:** `Directory.Packages.props` if the repo uses central package management

## Conventions

Follow this repo's existing conventions, plus these .NET-specific rules:

### Dependency Injection
- Register services in one composition root (`Program.cs` or an extension method per module).
- Constructor injection only; no service locator (`IServiceProvider.GetService` in business code).

### Async
- `async` all the way down. Never `.Result` or `.Wait()` on a task.
- No `async void` except event handlers.
- Pass `CancellationToken` through every I/O call.

### Error Handling
- One exception-handling middleware produces the org's error envelope (ProblemDetails).
- No stack traces to clients.

### Configuration
- Bind typed options with `IOptions<T>` from `appsettings.json`; secrets come from user secrets or the environment, never from committed files.

### Disposal
- `using` / `await using` for every `IDisposable` / `IAsyncDisposable` the code creates.
- `HttpClient` through `IHttpClientFactory`, never `new HttpClient()` per call.

## Testing

- **Principle:** test against real implementations of what you own; fake only what you don't.
- **Integration tests (the default here):** `WebApplicationFactory` + Testcontainers for the real database.
- **Unit tests:** xUnit (or the repo's framework) for pure logic.
- **Test projects:** `<Project>.Tests`, `<Project>.UnitTests` or `<Project>.IntegrationTests`; files named `<ClassUnderTest>Tests.cs`.
- **Pinned proof command:** commit `.claude/exloom-test-command`, e.g. `dotnet test App.sln`, when the root holds more than one solution or project.

## Running Locally

```bash
dotnet run --project src/<Project>
```

## Common Commands

```bash
# Run all tests
dotnet test

# Add a migration
dotnet ef migrations add <Name> --project src/<Project>

# Format
dotnet format
```

## Baselines

Document this project's own conventions for error handling, logging, and security here (or link the team's standards). New code follows them; existing code is not refactored to match.

## Overrides

_(Empty by default — use this section to explicitly override any default with a justification)_
