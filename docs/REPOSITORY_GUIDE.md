# Repository layout

| Directory | Purpose |
| --- | --- |
| `Sources/Glance` | Native app and SwiftUI screens |
| `Sources/GlanceKit` | Engines, stores, providers and browser protocol |
| `Tests` | Native unit tests |
| `Resources`, `assets` | App icon sources and public documentation images |
| `frontend` | Static landing page, extension guide, icon studies and focus dashboard |
| `browser-extension` | Loadable Chrome extension, local options, blocked page and browser tests |
| `protocol` | Public development identity and protocol documentation |
| `scripts` | Build, packaging, asset generation and verification |
| `docs` | Architecture, privacy and contributor documentation |

## Generated files

Run `python3 scripts/bundle-frontend.py` after updating landing styles/tokens, then `python3 scripts/sync-extension-dashboard.py` after updating extension UI. These regenerate the public CSS bundle, website token compatibility copy and hosted dashboard assets. Committing these generated static files keeps ordinary static hosting functional.

Build products, dependencies, browser profiles, QA screenshots, videos, credentials and deployment linkage are local artifacts and excluded by `.gitignore`. Do not add personal settings, pairing data, local environment files or signing credentials. The extension's development public key is intentionally public; private runtime credentials are generated outside the repo.

Before sharing changes, run `python3 scripts/check-public-repo.py`, native tests for Swift changes, and the browser/responsive checks documented in `browser-extension/QA.md`. The file scan detects common credential patterns; it does not replace security review.

Deploy the static site with `python3 scripts/prepare-vercel-static.py` and `npx vercel deploy --prebuilt --prod --yes` after linking the existing Vercel project. This publishes generated static assets without committing code or uploading local runtime data.
