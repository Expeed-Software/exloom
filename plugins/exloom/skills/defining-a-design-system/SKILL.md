---
name: defining-a-design-system
description: Use when the user asks for a design system, theme, style guide, design tokens or component library, or wants the product's screens to look consistent. Records the visual direction, tokens, components and UI patterns in docs/design-system.md, and themes a new project's skeleton. Run by exloom:starting-a-project for a product with a user interface. Not for the design of one screen.
---

# Defining a design system

Without one written down, every developer and every feature picks its own colours, spacing and components, and the product looks like several. This skill settles the look once, in one file the whole team and every later mock, feature and review reads.

## 1. Check that it applies

- **No user interface** (an API, a command-line tool, a library, a background service): say it does not apply, and stop.
- **No code and no stack yet:** run `exloom:starting-a-project` first; the component library depends on the framework.
- **`docs/design-system.md` already exists:** read it and ask whether to update it or replace it. When updating, add rows to its Decisions table and never change an existing one.

## 2. Read what exists

From `docs/product.md` take the users, devices and browsers, the accessibility constraint and the languages. From the architecture doc take the framework and styling approach. If there is UI code, find before asking anything:

- the component library and its version;
- the theme, token or global style files and their CSS variables;
- the colours, fonts, sizes, spacing and radii that repeat, and where values are hard-coded;
- the shared components (buttons, inputs, dialogs, tables, layout) and where they live;
- how forms, navigation, and empty, loading and error states are done today.

Tell the user in a few lines what you found.

## 3. Settle the design

Ask only what the docs and code do not settle, one question at a time, each with two to four options and your recommendation first:

1. With existing screens: write down what is there (recommended when it is mostly consistent), or set a new direction that later features move towards.
2. Brand material: a brand guide, logo, palette or design file. Use it, and skip what it settles.
3. The component library that fits the framework, or own components. Prefer a well-supported, accessible one, and check its current version and setup in its documentation.
4. The visual direction, tied to who uses the product and how often: calm and dense, friendly and spacious, or bold.
5. The primary colour. Check every text and background pair against the accessibility constraint.
6. The font family and type scale.
7. Light and dark mode.
8. The icon set, if the library brings none.

Decide the details yourself from those answers — the spacing scale, radii, elevation, motion and the patterns — and write them down for the user to read. Do not ask about each one.

## 4. Write it

Write `docs/design-system.md` from [design-system-template.md](design-system-template.md). Fill in every section; write "None" where there is nothing. Token and component names are the names in the code, with the path of the token file, so the next person finds and reuses them. Each pattern is one line, concrete enough that two features built separately would look the same. Link the file from the README.

## 5. Apply it

- **A new project** (a skeleton with no features): install the component library, create the token or theme file with the document's values, add the app shell (header, content area, and navigation if the product has more than one area), and style the skeleton's one page with them. Add no feature content, and keep the skeleton's test passing.
- **Existing screens:** change no code. Moving them onto the design system is a feature of its own, through `/exloom`. New features use it from now on.

## 6. Prove it

Skip this when `exloom:starting-a-project` ran this skill: it proves the skeleton afterwards. Skip it when no code changed.

Otherwise run every command in the README's table and record each exit code, at most three attempts. If a browser tool is available, start the app and look at the page at a phone width and a desktop width; without one, say the look was not checked. Stop any process you start.

## 7. Hand over

Show the user the document, the library and direction in one line, the files changed, and each command with its result. Ask them to read the document and apply their corrections. Unless `exloom:starting-a-project` is running this skill, propose one commit, `docs: design system for <project>`, and wait for their yes.
