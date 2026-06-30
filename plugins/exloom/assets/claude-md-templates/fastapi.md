# CLAUDE.md — FastAPI

## Project Overview

[TBD — fill in: what this service does, who uses it, and where it fits in the system.]

- **Service name:** [TBD]
- **Team owner:** [TBD]
- **Port (local):** [TBD, default 8000]
- **Database:** [TBD — e.g., PostgreSQL 15]

## Stack

- **Language:** Python 3.12+
- **Framework:** FastAPI (latest stable)
- **Validation:** Pydantic v2
- **ORM / query layer:** SQLAlchemy 2.x (if database is used) — detect from `pyproject.toml`
- **Migrations:** Alembic (if SQLAlchemy is present)
- **Package manager:** uv (preferred) or poetry — detect from `pyproject.toml` / `uv.lock`
- **ASGI server:** Uvicorn

## Conventions

Follow this repo's existing conventions, plus these FastAPI-specific rules:

### Type Hints
- Type hints everywhere — every function parameter, return type, and class attribute.
- No bare `dict`, `list`, or `tuple` — use `dict[str, Any]`, `list[str]`, etc.
- Prefer `X | None` over `Optional[X]` (Python 3.10+ union syntax).
- Run `mypy app` in strict mode; the CI gate must pass clean.

### Pydantic Models
- All request bodies and response schemas are Pydantic `BaseModel` subclasses (v2).
- Use `model_config = ConfigDict(from_attributes=True)` for ORM-mapped response models.
- Separate request models from response models — do not reuse the same class for input and output.
- Validators (`@field_validator`, `@model_validator`) for business-rule validation; not for type coercion.

### Dependency Injection
- Use FastAPI's `Depends()` for all cross-cutting concerns: DB sessions, auth, pagination params.
- Database session lifecycle: inject via `Depends(get_db)` — never instantiate sessions inside route handlers.
- Keep route handlers thin: validate, delegate to a service layer, return response model.

### Error Handling
- Implement your org's error envelope via FastAPI `@app.exception_handler` registrations.
- Use `HTTPException` for HTTP-level errors; use custom exception classes for domain errors.
- Map domain exceptions to HTTP exceptions in one central handler — not scattered across routes.
- No stack traces in HTTP responses to clients.

### Project Layout
```
app/
  main.py          # FastAPI app factory, router registration, lifespan hooks
  api/             # Route handlers grouped by resource
  schemas/         # Pydantic request/response models
  services/        # Business logic
  models/          # SQLAlchemy ORM models (if DB used)
  db/              # Database session, engine, migrations helpers
  core/            # Config, security, shared utilities
```

### Configuration
- Use Pydantic `BaseSettings` for all config — reads from environment variables automatically.
- Never hardcode URLs, credentials, secrets, or timeouts in source.
- One `Settings` instance per application, created at startup via `@lru_cache`.

## Testing

- **Principle:** test against real implementations of what you own; fake only what you don't. Use a real DB — don't mock your own repositories or query layer.
- **Framework:** pytest + pytest-asyncio (if using async routes).
- **HTTP testing:** `httpx.AsyncClient` with FastAPI's `ASGITransport` (or `TestClient` for sync).
- **Database integration:** Testcontainers Python (`testcontainers` package) for real PostgreSQL.
- **External boundaries:** fake only third-party HTTP calls and the clock — prefer a wire-level fake (e.g. `respx` / a stub server) over patching your own functions.
- **Test layout:** `tests/unit/` for pure logic, `tests/integration/` for route + DB tests.
- **Fixtures:** Use pytest fixtures for app setup, DB session, and test data — avoid global state.

## Running Locally

```bash
# uv
uvicorn app.main:app --reload

# poetry
poetry run uvicorn app.main:app --reload
```

Interactive API docs available at `http://localhost:8000/docs` (Swagger UI) and
`http://localhost:8000/redoc` when running in development mode.

Ensure a `.env` file exists (copy from `.env.example`). Required variables: [document here].

## Common Commands

```bash
# Run tests
pytest

# Run tests with coverage
pytest --cov=app --cov-report=term-missing

# Lint (ruff)
ruff check app tests

# Format (ruff)
ruff format app tests

# Type-check
mypy app

# Apply lint fixes
ruff check --fix app tests

# Database migrations (Alembic)
alembic upgrade head
alembic revision --autogenerate -m "description"

# Install dependencies (uv)
uv sync

# Install dependencies (poetry)
poetry install
```

## Baselines

Document this project's own conventions for error handling, logging, and security here (or link the team's standards). New code follows them; existing code is not refactored to match.

## Overrides

_(Empty by default — use this section to explicitly override any default with a justification)_
