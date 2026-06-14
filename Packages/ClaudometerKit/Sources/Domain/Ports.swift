import Foundation

/// Outbound port: discovers the Claude Code profiles available locally.
///
/// Implemented by the infrastructure layer (e.g. a Keychain adapter). The domain
/// and application layers depend only on this protocol, never on the adapter.
public protocol ProfileDirectory: Sendable {
    func profiles() async throws -> [Profile]
}

/// Outbound port: fetches the usage snapshot for a given profile.
public protocol UsageProvider: Sendable {
    func usage(for profile: Profile) async throws -> UsageSnapshot
}

/// Outbound port: reads exact historical token usage for a profile, bucketed
/// into trailing windows. Implemented by an adapter that parses Claude Code's
/// local session transcripts — the only source of exact per-account token counts
/// available to a Pro/Max subscription (the OAuth usage endpoint exposes only
/// percentages, and the token-count Admin APIs reject subscription tokens).
public protocol UsageLedger: Sendable {
    func entries(for profile: Profile, now: Date) async throws -> [LedgerEntry]
}
