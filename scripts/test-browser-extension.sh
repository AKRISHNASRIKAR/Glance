#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/sync-extension-dashboard.py
python3 scripts/check-site-metadata.py
swift build
node --test browser-extension/tests/core.test.js
cd browser-extension
npm ci --ignore-scripts --no-audit --no-fund
npx playwright install chromium
mkdir -p .test-results
node tests/responsive.test.js
node tests/blocked-page.test.js
node tests/browser.test.js
