import Foundation

/// Reads Claude Code OAuth tokens from the macOS Keychain.
///
/// On macOS, Claude Code stores each profile's OAuth credentials as a
/// generic-password item whose service name starts with
/// `"Claude Code-credentials"`. The default profile uses that exact name;
/// additional `CLAUDE_CONFIG_DIR` profiles get a `-<hash>` suffix derived
/// from the config-dir path. The stored blob is JSON:
///
/// ```json
/// { "claudeAiOauth": { "accessToken": "sk-ant-oat01-…", … } }
/// ```
enum Credentials {
    private static let servicePrefix = "Claude Code-credentials"

    /// Discover every profile by scanning the login keychain for matching items.
    static func discoverProfiles() -> [Profile] {
        guard let output = runSecurity(["dump-keychain"]) else { return [] }
        var services = Set<String>()
        for line in output.split(separator: "\n") {
            guard line.contains("\"svce\"<blob>="), line.contains(servicePrefix),
                  let eq = line.range(of: "=\"") else { continue }
            let name = String(line[eq.upperBound...].dropLast()) // strip trailing quote
            if name.hasPrefix(servicePrefix) { services.insert(name) }
        }
        return services.sorted().map { svc in
            let suffix = String(svc.dropFirst(servicePrefix.count)).drop(while: { $0 == "-" })
            return Profile(id: svc, displayName: suffix.isEmpty ? "default" : String(suffix))
        }
    }

    /// Read and decode the OAuth access token for a given Keychain service.
    static func accessToken(service: String) -> String? {
        guard let blob = runSecurity(["find-generic-password", "-s", service, "-w"]) else { return nil }
        let trimmed = blob.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let data = trimmed.data(using: .utf8) else { return nil }

        struct Store: Decodable {
            struct OAuth: Decodable { let accessToken: String }
            let claudeAiOauth: OAuth
        }
        return try? JSONDecoder().decode(Store.self, from: data).claudeAiOauth.accessToken
    }

    /// Run `/usr/bin/security` and capture stdout.
    private static func runSecurity(_ args: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = args
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()
        do { try process.run() } catch { return nil }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }
}
