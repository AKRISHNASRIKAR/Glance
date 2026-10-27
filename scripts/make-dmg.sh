#!/bin/bash
# Build a branded Finder drag-to-install DMG, ZIP and SHA-256 checksums.
set -euo pipefail
cd "$(dirname "$0")/.."
DIST=dist
APP="$DIST/Glance.app"
[[ -d "$APP" ]] || { echo "error: $APP not found — run scripts/make-app.sh first" >&2; exit 1; }
APP_VERSION=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Contents/Info.plist")
VERSION="${VERSION:-$APP_VERSION}"
[[ "$VERSION" == "$APP_VERSION" ]] || { echo "error: VERSION differs from the app bundle" >&2; exit 1; }
DMG="$DIST/Glance-$VERSION.dmg"
ZIP="$DIST/Glance-$VERSION.zip"
TOOLS="$DIST/dmg-tools"

# Keep packaging dependencies out of the user's global Python installation.
if [[ ! -x "$TOOLS/bin/python" ]]; then python3 -m venv "$TOOLS"; fi
"$TOOLS/bin/python" -m pip install --disable-pip-version-check -r packaging/dmg/requirements.txt
swift scripts/render-dmg-background.swift "$DIST/dmg-background.tiff"
rm -f "$ZIP" "$DMG"
ditto -c -k --keepParent "$APP" "$ZIP"
"$TOOLS/bin/python" scripts/build-dmg.py "$DMG"
(cd "$DIST" && shasum -a 256 "$(basename "$DMG")" "$(basename "$ZIP")" > "checksums-$VERSION.sha256")
echo "Packaged $DMG, $ZIP and $DIST/checksums-$VERSION.sha256"
