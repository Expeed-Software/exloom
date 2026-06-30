# CLAUDE.md — Default (Stack-Agnostic)

> **Note:** You are using the default fallback template because no stack-specific template
> matched this project. Consider writing a stack-specific template and contributing it back
> to the team via the `capturing-learnings` skill.

## Project Overview

[TBD — fill in: what this service does, who uses it, and where it fits in the system.]

- **Service name:** [TBD]
- **Team owner:** [TBD]
- **Primary language/runtime:** [Detect on use]
- **Repo type:** service | library | frontend | monorepo | other

## Stack

Detect on use — inspect `package.json`, `pom.xml`, `build.gradle`, `pyproject.toml`,
`Cargo.toml`, `go.mod`, or equivalent to determine the actual stack, then fill in:

- **Language:** [Detect on use]
- **Framework:** [Detect on use]
- **Build tool:** [Detect on use]
- **Test framework:** [Detect on use]
- **Database/persistence:** [Detect on use]

## Conventions

- Follow existing patterns in the codebase first — brownfield wins.
- For new code, apply this repo's established conventions; if the team has documented standards, follow them.
- Naming: match the dominant style already present in the codebase.
- File layout: match the existing module/package structure.
- No new dependencies without checking whether an existing library covers the need.

## Testing

- [Detect on use — identify the existing test framework and document it here.]
- Test against real implementations of what you own: real database (via a throwaway container such as Testcontainers), real HTTP via the framework's test client. Don't mock your own repositories or services — those tests pass while the system is broken.
- Fake only what you don't own: third-party APIs, payment/email/SMS gateways, and non-determinism (clock, randomness). Prefer wire-level fakes (a stub/mock web server) over mock objects.
- Cover business logic; add integration tests for every external I/O path (database, HTTP, message queues).
- Test file naming convention: [match project convention on use].

## Running Locally

- [Detect on use — document the actual dev run command here after inspecting the project.]
- Environment variables required: see `.env.example` if present.

## Common Commands

```bash
# Build
[Detect on use]

# Test
[Detect on use]

# Lint / format
[Detect on use]
```

## Baselines

Document this project's own conventions for error handling, logging, and security here (or link the team's standards). New code follows them; existing code is not refactored to match.

## Overrides

_(Empty by default — use this section to explicitly override any default with a justification)_
