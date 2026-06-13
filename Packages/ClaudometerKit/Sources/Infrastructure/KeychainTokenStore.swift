import Foundation
import Domain

/// Reads the OAuth access token for a profile from its Keychain credential blob:
/// `{ "claudeAiOauth": { "accessToken": "sk-ant-oat01-…", … } }`.
struct KeychainTokenStore {
    func accessToken(for id: ProfileID) throws -> String {
        guard let blob = SecurityCLI.run(["find-generic-password", "-s", id.rawValue, "-w"]) else {
            throw InfrastructureError.tokenUnavailable
        }
        let trimmed = blob.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8),
              let stored = try? JSONDecoder().decode(Stored.self, from: data) else {
            throw InfrastructureError.tokenUnavailable
        }
        return stored.claudeAiOauth.accessToken
    }

    private struct Stored: Decodable {
        struct OAuth: Decodable { let accessToken: String }
        let claudeAiOauth: OAuth
    }
}
