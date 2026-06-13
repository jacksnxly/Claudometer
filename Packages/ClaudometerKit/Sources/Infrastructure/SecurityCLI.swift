import Foundation

/// Thin wrapper over `/usr/bin/security` for reading the login Keychain.
///
/// NOTE: spawning this process requires the app **not** be sandboxed.
enum SecurityCLI {
    static func run(_ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = arguments
        let stdout = Pipe()
        process.standardOutput = stdout
        // Discard stderr via the null device rather than an unread Pipe(): an
        // undrained pipe can deadlock if the child ever fills its ~64 KB buffer
        // while we block reading stdout. FileHandle.nullDevice has no such buffer.
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }
}
