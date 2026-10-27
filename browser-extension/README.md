# Glance Focus: local developer preview

No signup, backend or frontend build is required. This directory is a directly loadable Manifest V3 Chrome extension.

## Try standalone first

1. Open `chrome://extensions` in **Chrome**.
2. Enable **Developer mode**, choose **Load unpacked**, and select this `browser-extension/` directory.
3. Pin **Glance Focus** from the Extensions menu and open it.
4. Add a website, for example `example.com`, and approve its website permission. Domain entries include subdomains unless unchecked. This grant is separate from optional usage tracking.
5. Start a focus session. Existing matching tabs are replaced, and new matching navigations open a focus page.
6. Use the popup or dashboard to pause, resume or end a session. The blocked page shows only the countdown and Manage list. Closing the popup does not end a session.
7. Open Dashboard and settings to enable optional website usage stats, add tracking exclusions, export data, or delete statistics.

There is no browser-extension build step. After editing files, click **Reload** on the extension's card in `chrome://extensions` and reopen its popup. Chrome clears session rules on extension reload/update; the worker restores valid ones from the saved deadline. Browser startup is not atomic with the first navigation.

Stable development extension ID: `cdhoadjbhjmgclemjdjdbcfknognhjdm`. The manifest public key stabilizes the unpacked ID. This is not a published Web Store ID or a secret.

## Pair with the Mac app

From the repository root:

```bash
make app
open dist/Glance.app
```

In Glance Settings → **Browser Focus**:

1. Click **Enable browser connection**. This copies the bundled Swift helper into your user Application Support folder and registers user-scoped Native Messaging manifests for Chrome, Chrome for Testing, and Chromium.
2. In the extension, click **Connect to Glance**.
3. Approve the pairing dialog in Glance. No account, QR code, local port, or manually copied token is used.

When paired, the Mac owns the timer. Popup Start/Pause/Resume/End commands affect its existing Pomodoro engine. The extension normally receives changes within half a second while connected. After a reload, an opted-in profile reconnects automatically and fetches the Mac snapshot before exposing its timer. Transient startup failures retry automatically; the last known deadline is retained while offline. Use standalone explicitly opts out of Mac sync. Connecting ends any competing standalone timer and adopts the Mac immediately, including its idle state. Chrome Start never changes the Mac duration.

The Mac Settings pane shows combined focus and browser statistics. The extension shows the Mac aggregate while connected and its local profile's statistics while standalone. Multiple profile website times are summed, not unique wall-clock activity.

**Emergency stop** ends browser enforcement without requiring the Mac to respond. Only enforcement is suppressed; the displayed timer continues to mirror the Mac. That session stays suppressed through reconnect until you explicitly choose Use Mac timer, a new session begins, or its authoritative state changes. The Mac timer may continue. **Use standalone** disconnects and returns to an independent browser timer. Mac restart returns the native engine to idle and the browser follows that authoritative state.

If needed, the bundled helper also provides a development CLI installer:

```bash
.build/release/GlanceBrowserBridge --install --extension-id cdhoadjbhjmgclemjdjdbcfknognhjdm
```

The Settings button is the normal setup path. The connection is not enabled unless you opt in. The test harness and installer should never be run against another user's data. This build is ad-hoc signed; a notarized companion installer and production extension ID are still release work. Brave/Edge/Firefox/Safari are not verified targets.

## Connection troubleshooting

If you previously saw `chrome.runtime.connectNative is not a function`, reload Glance Focus at `chrome://extensions`, reopen the popup and connect again. Native Messaging is now declared at installation to avoid stale API bindings after an optional grant. The browser fixture keeps that production declaration unchanged. If the error remains, verify you loaded this folder in Google Chrome rather than opening the popup HTML as a website.

If Chrome reports **Specified native messaging host not found**, open the rebuilt `dist/Glance.app`, go to Settings → Browser Focus, and choose **Enable browser connection** or **Repair browser connection**. This registers the helper with Chrome. Reconnect afterward. Loading the extension alone does not install its native host.

## Test locally

From the repository root:

```bash
# Existing native tests plus new browser-store/protocol tests
make test

# Fast extension policy tests; no browser or dependency install needed
node --test browser-extension/tests/core.test.js

# Blocked-page layout, keyboard, single action and state checks
(cd browser-extension && npm run test:blocked)

# Isolated Chromium + real native helper + Swift engine tests
scripts/test-browser-extension.sh
```

The integration test uses a fresh `/tmp/glance-extension-test-*` profile, temporary credentials/socket/data, the real Swift Native Messaging helper and a headless test-only Swift engine harness. It does not use your Chrome profile or modify user-level native host manifests. It auto-approves pairing in the test harness only; the real app requires approval. The harness never ships inside Glance.app.

The browser fixture pregrants its exact local test host and optional APIs to avoid automating OS/browser permission dialogs. Production uses optional, user-granted website and tracking permissions; Native Messaging is declared at installation. Manually check those prompts in your unpacked install. The local HTTP fixture serves harmless pages at `distraction.test` through a resolver rule. An actual one-minute expiry is tested, so the integration suite takes at least a minute.

