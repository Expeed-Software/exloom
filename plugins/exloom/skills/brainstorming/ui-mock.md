# UI mock before coding

A static HTML mock, approved by the user, so the screen is agreed before code exists. It never blocks a push.

## When

Only when the spec adds a new screen, or changes a layout or a user flow significantly — a new page, route, dialog or wizard step, or moving where the user does something.

- **Lane:** Standard and Certified only. Read the repo default from the committed `.claude/exloom-lane` (`.claude/exloom-strict` means Certified); with neither, it is Standard. Never on Sprint.
- **Never** for small tweaks: copy, colours, spacing, one field added to an existing form, a validation message.
- **Ask once** when it applies: "This adds a screen. Mock it first?" Recommend yes. On no, record nothing and continue.

## Visual style

Find the app's design tokens or theme (CSS variables, Tailwind config, a theme or tokens file) and copy their values into the mock as CSS variables, each citing its source file. With no tokens, copy the values the nearest existing screen uses. With neither, ask the user once: their design system or Figma link, their brand colours and font, or a plain neutral style decided later. Never invent a visual style.

If a UI or design skill is installed, you may use it to build the mock, within these values and the rules below.

## Build it

One self-contained file, `<spec-name>.mock.html`, next to the spec. Inline CSS, no external scripts, fonts or images, no build step: it opens from disk.

- **Four states**, side by side or switched by tabs in the page: **main** (realistic data), **empty** (first use, nothing yet), **loading**, and **error** (what the user sees and what they can do next).
- **Real content.** Field labels, button text, column headings and messages as they will ship. Lorem ipsum hides the decisions the mock exists to make.
- **Match the app.** Read the existing screens first and reuse their layout, navigation, component names and wording. Brownfield wins: the mock follows the app's conventions, not a fresh design.
- **No behaviour.** Links and buttons may switch states; nothing calls a server.

## Iterate

Show the user the file path and ask them to open it. Change what they ask for, one round at a time, until they approve. Approval is explicit: "looks fine" while it is half-built is not.

## Record the approval

In the spec, under the chosen approach:

```
UI mock: F-012-orders-export.mock.html — approved: "<the user's words>"
```

Commit the mock with the spec.

## Later use

- **Acceptance criteria refer to it:** `AC-2 · ui — GIVEN no exports yet WHEN the page opens THEN it shows the empty state in the mock`.
- **L1 checks the implementation against it:** each of the four states exists, with the mock's labels and fields.
- **The UI smoke test is compared to it:** the pasted result names any difference from the mock, and the user accepts or rejects it.
