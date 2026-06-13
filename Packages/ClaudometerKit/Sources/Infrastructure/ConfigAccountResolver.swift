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
    /// Email, slot tag, and plan label resolved for a Keychain service.
    struct Account {
        let email: String?
        let tag: String?
        let plan: String?
    }

    private let fileManager = FileManager.default

    /// Build the `shortHash → config-dir` map once, so resolving a batch of
    /// services doesn't re-list `$HOME` and re-hash every candidate dir per call.
    func configDirsByShortHash() -> [String: URL] {
        let home = fileManager.homeDirectoryForCurrentUser
        var map: [String: URL] = [:]
        for dir in candidateConfigDirs(home: home) {
            map[Self.shortHash(of: dir.path)] = dir
        }
        return map
    }

    /// Resolve one service against a precomputed `configDirs` map (see
    /// `configDirsByShortHash()`), reused across the whole refresh.
    func resolve(service: String, configDirs: [String: URL]) -> Account {
        let home = fileManager.homeDirectoryForCurrentUser
        let suffix = ProfileService.suffix(ofService: service)

        if suffix.isEmpty {
            let config = readConfig(at: home.appendingPathComponent(".claude.json"))
            return Account(email: config.email, tag: "claude", plan: Self.planLabel(for: config.tier))
        }

        guard let dir = configDirs[String(suffix)] else {
            return Account(email: nil, tag: nil, plan: nil)
        }
        let config = readConfig(at: dir.appendingPathComponent(".claude.json"))
        return Account(
            email: config.email,
            tag: Self.tag(forConfigDir: dir.lastPathComponent),
            plan: Self.planLabel(for: config.tier)
        )
    }

    /// Map Claude Code's `organizationRateLimitTier` to a friendly plan name,
    /// e.g. "default_claude_max_20x" → "Max 20x". Returns nil for unknown tiers
    /// rather than showing a raw internal string.
    static func planLabel(for tier: String?) -> String? {
        guard let tier else { return nil }
        let value = tier.lowercased()
        switch true {
        case value.contains("max_20x"), value.contains("max20x"): return "Max 20x"
        case value.contains("max_5x"), value.contains("max5x"): return "Max 5x"
        case value.contains("max"): return "Max"
        case value.contains("team"): return "Team"
        case value.contains("enterprise"): return "Enterprise"
        case value.contains("pro"): return "Pro"
        case value.contains("free"): return "Free"
        default: return nil
        }
    }

    /// Derive a "claudeN" slot tag from a config-dir name, e.g.
    /// ".claude-acct2" → "claude2", ".claude" → "claude". Uses only the FIRST
    /// contiguous run of digits, so ".claude-2-beta3" → "claude2" (not "claude23").
    static func tag(forConfigDir dirName: String) -> String {
        let firstRun = dirName.drop { !$0.isNumber }.prefix { $0.isNumber }
        return firstRun.isEmpty ? "claude" : "claude\(firstRun)"
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

    private func readConfig(at url: URL) -> (email: String?, tier: String?) {
        guard let data = try? Data(contentsOf: url) else { return (nil, nil) }
        struct Config: Decodable {
            struct Account: Decodable {
                let emailAddress: String?
                let organizationRateLimitTier: String?
            }
            let oauthAccount: Account?
        }
        let account = (try? JSONDecoder().decode(Config.self, from: data))?.oauthAccount
        return (account?.emailAddress, account?.organizationRateLimitTier)
    }

    /// First 8 hex characters (4 bytes) of the SHA-256 of `path`.
    static func shortHash(of path: String) -> String {
        SHA256.hash(data: Data(path.utf8))
            .prefix(4)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
