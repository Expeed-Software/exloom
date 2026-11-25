# Design system: {Name}

<!--
What the product looks and feels like, and which building blocks its screens use.
Token and component names here are the names in the code. A feature that adds a shared
component or pattern adds it to this file.
-->

## Principles

- {Three to five lines on how the screens should feel and behave, e.g. "Calm and dense: built for people who use it all day"}

## Foundations

Tokens live in `{path to the token or theme file}`.

### Colour

| Role | Token | Light | Dark |
|---|---|---|---|
| Primary (main actions, links) | `{token}` | {value} | {value, or "n/a"} |
| Surface (page and card backgrounds) | `{token}` | {value} | {value} |
| Text and muted text | `{token}` | {value} | {value} |
| Border | `{token}` | {value} | {value} |
| Success / warning / danger | `{tokens}` | {values} | {values} |

### Typography

| Use | Token | Font, size / line height, weight |
|---|---|---|
| {Page title, section heading, body, small, code} | `{token}` | {values} |

### Spacing, radius, elevation and motion

| Kind | Tokens | Scale |
|---|---|---|
| Spacing | `{tokens}` | {e.g. 4, 8, 12, 16, 24, 32 px} |
| Radius | `{tokens}` | {values} |
| Elevation | `{tokens}` | {values, or "None"} |
| Motion | `{tokens}` | {durations and easing; reduced-motion behaviour} |

## Components

**Library:** {name and version, or "None: own components"}. **Icons:** {set}.

| Component | Use it for | Location |
|---|---|---|
| {e.g. Button} | {when to use it, and its variants} | `{library, or path}` |

## Patterns

- **App shell and navigation:** {header, sidebar, content; how users move between areas}
- **Page layout and breakpoints:** {content widths, grid, breakpoints and what changes at each}
- **Forms and validation:** {labels, required fields, when and where errors show}
- **Lists and tables:** {sorting, paging, row actions}
- **Empty, loading and error states:** {what each looks like, and the component that shows it}
- **Feedback:** {toasts, inline messages, confirmations; when each is used}
- **Dialogs or pages:** {when a task opens in a dialog and when on its own page}
- **Destructive actions:** {how they are confirmed and undone}

## Accessibility

{How the accessibility constraint in docs/product.md is met: contrast, visible focus, keyboard use, labels, reduced motion. With no constraint, still require readable contrast and visible focus.}

## Content

- **Voice:** {e.g. "plain and direct; no jargon"}
- **Capitalisation:** {e.g. "sentence case for titles and buttons"}
- **Errors:** {e.g. "say what happened and what to do next"}

## Rules

- Use the tokens above; never write raw colours, sizes, spacing or fonts in components.
- Reuse a listed component before writing a new one.
- {Any other rule, or "None"}

## Decisions

| Decision | Chosen | Rejected | Why |
|---|---|---|---|
| {design question that was settled} | {answer} | {alternatives} | {reason} |
