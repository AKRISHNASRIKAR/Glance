# Architecture

Glance is a SwiftPM package with two targets plus tests:

| Target | Role |
|---|---|
| `GlanceKit` (library) | Engines, models, providers. Headless, no UI imports beyond AppKit where system APIs require it. Everything here is unit-testable. |
| `Glance` (executable) | The app: AppKit notch panel, SwiftUI content, Settings window, status item. |
| `GlanceKitTests` | Swift Testing suite (90 tests) driven by injected fake clocks/schedulers. |

## Data flow

```
Provider ──typed events──► Activity Engine ──► Interruption Engine ──► Notch UI
    │                                                    ▲
    └──published state (Combine) ──► Screen views ───────┘
```

Rules enforced by design:

- **Providers never touch the UI.** They publish typed state (`@Published`) and emit `NotchInterruption` values through a sink the Activity Engine wires in.
- **The UI never polls system APIs.** It renders published engine state. The only timers in views are 1 Hz `TimelineView`s while the relevant screen is visible.
- **Providers fail independently.** `ActivityEngine` starts/stops each provider from its settings predicate; failures surface as `ProviderStatus` (`running / disabled / notConfigured / permissionRequired / unavailable / error`) shown in Settings, never as crashes.

## Core components

- `SettingsStore` — single typed `GlanceSettings` value persisted as versioned JSON (`schemaVersion` + migration pipeline + structural sanitizer). Debounced atomic writes.
- `ScreenStore` — screen list, ordering, selection, restoration policy (returns to first screen after 30 min closed; otherwise remembers selection).
- `InterruptionEngine` — priority queue with preemption, minimum-display semantics, per-kind debouncing, queue TTL, persistent interruptions, and provider-driven resolution. See INTERRUPTION_ENGINE.md.
- `ActivityEngine` — provider lifecycle + status registry.
- `PomodoroEngine` — wall-clock anchored state machine (immune to missed ticks/sleep).
- `NowPlayingProvider` + `MediaSource`s — see NOW_PLAYING.md.
- `ContextEngine` — pure signal classifier + session tracker; `ContextProvider` feeds it real signals. See CONTEXT_ENGINE.md.
- `ClaudeCodeProvider` — hook spool watcher + state machine. See CLAUDE_CODE_INTEGRATION.md.

## Notch window

- `NotchPanel` (NSPanel, `.borderless .nonactivatingPanel`, status-bar level, all-Spaces) has a **fixed frame** large enough for the expanded state. The visible black shape animates inside it — the window itself never resizes, which eliminates resize jank.
- `NotchHostingView.hitTest` rejects events outside the current shape, so the invisible window regions are click-through.
- Geometry comes from `NSScreen.safeAreaInsets` + `auxiliaryTopLeftArea/auxiliaryTopRightArea` — no hard-coded notch sizes. Displays without a notch get a synthetic top-center surface (configurable off).
- Display changes (`didChangeScreenParametersNotification`) rebuild or reposition the panel.

## Concurrency

- All engines and providers are `@MainActor`; cross-thread inputs (distributed notifications, NWPathMonitor, IOKit callbacks) hop to the main actor at the boundary.
- Deferred work goes through the `GlanceScheduler` protocol (`TimerScheduler` in production, a virtual-time `TestClock` in tests); "now" comes from `TimeSource`. No test sleeps.
- AppleScript execution is confined to one serial queue (`ScriptRunner`); artwork decode/analysis runs in a detached utility task with cancellation + stale-result guards.
- Swift 6 language mode; the package compiles with strict concurrency checking.

## Performance-sensitive components

| Component | Cost profile |
|---|---|
| Idle notch | Zero timers, zero polling. Event-driven only. |
| Pomodoro | 1 Hz timer **only while running** (10% tolerance). |
| Now Playing | Event-driven (distributed notifications). Position sampled every 5 s only while the screen is open and playing. Artwork analyzed once per track (16×16 thumbnail) and cached (LRU 24). |
| Network | 2 s counter sampling **only while the provider is enabled**; connectivity via NWPathMonitor (event-driven). |
| Battery | IOKit notification source; no polling. |
| Context | Frontmost-app events + one idle-time syscall every 30 s while enabled. |
| Claude Code | Dispatch file-system source on the spool directory; no polling. |
