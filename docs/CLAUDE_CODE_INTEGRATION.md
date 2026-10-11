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
- **SessionEnd doesn't always fire.** It only runs if Claude Code exits
  somewhat gracefully; a force-closed terminal, a killed process, or the
  machine sleeping through it means Glance never hears about it, and hooks
  are the only signal it has — there is no process to check. Left
  unhandled, that would leave `needsInput`/`permissionRequired`/`completed`
  showing forever for a session that's actually long gone.
  `ClaudeCodeProvider.stalenessTimeout` (20 minutes) is a fallback: any hook
  event at all resets it, but if nothing arrives for that long while sitting
  in one of those three states, Glance synthesizes a `SessionEnd` for itself
  and falls back to idle. `.working` is deliberately exempt — a single
  long-running tool call can go quiet for a while without that meaning the
  session is gone.
- Glance tracks exactly one session at a time (v0 limitation — no real
  multi-session model, just a single `sessionID` slot with no per-session
  liveness tracking). Once a session is being tracked, though, an event
  carrying a *different* `session_id` is ignored outright rather than
  "most recent wins" — a second concurrent session (another terminal, another
  project) can never mutate the tracked one's state, whether via `SessionEnd`
  wiping it out, a stray `Notification`/`Stop` silently reassigning which
  session Glance is "the" tracked one, or (by extension) re-anchoring the
  staleness fallback above to the wrong session. `SessionStart` is the one
  deliberate exception — a new session starting is expected to take over
  tracking.

## Main agent vs. subagent

Claude Code's hook payload carries `agent_id`/`agent_type` whenever a hook
fires inside a subagent (a Task-tool invocation); both are absent for the
main session. `session_id` is shared between a session and every subagent it
spawns, so `agent_id` is the only signal that distinguishes "the main agent
needs you" from "a subagent needs you" — the `Notification` hook (the one
that actually drives `needsInput`/`permissionRequired`) already carries it,
no installer changes required. When present, the interruption subtitle and
the Claude Screen name the subagent (e.g. "Explore is waiting for you")
instead of an ambiguous "Claude is waiting for you".

The `UserPromptSubmit`/`PreToolUse` markers are written empty by design (see
above) and so never carry `agent_id` — a parallel subagent's ordinary tool
activity can therefore still resolve a pending attention state that was
actually raised by a sibling subagent. Closing this fully would require
teaching those hook commands to emit session/agent identifiers (still no
prompt or tool content) rather than an empty file; not done today.

## Interruptions

| Event | Interruption | Priority | Notch surface |
|---|---|---|---|
| Needs input | "Claude · Needs input — Claude is waiting for you" `[Open Claude]` | important | up to 60 s (resolved immediately if Claude resumes first) |
| Permission required | "Claude · Permission" + system message `[Open Claude]` | important | up to 60 s (resolved immediately if Claude resumes first) |
| Completed | "Claude · Completed — Finished in 3m 12s" | important | no (5 s) |

"Needs input"/"permission required" are bounded, not persistent forever
(`ClaudeCodeProvider.attentionDisplayDuration`): if the user is away, the
notch's attention-grabbing peek surface recedes on its own after 60 s rather
than holding the notch open indefinitely. The Claude Screen (opened
manually) still reflects the real state for as long as it's actually
true — only the unsolicited notch pop-up times out.

Each is individually toggleable. **Open Claude** activates the frontmost
running terminal app (iTerm2, Terminal, Warp, WezTerm, kitty, Ghostty) — the
app cannot know which window hosts Claude, so activating the terminal is the
honest best effort.
