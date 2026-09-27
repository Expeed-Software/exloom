# CLAUDE.md — Flutter

## Project Overview

[TBD — fill in: what this app does, who uses it, and which platforms it ships to.]

- **App name:** [TBD]
- **Team owner:** [TBD]
- **Platforms:** [TBD — Android / iOS / web / desktop]
- **Backend:** [TBD — the API this app talks to]

## Stack

- **Language:** Dart 3.x
- **Framework:** Flutter 3.x
- **Dependencies:** `pubspec.yaml`, locked by `pubspec.lock`
- **State management:** [TBD — detect: Riverpod, Bloc, Provider]
- **Routing:** [TBD — detect: go_router, auto_route]

## Conventions

Follow this repo's existing conventions, plus these Flutter-specific rules:

### Widgets
- Prefer small `StatelessWidget`s; keep business logic out of `build()`.
- `const` constructors wherever the widget allows it.
- Dispose every controller, stream subscription and animation controller the widget creates.

### Async
- Never use a `BuildContext` after an `await` without checking `mounted`.
- Surface errors from futures and streams; no empty `catchError`.

### Configuration
- Environment values through `--dart-define` or the repo's flavor setup, never hardcoded.

## Testing

- **Unit and widget tests:** `test/`, files named `<name>_test.dart`.
- **Integration tests:** `integration_test/`, run on a device or emulator.
- **Fakes:** fake only what you don't own (HTTP, platform channels, the clock).
- **Pinned proof command:** commit `.claude/exloom-test-command` as `flutter test`, which runs `test/` without a device.

## Running Locally

```bash
flutter run
```

## Common Commands

```bash
# Unit and widget tests
flutter test

# Integration tests (needs a device or emulator)
flutter test integration_test

# Static analysis and format
flutter analyze
dart format .
```

## Baselines

Document this project's own conventions for error handling, logging, and security here (or link the team's standards). New code follows them; existing code is not refactored to match.

## Overrides

_(Empty by default — use this section to explicitly override any default with a justification)_
