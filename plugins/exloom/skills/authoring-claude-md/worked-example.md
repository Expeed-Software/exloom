# Worked Example — authoring-claude-md

One repo taken through every step.

**Scenario:** Brownfield mode on an existing Node.js Express API with TypeScript. The developer just joined this project and found it has no CLAUDE.md.

**Step 1 — Detect stack.**

Found `package.json` at the repo root. Reading its contents:
- `engines.node`: `">=20"`
- `devDependencies`: `typescript` 5.3, `jest` 29, `ts-jest`, `@types/express`
- `dependencies`: `express` 4.18, `@prisma/client` 5.x, `pino` 8.x, `zod` 3.x
- `scripts.start`: `"node dist/app.js"`, `scripts.dev`: `"tsx watch src/app.ts"`

Also found `.nvmrc` specifying `20.11.0` and a `Dockerfile` with `FROM node:20-alpine`.

No other build files at root. Checked subdirectories — no `pom.xml`, no `build.gradle`. This is a single-stack Node.js TypeScript project.

**Step 2 — Scan structure.**

Top two directory levels:
```
src/
  controllers/    -- route handlers
  services/       -- business logic
  middleware/     -- auth, error handling, logging
  prisma/         -- Prisma client setup
  types/          -- shared TypeScript types
  config.ts       -- environment config with zod validation
  app.ts          -- Express app setup and middleware chain
__tests__/
  controllers/    -- unit tests for controllers
  services/       -- unit tests for services
  integration/    -- API integration tests with supertest
prisma/
  schema.prisma   -- database schema
  migrations/     -- migration history
.env.example
tsconfig.json
jest.config.ts
package.json
```

Pattern: layered architecture (controllers call services, services call Prisma). Tests mirror the source structure in a separate `__tests__/` root. Integration tests are separated from unit tests. Prisma schema and migrations live at the repo root, not inside `src/`.

**Step 3 — Sample conventions.**

Read five files: `src/controllers/userController.ts`, `src/services/orderService.ts`, `src/middleware/authMiddleware.ts`, `__tests__/services/orderService.test.ts`, `src/config.ts`.

Observations:
- **Naming:** camelCase for variables and functions, PascalCase for types, interfaces, and classes. Files use camelCase (`userController.ts`, not `user-controller.ts`).
- **Indentation:** 2 spaces, no tabs. Consistent across all sampled files.
- **Error handling:** Services return `Result<T, AppError>` — a discriminated union. Services never throw. Controllers unwrap the Result and map `AppError` to HTTP status codes. This is stricter than thrown exceptions.
- **Imports:** Grouped in three blocks separated by blank lines — Node stdlib, then npm packages, then internal modules. Sorted alphabetically within each block.
- **Tests:** `describe`/`it` blocks. Test files named `*.test.ts`. Each test file mirrors one source file. Integration tests use `supertest` against the Express app.

**Step 4 — Choose template.**

`nodejs.md` matches — Node.js with TypeScript. Express is a standard Node.js framework covered by this template.

**Step 5 — Draft CLAUDE.md.**

Fill the `nodejs.md` template with observed patterns. Key decision point: the `Result<T, AppError>` pattern is stricter than your org's error handling baseline, which allows thrown domain errors caught by Express error middleware. The codebase's pattern is better for this project — it makes error handling explicit at every call site and prevents unhandled exceptions. Document the `Result` pattern as the project's error handling convention, not your org's default.

Also noted: `zod` is used for runtime validation of environment config and request bodies. This is an established pattern worth documenting — new endpoints should use zod schemas for input validation.

**Step 6 — Annotate baselines.**

Add the Baselines section:
- **Planning workflow:** added, no conflict with existing patterns
- **Review workflow:** added, no conflict
- **Error envelope:** added — compatible with the Result pattern. The controller layer already maps `AppError` variants to a consistent `{ error: string, code: string, details?: unknown }` JSON envelope.
- **Logging:** added — project already uses `pino` structured logging, which aligns with the baseline. Noted `pino` specifically in the conventions.
- **Security:** added — `.env.example` demonstrates the env-vars-only pattern. No secrets found in source.
- **Test coverage 80% for new code:** added to baselines. Existing coverage is 73%. Added an Override: "Legacy service modules (`orderService`, `inventoryService`) are below 80% — coverage target applies to new code and new modules only."

**Step 7 — Present to user.**

Showed the complete draft. User feedback:
- "We use pnpm, not npm — all build commands should reference pnpm." Fixed `npm run` to `pnpm` in the Build and Run section.
- "The Result pattern was introduced by our tech lead — good that you caught it. Keep it prominent."

User approved. File written with `docs: add CLAUDE.md for order-api`.

**Key moment:** The codebase uses a stricter error handling pattern than the baseline recommends. Brownfield wins — document what is there, do not downgrade it to match the baseline. The CLAUDE.md reflects the project's actual `Result<T, AppError>` pattern, and your org's error baseline is noted as compatible rather than authoritative.
