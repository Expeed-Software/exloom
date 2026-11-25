# Architecture: {Name}

<!--
What it is built on and how it is organised. Product questions belong in docs/product.md.
Keep it true: exloom:maintaining-reference-docs updates it when a change touches it.
-->

## Stack

| Layer | Choice | Version |
|---|---|---|
| {Language / runtime} | {choice} | {version} |
| {Framework} | {choice} | {version} |
| {Storage} | {choice, or "None"} | {version} |
| {Tests} | {choice} | {version} |
| {Lint / format} | {choice} | {version} |
| {Package manager} | {choice} | {version} |

## Layout

| Path | What goes there |
|---|---|
| `{folder}/` | {role} |

## Components

{The main parts of the system and how they talk to each other.}

## Data and storage

{Where data lives, how it is accessed, and how the schema changes. "None" if nothing is stored.}

## Conventions

- **Errors:** {how errors are raised, handled and shown}
- **Logging:** {what is logged and where}
- **Configuration and secrets:** {where settings live; secrets are never committed}
- **Authentication and authorisation:** {approach, or "None"}
- **Testing:** {kinds of test, where each lives, and naming}

## How the constraints are met

| Constraint (docs/product.md) | How it is met |
|---|---|
| {constraint} | {technical answer} |

## Deployment

{Where and how it runs, or "Not decided yet".}

## Decisions

| Decision | Chosen | Rejected | Why |
|---|---|---|---|
| {technical question that was settled} | {answer} | {alternatives} | {reason} |
