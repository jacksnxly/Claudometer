import Foundation
import Domain

/// `UsageProvider` adapter that calls Anthropic's **unofficial** OAuth usage
/// endpoint and maps the wire response into the domain's `UsageSnapshot`.
///
/// ⚠️ `GET /api/oauth/usage` is undocumented and aggressively rate-limited with
/// no `Retry-After`. Refresh on demand only — never poll tightly.
public struct AnthropicUsageProvider: UsageProvider {
    private let tokenStore = KeychainTokenStore()
    private let session: URLSession
    private let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    /// Sent so requests land in the normal (not the punitive) rate-limit bucket.
    private let userAgent = "claude-code/2.1.0 (Claudometer)"

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func usage(for profile: Profile) async throws -> UsageSnapshot {
        let token = try tokenStore.accessToken(for: profile.id)

        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw InfrastructureError.badResponse }
        switch http.statusCode {
        case 200: break
        case 429: throw InfrastructureError.rateLimited
        default: throw InfrastructureError.http(http.statusCode)
        }

        return try JSONDecoder().decode(UsageDTO.self, from: data).toDomain(profile: profile)
    }
}

// MARK: - Wire format (private to infrastructure)

private struct UsageDTO: Decodable {
    let fiveHour: WindowDTO?
    let sevenDay: WindowDTO?
    let sevenDayOpus: WindowDTO?
    let sevenDaySonnet: WindowDTO?

    enum CodingKeys: String, CodingKey {
        case fiveHour = "five_hour"
        case sevenDay = "seven_day"
        case sevenDayOpus = "seven_day_opus"
        case sevenDaySonnet = "seven_day_sonnet"
    }

    func toDomain(profile: Profile) -> UsageSnapshot {
        let mapping: [(UsagePeriod, WindowDTO?)] = [
            (.fiveHour, fiveHour),
            (.sevenDay, sevenDay),
            (.sevenDayOpus, sevenDayOpus),
            (.sevenDaySonnet, sevenDaySonnet),
        ]
        let windows = mapping.compactMap { period, dto -> UsageWindow? in
            guard let dto else { return nil }
            return UsageWindow(
                period: period,
                utilization: Utilization(dto.utilization),
                resetsAt: dto.resetDate
            )
        }
        return UsageSnapshot(profile: profile, windows: windows)
    }
}

private struct WindowDTO: Decodable {
    let utilization: Double
    let resetsAt: String?

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }

    /// `resets_at` arrives as ISO-8601 with fractional seconds and an offset,
    /// e.g. `2026-04-11T07:00:00.528743+00:00`. `ISO8601DateFormatter` only
    /// accepts up to millisecond precision, so fall back to stripping the
    /// sub-second component before parsing.
    var resetDate: Date? {
        guard let resetsAt else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: resetsAt) { return date }

        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: Self.removingFractionalSeconds(from: resetsAt))
    }

    /// Strip a `.123456` sub-second component, e.g.
    /// `…:00.528743+00:00` → `…:00+00:00`.
    static func removingFractionalSeconds(from value: String) -> String {
        guard let dot = value.firstIndex(of: ".") else { return value }
        let afterDot = value.index(after: dot)
        guard let offset = value[afterDot...].firstIndex(where: { $0 == "+" || $0 == "-" || $0 == "Z" })
        else { return value }
        var copy = value
        copy.removeSubrange(dot..<offset)
        return copy
    }
}
