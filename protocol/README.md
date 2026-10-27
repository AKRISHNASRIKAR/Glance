# Glance local browser protocol v1

Transport: Chrome Native Messaging (4-byte little-endian UTF-8 JSON length) to a Swift helper, then newline JSON over a user-owned Unix socket to the running app. Each message is capped at 256 KiB. No TCP listener is used. The helper checks the exact origin against mode-600 local configuration, adds the app-issued token, and the socket server verifies peer UID and token. Same-user local compromise and impersonated unpacked IDs are not prevented by this development transport. The app explicitly approves each profile UUID.

Requests: `{protocolVersion:1,id:UUID,clientID:UUID,type,payload}`. The helper adds `origin` and `token`, neither accepted from the extension as authority. Replies: `{id,ok,payload?,error?}`.

- `pair {}`: explicit approval, then authoritative snapshot.
- `snapshot {}`: approved-client snapshot, epoch, revision, session, aggregate local stats, native Pomodoro settings, and revisioned browser preferences.
- `timer {action:start|pause|resume|stop, expectedRevision}`: Start uses the existing native configuration/phase and ignores legacy minutes payloads. Only matching revisions apply; successful command IDs are cached for idempotent retries (bounded, current process only).
- `stats {events:[...]}`: at most 100 events, with `id=clientID:sequence`, type `usage|focus|blocked`, hostname only, milliseconds epoch timestamp, seconds, optional sessionID/outcome. Browser events are acknowledged by sequence and duplicate/replayed IDs are ignored.
- `purgeStats {throughSequence}`: delete this profile's Mac copy and retain its acknowledgement cursor, preventing resurrection on replay.

Snapshot session: `{id?,owner:'mac',phase:'focus'|'shortBreak'|'longBreak',state:'idle'|'running'|'paused',remaining:milliseconds,endAt:epochMilliseconds|null,revision}`. An app-run epoch changes on restart. The app does not persist an active native timer, so its idle state after restart is authoritative. Browser focus IDs and Mac focus IDs have separate owners. Browser-mirrored sessions are not uploaded as duplicate focus events.

`development.json` contains a public development key and stable unpacked extension ID. It is not a signing secret or security credential. Replace/allow the actual Web Store ID deliberately before release. Private pairing tokens are generated locally and must never enter this repo or an extension package.

- `preferences {expectedRevision,value:{entries:[{domain,subdomains,enabled}],tracking,exclusions}}`: validate and atomically save app-owned shared browser settings; reject stale revisions. Snapshot preferences include `initialized`, `revision` and `value`. Only the first profile initializes an unused native store.
- `pomodoroSettings {expected:PomodoroSettings,value:PomodoroSettings}`: compare the complete expected configuration, validate bounded durations/cycles/presets, save through native SettingsStore, and return the authoritative snapshot. Active deadlines remain intact.

The hosted dashboard bridge is separate from Native Messaging: Chrome `onMessageExternal` accepts only top-level `https://glance-notch.vercel.app/extension/dashboard/` pages after explicit authorization in the extension. Commands are allowlisted; the site never receives helper credentials or native filesystem/socket access. Permission requests are handed to packaged extension UI. The hosted page stores no independent state and sends no data to a server. It is an authorized control surface, not a remote/cloud database.
