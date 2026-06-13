import Foundation

/// One usage window returned by the Anthropic OAuth usage endpoint.
/// `utilization` is a percentage (0–100). `resetsAt` is an ISO-8601 string.
struct UsageWindow: Codable, Hashable {
    let utilization: Double
    let resetsAt: String?

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }
}

/// Shape of `GET https://api.anthropic.com/api/oauth/usage`.
/// NOTE: this is an **undocumented, unofficial** endpoint used by Claude Code
/// itself. Fields may change without notice. See README for details.
struct UsageResponse: Codable, Hashable {
    let fiveHour: UsageWindow?
    let sevenDay: UsageWindow?
    let sevenDayOpus: UsageWindow?
    let sevenDaySonnet: UsageWindow?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDayOpus = "seven_day_opus"
        case sevenDaySonnet = "seven_day_sonnet"
    }
}

/// A discovered Claude Code profile (one Keychain credential entry).
struct Profile: Identifiable, Hashable {
    let id: String          // Keychain service name, e.g. "Claude Code-credentials-eaa58386"
    let displayName: String // "default", "eaa58386", …
}

/// The usage result for a single profile after a refresh.
struct ProfileUsage: Identifiable {
    var id: String { profile.id }
    let profile: Profile
    let usage: UsageResponse?
    let error: String?
}
