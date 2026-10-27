# Verification

## Automated checks

- `swift test`: native engine, protocol, persistence, validation and stale-write handling.
- `node --test browser-extension/tests/core.test.js`: domain policy, deadlines, display rounding, permissions and restricted hosted origin.
- `node browser-extension/tests/blocked-page.test.js`: the real unpacked blocked page, one action, keyboard navigation, responsive layout, enlarged text, paused/finished/error states.
- `node browser-extension/tests/responsive.test.js`: public-page layouts, enlarged text, shared mobile menus and local links.
- `scripts/test-browser-extension.sh`: isolated Chromium with the real Native Messaging helper and native engine harness. Covers authoritative timing, reload/reconnect, shared preferences, hosted controls, authorization and revocation.
- `python3 scripts/check-public-repo.py`: high-confidence credential patterns and accidentally publishable local files. This is a guardrail, not a full security audit.

Browser fixtures use temporary profiles and data. They pregrant their test permissions and approve pairing only in the test harness. No user profile or real activity is used. Generated screenshots, profiles and reports are ignored by Git.

## Manual release checks

Verify real Chrome permission dialogs, native pairing approval, OS idle/lock behavior, accessibility, multiple profiles, permission revocation, broad site compatibility and signing/notarization. This is bypassable focus software. Browser startup, sleep/wake and connection loss can delay enforcement.

The blocked timer page is intentionally preserved independently of shared dashboard styling.