Integration checks cover an already-open tab, subdomains, new navigation, pause/resume/end, worker restart, full extension reload during a Mac session, reload while the Mac is unavailable, automatic retry, native pairing, native engine control, emergency suppression, disconnect/reconnect, app restart, command replay/stale revision, stats deduplication/purge, popup closure and actual deadline expiry. Results and dashboard screenshot are in `.test-results/` (ignored by Git). Physical OS idle/lock timing, production Developer ID signing and store review are not asserted by that suite.

## Local data and permission model

- Required: local storage, alarms, and declarativeNetRequestWithHostAccess.
- On adding a domain: only that domain's HTTP(S) host patterns are requested.
- Usage stats: optional `tabs` metadata and `idle`; no history, cookies, page content, keystrokes or screenshots.
- Mac connection: `nativeMessaging` is declared at installation so Chrome exposes its API from worker startup. Connecting and native app approval remain opt-in.
- Incognito is disabled for this preview.
- Chrome internal pages, local addresses, and private windows are excluded from usage tracking.
- Usage measures the active tab in a focused normal browser window while Chrome reports the OS as active, with a 60-second idle threshold. It is an approximate attention measure, not proof that someone read a page.
- Usage checkpoints are capped at 60 seconds. Worker suspension uses in-memory browser session storage to preserve a short span; browser restart discards it to avoid inventing offline time. A crash can lose the latest checkpoint. Clock jumps are bounded rather than credited as hours of browsing.
- Events and aggregates use domain names only and are retained for 30 days, bounded to the latest 50,000 events. Very heavy usage can reach that cap sooner. Blocked visits count displayed top-level focus pages with a 10-second same-tab/domain/session debounce, not every blocked network request.
- Extension data uses `chrome.storage.local`, not cloud-sync storage. No analytics or vendor telemetry is included. Mac data is mode-600 JSON under `~/Library/Application Support/Glance/Browser/`; local files are not encrypted by Glance.
- Mac sync is acknowledged and deduplicated. Clearing extension stats queues deletion of that profile's Mac copy for its next connection. Clearing only the Mac copy does not erase extension history, but acknowledged entries do not get imported again.
- Anyone controlling your same OS account can potentially access local files. This developer bridge is not a security boundary against same-user compromise or an impersonated unpacked extension; approval, credentials, peer UID and narrow commands reduce accidental exposure.

## Package and website

```bash
python3 scripts/package-extension.py  # run from repository root
python3 -m http.server 4173 --directory frontend
```

The ZIP is written to `dist/Glance-Focus-0.1.0.zip` with manifest.json at its root. Only extension runtime assets are included, never tests, profiles, private keys or native credentials. The local setup page is `http://localhost:4173/extension/`. The hosted guide and dashboard are available at glance-notch.vercel.app. Web Store registration/submission and a production-ready signed companion release are separate actions.

## Limitations to check before public release

This is bypassable focus software. Startup/sleep/wake and connection loss can delay rule reconciliation. Preloaded tabs, redirects and SPA navigation are guarded by navigation rules plus tab updates, but every site's service-worker/cache behavior needs wider beta testing. Restricted Chrome pages cannot be blocked. A paused session allows sites; breaks allow sites. Ordinary browser shutdown, extension update, permission revocation, upgrades, multiple profiles and accessibility should receive broader manual release testing. The native app still has its existing wall-clock timer semantics and does not restore an active session after quitting.

### Extension icon

The toolbar and Extensions view use the light sage outline-notch variant. The app icon is unchanged. Regenerate PNG assets with `swift scripts/render-extension-icon.swift "$PWD/browser-extension/icons"` from the repository root.

## One shared dashboard and app-owned settings

The canonical web view is `https://glance-notch.vercel.app/extension/dashboard/`. Open it with **Open web dashboard** in the extension to explicitly allow local access. Revoke that access in extension settings. The page talks only to the installed extension on this exact origin/path; the extension talks to the paired Mac. There is no website localStorage database, account, telemetry or activity upload. Pairing, mode changes and new browser permission grants stay in extension-owned UI.

While paired, the Mac stores shared block rules, exclusions and desired tracking state in `Browser/focus-preferences.json` (mode 600). Pomodoro settings use the existing native `settings.json`. Each profile retains a cache, permission grants and an event journal. Native preferences are imported from the first connecting profile only if the native preference store has never been initialized. Later profiles always adopt the Mac's copy. Stale settings writes are rejected. No edits to shared settings or new local timer starts are allowed during reconnection; choose standalone explicitly to operate independently.

The Mac's selected phase, run state, remaining time and deadline always win while connected. Browser Start uses the existing Mac configuration, regardless of a stale dropdown value. Change Pomodoro durations explicitly with **Save on Mac**; active sessions keep their original deadline. The native app and packaged options expose focus/break durations, cycle length, auto-start, sound, completion notifications, appearance and minute presets. The hosted dashboard keeps timer controls, browser preferences and activity, with a visual Mac connection panel. Native Browser Focus settings also show/edit shared website rules and desired tracking.

Regenerate hosted UI assets after changing extension UI: `python3 scripts/sync-extension-dashboard.py`. This copies the utility renderer/styles; only the transport differs. Website and extension tokens remain independently owned, as specified in DESIGN.md. For local QA, the integration suite serves these files at the exact HTTPS dashboard origin using an isolated browser route. It checks authorization, app persistence and revocation without touching the deployed site. An ordinary localhost page deliberately cannot connect to the native data bridge.
