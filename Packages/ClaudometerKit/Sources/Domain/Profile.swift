import Foundation

/// Value object: the opaque identity of a Claude Code profile.
///
/// Internally this happens to be the macOS Keychain service name, but the domain
/// treats it as an opaque token and never interprets its contents.
public struct ProfileID: Hashable, Sendable {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }
}

/// Entity: a single Claude Code login / profile.
public struct Profile: Identifiable, Hashable, Sendable {
    public let id: ProfileID
    /// Technical fallback label (e.g. "default" or the Keychain hash suffix).
    public let name: String
    /// The account's email address, when it can be resolved from local config.
    public let email: String?
    /// Short, stable handle for the profile slot (e.g. "claude1"), derived from
    /// the `CLAUDE_CONFIG_DIR`.
    public let tag: String?
    /// Friendly subscription plan label (e.g. "Max 20x"), when resolvable.
    public let plan: String?

    public init(
        id: ProfileID,
        name: String,
        email: String? = nil,
        tag: String? = nil,
        plan: String? = nil
    ) {
        self.id = id
        self.name = name
        self.email = email
        self.tag = tag
        self.plan = plan
    }

    /// What to show the user: the email if known, otherwise the technical name.
    public var displayName: String { email ?? name }
}
