# Contributing to Glance

Thanks for your interest! Before writing code, read the product philosophy in
the README — most rejected PRs fail on principle, not on code quality:

- The notch is a scarce attention surface. Features must be quiet by default.
- No fake states, no invented data, no settings that do nothing.
- No private macOS APIs. If a feature needs one, it doesn't ship.
- Providers stay isolated and never touch the UI directly.
- Privacy-sensitive signals are opt-in, and "not enabled" means "not read".

## Development

```bash
make build   # debug build
make test    # full test suite
make app     # dist/Glance.app (ad-hoc signed)
```

Works with full Xcode (`swift build` / `swift test` directly) or with
Command Line Tools only (the Makefile adds the Swift Testing search paths).

## Project layout

- `Sources/GlanceKit` — engines, models, providers (headless, tested)
- `Sources/Glance` — the app (notch panel, SwiftUI views, settings)
- `Tests/GlanceKitTests` — Swift Testing suite with virtual clocks
- `docs/` — architecture and subsystem docs; keep them in sync with code

## Expectations for PRs

1. Tests for engine/provider behavior changes (use `TestClock`, no sleeps).
2. Swift 6 strict concurrency clean — no `@unchecked Sendable` without a
   comment justifying the confinement.
3. No new polling loops that run while the feature is inactive.
4. `os.Logger` categories from `GlanceLog`; never log user content.
5. Update the relevant `docs/*.md` when behavior changes.

## Reporting issues

Use the issue templates. For crashes, include
`log show --predicate 'subsystem == "app.glance.Glance"' --last 10m`
(scrub anything you consider private).
