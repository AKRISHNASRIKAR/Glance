#!/bin/bash
# Packages dist/Glance.app into dist/Glance-<version>.dmg with an
# /Applications shortcut, plus a ZIP and SHA-256 checksums.
#
# Reproducible: no developer-specific paths; run scripts/make-app.sh first
# (or `make dmg`, which does both).
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="${VERSION:-0.1.0}"
DIST=dist
APP="$DIST/Glance.app"
DMG="$DIST/Glance-$VERSION.dmg"
ZIP="$DIST/Glance-$VERSION.zip"
STAGING="$DIST/dmg-staging"

[[ -d "$APP" ]] || { echo "error: $APP not found — run scripts/make-app.sh first" >&2; exit 1; }

# --- ZIP (for Sparkle / direct download) ---
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

# --- DMG ---
rm -rf "$STAGING" "$DMG"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

hdiutil create \
    -volname "Glance" \
    -srcfolder "$STAGING" \
    -ov -format UDZO \
    "$DMG"
rm -rf "$STAGING"

# --- Checksums ---
(cd "$DIST" && shasum -a 256 "$(basename "$DMG")" "$(basename "$ZIP")" > "checksums-$VERSION.sha256")

echo "Packaged:"
echo "  $DMG"
echo "  $ZIP"
echo "  $DIST/checksums-$VERSION.sha256"
