# Security Policy

## Supported versions

The latest tagged release receives security fixes.

## Reporting a vulnerability

Please use GitHub's **private vulnerability reporting** on this repository
(Security tab → "Report a vulnerability") rather than a public issue.
You should receive an initial response within 7 days.

## Scope notes for researchers

Areas of particular interest:

- The Claude Code hook installer (writes to `~/.claude/settings.json`):
  injection into hook commands, path traversal in the spool directory,
  symlink tricks on the backup path.
- Spool-file parsing (`ClaudeCodeEventNormalizer`): malformed/adversarial
  JSON must never crash the app or smuggle content into the UI.
- The Spotify artwork fetch (the only network request): URL validation is
  restricted to HTTPS; anything that widens that is a bug.
- Settings JSON decoding: corrupt files must degrade to defaults, never
  execute or crash.

Out of scope: anything requiring the attacker to already control the user's
`~/.claude/settings.json` or Application Support directory with the user's
own privileges.
