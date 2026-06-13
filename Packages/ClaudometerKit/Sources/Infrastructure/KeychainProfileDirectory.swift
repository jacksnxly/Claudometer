import Foundation
import Domain

/// `ProfileDirectory` adapter that discovers Claude Code profiles by scanning the
/// login Keychain for generic-password items named `Claude Code-credentials`
/// (the default profile) or `Claude Code-credentials-<hash>` (extra
/// `CLAUDE_CONFIG_DIR` profiles).
public struct KeychainProfileDirectory: ProfileDirectory {
    private let accounts = ConfigAccountResolver()

    public init() {}

    public func profiles() async throws -> [Profile] {
        guard let dump = SecurityCLI.run(["dump-keychain"]) else { return [] }

        var services = Set<String>()
        for line in dump.split(separator: "\n") {
            guard line.contains("\"svce\"<blob>="),
                  line.contains(ProfileService.prefix),
                  let marker = line.range(of: "=\"") else { continue }
            let name = String(line[marker.upperBound...].dropLast()) // strip trailing quote
            if name.hasPrefix(ProfileService.prefix) { services.insert(name) }
        }

        return services
            .map { service in
                let suffix = ProfileService.suffix(ofService: service)
                let account = accounts.resolve(service: service)
                return Profile(
                    id: ProfileID(service),
                    name: suffix.isEmpty ? "default" : String(suffix),
                    email: account.email,
                    tag: account.tag,
                    plan: account.plan
                )
            }
            .sorted { ($0.tag ?? "~", $0.displayName) < ($1.tag ?? "~", $1.displayName) }
    }
}
