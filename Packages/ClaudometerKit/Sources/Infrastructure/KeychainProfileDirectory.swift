import Foundation
import Domain

/// `ProfileDirectory` adapter that discovers Claude Code profiles by scanning the
/// login Keychain for generic-password items named `Claude Code-credentials`
/// (the default profile) or `Claude Code-credentials-<hash>` (extra
/// `CLAUDE_CONFIG_DIR` profiles).
public struct KeychainProfileDirectory: ProfileDirectory {
    private let servicePrefix = "Claude Code-credentials"
    private let accounts = ConfigAccountResolver()

    public init() {}

    public func profiles() async throws -> [Profile] {
        guard let dump = SecurityCLI.run(["dump-keychain"]) else { return [] }

        var services = Set<String>()
        for line in dump.split(separator: "\n") {
            guard line.contains("\"svce\"<blob>="),
                  line.contains(servicePrefix),
                  let marker = line.range(of: "=\"") else { continue }
            let name = String(line[marker.upperBound...].dropLast()) // strip trailing quote
            if name.hasPrefix(servicePrefix) { services.insert(name) }
        }

        return services
            .map { service in
                let suffix = String(service.dropFirst(servicePrefix.count)).drop { $0 == "-" }
                return Profile(
                    id: ProfileID(service),
                    name: suffix.isEmpty ? "default" : String(suffix),
                    email: accounts.email(forService: service)
                )
            }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }
}
