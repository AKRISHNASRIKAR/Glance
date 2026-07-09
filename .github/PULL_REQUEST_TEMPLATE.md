## What does this change?

<!-- Summary of the change and motivation. -->

## Checklist

- [ ] `swift test` passes (or `make test` on a Command Line Tools-only machine)
- [ ] No private macOS APIs introduced (or the exception is documented in the PR)
- [ ] No new always-on polling; timers only run while their feature is active
- [ ] Settings additions are typed (no raw UserDefaults keys) and actually do something
- [ ] Privacy: no logging of titles, prompts, window contents, or other user content
- [ ] Docs updated if behavior changed (`docs/`, README)
