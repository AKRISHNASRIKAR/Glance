# Pomodoro

## Architecture: one engine, many renderers

```
PomodoroEngine (timer logic — the only place it exists)
        │
        ▼
PomodoroDisplayState + PomodoroActions   (Sources/Glance/Notch/Screens/Pomodoro/PomodoroDisplayState.swift)
        │
        ▼
PomodoroScreenView (dispatcher, switches on PomodoroSettings.appearance)
        │
        ├── ClassicPomodoroRenderer
        ├── MinimalPomodoroRenderer
        ├── CompactPomodoroRenderer
        ├── AmbientPomodoroRenderer
        └── ArtworkPomodoroRenderer
```

`PomodoroEngine` (`Sources/GlanceKit/Pomodoro/PomodoroEngine.swift`) is untouched
by this system: phase, run state, remaining time, and progress are computed
from wall-clock anchors exactly as before. No renderer reads it directly.
`PomodoroDisplayState` and `PomodoroActions` read from it (`engine.phaseDuration`
for "how long is the active phase", never re-deriving that switch themselves)
rather than duplicating anything it already computes.

Each render, `PomodoroScreenView` builds two plain value types from the
engine + settings:

- **`PomodoroDisplayState`** — an immutable snapshot (phase, run state,
  remaining, progress, session counts, phase color, the Artwork tint). Pure
  data; a renderer's whole job is to lay this out.
- **`PomodoroActions`** — closures (`start`, `pause`, `resume`, `reset`,
  `skipBreak`, `selectPhase`, `adjustDuration`) that close over the engine
  and `SettingsStore`. This is the *only* path through which any renderer
  can affect the timer — none of them hold a reference to `PomodoroEngine`
  or `SettingsStore` themselves.

`PomodoroPrimaryActionSpec` centralizes the one piece of UI-facing logic
that isn't pure layout: what the main button says and does for the current
run state (Start → Pause → Resume). Every renderer that has a primary
button derives it from this instead of re-deriving the same switch
statement five times.

Classic and Artwork are both rich enough to want the same composite —
stepper (idle) + ring + phase header + controls — so they share it via
`PomodoroRingHeaderLayout` (`PomodoroUIKit.swift`), parameterized by accent
color and a few size/opacity constants; each renderer is little more than
that composite plus its own outer padding/background. Compact, Minimal, and
Ambient are different enough in shape that they compose the smaller atoms
directly instead.

## Adding a new appearance

1. Add a case to `PomodoroAppearance` (`Sources/GlanceKit/Settings/GlanceSettings.swift`).
2. Write a new `SomethingPomodoroRenderer: View` taking `state: PomodoroDisplayState`
   and `actions: PomodoroActions` (plus `reduceMotion: Bool` if it animates).
   Build it from the shared atoms in `PomodoroUIKit.swift`
   (`PomodoroRingView`, `PomodoroSessionTrack`, `PomodoroStepperPill`,
   `PomodoroPhaseSelector`, `PomodoroControlsRow`) wherever they fit; write
   new ones only for looks the existing atoms can't express.
3. Add one switch arm in `PomodoroScreenView`.

No engine or settings-persistence code needs to change — the new case
round-trips through `PomodoroSettings.appearance`'s existing `Codable`
conformance automatically.

## The five appearances

| Appearance | Idea | Distinguishing choice |
|---|---|---|
| Classic (default) | The balanced experience | Ring + text column, same grammar as Now Playing |
| Minimal | Almost entirely typography | No ring at all — a hairline progress rule instead |
| Compact | Smallest footprint | Icon-only controls, no stepper; usable at half notch width |
| Ambient | Nearly invisible | Hairline ring at low opacity; controls fade in only on hover |
| Artwork | Expressive | Full-bleed translucent color wash behind the whole notch shape |

Design language shared across all five (matching the redesigned Now Playing
screen): the same ring math and `AngularGradient` fill, the same session
progress bars, the same button styles (`NotchCapsuleButtonStyle`,
`NotchIconButton`), the same phase colors (orange/mint), the same
reduce-motion handling. Nothing here uses dashboards, statistics,
motivational text, neon color, or oversized shadows/glassmorphism.

## Artwork's background

Unlike Now Playing, there's no album art to derive a background from.
`PomodoroArtworkBackgroundView` washes two large, heavily blurred circles of
a phase-specific tint (cool blue for Focus, soft green for short break,
purple for long break — `PomodoroDisplayState.artworkTint`) over black,
under a fixed dark scrim for contrast. It's wired into
`NotchRootView.fullBleedArtwork` alongside Now Playing's artwork
background — the two are mutually exclusive since they're different
Screens, so only one full-bleed background is ever active. The scrim is a
fixed opacity rather than an adaptive per-pixel analysis (like artwork's
`ArtworkAnalyzer`) — the three tints are known and bounded ahead of time,
so there's nothing to analyze.

## Settings

Settings → Pomodoro → Appearance is a radio-button picker over
`PomodoroAppearance.allCases`; the choice is `PomodoroSettings.appearance`,
persisted like every other setting and applied live (the dispatcher reads
it every render, so switching appearances updates the Screen immediately,
no restart).
