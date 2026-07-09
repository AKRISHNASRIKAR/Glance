# Screen System

Screens are focused notch experiences arranged horizontally. Exactly one is
visible at a time in the expanded notch.

## Model

`NotchScreen { id, type, isEnabled }`, ordered by position in
`GlanceSettings.screens`. `ScreenType` is extensible
(`nowPlaying, pomodoro, claudeCode, codingContext`); unknown persisted types
decode tolerantly and are dropped rather than crashing older builds.

Default first-launch configuration — exactly:

1. Now Playing
2. Pomodoro

`claudeCode` and `codingContext` become addable only when their provider is
enabled (`ScreenStore.addableScreenTypes(providerEnabled:)`). Disabling a
provider removes its screens.

## Navigation

While expanded:

- two-finger horizontal trackpad swipe / horizontal mouse scroll
  (local `scrollWheel` monitor, 30 pt accumulation threshold, 350 ms settle
  between page turns)
- ⌘← / ⌘→ — handled by the panel's `keyDown` only while the notch panel is
  key, so it can never shadow shortcuts in other apps or active text input
- clickable chevrons + page dots (the accessibility affordance)
- Escape or clicking anywhere outside collapses

Navigation clamps at the ends (no wraparound) so spatial position stays
predictable. Transitions slide content horizontally inside the fixed shape
with a restrained spring; the window never moves. Reduce Motion disables the
spring and crossfades instead.

## Restoration (documented behavior)

- The selected screen persists across open/close and app relaunch.
- If the notch is reopened **more than 30 minutes** after it was closed,
  selection resets to the first screen (`GeneralSettings.screenResetAfterSeconds`).
  Rationale: after a long absence, a stale deep pager position is more
  confusing than a predictable home screen.
- Interruptions never change the selection — when one ends, the previous
  screen is simply revealed again.

## Configuration UI

Settings → Notch Screens: toggle, remove (non-default screens), drag to
reorder, and an Add Screen menu listing only screens whose providers are
enabled. There are no placeholder screens for unimplemented features.
