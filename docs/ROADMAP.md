# Roadmap

The repository started at 0.x with the engine + UI foundation built together,
so 0.1 ships more than a typical first tag. Milestones below reflect the
actual sequencing from here.

## 0.1 — Foundation (current)

- Notch window with idle / peek / live / expanded states
- Screen system (navigation, persistence, restoration)
- Now Playing (Minimal + Artwork, adaptive contrast, crossfades)
- Pomodoro + completion interruptions
- Interruption engine (priority, preemption, debounce, persistence)
- Typed settings store with migrations
- Optional Battery, Network, Context foundation, Coding Context
- Claude Code hooks integration (needs input / permission / completed)
- CI, release workflow, DMG/ZIP packaging, Homebrew cask template

## 0.2 — Polish

- Real screenshots + product page assets
- Artwork-mode tuning on edge-case art; hover states pass
- VoiceOver audit of the expanded notch
- Localization scaffolding

## 0.3 — Context depth

- Opt-in window-title signal → project detection + git branch (Coding screen)
- Context screen refinements, better classification tables

## 0.4 — Claude Code depth

- Multi-session awareness
- Failure detection if/when hooks expose it
- Optional standard macOS notifications as a secondary channel (user setting)

## 0.5 — Universal Activities + hardening

- Unix-domain-socket activity server + signed `glance` CLI
  (protocol: docs/EXTERNAL_ACTIVITIES.md)
- Privacy hardening (screen-sharing redaction if reliably detectable)
- Performance audit under long uptime; multi-display refinements

## 1.0 — Stable public release

- Signed + notarized DMG/ZIP via GitHub Releases
- Sparkle automatic updates (docs/RELEASING.md checklist)
- Homebrew cask published

## Later / exploratory

- Additional media sources (browser players) — only with a public-API path
- Localhost service activity, git activity, background process activity
- Focus recipes; deployment integrations; iPhone companion & cross-device
  activities

## Explicit non-goals

System notification interception · Notification Center scraping · banner
suppression · generic agent detection · clipboard manager · screenshot shelf
· plugin marketplace · analytics dashboards.
