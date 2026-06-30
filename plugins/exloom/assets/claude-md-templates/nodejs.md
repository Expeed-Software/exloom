# CLAUDE.md — Node.js / TypeScript

## Project Overview

[TBD — fill in: what this service does, who uses it, and where it fits in the system.]

- **Service name:** [TBD]
- **Team owner:** [TBD]
- **Framework:** [TBD — e.g., Express 4, NestJS 10, Fastify 4]
- **Port (local):** [TBD, default 3000]
- **Database:** [TBD]

## Stack

- **Runtime:** Node.js 20+ LTS
- **Language:** TypeScript (strict mode — `"strict": true` in tsconfig)
- **Module system:** ESM (`"type": "module"` in package.json; `import`/`export` everywhere)
- **Package manager:** npm or pnpm — detect from lockfile (`package-lock.json` vs `pnpm-lock.yaml`)
- **Framework:** Detect from project (Express / NestJS / Fastify — document above)
- **ORM / query builder:** [Detect — Prisma, Drizzle, Knex, TypeORM, etc.]

## Conventions

Follow this repo's existing conventions, plus these Node-specific rules:

### TypeScript
- `"strict": true` is non-negotiable. Every file must compile clean.
- No `any` without an explicit inline comment justifying why it is unavoidable.
- Prefer `unknown` over `any` for values of undetermined type; narrow explicitly.
- No `ts-ignore` or `ts-expect-error` without an accompanying ticket reference.
- Return types on all exported functions — don't rely on inference for public API.

### Async patterns
- `async`/`await` only. No raw `.then()/.catch()` chains, no callbacks.
- Unhandled promise rejections crash the process — always await or explicitly handle.
- Use `Promise.all` / `Promise.allSettled` for concurrent operations; don't serialize what can run in parallel.

### Error handling
- Explicit error strategy: either a `Result<T, E>` type (functional) or thrown typed domain errors.
- No `throw new Error("string")` for domain errors — create typed error classes or discriminated unions.
- Implement your org's error envelope in the framework's error/exception handler so all HTTP errors
  return a consistent JSON structure.

### Modules and imports
- Barrel files (`index.ts`) are acceptable at module boundaries; avoid deep internal re-exports.
- Use path aliases (configured in `tsconfig.json` and bundler) instead of `../../..` traversals.
- No circular dependencies — use a linting rule or `madge` to enforce.

### Code style
- ESLint + Prettier (detect config files in project root).
- `const` by default; `let` only when reassignment is required; never `var`.
- Destructure when it improves readability; don't destructure just to destructure.

## Testing

- **Principle:** test against real implementations of what you own; fake only what you don't. Don't mock your own modules or the database — use the real thing.
- **Framework:** Vitest (preferred for ESM projects) or Jest + ts-jest.
- **HTTP integration:** Supertest (or the framework's test client) against the running app.
- **Database integration:** Testcontainers (Node.js flavor: `testcontainers` npm package) for a real DB.
- **External boundaries:** fake only third-party HTTP and the clock — prefer a wire-level fake (e.g. `nock` / MSW / a stub server) over a mock object.
- **E2E:** Playwright if the service has a UI; skip for pure APIs.
- **Test file naming:** `<module>.test.ts` colocated or in a `__tests__` folder — match project convention.
- Aim for behavior tests, not implementation tests.

## Running Locally

```bash
# npm
npm run dev

# pnpm
pnpm dev
```

Ensure a `.env` file exists (copy from `.env.example`). Required variables: [document here].

## Common Commands

```bash
# Run tests
npm test          # or: pnpm test

# Run tests in watch mode
npm run test:watch

# Lint
npm run lint      # or: pnpm lint

# Type-check (without emitting)
npm run typecheck

# Build (compile TypeScript)
npm run build

# Format (Prettier)
npm run format
```

## Baselines

Document this project's own conventions for error handling, logging, and security here (or link the team's standards). New code follows them; existing code is not refactored to match.

## Overrides

_(Empty by default — use this section to explicitly override any default with a justification)_
