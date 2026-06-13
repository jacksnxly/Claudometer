import Foundation
import CryptoKit

/// Resolves a Keychain credential service name to the account email by reading
/// Claude Code's `.claude.json` config files.
///
/// The Keychain service name encodes which config directory a profile uses:
///
///   "Claude Code-credentials"          → default profile; account lives in
///                                         `~/.claude.json`
///   "Claude Code-credentials-<hash>"   → a `CLAUDE_CONFIG_DIR` profile, where
///                                         `<hash>` is the first 8 hex chars of
///                                         `SHA-256(<absolute config-dir path>)`;
///                                         account lives in `<dir>/.claude.json`
struct ConfigAccountResolver {
    private let servicePrefix = "Claude Code-credentials"
    private let fileManager = FileManager.default

    func email(forService service: String) -> String? {
        let home = fileManager.homeDirectoryForCurrentUser
        let suffix = String(service.dropFirst(servicePrefix.count)).drop { $0 == "-" }

        if suffix.isEmpty {
            return email(atConfigFile: home.appendingPathComponent(".claude.json"))
        }

        for dir in candidateConfigDirs(home: home) where Self.shortHash(of: dir.path) == suffix {
            return email(atConfigFile: dir.appendingPathComponent(".claude.json"))
        }
        return nil
    }

    /// All `~/.claude*` directories — the possible `CLAUDE_CONFIG_DIR` locations.
    private func candidateConfigDirs(home: URL) -> [URL] {
        let names = (try? fileManager.contentsOfDirectory(atPath: home.path)) ?? []
        return names
            .filter { $0.hasPrefix(".claude") }
            .map { home.appendingPathComponent($0) }
            .filter { url in
                var isDirectory: ObjCBool = false
                return fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory)
                    && isDirectory.boolValue
            }
    }

    private func email(atConfigFile url: URL) -> String? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        struct Config: Decodable {
            struct Account: Decodable { let emailAddress: String? }
            let oauthAccount: Account?
        }
        return (try? JSONDecoder().decode(Config.self, from: data))?.oauthAccount?.emailAddress
    }

    /// First 8 hex characters (4 bytes) of the SHA-256 of `path`.
    static func shortHash(of path: String) -> String {
        SHA256.hash(data: Data(path.utf8))
            .prefix(4)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
