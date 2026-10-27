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
- The Spotify artwork fetch: URL validation is
  restricted to HTTPS; anything that widens that is a bug.
- Settings JSON decoding: corrupt files must degrade to defaults, never
  execute or crash.

Out of scope: anything requiring the attacker to already control the user's
`~/.claude/settings.json` or Application Support directory with the user's
own privileges.

## Browser companion boundary

The Chrome extension and Native Messaging helper are developer-preview components. Reports concerning origin/extension-ID validation, pairing-token handling, filesystem permissions, IPC framing, stale command replay, website-rule matching or permission bypass are in scope. The hosted dashboard must require explicit extension authorization, restrict its exact origin/path and forward only allowed commands. Never attach real activity exports, tokens, browser profiles or local Browser JSON files to an issue.

The marketing website requests static assets and fonts; it must not upload focus or browsing activity. Public metadata and labelled demo captures contain no real browsing history. A passing repository pattern scan is a limited hygiene check, not a security certification.
