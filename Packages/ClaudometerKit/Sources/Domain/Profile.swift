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

    public init(id: ProfileID, name: String, email: String? = nil) {
        self.id = id
        self.name = name
        self.email = email
    }

    /// What to show the user: the email if known, otherwise the technical name.
    public var displayName: String { email ?? name }
}
