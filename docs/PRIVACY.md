# Privacy

> Mac activity is analysed locally. The optional Chrome companion shares
> focus state and opted-in domain statistics between your browser and Mac.
> There is no activity upload service.

## Network traffic

| Feature | Traffic |
|---|---|
| Core app, Pomodoro, screens, interruptions | none |
| Apple Music integration | none (local notifications + local Apple Events) |
| Spotify integration | HTTPS GET of album artwork from Spotify's image CDN (the artwork URL Spotify itself reports). Off if Now Playing is disabled. |
| System-wide Now Playing (Experimental, off by default) | none — local IPC to a system daemon (MediaRemote) only, same as Control Center's widget. Reads title/artist/album/artwork of whatever any app is playing, system-wide, while enabled. |
| Context awareness, coding context, battery, network, Claude Code | none |
| Optional Chrome companion | Local Native Messaging / Unix socket to Glance; no activity upload endpoint |
| Marketing website and hosted dashboard | Static assets from the website host and Google Fonts. Hosting providers receive ordinary request metadata. Dashboard activity access requires explicit extension authorization; activity is not sent to the website host. |

There is no telemetry, no crash reporting, no update phone-home (Sparkle is
not integrated yet; when it is, it will be documented here first).

## What is stored, and where

| Data | Location | Control |
|---|---|---|
| Settings | `~/Library/Application Support/Glance/settings.json` | — |
| Context sessions (kind, app name, start/end) | `…/context-history.json` | retention picker + Clear button |
| Claude Code session state | memory only; durations optionally in history | toggle |

## What is never logged or stored

- prompts and tool inputs (discarded by hook design — see
  CLAUDE_CODE_INTEGRATION.md)
- source code contents
- clipboard contents
- tokens, API keys
- window titles and terminal processes (not read by context observation)
- page contents, URL paths, search queries and keystrokes (the optional extension reads domains only)
- track titles or any user content in the unified log (log lines carry state
  names and counts only)

## Controls

- **Never Track list** (Settings → Privacy): bundle identifiers Glance must
  ignore in every context feature, with an "Add Frontmost Application"
  shortcut.
- Context observation and website usage tracking require explicit opt-in. Blocking permission and usage tracking permission are separate.
- Interruptions carry a privacy classification; `sensitive` ones (e.g. the
  Claude permission message) are marked in the model. Automatic redaction
  while screen sharing is **Planned** — macOS offers no reliable public "am I
  being captured by another app" signal, and Glance does not ship unreliable
  privacy features.

## Permissions Glance may request

| Permission | Trigger | Purpose |
|---|---|---|
| Automation (Apple Events) for Music/Spotify | first playback control / artwork fetch | read position, control playback |

Nothing else: no Accessibility, no Screen Recording, no Input Monitoring, no
Full Disk Access. **This includes notifications**: Glance does not read,
intercept, or store the content of other apps' notifications (WhatsApp,
Mail, iMessage, or anything else). There is no public API for that, and the
only ways to do it — Accessibility scraping of Notification Center's UI, or
reading its private on-disk database — are both things this project
deliberately does not do. Notch Interruptions are generated only by Glance's
own providers (Pomodoro, Claude Code, battery, network, media); see
docs/INTERRUPTION_ENGINE.md.

## Private API use

One feature, System-wide Now Playing, is opt-in and off by default, and uses
Apple's private, undocumented MediaRemote framework because there is no
public alternative (see docs/NOW_PLAYING.md). It is the **only** place in
the codebase that touches a private API, it is not loaded into the process
until the user explicitly enables it, and it reads only media metadata —
the same information Control Center already surfaces.

## Optional browser companion

Glance Focus stores website rules, session state, per-profile permissions and an event journal in `chrome.storage.local`, not cloud-sync storage. When usage tracking is enabled, it records domain-level active time, focus sessions and blocked-site attempts. Only an active tab in a focused normal window counts, while Chrome reports the system active (60-second idle threshold). Internal pages, local addresses and private windows are excluded. Time is approximate; crashes can lose the latest checkpoint. Activity is retained for 30 days.

When paired, the Mac is the source of truth for the timer and shared preferences. Files under `~/Library/Application Support/Glance/Browser/` include `focus-preferences.json` (rules and tracking preferences), `statistics.json` (activity) and local bridge credentials/configuration. They use owner-only file permissions; Glance does not encrypt these files. Do not share them in issues or commit them. Native Pomodoro configuration remains in the app's `settings.json`.

The extension requests Native Messaging, storage, alarms and declarative website-blocking access. Site permissions are granted per website; optional `tabs` and `idle` permissions enable usage stats. You can pause tracking, exclude domains, export or delete statistics and revoke web-dashboard access in extension settings. Pairing and new permission grants remain in extension-owned UI. The web dashboard is not a cloud database and has no signup. See [Browser Focus release notes](releases/v0.2.0.md) for the app release scope.
