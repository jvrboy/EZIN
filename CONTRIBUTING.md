# Contributing to EZIN

## Branching

- Create feature branches from `main`.
- Use conventional commit prefixes such as `feat:`, `fix:`, `test:`, `docs:`, `chore:`, and `ci:`.
- Keep pull requests focused on one feature, fix, or migration boundary.

## Required local checks

Run the checks that apply to the files changed:

```bash
xcodegen generate
xcodebuild -scheme EZIN -destination 'platform=iOS Simulator,name=iPhone 15' test
npm --prefix backend/functions ci
npm --prefix backend/functions run lint
npm --prefix backend/functions test
npm --prefix backend/functions run build
firebase emulators:exec --only firestore 'npm --prefix backend/functions test'
```

## Review checklist

- No secrets, tokens, private keys, or account identifiers are committed.
- Live trading remains gated behind explicit user confirmation and app settings.
- New shared mutable state is isolated with actors, `@MainActor`, or immutable values.
- Networking supports cancellation and user-visible error reporting.
- User-facing strings are prepared for localization.
- Tests or fixtures are added for deterministic trading, parsing, risk, and persistence logic.
- Privacy, security rules, and audit logging are updated when data flows change.
