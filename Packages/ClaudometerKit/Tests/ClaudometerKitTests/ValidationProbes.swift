import Testing
import Foundation
import Domain
import Application
@testable import Presentation
@testable import Infrastructure

// Keryx Stage-2 validation probes for the main-branch review (c72a69b).
// Tests assert the DESIRED behavior, so a RED run here is the runtime proof that
// the reviewed defect reproduces. They double as the Stage-3 RED→GREEN regression set.
// Findings flagged "observe_" assert the CURRENT behavior to document it at runtime.

// MARK: - Test doubles (real Application/Presentation code, controlled adapters)

private struct FakeDirectory: ProfileDirectory {
    let result: [Profile]
    func profiles() async throws -> [Profile] { result }
}

/// Sleeps long enough that we can cancel mid-flight; the sleep throws on cancel.
private struct SlowProvider: UsageProvider {
    func usage(for profile: Profile) async throws -> UsageSnapshot {
        try await Task.sleep(for: .seconds(5))
        return UsageSnapshot(profile: profile, windows: [])
    }
}

/// No-op ledger for view-model tests that don't exercise cost.
private struct EmptyLedger: UsageLedger {
    func entries(for profile: Profile, now: Date) async throws -> [LedgerEntry] { [] }
}

// MARK: - Finding 1 — .task cancellation must not commit failure rows

@MainActor
@Test func finding1_cancelledRefresh_doesNotCommitResults() async {
    let vm = MenuBarViewModel(
        refreshUsage: RefreshUsageUseCase(
            directory: FakeDirectory(result: [Profile(id: ProfileID("svc-a"), name: "a")]),
            provider: SlowProvider()
        ),
        refreshCost: RefreshCostUseCase(ledger: EmptyLedger())
    )
    let task = Task { await vm.refresh() }
    try? await Task.sleep(for: .milliseconds(100)) // let it enter the in-flight network call
    task.cancel()                                  // user closes the popover → .task cancelled
    await task.value

    // Desired: a cancelled refresh leaves results empty so the next open auto-refreshes.
    // Current (buggy): execute() catches the per-profile CancellationError as a failure and
    // refresh() commits it, so results is non-empty and auto-refresh is suppressed.
    #expect(vm.results.isEmpty)
}

// MARK: - Finding 3 — tag(forConfigDir:) must use only the first digit run

@Test func finding3_tag_multiDigitGroups_collapse() {
    // Documented cases still work.
    #expect(ConfigAccountResolver.tag(forConfigDir: ".claude-acct2") == "claude2")
    #expect(ConfigAccountResolver.tag(forConfigDir: ".claude") == "claude")
    #expect(ConfigAccountResolver.tag(forConfigDir: ".claude-10") == "claude10")
    // First contiguous digit run only.
    // Current (buggy): filter(\.isNumber) concatenates ALL digits → "claude23".
    #expect(ConfigAccountResolver.tag(forConfigDir: ".claude-2-beta3") == "claude2")
}

// MARK: - Finding 2 — countdown must not render "in 0m" for sub-minute resets
// Exercises the real ResetCountdown.text (extracted from WindowMeter) via @testable.

@Test func finding2_countdown_subMinute_isNotZeroMinutes() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    func cd(_ seconds: Int) -> String { ResetCountdown.text(to: now.addingTimeInterval(Double(seconds)), from: now) }
    #expect(cd(3600) == "in 1h")  // sanity: existing cases unchanged
    #expect(cd(90) == "in 1m")    // sanity
    #expect(cd(0) == "now")       // elapsed
    // Current (buggy): 45s → "in 0m". Fixed: a sub-minute reset reads "<1m".
    #expect(cd(45) == "<1m")
    #expect(cd(45) != "in 0m")
}

// MARK: - Finding 5 — malformed credential blob must not masquerade as "no token"

