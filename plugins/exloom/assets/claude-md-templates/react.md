# CLAUDE.md — React

## Project Overview

[TBD — fill in: what this frontend does, who uses it, and where it fits in the system.]

- **App name:** [TBD]
- **Team owner:** [TBD]
- **Bundler / meta-framework:** [TBD — Vite (SPA) or Next.js (SSR/SSG) — detect from project]
- **Design system:** [TBD — e.g., internal design system, MUI, shadcn/ui]
- **API base URL (local):** [TBD]

## Stack

- **Library:** React 18+
- **Language:** TypeScript (strict mode)
- **Bundler:** Vite or Next.js — detect from `package.json` scripts and config files
- **Data fetching:** React Query (TanStack Query) or SWR — detect from dependencies
- **State management:** Zustand or Redux Toolkit — detect from dependencies
- **Styling:** [Detect — Tailwind, CSS Modules, styled-components, or design system tokens]
- **Package manager:** npm or pnpm — detect from lockfile

## Conventions

Follow this repo's existing conventions, plus these React-specific rules:

### Components
- Functional components only. No class components.
- One component per file. File name matches the component name (PascalCase).
- Organize by feature/domain, not by type:
  ```
  src/
    features/
      user-profile/
        UserProfile.tsx
        UserProfile.test.tsx
        useUserProfile.ts
        userProfileApi.ts
    shared/
      components/
      hooks/
  ```
- No inline styles. Use the project's design system tokens or CSS Modules.

### TypeScript
- `"strict": true` is non-negotiable.
- Explicit prop types via `interface` or `type` — no implicit `any` props.
- No `any` without justification comment. Prefer `unknown` and narrow explicitly.
- Event handler types: `React.ChangeEvent<HTMLInputElement>` etc. — be precise.

### Hooks
- Custom hooks for all reusable stateful logic — prefix with `use`.
- `useEffect` must have a dependency array. Justify empty arrays with a comment.
- `useMemo` and `useCallback` only when there is a measured performance reason — don't premature-optimize.

### Data Fetching
- All server state via React Query or SWR — no `useState + useEffect` for fetching.
- Mutations via `useMutation` (React Query) or equivalent.
- API layer: thin functions in `<feature>Api.ts` that return typed responses — no fetch calls inside components.

### State Management
- Zustand stores or Redux Toolkit slices for global/shared client state.
- Local component state (`useState`) for UI-only state that does not need to be shared.
- Do not put server state into the global store — use React Query cache instead.

### Accessibility
- All interactive elements must be keyboard-accessible.
- Semantic HTML first; ARIA attributes only when semantic HTML is insufficient.
- Images must have `alt` text; decorative images use `alt=""`.

## Testing

- **Unit/component tests:** Vitest + React Testing Library.
- No Enzyme. Test behavior (what the user sees and does), not implementation details.
- Avoid `getByTestId` unless no semantic query works — prefer `getByRole`, `getByLabelText`.
- **Network:** fake the API at the wire with MSW (Mock Service Worker), not by mocking your own hooks or components — render real components against realistic responses.
- **E2E tests:** Playwright for critical user journeys.
- **Test file naming:** `<Component>.test.tsx` colocated with the component.

## Running Locally

```bash
# npm
npm run dev

# pnpm
pnpm dev
```

The app runs at `http://localhost:5173` (Vite default) or `http://localhost:3000` (Next.js default).

Ensure a `.env.local` file exists (copy from `.env.example`). Required variables: [document here].

## Common Commands

```bash
# Run tests
npm test          # or: pnpm test

# Run tests in watch mode
npm run test:watch

# Type-check (without emitting)
npm run typecheck

# Lint
npm run lint

# Format (Prettier)
npm run format

# Build for production
npm run build

# Preview production build locally
npm run preview   # Vite only
```

## Baselines

Document this project's own conventions for error handling, logging, and security here (or link the team's standards). New code follows them; existing code is not refactored to match.

## Overrides

_(Empty by default — use this section to explicitly override any default with a justification)_
