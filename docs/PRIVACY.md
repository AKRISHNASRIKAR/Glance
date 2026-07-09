# Privacy

> Your Mac activity is analysed locally. Activity data does not leave this
> Mac unless an explicitly enabled integration requires external
> communication.

## Network traffic, exhaustively

| Feature | Traffic |
|---|---|
| Core app, Pomodoro, screens, interruptions | none |
| Apple Music integration | none (local notifications + local Apple Events) |
| Spotify integration | HTTPS GET of album artwork from Spotify's image CDN (the artwork URL Spotify itself reports). Off if Now Playing is disabled. |
| System-wide Now Playing (Experimental, off by default) | none — local IPC to a system daemon (MediaRemote) only, same as Control Center's widget. Reads title/artist/album/artwork of whatever any app is playing, system-wide, while enabled. |
| Context awareness, coding context, battery, network, Claude Code | none |

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
- window titles, browser history/domains, terminal processes (not even read)
- track titles or any user content in the unified log (log lines carry state
  names and counts only)

## Controls

- **Never Track list** (Settings → Privacy): bundle identifiers Glance must
  ignore in every context feature, with an "Add Frontmost Application"
  shortcut.
- All observation features are **off by default**; enabling one is explicit.
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
