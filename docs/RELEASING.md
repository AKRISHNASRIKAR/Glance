# Releasing Glance

## Versioning

Semantic Versioning, tags `vMAJOR.MINOR.PATCH` (`v0.1.0`, `v0.2.0`, `v1.0.0`).
For now, `v0.x.y` releases are treated as GitHub prereleases.

## Automated pipeline

Pushing a `v*` tag runs `.github/workflows/release.yml`:

1. checkout, select Xcode, `swift test`
2. import the Developer ID certificate (from secrets)
3. `scripts/make-app.sh` — release build, app bundle, Hardened Runtime
   signing when `CODESIGN_IDENTITY` is set
4. `notarytool submit --wait` + `stapler staple`
5. `scripts/make-dmg.sh` — DMG (with /Applications shortcut), ZIP, SHA-256
   checksums
6. GitHub prerelease with the artifacts. **Unsigned builds are published as
   drafts only** — the workflow never fakes signing.

## Required repository secrets

| Secret | Contents |
|---|---|
| `MACOS_CERTIFICATE_P12` | base64 of the Developer ID Application cert + private key (`base64 -i cert.p12`) |
| `MACOS_CERTIFICATE_PASSWORD` | password of that .p12 |
| `CODESIGN_IDENTITY` | `Developer ID Application: Your Name (TEAMID)` |
| `NOTARY_APPLE_ID` / `NOTARY_TEAM_ID` / `NOTARY_PASSWORD` | notarytool credentials (app-specific password) |

Never commit certificates, provisioning profiles, or Sparkle keys. The
.gitignore blocks the common file types as a backstop.

## Manual release (fallback)

```bash
VERSION=0.1.0 CODESIGN_IDENTITY="Developer ID Application: …" scripts/make-app.sh
ditto -c -k --keepParent dist/Glance.app notarize.zip
xcrun notarytool submit notarize.zip --apple-id … --team-id … --password … --wait
xcrun stapler staple dist/Glance.app
VERSION=0.1.0 scripts/make-dmg.sh
gh release create v0.1.0 dist/Glance-0.1.0.dmg dist/Glance-0.1.0.zip dist/checksums-0.1.0.sha256
```

## Homebrew Cask

After a signed release: update `packaging/homebrew/glance.rb` (owner,
version, DMG sha256 from the checksums file) and submit to homebrew-cask or
your own tap. Not automated on purpose — a human verifies the notarized
artifact first.

## Sparkle (evaluated, not yet integrated)

Sparkle 2 is the right update mechanism for a Developer ID app and is planned
for 1.0. Integration checklist for the maintainer:

1. Add `https://github.com/sparkle-project/Sparkle` as a SwiftPM dependency.
2. Generate an EdDSA key pair (`generate_keys`); public key goes in
   Info.plist (`SUPublicEDKey`), **private key stays in a password manager /
   CI secret**.
3. Host an appcast (GitHub Pages or Releases-based) and set `SUFeedURL`.
4. Sign each release ZIP with `sign_update` in the release workflow and add
   the signature to the appcast.
5. Document the update feed in PRIVACY.md (it is the one new network call).

Until then, updates are manual via GitHub Releases; the DMG/ZIP artifacts are
already Sparkle-compatible.

## Mac App Store (evaluated honestly)

Not pursued. The App Store sandbox blocks the things Glance fundamentally
does: Apple Events to Music/Spotify require temporary-exception entitlements
that App Review no longer grants in practice, and writing hook entries into
`~/.claude/settings.json` is impossible from the sandbox. Developer ID +
notarization is the correct distribution channel for this product.
