# CLAUDE.md — Angular

## Project Overview

[TBD — fill in: what this frontend does, who uses it, and where it fits in the system.]

- **App name:** [TBD]
- **Team owner:** [TBD]
- **Angular version:** [TBD — 17+]
- **Design system:** [TBD — e.g., Angular Material, internal DS]
- **API base URL (local):** [TBD]

## Stack

- **Framework:** Angular 17+ (standalone components as default)
- **Language:** TypeScript strict mode
- **Async:** RxJS for streams; Angular signals for reactive local state (Angular 17+)
- **State management:** NgRx (store + effects) or Angular signals — detect from project
- **HTTP:** Angular `HttpClient`
- **Styling:** [Detect — Angular Material, Tailwind, SCSS modules]
- **Package manager:** npm — detect if pnpm is configured

## Conventions

Follow this repo's existing conventions, plus these Angular-specific rules:

### Components
- **Standalone components** are the default (Angular 17+). Use `NgModule` only in legacy code or when
  interoperating with libraries that require it.
- One component per file. Component class name: `UserProfileComponent`; selector: `app-user-profile`.
- `ChangeDetectionStrategy.OnPush` on all new components — no exceptions without documented justification.
- Keep templates lean: complex display logic belongs in the component class or a pipe, not the template.

### Dependency Injection
- Use `inject()` function inside the component/service body — not constructor parameter injection —
  for new code (Angular 14+ preferred style).
- Services are `@Injectable({ providedIn: 'root' })` by default unless scope isolation is needed.

### TypeScript
- `"strict": true` is non-negotiable. All files must compile clean.
- No `any` — use `unknown` and narrow, or define a precise type.
- No `// @ts-ignore` without a ticket reference.
- Typed reactive forms (`FormGroup<{...}>`) — never untyped `FormGroup`.

### Forms
- Reactive forms only for non-trivial forms. Template-driven forms only for simple, isolated cases.
- Typed form controls (`FormControl<string>`, `FormControl<number | null>`).
- Custom validators as plain functions (`ValidatorFn`) — not classes.

### RxJS and Signals
- Prefer Angular signals for synchronous local state (replaces simple `BehaviorSubject` patterns).
- Use RxJS for genuinely asynchronous event streams (HTTP, WebSockets, complex async coordination).
- Always unsubscribe: use `takeUntilDestroyed()` (Angular 16+), `async` pipe, or `toSignal()`.
- Never subscribe inside another subscribe — use `switchMap`, `mergeMap`, `concatMap`.

### State Management (NgRx)
- Actions, reducers, effects, selectors in `store/` folder per feature.
- Actions use `createAction` with typed props — no string literal action types.
- Effects handle all side effects (HTTP calls, navigation) — no HTTP calls inside components.
- Selectors are memoized via `createSelector`.

### Error Handling
- Global HTTP error interception via `HttpInterceptor` — implement your org's error envelope mapping here.
- Component-level errors: use Angular's `ErrorHandler` for uncaught exceptions.
- No `console.error` in production code — log through your org's logging conventions.

## Testing

- **Unit tests:** Jasmine + Karma (Angular default) or Jest if configured — detect from `angular.json`.
- **Component tests:** `TestBed` with `ComponentFixture` and real child components/services; test rendered output and user interactions, not internals.
- **Service tests:** `TestBed` with `HttpClientTestingModule` — this fakes HTTP at the wire (the right boundary), so test services against real responses rather than mocking your own collaborators.
- **External boundaries:** fake only third-party APIs and the clock at the wire; don't mock your own services.
- **E2E tests:** Cypress or Playwright — detect from `package.json`. Test critical user journeys only.
- Avoid testing implementation details (private methods, internal state); test component behavior.

## Running Locally

```bash
ng serve
```

The app runs at `http://localhost:4200` by default.

Ensure `src/environments/environment.development.ts` is configured for local API URLs.

## Common Commands

```bash
# Serve with live reload
ng serve

# Run unit tests (watch mode)
ng test

# Run unit tests (single run, for CI)
ng test --watch=false --browsers=ChromeHeadless

# Build for production
ng build

# Lint
ng lint

# Generate component (standalone)
ng generate component features/my-feature/my-component

# Generate service
ng generate service core/my-service

# E2E tests (if Cypress configured)
ng e2e
```

## Baselines

Document this project's own conventions for error handling, logging, and security here (or link the team's standards). New code follows them; existing code is not refactored to match.

## Overrides

_(Empty by default — use this section to explicitly override any default with a justification)_
