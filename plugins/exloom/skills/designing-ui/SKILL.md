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

**Context:** The team is adding a user settings page to an internal Angular tool that already has a dashboard, a list view, and a detail view. No formal design system. No designer on the team. The stack is Angular 17 with Angular Material and SCSS — the common shape for this org.

### Design Thinking

> **Purpose:** Let users update their notification preferences and profile info. One thing to accomplish: change a setting and confirm it saved.
>
> **Tone:** Match existing — the tool is industrial/technical. Dense data tables, muted grays, a single accent color.
>
> **Constraints:** Angular 17 + Angular Material + SCSS. Must work on laptop screens (1280px+). No mobile requirement for this internal tool. Must follow the existing `mat-sidenav` shell.
>
> **Differentiation:** Not needed — this is an internal tool. Consistency with existing pages is the goal, not novelty.

### Three-Screen Audit

Screenshots of: Dashboard, Users List, User Detail.

Findings (read from `styles/_theme.scss` and the existing component stylesheets, not guessed):
- **Colors:** the project defines a Material theme — primary `$accent: #3b82f6`, surface `#ffffff`, app background `#f1f5f9`, text `#1e293b`. These are SCSS variables in `styles/_tokens.scss`, not ad-hoc hex.
- **Spacing:** an 8px scale via a `spacing()` SCSS function (`spacing(2)` = 16px) used consistently.
- **Typography:** Material typography config; page titles use the `headline-6` level, body uses `body-2`.
- **Components:** `mat-card` for containers, `mat-table` for lists, `mat-raised-button color="primary"` for primary actions.
- **Tone:** Clean, dense, professional. No playfulness.

### Implementation Decision

No new visual primitives needed. The settings page reuses `mat-card`, Material form fields matching the existing forms, and `mat-raised-button` for actions. The only new pattern is a `mat-tab-group` for "Profile" vs "Notifications" — already part of Angular Material, so it inherits the theme automatically. No new colors, spacing values, or typography levels introduced; everything references the existing SCSS tokens and Material theme.

### Accessibility Check

- Material form fields use `<mat-label>`, which wires the label to the input automatically
- `mat-tab-group` provides keyboard navigation and ARIA tab roles out of the box; verified the focus indicator is visible against the theme
- Save confirmation uses `MatSnackBar` with an `aria-live` region; the success/error distinction includes an icon, not color alone
- Save button uses `[disabled]` during submission and announces busy state

### Result

The settings page is indistinguishable from the rest of the tool in visual quality. It introduced zero new tokens — it consumed the existing Material theme and SCSS variables. The team didn't need a designer or a design system; they needed to read what already existed and stay inside it.

## Failure Modes

### "I'll match the existing design later"

**The thought:** "Let me get the functionality working first, then I'll make it look consistent."

**Why it feels right:** Functionality is the hard part. Styling is just CSS — easy to change later.

**What actually happens:** "Later" never comes. The inconsistent UI ships. Now you have a 16th shade of blue and a button that's 2px taller than every other button. Every subsequent developer copies your inconsistency because they think it was intentional.

**Fix:** Do the three-screen audit before writing any component code. Extract the tokens first. Build with the right values from the start — it takes the same amount of time as building with wrong values.

### "The existing UI is bad, I'll do it better"

**The thought:** "These screens look dated. My new page will use modern patterns and better spacing."

**Why it feels right:** You have better taste. The existing UI was built under time pressure. Yours will be better.

**What actually happens:** Your page looks great in isolation. In the product, it looks like it was built by a different company. Users distrust it. The team now has two visual styles to maintain. Nobody knows which one is "right."

**Fix:** Match first, improve later. If the existing UI genuinely needs improvement, propose a visual refresh as a separate task that updates everything together. Don't unilaterally modernize one page.

### "I don't need to check accessibility for an internal tool"

**The thought:** "Only 50 people use this. None of them are visually impaired."

**Why it feels right:** Accessibility feels like overhead for a small internal audience.

**What actually happens:** A team member with RSI can't use keyboard navigation. A colorblind developer can't distinguish error states from success states. Someone using a large monitor can't read 12px gray-on-light-gray text. Accessibility isn't just screen readers — it's everyone.

**Fix:** Run axe-core. It takes 30 seconds. Fix the violations. This is the floor, not the ceiling.

### "We need a design system before we can build more UI"

**The thought:** "We keep building inconsistent UI. We need to stop feature work and build a design system first."

**Why it feels right:** A design system would solve the consistency problem once and for all.

**What actually happens:** The team spends 3 months building a component library that nobody uses because it doesn't match what they actually need. Features are delayed. The design system becomes stale because it was built in a vacuum.

**Fix:** Extract, don't invent. Ship features. When you see duplication, extract it. When the extracted components pile up, that's your design system. It matches what you actually build because it came from what you actually built.

### "A component library means I can skip the design work"

**The thought:** "We use Angular Material (or PrimeNG, Material UI, Ant) — drop the components in and design takes care of itself."

**Why it feels right:** Professional components, accessibility handled, looks good immediately. And if your org standardizes on one library, using it genuinely *is* the right call — that's the convention.

**What actually happens — two failure shapes:**
- **Un-themed adoption.** You use the library with its default theme, so your product looks like every other un-themed Material app: generic, identity-less, "obviously a Material site." The library was supposed to be a foundation, not the finished look.
- **Library sprawl.** You reach for a second component library because one widget was easier there, and now the product mixes two visual languages, doubles the bundle, and fractures the token system.

**Fix:** The work isn't avoiding the component library — it's *theming the one you have*. Configure its token/theme layer to your product's colors, spacing, and typography (Angular Material's theming API, PrimeNG's design tokens, the library's theme config) and extend that single library rather than bolting a second one alongside it. A component library plus a deliberately configured theme **is** your design system — that's exactly what the worked example above does. What you must not do is ship it raw and un-themed, or stack libraries.

## Pairing with a creative-direction skill

This skill covers the *process and standards* — accessibility, workflow, token extraction, component architecture. If your setup also has a dedicated visual/creative-direction skill, pair them: use `exloom:designing-ui` for the disciplined process, and the creative skill for bold aesthetic direction on greenfield or identity-defining work.
