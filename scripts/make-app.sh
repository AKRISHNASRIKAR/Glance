#!/bin/bash
# Assembles dist/Glance.app from the SwiftPM release build.
#
# Usage:
#   scripts/make-app.sh                # unsigned local build
#   VERSION=0.2.0 scripts/make-app.sh  # explicit version
#
# Signing (optional, for release):
#   CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" scripts/make-app.sh
set -euo pipefail

cd "$(dirname "$0")/.."

VERSION="${VERSION:-0.1.0}"
BUNDLE_ID="${BUNDLE_ID:-app.glance.Glance}"
DIST=dist
APP="$DIST/Glance.app"

swift build -c release

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp .build/release/Glance "$APP/Contents/MacOS/Glance"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Glance</string>
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>
    <string>Glance</string>
    <key>CFBundleDisplayName</key>
    <string>Glance</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>Glance uses Automation to read what's playing and control playback in Music and Spotify.</string>
    <key>NSHumanReadableCopyright</key>
    <string>MIT License</string>
</dict>
</plist>
PLIST

if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
    echo "Signing with: $CODESIGN_IDENTITY"
    codesign --force --deep --options runtime \
        --sign "$CODESIGN_IDENTITY" \
        "$APP"
    codesign --verify --strict --verbose=2 "$APP"
else
    # Ad-hoc signature so local builds run without Gatekeeper complaints
    # about a missing signature (still requires right-click → Open).
    codesign --force --deep --sign - "$APP"
    echo "NOTE: ad-hoc signed (set CODESIGN_IDENTITY for Developer ID signing)"
fi

echo "Built $APP (version $VERSION)"
