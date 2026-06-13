# Claudometer 🎛️

A tiny macOS menu-bar app that shows your **Claude usage** across **multiple
Claude Code profiles** at a glance — 5-hour and 7-day quota meters per account.

Built for people running several Claude (Pro/Max) logins side-by-side via
separate `CLAUDE_CONFIG_DIR`s and tired of guessing which one still has headroom.

> ⚠️ **Status: early v0.** Discovers profiles from the macOS Keychain and fetches
> usage from Anthropic's OAuth usage endpoint. Functional skeleton, not polished.

## How it works

- **Profile discovery** — scans the login Keychain for generic-password items
  named `Claude Code-credentials[-<hash>]`. The default profile uses the bare
  name; extra `CLAUDE_CONFIG_DIR` profiles get a path-derived `-<hash>` suffix.
- **Token** — reads `claudeAiOauth.accessToken` from each Keychain item.
- **Usage** — `GET https://api.anthropic.com/api/oauth/usage` with headers:
  - `Authorization: Bearer <token>`
  - `anthropic-beta: oauth-2025-04-20`
  - `User-Agent: claude-code/<version>`
- **Response** — `five_hour` / `seven_day` (plus `_opus` / `_sonnet`) objects,
  each with `utilization` (0–100%) and `resets_at`.

### ⚠️ This endpoint is unofficial

`/api/oauth/usage` is **undocumented** and used internally by Claude Code. It can
change or disappear without notice, and it is **aggressively rate-limited** with
**no `Retry-After`** header — tight polling earns persistent `429`s that can stick
for 30+ minutes. Claudometer therefore refreshes **on demand only** (no background
polling yet). Don't hammer it. Tracking issues:
[#44328](https://github.com/anthropics/claude-code/issues/44328),
[#32796](https://github.com/anthropics/claude-code/issues/32796) request an
official equivalent.

## Build & run

Requires macOS 14+ and a Swift 6 toolchain (Xcode 16+).

```bash
swift run
```

A gauge icon appears in your menu bar; click it for per-profile meters and a
manual refresh button.

## Roadmap

- [ ] On-disk cache (`~/.claude/usage-exact.json` style) with a 5-min TTL + file lock
- [ ] Read `rate_limits` off Claude Code statusline stdin for the active profile (no network)
- [ ] Friendly profile names (map Keychain hash → `CLAUDE_CONFIG_DIR`)
- [ ] Reset countdowns from `resets_at`
- [ ] Opus / Sonnet sub-meters
- [ ] Launch-at-login, packaged `.app`

## License

[MIT](LICENSE)
