# Browser focus

Glance Focus is a Manifest V3 Chrome extension in `browser-extension/`. It supports independent focus sessions and an optional local connection to Glance on macOS. It is a developer preview, not a published Chrome Web Store listing.

## Ownership and persistence

When connected, the Mac owns the phase, run state, deadline, Pomodoro settings, block list, exclusions and desired usage-tracking state. Chrome adopts that state and sends acknowledged commands. Browser Start does not overwrite the Mac duration. While disconnected, the extension preserves the last known deadline and retries; explicitly choosing standalone enables independent browser operation.

The existing native SettingsStore persists Pomodoro settings. Browser preferences and imported statistics live in the Mac's Application Support folder with user-only permissions. Chrome keeps a local cache, event journal and its own permission grants. Permission grants cannot be shared between browser profiles. Stats imports are acknowledged and deduplicated.

## Dashboard

The hosted `/extension/dashboard/` page is a control surface for local data. It connects only after the user selects Open web dashboard in the extension. Chrome forwards allowlisted commands to the extension; the extension uses Native Messaging to reach the app. The website does not store an independent timer or upload activity. Access can be revoked in packaged extension settings.

Native Messaging credentials, socket paths and browser profiles are runtime data, never repository assets. The development key in `protocol/development.json` is a public key used to stabilize the unpacked extension ID, not a private credential.

## Development

See the [extension guide](../browser-extension/README.md) for local loading, pairing and tests, and the [protocol](../protocol/README.md) for request schemas. Website tokens live in `frontend/design-system.css` and extension-owned tokens live in `browser-extension/ui.css`; regenerate the landing bundle and hosted dashboard after changes. The blocked page intentionally retains its own layout stylesheet.

Before release, complete signing/notarization, Chrome Web Store packaging/review, permission-prompt testing and broader browser/OS beta coverage. The test harness is never shipped inside Glance.app.
