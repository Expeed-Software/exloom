# CLAUDE.md — Strapi

## Project Overview

[TBD — fill in: what this CMS/API does, who uses it, and where it fits in the system.]

- **Service name:** [TBD]
- **Team owner:** [TBD]
- **Strapi version:** [TBD — 4.x or 5.x]
- **Database:** [TBD — typically PostgreSQL 15+]
- **Port (local):** 1337 (default)

## Stack

- **CMS:** Strapi 4.x or 5.x — detect from `package.json`
- **Runtime:** Node.js 20+
- **Language:** JavaScript or TypeScript — detect from project config
- **Database:** PostgreSQL (production default); SQLite acceptable for local dev only
- **Package manager:** npm or yarn — detect from lockfile

## Conventions

Follow this repo's existing conventions, plus these Strapi-specific rules:

### Content Types
- Define content types through the Strapi admin UI first; then commit the generated schema
  files (`src/api/<content-type>/content-types/<content-type>/schema.json`) to git.
- Never hand-edit schema JSON files while the server is running — use the Content-Type Builder.
- Schema files are source of truth; do not diverge them from what the UI shows.

### Custom Controllers and Services
- Custom controllers extend (or replace) the generated Strapi controller using
  `strapi.controller('api::<content-type>.<content-type>')` factory pattern.
- Custom services extend generated services the same way — never overwrite generated files directly.
- Keep controller logic minimal: delegate to services for business rules.
- Use Strapi's `EntityService` / `DocumentService` (v5) instead of raw DB queries wherever possible.

### Plugin Architecture
- Reusable cross-cutting features (auth hooks, custom field types, integrations) belong in
  Strapi plugins under `src/plugins/`.
- Single-use customizations belong in `src/api/` or `src/extensions/`.
- Register plugins in `config/plugins.js` (or `.ts`); document each plugin's purpose.

### Policies and Middlewares
- Route-level authorization: use Strapi policies (`src/api/<ct>/policies/`).
- Request/response transformation: use Strapi middlewares.
- Do not put authorization logic inside controllers or services.

### Environment and Config
- All environment-specific values (DB credentials, API keys, S3 buckets) go in `.env`.
- Use `config/` files for structural config; never hardcode environment values in config files.
- Commit `.env.example` with all required keys documented; never commit `.env`.

## Testing

- **Principle:** test against real implementations of what you own; fake only what you don't (third-party APIs, the clock) and prefer wire-level fakes.
- **Unit tests:** Jest for custom services, policies, and utility functions (pure logic).
- **Integration tests (the default here):** boot Strapi in test mode against a real test database (PostgreSQL via Testcontainers for CI parity); exercise real services, policies, and lifecycle hooks.
- **Controller paths:** prefer testing the underlying service logic, plus integration tests through the booted instance for critical controller paths.
- Focus test coverage on: custom services, policies, lifecycle hooks, and plugin logic.
- Generated CRUD controllers that are unchanged do not need tests.

## Running Locally

```bash
# Development mode (admin UI + auto-reload)
npm run develop

# Production mode (no admin UI, no auto-reload)
npm run start
```

Admin UI is accessible at `http://localhost:1337/admin` in development mode.

Database must be running before starting Strapi. Use Docker Compose if provided:
```bash
docker compose up -d db
```

## Common Commands

```bash
# Development with admin panel
npm run develop

# Build admin panel for production
npm run build

# Start in production mode
npm run start

# Strapi CLI (content-type generation, plugin scaffolding, etc.)
npm run strapi -- --help

# Generate a new API (content type + CRUD)
npm run strapi generate

# Export content (for seeding or migration)
npm run strapi export

# Run tests
npm test
```

## Baselines

Document this project's own conventions for error handling, logging, and security here (or link the team's standards). New code follows them; existing code is not refactored to match.

## Overrides

_(Empty by default — use this section to explicitly override any default with a justification)_
