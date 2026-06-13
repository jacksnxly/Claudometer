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
| **Domain** | nothing | `Profile`, `Utilization`, `UsageWindow`, `UsageSnapshot`, and the outbound ports `ProfileDirectory` / `UsageProvider`. No Keychain, no HTTP, no SwiftUI. |
| **Application** | Domain | `RefreshUsageUseCase` — orchestrates "for each profile, fetch usage", capturing per-profile failures. |
| **Infrastructure** | Domain | `KeychainProfileDirectory` + `AnthropicUsageProvider` implement the domain ports (the `security` CLI and the HTTP endpoint live here, behind the ports). |
| **Presentation** | Domain, Application | `MenuBarViewModel` (`@Observable`) + SwiftUI `MenuView`. Knows nothing about Keychain or HTTP. |
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

- [ ] On-disk cache with a 5-min TTL + file lock (shared across launches)
- [ ] Read `rate_limits` off Claude Code statusline stdin for the active profile (no network)
- [ ] Map Keychain hash → friendly `CLAUDE_CONFIG_DIR` name
- [ ] Reset countdowns from `resets_at`; Opus / Sonnet sub-meters
- [ ] Launch-at-login; unit tests for the use case (Domain is pure → trivial to test)

## License

[MIT](LICENSE)
