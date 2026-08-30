---
name: designing-ui
description: Use for UI design and development tasks — guides design-first, accessible, production-grade UI work with intentional aesthetics. Works with or without a formal design system.
---

# Designing UI

## Overview

This skill guides design-first UI development — the discipline of thinking about what you're building and why before writing component code. It covers design thinking, accessibility, visual fundamentals, and the process of building consistent UI across teams — with or without a formal design system.

The universal fundamentals (typography, color, motion) are a shared *baseline* so the whole team converges instead of each inventing their own. The **"Building Consistency Without a Design System"** process is the core: extract the conventions the codebase already has, keep new work inside them, and let developers review UI without a designer in the loop.

**Brownfield rule:** If the project has an established design system, component library, or style guide, follow it. Do not introduce new patterns, colors, spacing, or component variants without explicit approval. The guidance below applies to new projects or where the project has no established visual direction.

## Design Thinking — Before You Code

Before writing any component code, answer these questions. Write the answers down (in a spec, a comment, or a message to the user).

### 1. Purpose

What problem does this UI solve? Who uses it? What's the one thing they need to accomplish? If you can't answer in one sentence, the scope is too broad — narrow it before designing.

### 2. Tone and aesthetic direction

Commit to a specific aesthetic. "Clean and modern" is not a direction — it's the absence of one. Pick something with personality:

- **Brutally minimal** — maximum whitespace, one accent color, stark typography
- **Editorial / magazine** — strong typographic hierarchy, large imagery, asymmetric layouts
- **Soft / pastel** — rounded corners, gentle gradients, warm tones, generous padding
- **Industrial / technical** — monospace type, visible grid lines, data-dense layouts
- **Luxury / premium** — dark backgrounds, thin serif typography, subtle animations
- **Playful / bold** — bright saturated colors, oversized elements, unexpected layouts
- **Retro-futuristic** — neon accents, glass morphism, dark mode with glow effects

The project's existing visual language overrides this. But when there is no established language, make a deliberate choice rather than defaulting to generic.

### 3. Constraints

What are the technical requirements? Mobile-first? Must work in IE? Specific framework (React, Angular, vanilla)? Performance budget? Offline support? These constrain what's possible — identify them upfront.

### 4. Differentiation

What makes this interface distinctive? If the answer is "nothing," push harder. Even internal tools benefit from intentional design — it signals quality and builds trust with users.

## Accessibility — Non-Negotiable

Target WCAG 2.1 AA compliance as a minimum. This is not optional regardless of project type, timeline pressure, or "it's just internal."

### Structure
- Semantic HTML elements over generic `<div>` and `<span>` — use `<nav>`, `<main>`, `<article>`, `<section>`, `<button>`, `<a>` for their intended purposes
- Heading hierarchy (`h1` → `h2` → `h3`) must be logical, not chosen for visual size
- Landmark regions for screen reader navigation

### Interaction
- All interactive elements keyboard-accessible with visible focus indicators
- Focus order follows visual reading order
- No keyboard traps — users can always tab away from any element
- Touch targets: 24×24 CSS px is the WCAG 2.2 AA floor (SC 2.5.8); aim larger for primary and mobile actions — 44×44 px (WCAG AAA, Apple HIG) or 48×48 dp (Material)

### Visual
- Color contrast: 4.5:1 for normal text, 3:1 for large text — where "large" is WCAG's definition of ≥18pt (≈24px), or ≥14pt (≈18.66px) when bold (note: points, not pixels)
- No information conveyed by color alone — use icons, patterns, or text labels alongside
- Respect `prefers-reduced-motion` — disable non-essential animations when set
- Respect `prefers-color-scheme` — support dark mode when feasible

### Assistive technology
- ARIA labels where semantic HTML is insufficient — but prefer semantic HTML first
- `alt` text on all meaningful images; decorative images get `alt=""`
- Form inputs have visible associated `<label>` elements
- Error messages are programmatically associated with their fields via `aria-describedby`

## Visual Fundamentals (shared baseline)

These are the conventions to default to so work converges instead of drifting. If the project already establishes different values, follow the project.

