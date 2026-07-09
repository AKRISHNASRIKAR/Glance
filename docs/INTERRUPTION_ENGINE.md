# Interruption Engine

Interruptions are temporary, priority-driven notch events generated **only by
Glance's own providers**. Glance does not intercept, scrape, or suppress
macOS notifications, and never will (see the product constraints in the
README).

## Model

```
NotchInterruption {
  id, provider, kind, title, subtitle, symbolName,
  priority (passive | normal | important | urgent),
  createdAt, displayDuration, isPersistent,
  actions [InterruptionAction], privacy (ordinary | sensitive)
}
```

Example priorities in use:

| Event | Priority | Persistent |
|---|---|---|
| Track changed | passive | no |
| Charger connected / network restored | normal | no |
| Pomodoro complete / Claude completed | important | no |
| Claude needs input / permission | important | **yes** |
| Battery critical | urgent | no |

## Rules (each covered by a unit test)

- **Debounce** — same `provider/kind` within 8 s of last display is dropped.
  Passive events cannot repeatedly steal the surface.
- **Preemption** — strictly higher priority replaces the current
  interruption immediately. A preempted *persistent* interruption returns to
  the queue; a preempted transient one is dropped.
- **Minimum display** — equal or lower priority arrivals queue; they never
  cut the current interruption short.
- **Expiry** — transient interruptions end after `displayDuration`; queued
  transient interruptions older than 30 s are skipped when dequeued.
- **Persistence** — persistent interruptions stay until the user dismisses
  them or the provider resolves them (`resolve(provider:kind:)`), e.g. Claude
  resuming work resolves "needs input".
- **Return to previous screen** — the engine publishes `current`; the UI
  overlays it and reveals the unchanged screen selection when it ends. The
  engine has no access to screen selection at all.
- **Provider teardown** — stopping a provider removes all of its queued and
  displayed interruptions.

## Presentation

- Peek state: compact wings beside the notch (icon + title, subtitle on the
  trailing side), color-coded by priority.
- If the user expands during an interruption: full detail view with actions
  (e.g. **Open Claude**) and Dismiss.
