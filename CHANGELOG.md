# Changelog

All notable changes to Glance are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com) and the project follows
Semantic Versioning.

## [Unreleased]

### Added

- Notch surface with idle, peek, live, and expanded states; fixed-frame
  panel with shape-based hit-testing and spring motion (Reduce Motion aware)
- Horizontal Screen system with swipe / ⌘←→ / chevron navigation,
  persistence, and 30-minute restoration policy
- Now Playing for Apple Music and Spotify: Minimal and Artwork appearances,
  adaptive artwork contrast engine with per-artwork caching, crossfading
  backgrounds, honest interpolated progress
- Pomodoro with focus/short/long break cycle, auto-start options, sound, and
  completion interruptions; idle-only +/- arrows beside the ring to dial in
  a custom phase duration directly, without opening Settings; session-
  progress dots for the focus cycle
- Interruption engine: priorities (passive/normal/important/urgent),
  preemption, debouncing, queue TTL, persistent interruptions, actions
- Optional providers: Battery & Charging (IOKit, event-driven), Network
  Activity (threshold-gated throughput + connectivity), Context Awareness
  (local classification + history with retention controls), Coding Activity
- Claude Code integration via official hooks with safe installer (backup,
  idempotent, uninstall), prompt-discarding hook design, needs-input /
  permission / completed interruptions, optional status Screen
- Typed settings store (versioned JSON, migrations, sanitization)
- Settings window: General, Notch Screens, Now Playing, Pomodoro,
  Activities, Context Awareness, Claude Code, Privacy, About
- Privacy: Never Track list, local-only history, no telemetry
- Packaging: app-bundle + DMG/ZIP scripts, CI, tag-driven release workflow
  with signing/notarization gates, Homebrew cask template
- App icon and a new menu bar glyph — a notch-shaped mark with a centered
  "live" indicator dot, replacing the placeholder SF Symbol
- 90-test suite covering engines, providers, persistence, and normalization

### Changed

- Now Playing: tightened the gap between the track text and transport
  controls, nudged content down from the top edge, and centered the
  transport cluster under the progress bar instead of hugging the left edge
- Pomodoro Screen redesigned: centered layout consistent with the other
  Screens, larger ring, session-progress dots

### Removed

- The passive "track changed" Notch Interruption for Now Playing — song
  changes are natural and no longer raise a dismissable notification
