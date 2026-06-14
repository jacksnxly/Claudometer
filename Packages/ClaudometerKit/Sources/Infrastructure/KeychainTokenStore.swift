import Foundation
import Domain

/// Reads the OAuth credential for a profile from its Keychain blob:
/// `{ "claudeAiOauth": { "accessToken": "sk-ant-oat01-…", "refreshToken": …,
///   "expiresAt": <epoch-ms>, … } }`.
struct KeychainTokenStore {
    /// The parsed OAuth credential. `refreshToken` / `expiresAt` are optional
    /// because older credential blobs may omit them.
    struct Credential: Equatable, Sendable {
        let accessToken: String
        let refreshToken: String?
        let expiresAt: Date?
    }

    func accessToken(for id: ProfileID) throws -> String {
        try credential(for: id).accessToken
    }

    func credential(for id: ProfileID) throws -> Credential {
        guard let blob = SecurityCLI.run(["find-generic-password", "-s", id.rawValue, "-w"]) else {
            throw InfrastructureError.tokenUnavailable
        }
        return try Self.credential(fromBlob: blob)
    }

    /// Parse the credential blob in isolation (testable without the Keychain). A
    /// present-but-unparseable blob throws `.badCredentialFormat` — distinct from
    /// `.tokenUnavailable` (no item) so the surfaced error is actionable.
    static func credential(fromBlob blob: String) throws -> Credential {
        let trimmed = blob.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8),
              let stored = try? JSONDecoder().decode(Stored.self, from: data) else {
            throw InfrastructureError.badCredentialFormat
        }
        let oauth = stored.claudeAiOauth
        return Credential(
            accessToken: oauth.accessToken,
            refreshToken: oauth.refreshToken,
            expiresAt: Self.date(fromEpoch: oauth.expiresAt)
        )
    }

    static func accessToken(fromBlob blob: String) throws -> String {
        try credential(fromBlob: blob).accessToken
    }

    /// Claude Code stores `expiresAt` in epoch **milliseconds**; tolerate seconds
    /// too. Values below ~1e11 are treated as seconds.
    private static func date(fromEpoch value: Double?) -> Date? {
        guard let value, value > 0 else { return nil }
        let seconds = value >= 100_000_000_000 ? value / 1000 : value
        return Date(timeIntervalSince1970: seconds)
    }

    private struct Stored: Decodable {
        struct OAuth: Decodable {
            let accessToken: String
            let refreshToken: String?
            let expiresAt: Double?
        }
        let claudeAiOauth: OAuth
    }
}
