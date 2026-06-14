# Claudometer 🎛️

A tiny macOS menu-bar app that shows your **Claude usage** across **multiple
Claude Code profiles** at a glance — 5-hour and 7-day quota meters per account.

Built for people running several Claude (Pro/Max) logins side-by-side via
separate `CLAUDE_CONFIG_DIR`s and tired of guessing which one still has headroom.

> **Status: v0.1 — builds & runs.** Discovers profiles from the macOS Keychain,
> fetches usage from Anthropic's OAuth usage endpoint, and renders one meter
> block per profile in the menu bar.

## Architecture — strict DDD

The code follows a textbook Domain-Driven Design / hexagonal layering, with the
boundaries **enforced by the Swift module graph** (a layer that imports "upward"
simply won't compile). The four layers live as targets in one local Swift
package, `Packages/ClaudometerKit`; the Xcode app target is the composition root.

```
┌─────────────────────────────────────────────────────────────┐
│ App  (Claudometer.xcodeproj)  — COMPOSITION ROOT             │
│   ClaudometerApp.swift: wires adapters → use case → view     │
│   …the only place allowed to import Infrastructure           │
└───────────────┬──────────────────────────────┬──────────────┘
                │                               │
        ┌───────▼────────┐            ┌─────────▼─────────┐
        │ Presentation   │            │ Infrastructure    │
        │ MenuView       │            │ KeychainProfile…  │
        │ MenuBarViewModel│           │ AnthropicUsage…   │
        └───────┬────────┘            └─────────┬─────────┘
                │                                │
        ┌───────▼────────┐                       │
        │ Application    │                       │
        │ RefreshUsage…  │                       │
        └───────┬────────┘                       │
                │                                │
        ┌───────▼────────────────────────────────▼─────────┐
        │ Domain  (pure: entities, value objects, PORTS)    │
        │ Profile · Usage* · ProfileDirectory · UsageProvider│
        └───────────────────────────────────────────────────┘
```

| Layer | Depends on | Responsibility |
|---|---|---|
| **Domain** | nothing | `Profile`, `Utilization`, `UsageWindow`, `UsageSnapshot`; the spend model `TokenUsage` · `Money` · `PricingPolicy` · `CostReport` (+ `CostReportBuilder`); and the outbound ports `ProfileDirectory` / `UsageProvider` / `UsageLedger`. No Keychain, no HTTP, no SwiftUI. |
| **Application** | Domain | `RefreshUsageUseCase` (per-profile quota %) and `RefreshCostUseCase` (per-profile token spend), each capturing per-profile failures. |
| **Infrastructure** | Domain | `KeychainProfileDirectory` + `AnthropicUsageProvider` (auto-refreshing the OAuth token via `OAuthTokenProvider`) + `TranscriptUsageLedger` implement the domain ports. The `security` CLI, the HTTP endpoints, and the transcript parser live here, behind the ports. |
| **Presentation** | Domain, Application | `MenuBarViewModel` (`@Observable`) + SwiftUI `MenuView` — a two-pane dashboard (**Usage**: per-account quota meters · **Spend**: a cross-account total + per-account estimated value) with a privacy (email-blur) toggle. Knows nothing about Keychain or HTTP. |
| **App** | all of the above | Composition root: builds the concrete adapters and injects them. |

```
Claudometer/
├── Claudometer/                      # Xcode project (app target = composition root)
│   ├── Claudometer.xcodeproj
│   └── Claudometer/ClaudometerApp.swift
└── Packages/
    └── ClaudometerKit/
        └── Sources/
            ├── Domain/
            ├── Application/
            ├── Infrastructure/
            └── Presentation/
```

## How it works

- **Profile discovery** — scans the login Keychain for generic-password items
  named `Claude Code-credentials[-<hash>]`. The default profile uses the bare
  name; extra `CLAUDE_CONFIG_DIR` profiles get a path-derived `-<hash>` suffix.
- **Token** — reads `claudeAiOauth.accessToken` from each Keychain item.
- **Usage** — `GET https://api.anthropic.com/api/oauth/usage` with headers
  `Authorization: Bearer <token>`, `anthropic-beta: oauth-2025-04-20`,
  `User-Agent: claude-code/<version>`.
- **Response** — `five_hour` / `seven_day` (plus `_opus` / `_sonnet`) objects,
  each with `utilization` (0–100%) and `resets_at`.
- **Stale-token recovery** — the OAuth access token expires when Claude Code
  hasn't run recently, which makes the usage endpoint return `401`. Claudometer
  does what Claude Code does: exchanges the stored `refreshToken` at
  `https://console.anthropic.com/v1/oauth/token` (proactively before `expiresAt`,
  and reactively on a `401`), caching the new token in memory.
- **Estimated spend** — the usage endpoint only returns percentages, and the
  token-count Admin/Analytics APIs reject subscription tokens (`403`). So exact
  token counts come from parsing Claude Code's own session transcripts
  (`<CLAUDE_CONFIG_DIR>/projects/**/*.jsonl`, deduped by `message.id`+`requestId`),
  priced per-model with `PricingPolicy` into a 7/14/30-day **equivalent API value**.
  This is a value/ROI estimate (it dominated by cached-context reads), **not** what
  a flat Pro/Max subscription is billed. Fully local — no network, no rate limit.
- **Privacy mode** — an eye toggle blurs account emails so the spend stats can be
  screenshotted for sharing without leaking identity.

### ⚠️ The usage endpoint is unofficial & rate-limited

`/api/oauth/usage` is **undocumented**, used internally by Claude Code, and can
change without notice. It is **aggressively rate-limited** with **no
`Retry-After`** — tight polling earns persistent `429`s that stick for 30+ min.
Claudometer refreshes **on demand only**. Don't hammer it.

### Note on the App Sandbox

The app ships with **App Sandbox disabled** (`ENABLE_APP_SANDBOX = NO`). It must
spawn `/usr/bin/security` to read the Keychain and reach the network — neither is
possible inside the sandbox. On first run macOS will prompt to allow Keychain
access per profile; click **Always Allow**.

## Build & run

Requires macOS 14+ and Xcode 16+.

```bash
# Open in Xcode and Run (⌘R) — a gauge icon appears in the menu bar:
open Claudometer/Claudometer.xcodeproj

# …or build the layered package on its own:
cd Packages/ClaudometerKit && swift build
```

## Roadmap

- [x] Map Keychain hash → friendly `CLAUDE_CONFIG_DIR` name (account email + plan)
- [x] Reset countdowns from `resets_at`
- [x] Exact token usage + estimated $ per account from local transcripts (7/14/30-day)
- [x] OAuth access-token auto-refresh (fixes the stale-session `401`)
- [x] Privacy mode — blur emails for sharing stats
- [ ] On-disk cache of the transcript parse (avoid re-scanning every refresh)
- [ ] Read `rate_limits` off Claude Code statusline stdin for the active profile (no network)
- [ ] Opus / Sonnet sub-meters; cost trend sparkline
- [ ] Launch-at-login; unit tests for the use case (Domain is pure → trivial to test)

## License

[MIT](LICENSE)
