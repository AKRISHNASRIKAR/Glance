# Now Playing

## The honest constraint

macOS provides **no public API to read another application's now-playing
state**. `MPNowPlayingInfoCenter` is publish-only; the framework that powers
Control Center's media widget (`MediaRemote`) is private, undocumented, and
unversioned.

Glance ships two tiers, and is explicit in the UI about which is which:

| Source | State changes | Position | Artwork | Control | API surface |
|---|---|---|---|---|---|
| Apple Music | `com.apple.Music.playerInfo` distributed notification (event-driven) | Scripting (`player position`) | Scripting (`data of artwork 1`) | Scripting | Public (Apple Events / Automation) |
| Spotify | `com.spotify.client.PlaybackStateChanged` (includes position) | Scripting | `artwork url` → HTTPS fetch from Spotify's CDN | Scripting | Public |
| System-wide (**Experimental**, opt-in) | `MediaRemote` notification (event-driven) | From the last info dictionary | Embedded artwork data in the info dictionary | `MRMediaRemoteSendCommand` | **Private, undocumented** |

Scripting uses Apple Events, which macOS gates behind the **Automation
permission** (`NSAppleEventsUsageDescription`); the user is prompted on first
control/artwork access per app. Glance never sends Apple Events to an app
that isn't running.

### System-wide Now Playing (Experimental)

Every app that shows a system-wide Now Playing widget — including Control
Center itself — reads from Apple's private `MediaRemote.framework`. There is
no alternative; this is the only way to see what's playing in an arbitrary
app (Safari, Chrome, VLC, a podcast app, ...).

Glance isolates this to two files:

- `MediaRemoteBridge.swift` — dlopen's the framework and dlsym's each symbol
  it needs (`MRMediaRemoteGetNowPlayingInfo`,
  `MRMediaRemoteRegisterForNowPlayingNotifications`, `MRMediaRemoteSendCommand`,
  and — best-effort only — `MRMediaRemoteGetNowPlayingClient` to label the
  source with a real app name). Every lookup is nil-checked; if the
  framework or a required symbol is missing, `isAvailable` is `false` and
  the feature reports **Unavailable** rather than crashing or faking data.
  The dictionary key names it reads (`kMRMediaRemoteNowPlayingInfoTitle` and
  siblings) are the values used consistently across community
  reverse-engineering and several public open-source MediaRemote wrappers —
  Apple has never published them.
- `SystemMediaRemoteSource.swift` — the `MediaSource` conformance that turns
  the raw dictionary into a `MediaState`.

This is **the only place in the codebase that uses a private API**, and it
is fully opt-in:

- Off by default. `NowPlayingSettings.enableSystemMediaRemote` gates it.
- The private framework is not even `dlopen`'d until the user turns the
  toggle on — `MediaRemoteBridge.shared` is a lazy singleton nothing
  references until then.
- Settings labels it **Experimental** with an explicit note that it uses an
  undocumented API that could break on any macOS update without notice.
- It never replaces or disables the Apple Music/Spotify integrations; all
  three sources arbitrate normally (playing beats paused; most-recent-change
  breaks ties).
- The resolved app name (e.g. "Safari") is best-effort via
  `MediaState.sourceAppName`; when it can't be resolved, the UI falls back to
  the generic "System Media" label rather than guessing.

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
adaptive contrast toggle, show/hide for artwork, progress, and
previous/next controls, and the System-wide Now Playing experimental toggle
— all applied live, no restart.
