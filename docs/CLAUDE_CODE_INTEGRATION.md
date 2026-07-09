# Claude Code Integration

Glance integrates with Claude Code **exclusively through its official hooks**
(https://docs.anthropic.com/en/docs/claude-code/hooks). No screen scraping,
no process inspection, no generic "agent detection".

## How it works

```
Claude Code ── hook command ──► spool file ──► ClaudeCodeProvider
   (official)                  (~/Library/Application Support/
                                Glance/claude-code-events/)
                                        │  DispatchSource (event-driven)
                                        ▼
                          normalize → state machine → Activity Engine
                                        │
                    Claude Screen  ◄────┴────►  Notch Interruptions
```

Installed hooks and what each writes:

| Hook | Spool file | Contents |
|---|---|---|
| SessionStart | `sessionstart-*.json` | hook JSON (session id, cwd) |
| UserPromptSubmit | `prompt-*.marker` | **empty** — stdin is discarded |
| PreToolUse | `tool-*.marker` | **empty** — stdin is discarded |
| Notification | `notification-*.json` | hook JSON incl. the system message ("Claude needs your permission to use Bash") |
| Stop | `stop-*.json` | hook JSON (no message content) |
| SessionEnd | `sessionend-*.json` | hook JSON |

**Prompt privacy is structural, not policy:** the `UserPromptSubmit` and
`PreToolUse` hook commands are `cat > /dev/null && mktemp …` — the prompt and
tool payloads are discarded by the shell before anything touches disk. Spool
files are deleted immediately after normalization; only the typed state and
session durations remain in memory (durations optionally in local history).

## Installer safety

Settings → Claude Code → Install Hooks:

- shows the exact hook commands before you confirm
- backs up `~/.claude/settings.json` to `settings.json.glance-backup-<timestamp>`
- edits via JSON round-trip that preserves every existing key and hook
- is idempotent (re-install replaces only Glance's entries)
- uninstall removes exactly the entries whose command references Glance's
  spool directory — nothing else
- every hook command ends in `|| true`, so a Glance bug can never block
  Claude Code

Manual setup: add the commands shown in the install preview to the matching
hook events yourself; Glance detects them by the spool path.

## State model (only reliably derivable states)

```
idle → working (prompt/tool marker) → needsInput | permissionRequired (Notification)
                                    → completed (Stop) → idle (SessionEnd)
```

`permissionRequired` vs `needsInput` is distinguished by the Notification
message containing "permission".

**Documented limitations:**

- Hooks do not report granular activity ("editing X", "running tests",
  "thinking") — Glance shows *Working*, nothing more specific, on purpose.
- Hooks do not report failures. The `failed` state exists in the model but is
  never produced today, and Settings does not offer a failure toggle. If a
  future hook reports failures reliably, the wiring is ready.
- Multiple concurrent sessions collapse into "most recent event wins" (v0
  limitation).

## Interruptions

| Event | Interruption | Priority | Persistent |
|---|---|---|---|
| Needs input | "Claude · Needs input — Claude is waiting for you" `[Open Claude]` | important | yes (resolved when Claude resumes) |
| Permission required | "Claude · Permission" + system message `[Open Claude]` | important | yes |
| Completed | "Claude · Completed — Finished in 3m 12s" | important | no (5 s) |

Each is individually toggleable. **Open Claude** activates the frontmost
running terminal app (iTerm2, Terminal, Warp, WezTerm, kitty, Ghostty) — the
app cannot know which window hosts Claude, so activating the terminal is the
honest best effort.
