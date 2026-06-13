import Foundation

/// Single source of truth for the Claude Code Keychain service-name format:
/// `"Claude Code-credentials"` (the default profile) or
/// `"Claude Code-credentials-<hash>"` (a `CLAUDE_CONFIG_DIR` profile).
///
/// Centralised here so `KeychainProfileDirectory` and `ConfigAccountResolver`
/// can't drift if Claude Code ever changes the service-name shape.
enum ProfileService {
    static let prefix = "Claude Code-credentials"

    /// The part after the prefix with the separating `-` removed:
    /// `"Claude Code-credentials"` → `""`,
    /// `"Claude Code-credentials-ab12cd34"` → `"ab12cd34"`.
    static func suffix(ofService service: String) -> Substring {
        String(service.dropFirst(prefix.count)).drop { $0 == "-" }
    }
}
