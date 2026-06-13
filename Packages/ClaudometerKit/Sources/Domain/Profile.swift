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
    public let name: String

    public init(id: ProfileID, name: String) {
        self.id = id
        self.name = name
    }
}
