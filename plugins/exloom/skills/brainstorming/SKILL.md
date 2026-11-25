---
name: brainstorming
description: Use when the user asks for a new feature, or when what to build is unclear or disputed. Not for bug fixes, refactors, review findings or changes whose requirements are already stated. Explores intent, requirements and design before implementation. Brownfield-aware.
---

# Brainstorming

Explore intent, requirements and design before any code exists, starting from "what already exists, and what is the minimum we need to add?" The output is a written spec for `exloom:planning-for-handoff`.

Depth scales with the work: a CRUD endpoint gets a half-page spec, a new subsystem two to four pages. No step is skipped. Too large for one spec: decompose, and brainstorm the first part.

## Change-note mode

When `/exloom` recorded `**Work type:** change to existing code`, skip the spec and write a change note in its place, in the same location: what the code does now, what it will do instead, and the acceptance criteria, numbered as a spec's are. One or two paragraphs. Record it in the checklist as `**Spec:**`. A single task records `**Plan:** none`; two or more still need a plan. The process below, including the lint, is for a new feature: do not run it on a change note.

## Process

1. **Read first.** CLAUDE.md, the README, recent commits, similar features and the test patterns. Never ask what the code already answers.
2. **Find the problem under the solution.** "I need a caching layer" may be a slow query. Who has the problem, how do they solve it today, what happens if we do not build this?
3. **Ask one question at a time**, most important first, multiple choice where possible. Ask about constraints, not preferences. Stop when you can predict the answer.
4. **Offer two or three approaches**, your recommendation first, each grounded in this codebase. No strawmen. If the user disagrees, they decide; note both views in the spec.
5. **Present the design in sections** and pause after each: overview, components (every file, class, endpoint, table), data flow, error handling, edge cases, non-goals. Get the overview approved first. A new screen or a significant layout change on the Standard or Certified lane needs an approved static mock before the spec: [ui-mock.md](ui-mock.md).
6. **Write the spec.** Copy `templates/spec-template.md` to where the repo keeps specs, else `docs/exloom/specs/F-<nnn>-<slug>.md`, with `<nnn>` one past the highest there. Write for someone who was not in the session, citing code by path.
   - Each requirement (`R-<n> · <type>`) is one behaviour in an EARS shape, with at least one acceptance criterion (`AC-<n> · <level>`) as Given/When/Then. "Works correctly" is not a requirement.
   - Say what the system does, never how it is built: `SHALL persist the job so it survives a restart`, not `SHALL store the job in Postgres`.
   - Anything touching money, permissions or data loss needs an `unwanted` requirement: `IF <bad thing> THEN THE SYSTEM SHALL <response>`.
   - Refs such as `F-012/R-3/AC-2` are permanent once the spec is approved. Changing what one means creates a new one and marks the old `superseded`.
7. **Lint it** and fix the errors. Warnings are heuristics: judge them.

   ```bash
   XL_ROOT='${CLAUDE_PLUGIN_ROOT}';XL_FILE="$XL_ROOT/scripts/lint-spec.sh";[[ $XL_ROOT =~ ^(/|[A-Za-z]:/) && -f $XL_FILE ]]||{ echo "exloom: $XL_FILE missing; reinstall exloom or update Claude Code">&2;exit 1;};bash "$XL_FILE" docs/exloom/specs/F-012-slug.md
   ```

8. **Get the user's approval of the whole spec**, then invoke `exloom:planning-for-handoff`. Never go straight to implementation.

## Brownfield discipline

The codebase already has an opinion; find it before forming yours.

- **Search by concept, not only by name.** For notifications, also search "alert", "event", "publish". Prove nothing exists before proposing something new.
- **Match the surrounding code**: its base classes, error handling, logging and DI. Check for an existing library before adding a dependency.
- **Extend before building new.** If an existing feature does most of what is needed, extend it.
- **Justify any deviation in the spec.** The bar: the existing pattern cannot solve the problem. "Simpler" is not a justification.

See [failure-modes.md](failure-modes.md) and [worked-example.md](worked-example.md).