- **Typography.** At most two fonts (one display, one body); avoid forgettable defaults when custom fonts are allowed. Define a 4-6 step type scale as tokens (hero/h1/h2/body/caption). Line height ~1.4-1.6 body, ~1.1-1.2 headings.
- **Color.** A small, purposeful palette as semantic tokens (`primary`, `error`, `success`, `surface`, `text`); roughly 60% dominant / 30% secondary / 10% accent. For dark mode, redesign the palette rather than inverting — avoid pure white on pure black, distinguish elevation with subtle surface shifts.
- **Layout & spacing.** Grid/Flexbox, never floats. A consistent spacing scale as tokens (4/8/12/16/24/32/48/64). Mobile-first with `min-width` queries; let content, not device widths, drive breakpoints. Use whitespace deliberately.
- **Motion.** Animate state changes, entrances, and micro-interactions — not critical content the user is waiting on, and never when `prefers-reduced-motion: reduce` is set. Use `transform`/`opacity` (no layout reflow); short durations (150-300ms micro, 300-500ms transitions); `ease-out` in, `ease-in` out.

All of the above live as tokens in whatever your stack uses — SCSS variables or a theme file in Angular, `tailwind.config` in Tailwind, CSS custom properties otherwise. For *extracting and enforcing* a project's actual values, see "Building Consistency Without a Design System" below.

## Design-First Workflow

1. **Understand the problem.** Complete the Design Thinking section above before sketching.
2. **Low-fidelity first.** Sketch the layout and flow. A whiteboard photo or rough wireframe is sufficient. Focus on information hierarchy and user flow, not visual polish.
3. **Get feedback early.** Show the low-fi to the user or stakeholder before investing in high-fidelity implementation. It's cheaper to move boxes than to refactor components.
4. **High-fidelity implementation.** Build using the project's component library and design tokens. If no library exists, build components bottom-up: tokens → primitives → composites → pages.
5. **Visual review.** Compare implementation to approved design side-by-side. Check spacing, alignment, typography, color, and responsive behavior at multiple viewport sizes.
6. **Accessibility audit.** Run axe-core or Lighthouse accessibility audit. Fix all violations before requesting code review.

## Component Architecture

### Build bottom-up
- **Design tokens** → colors, spacing, typography, shadows, radii as whatever your stack uses for tokens (SCSS variables or a theme file in Angular, CSS custom properties in plain CSS, `tailwind.config` in Tailwind, theme JSON in a token pipeline)
- **Primitive components** → Button, Input, Text, Icon, Card (single responsibility, no business logic)
- **Composite components** → SearchBar, UserCard, NavigationMenu (compose primitives)
- **Page layouts** → compose composites into full views

### Component principles
- Each component owns its internal layout but not its external positioning (parent controls where it sits)
- Inputs/props control behavior and variants, not style overrides reached in from parents
- Co-locate styles with components (Angular component stylesheets, CSS modules, scoped styles, or styled-components — whatever the framework uses)
- Export a clear public API — consumers shouldn't need to know internal structure

## Building Consistency Without a Design System

Most teams don't have a formal design system — and don't need one to build consistent UI. What they need is a process for discovering what they already have, documenting it lightly, and keeping new work aligned with existing work.

### Step 1: The three-screen audit

Before adding any new UI to an existing product, screenshot three existing screens. Place them side by side. Your new work must look like it belongs with them.

What to extract from those screenshots:
- **Colors actually in use** — not what's in a brand guide, what's in the product right now
- **Spacing patterns** — are elements spaced at 8px intervals? 16px? Irregular?
- **Typography** — what fonts, sizes, weights are actually rendered?
- **Component patterns** — how do buttons, cards, forms, tables look?
- **Visual tone** — is it dense or spacious? Rounded or sharp? Colorful or muted?

If the three screens are inconsistent with each other, that's your first finding. Pick the most recent or most polished screen as the baseline and flag the inconsistencies.

### Step 2: Extract implicit tokens

Every codebase with UI already has a design system — it's just undocumented. Extract it. On a bash/macOS/Linux shell:

