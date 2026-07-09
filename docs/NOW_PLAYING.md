# Now Playing

## The honest constraint

macOS provides **no public API to read another application's now-playing
state**. `MPNowPlayingInfoCenter` is publish-only; the framework that powers
Control Center's media widget (`MediaRemote`) is private. Glance **does not
use MediaRemote** — private frameworks break without notice, are grounds for
notarization/App Review problems, and violate this project's rules.

Instead, Glance ships per-source providers behind a `MediaSource`
abstraction:

| Source | State changes | Position | Artwork | Control |
|---|---|---|---|---|
| Apple Music | `com.apple.Music.playerInfo` distributed notification (event-driven) | Scripting (`player position`) | Scripting (`data of artwork 1`) | Scripting |
| Spotify | `com.spotify.client.PlaybackStateChanged` (includes position) | Scripting | `artwork url` → HTTPS fetch from Spotify's CDN | Scripting |

Scripting uses Apple Events, which macOS gates behind the **Automation
permission** (`NSAppleEventsUsageDescription`); the user is prompted on first
control/artwork access per app. Glance never sends Apple Events to an app
that isn't running.

Consequence, stated plainly: **Safari, Chrome, YouTube, and other players are
not supported today.** Additional `MediaSource` implementations are the
extension point (documented future work), not a universal scraper.

## Normalization

Both sources normalize into `MediaState { title, artist, album, duration,
elapsed, elapsedCapturedAt, playbackState, source, artworkID }`. The pure
notification→state mapping lives in `MediaNotificationNormalizer` and is unit
tested.

**Progress honesty:** `elapsed` is always a position the player actually
reported, stamped with capture time. While playing, the UI interpolates
`elapsed + (now − capturedAt)` clamped to duration — interpolation of real
data, not invention. While the Now Playing screen is open and playing, the
true position is re-sampled every 5 s to correct drift; closed, there is no
polling at all.

## Source arbitration

A playing source beats a paused one; ties go to the most recent change.
Transport commands route to whichever source owns the current state.

## Artwork pipeline (Artwork appearance)

```
artwork bytes → aspect fill → 1.12× scale → blur (6–30 pt, user setting)
             → translucent dark layer → adaptive contrast overlay → content
```

The **adaptive contrast engine** (`ArtworkAnalyzer`) downsamples artwork to a
16×16 thumbnail, computes Rec. 709 luminance mean + variance, and maps them
to an overlay opacity (bright art ≈ 0.62+, dark art ≈ 0.25, busy art gets up
to +0.1), clamped to 0.15–0.75 so text is always readable. Analysis runs
**once per artwork identifier**, off the main actor, and is LRU-cached (24
entries) — track changes cost one tiny decode, never per-frame work.

Track changes crossfade the background and the square artwork independently
(~450–500 ms ease); Reduce Motion replaces animation with a direct swap.

## Settings

Player appearance (Minimal / Artwork), artwork blur, background intensity,
adaptive contrast toggle, and show/hide for artwork, progress, and
previous/next controls — all applied live, no restart.
