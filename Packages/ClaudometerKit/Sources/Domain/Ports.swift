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
