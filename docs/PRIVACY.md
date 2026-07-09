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
Full Disk Access.
