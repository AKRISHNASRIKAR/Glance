# Context Engine

Off by default. When enabled, Glance classifies what you're broadly doing —
**locally, from coarse signals only**.

## Signals (current)

| Signal | Mechanism | Cost |
|---|---|---|
| Frontmost application | `NSWorkspace.didActivateApplicationNotification` | event-driven |
| Idle time | `CGEventSource.secondsSinceLastEventType` | one syscall / 30 s |
| Media playing | pushed from NowPlayingProvider via the coordinator | none |
| Pomodoro focus | pushed from PomodoroProvider via the coordinator | none |

Window titles, browser domains, and terminal processes are **not read at
all**. They appear in the settings model as opt-in flags for a future
version; the Settings UI explicitly says they are planned and unused, so no
toggle pretends to do something it doesn't.

## Classification ladder

```
away (idle ≥ 5 min) > focus (pomodoro running) >
coding | meeting | designing | studying | entertainment (bundle-ID tables) >
general
```

`ContextEngine` is a pure struct: signals in → kind out, plus session
tracking (min 60 s to record; `away`/`general` time is never recorded).

## History

`ContextHistoryStore` keeps finished sessions as local JSON
(`~/Library/Application Support/Glance/context-history.json`). Retention:
today / 7 days / 30 days / forever, pruned on every write; one-click
**Clear Activity History**. No cloud sync, no analytics dashboard — the only
consumer is the lightweight "Today" summary on the Coding screen.

## Coding Context (separate provider)

`CodingContextProvider` is deliberately independent of the general context
engine (provider isolation): it watches frontmost activations against the
configured coding apps (VS Code, Xcode, Terminal, iTerm2, Zed, Cursor, …),
and promotes a session after the configured delay (default 5 min).
Project/git-branch detection would require window-title access and is
**Planned**, not implemented — the Screen shows elapsed time and the editor
name. Apps on the Never Track list are ignored everywhere.
