# Universal Activities (Planned)

**Status: protocol draft. Not implemented in the current release.** This
document exists so the design is public before code lands; nothing below
ships today.

## Goal

Let local tools and scripts publish declarative Live Activities to the notch:

```
glance activity create --id build-42 --title "Building CinemaScope" --progress 0.3
glance activity update --id build-42 --progress 0.8
glance activity complete --id build-42
```

This is a **local developer integration**, not a notification system.

## Transport decision

Evaluated:

| Option | Verdict |
|---|---|
| Unix domain socket in `~/Library/Application Support/Glance/` | **Chosen.** Filesystem permissions scope it to the user; no network exposure; trivial from any language. |
| XPC | Great for bundled helpers, poor for arbitrary scripts (needs a compiled client). Possible later for a signed CLI. |
| localhost TCP/HTTP | Rejected — an open port is reachable by any local process and misconfiguration can expose it externally. |

The socket will be created mode 0600. **No external network listener, ever.**

## Protocol sketch (v0 draft)

Newline-delimited JSON over the socket:

```json
{"v":1,"op":"create","id":"build-42","title":"Building CinemaScope",
 "subtitle":"release","progress":0.3,"state":"active",
 "priority":"passive","displayDuration":null}
{"v":1,"op":"update","id":"build-42","progress":0.8}
{"v":1,"op":"complete","id":"build-42"}
{"v":1,"op":"fail","id":"build-42","subtitle":"link error"}
{"v":1,"op":"remove","id":"build-42"}
```

Hard rules for the implementation:

- Payloads are **declarative data only**. No field is ever interpreted as a
  command; nothing is executed. Unknown fields are ignored.
- Priority is capped at `important`; external tools cannot claim `urgent`.
- Per-connection rate limiting and a cap on concurrent activities.
- Activities from external tools are visually attributed ("via CLI").
- Master toggle in Settings → Activities, off by default.

## Roadmap position

Targeted at 0.5 together with a small signed `glance` CLI. See ROADMAP.md.