```bash
# Find all colors in use
grep -roh '#[0-9a-fA-F]\{3,8\}' src/ | sort | uniq -c | sort -rn | head -20
grep -roh 'rgb[a]\?([^)]*)'  src/ | sort | uniq -c | sort -rn | head -20

# Find all font sizes
grep -roh 'font-size:\s*[^;]*' src/ | sort | uniq -c | sort -rn

# Find all spacing values
grep -roh 'padding:\s*[^;]*'  src/ | sort | uniq -c | sort -rn | head -20
grep -roh 'margin:\s*[^;]*'   src/ | sort | uniq -c | sort -rn | head -20
```

On Windows PowerShell (where the above `grep`/`uniq` pipeline does not exist), use `ripgrep` (`rg`) plus `Group-Object`:

```powershell
# Find all colors in use (hex)
rg -oI '#[0-9a-fA-F]{3,8}' src | Group-Object | Sort-Object Count -Descending | Select-Object Count, Name -First 20

# Find all font sizes
rg -oI 'font-size:\s*[^;]*' src | Group-Object | Sort-Object Count -Descending | Select-Object Count, Name -First 20
```

Or just use your editor's project-wide regex search — the tool does not matter, the extracted list does. Turn the top values into design tokens. This is not a design system — it's a snapshot of what exists. It costs 30 minutes and prevents your new code from introducing a 15th shade of blue.

**Tokens are not CSS-specific.** This skill uses CSS custom properties in examples because they are the most common case, but the principle applies to any UI stack. In Angular, tokens live in SCSS variables or a theme file (and Angular Material uses its own theming API). In a Tailwind project, they live in `tailwind.config`. In React Native or a design-token pipeline (Style Dictionary), they are platform-agnostic JSON compiled to each target. Component-framework-native systems (Angular Material, PrimeNG, Material UI) ship their own token layer — extend that layer rather than bolting CSS variables alongside it. Extract whatever the project already uses; do not impose CSS variables on a codebase that themes a different way.

### Step 3: Progressive formalization

Don't build a design system upfront. Let it emerge:

- **1-2 shared patterns** → CSS custom properties in a shared file. That's enough.
- **3-5 shared components** → A `shared/` or `common/` directory with those components. Still not a design system.
- **10+ shared components with documented props** → Now you have a design system. Name it, give it a README, and treat it as a dependency.

The mistake is building the design system before you know what goes in it. Ship features. Extract patterns. Formalize what survives.

### Step 4: Cross-team consistency without a central design team

When multiple teams build UI in the same product:

- **One team owns the shared components directory.** Not a "design system team" — just the team that happened to extract the first shared component. Ownership means they review PRs that touch shared components.
- **New components start local.** Build it in your feature first. If another team needs it, move it to shared. Don't pre-optimize for reuse.
- **Screenshot diffs in PRs.** When a PR changes UI, include before/after screenshots. Reviewers can spot visual drift without design expertise.
- **Quarterly visual audit.** Once a quarter, screenshot every major screen. Place them in a grid. Inconsistencies become obvious. Fix the worst three. Don't try to fix everything — diminishing returns hit fast.

### Step 5: Design review by developers

You don't need designers to review UI changes. Developers can check:

1. **Consistency** — Does it look like it belongs in this product? Compare with existing screens.
2. **Accessibility** — Run axe-core. Check keyboard navigation. Verify contrast ratios.
3. **Responsiveness** — Resize the browser from 320px to 1920px. Does it break?
4. **States** — Empty state, loading state, error state, full-data state. Are they all handled?
5. **Edge cases** — Long text, missing images, slow network, right-to-left text if applicable.

Approval criteria: "Would a user notice this is a different part of the product?" If yes, it needs more work.

## Worked Example: Adding a User Settings Page to an Existing Angular Tool

See [worked-example.md](worked-example.md).
## Failure Modes

See [failure-modes.md](failure-modes.md).
## Pairing with a creative-direction skill

This skill covers the *process and standards* — accessibility, workflow, token extraction, component architecture. If your setup also has a dedicated visual/creative-direction skill, pair them: use `exloom:designing-ui` for the disciplined process, and the creative skill for bold aesthetic direction on greenfield or identity-defining work.
