# Pomodoro UI

The native timer has three appearances:

- **Classic:** centered ring with the countdown inside, phase controls above, duration adjustment on the left, Start/Pause/Resume on the right, and session dots below. All content clears the bottom page-navigation strip.
- **Artwork:** the same centered layout over a translucent phase-colored background. All Pomodoro appearances now share a full-notch phase gradient: sage/plum for focus, blue/plum for short rest, and lavender/plum for long rest.
- **Minimal:** only the countdown at the true horizontal center, with duration arrows on either side and a separately aligned playback control at the right edge. Right-click for phase selection, reset, and skip-rest actions. Arrows select exactly 5, 15, 25, or 50 minutes and are disabled while running or paused.

Ambient and Compact have been retired. Existing saved values decode to Classic without resetting other Pomodoro settings.

While running with the notch closed, focus and rest show a breathing progress orbit. Rainfall has been removed. Animation pauses with the timer and respects Reduce Motion. Decoration never changes timer progress or engine state.

## Architecture

`PomodoroScreenView` builds one `PomodoroDisplayState` and `PomodoroActions` bundle from the existing engine. Each renderer receives those values; timer logic remains in `PomodoroEngine`.

`ClassicPomodoroRenderer` supplies both Classic and Artwork foregrounds. `PomodoroRingView` owns the animated orbit. `PomodoroArtworkBackgroundView` renders the full expanded background from `NotchRootView`.

The phase selector, session track, duration stepper, and primary action mapping are shared. Classic and Artwork use the configured duration pool; Minimal supplies its fixed duration pool through the same action helper.

## Validation

Run `make test` for timer/provider/settings coverage, including migration of retired appearances. Run `make app` to build `dist/Glance.app`. Review the appearances at full and paired screen widths, and check active focus, active rest, pause, reset, and Reduce Motion.
