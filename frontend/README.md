# Glance website

Static pages for the native Glance utility, extension setup, icon studies, and the authorized local-data dashboard. The landing page retains its earlier design at the user's request, with extension details added. The companion-page direction is recorded in `DESIGN.md`.

## Local review

From the repository root:

```sh
python3 scripts/bundle-frontend.py
python3 scripts/sync-extension-dashboard.py
python3 -m http.server 4173 --bind 127.0.0.1 --directory frontend
```

Open `http://localhost:4173/`. No package install or native app rebuild is needed to review the website. The local dashboard intentionally shows its authorization gate: live native data is restricted to the production origin and packaged extension UI.

## Design sources

- `design-system.css`: canonical website palette, type, spacing, shared navigation and controls.
- `site-pages.css`: MacBook hero, product scenes and companion-page layouts.
- `design-tokens.css`: generated compatibility token copy, not an editing source.
- `navigation.js`: disclosure menu and keyboard dismissal.
- `app.js`: the restored interactive landing preview, explicitly labelled as a browser-only demonstration.
- `landing/`: original landing styles, including the MacBook, native preview and motion. `landing.css` is the generated landing bundle.
- `icon-studies.css` and `icon-studies.js`: motion studies, explicit play/pause, and Reduce Motion defaults.
- `site.css`: generated bundle of the canonical system and page layouts.

The hero keeps a front-facing CSS MacBook at the user's request. Music, Pomodoro and optional activity scenes use actual app captures from `assets/screenshots/`, copied into the static asset directory. Captures are labelled as noninteractive images. No Apple product photograph, invented playback state or fake notification is used.

The icon studies use the app's existing WebP artwork, the extension's actual outline SVG, and a raster of `Sources/Glance/Resources/MenuBarIcon.pdf`. Interface motion is limited to explicit state changes. Marketing scroll reveals, breathing halos, equalizer loops and animated headers have been removed.

## Extension surfaces

The extension owns its matching utility tokens in `browser-extension/ui.css`, with system fonts and no external font requests. Its blocked page keeps a separate stylesheet to protect its layout and single Manage list action. The updated palette is applied without changing that layout.

Generate the hosted dashboard after extension UI changes with `python3 scripts/sync-extension-dashboard.py`. The hosted UI keeps Pomodoro configuration removed, following the direct product decision. Native and packaged settings retain those controls.

## Checks and deployment

Run `node browser-extension/tests/responsive.test.js` for five viewport sizes, enlarged text, keyboard navigation, media failure/retry, and reduced-motion controls. The native-bridge integration suite also checks the connected settings layout and app-owned state.

This revision is for local review. Do not deploy until the user approves it. The existing deployment helper remains `scripts/prepare-vercel-static.py` for the already-linked Vercel project.

## Extension marketing and discovery

The original MacBook homepage stays in `landing/`. `/extension/` uses `extension.css` for the forest-green visual direction, real extension captures and upright serif headline. `/extension/connect/` has the detailed developer-preview pairing guide. `grain.css` places subtle tiled grain under content on website surfaces. The blocked timer layout is unchanged.

Run `python3 scripts/sync-extension-dashboard.py` after editing extension UI. It also runs `scripts/site_metadata.py`, the single source of canonical URLs, Open Graph/Twitter cards, JSON-LD, robots, sitemap and LLM guides. Run `python3 scripts/check-site-metadata.py` to verify repeatable generation and local assets. The dashboard has `noindex, follow` and is excluded from the sitemap, but crawlers can read its noindex directive. LLM guides describe the project; they do not promise search ranking or indexing.

Social previews are reproducible with `node scripts/generate-social-previews.mjs` while the site runs at localhost:4173. The real Chrome/native demo captures can be regenerated with `node scripts/capture-extension-preview.mjs` after building the native bridge/harness; the script uses an isolated temporary profile and removes it afterwards. Install Playwright with `npm ci --prefix browser-extension` first. Neither capture script touches the user's normal Chrome profile.

The static deployment preparer supports `/extension/connect/` with a trailing-slash redirect. Preparing output does not publish it. These changes are local for review.