@Test func finding5_malformedBlob_isDistinctFromMissing() throws {
    // Present-but-unparseable blob → a distinct, actionable error (not tokenUnavailable).
    #expect(throws: InfrastructureError.badCredentialFormat) {
        _ = try KeychainTokenStore.accessToken(fromBlob: #"{"not":"the expected shape"}"#)
    }
    #expect(throws: InfrastructureError.badCredentialFormat) {
        _ = try KeychainTokenStore.accessToken(fromBlob: "not json at all")
    }
    // Happy path still returns the token.
    let valid = #"{"claudeAiOauth":{"accessToken":"sk-ant-oat01-xyz"}}"#
    #expect(try KeychainTokenStore.accessToken(fromBlob: valid) == "sk-ant-oat01-xyz")
}

// MARK: - Finding 8 — one shared source of truth for the service-name format

@Test func finding8_profileServiceSuffix() {
    #expect(ProfileService.prefix == "Claude Code-credentials")
    #expect(String(ProfileService.suffix(ofService: "Claude Code-credentials")) == "")
    #expect(String(ProfileService.suffix(ofService: "Claude Code-credentials-ab12cd34")) == "ab12cd34")
}

// MARK: - Finding 7 — resolve against a precomputed config-dir map (behavior preserved)

@Test func finding7_resolveUsesPrecomputedConfigDirs() throws {
    let resolver = ConfigAccountResolver()
    let fm = FileManager.default
    let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("keryx-claude-\(ProcessInfo.processInfo.globallyUniqueString)")
    try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: tmp) }
    let json = #"{"oauthAccount":{"emailAddress":"probe@example.com","organizationRateLimitTier":"default_claude_max_20x"}}"#
    try json.write(to: tmp.appendingPathComponent(".claude.json"), atomically: true, encoding: .utf8)

    // Hashed-profile path: looks up the dir in the precomputed map and reads its config.
    let account = resolver.resolve(service: "Claude Code-credentials-deadbeef", configDirs: ["deadbeef": tmp])
    #expect(account.email == "probe@example.com")
    #expect(account.plan == "Max 20x")
    // Unknown hash → empty account, no crash.
    #expect(resolver.resolve(service: "Claude Code-credentials-unknown0", configDirs: ["deadbeef": tmp]).email == nil)
}

// MARK: - Finding 4 — meter label truncates instead of rounding (documents the fact)

@Test func observe_finding4_intTruncationVsRounding() {
    #expect(Int(99.9) == 99)            // current meter label: Text("\(Int(percentage))%")
    #expect(Int(99.9.rounded()) == 100) // recommendation text uses .rounded(); inconsistent
}

// MARK: - Finding 10 — ranking treats a data-less snapshot as an available #1 (observe)

@Test func observe_finding10_datalessSnapshotOutranksCoolingAccount() {
    let policy = AccountRankingPolicy()
    let now = Date(timeIntervalSince1970: 1_000_000)

    // A snapshot with no windows (e.g. a keyless 200 body decoded to empty).
    let dataless = UsageSnapshot(profile: Profile(id: ProfileID("empty"), name: "empty"), windows: [])
    // A real account whose 5-hour window is exhausted but has weekly capacity left.
    let cooling = UsageSnapshot(
        profile: Profile(id: ProfileID("cooling"), name: "cooling"),
        windows: [
            UsageWindow(period: .fiveHour, utilization: Utilization(100), resetsAt: now.addingTimeInterval(3600)),
            UsageWindow(period: .sevenDay, utilization: Utilization(20), resetsAt: now.addingTimeInterval(86_400)),
        ]
    )

    let pe = policy.priority(for: dataless, now: now)
    let pc = policy.priority(for: cooling, now: now)

    // Missing five_hour window defaults utilization to 0 → treated as available.
    #expect(pe.availableNow == true)
    #expect(pc.availableNow == false)
    // Consequence: the data-less account outranks the genuinely-cooling real one.
    #expect(policy.isHigherPriority(pe, than: pc) == true)
}
