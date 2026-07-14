# AGENTS.md

## Purpose
This file guides AI coding agents working in this Flutter project. Follow these instructions unless the user gives a more specific requirement.

## Project context
- Primary platform: Flutter mobile app.
- Primary language: Dart.
- Main entry points: `lib/`, `test/`, and `pubspec.yaml`.
- Prefer stable, idiomatic Flutter/Dart patterns over experimental or overly clever solutions.

## Working rules
1. Inspect the existing structure before making changes.
   - Read `pubspec.yaml`
   - Review `lib/` and `test/`
   - Check `analysis_options.yaml` and `README.md` if present
2. Make the smallest change that solves the problem.
3. Preserve existing architecture, naming, and code style.
4. Avoid adding dependencies unless they are clearly justified.
5. Prefer readability and maintainability over premature abstraction.

## Architecture guidance
- Keep UI, state management, business logic, and data access separated.
- Favor a feature-based or layered structure that matches the existing app.
- Avoid mixing network, storage, and presentation logic inside widgets.
- Keep widgets focused on rendering and delegate logic to services/controllers/providers.

## Flutter and Dart conventions
- Follow effective Dart style and Flutter best practices.
- Use `const` constructors where possible.
- Prefer `final` for immutable values.
- Use null safety correctly and avoid unnecessary `!` or `dynamic`.
- Use meaningful names for variables, functions, classes, and files.
- Avoid hardcoded strings; prefer localization and constants.
- Handle async errors clearly and provide user-friendly feedback.
- Keep accessibility and responsiveness in mind for UI changes.

## Testing expectations
- Add or update tests for meaningful behavior changes.
- Prefer widget tests for UI behavior and unit tests for logic.
- When fixing a bug, add a regression test if practical.
- Do not rely on mocks unless they are necessary and well justified.

## Commands to use
Run these before considering a change complete:
- `flutter pub get`
- `flutter analyze`
- `flutter test`
- `flutter run` for local verification when relevant

## Safety and constraints
- Never commit secrets, API keys, or credentials.
- Do not modify signing, platform config, or native setup unless explicitly requested.
- When introducing new packages, update dependencies and verify the app still builds.
- If a requirement is ambiguous, ask for clarification rather than making a large architectural assumption.

## Output expectations
- Summarize what changed and why.
- Mention any assumptions or follow-up work.
- Call out validation results from analysis or tests.
