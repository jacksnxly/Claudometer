import Foundation
import Observation

enum UsageError: LocalizedError {
    case rateLimited
    case http(Int)
    case badResponse

    var errorDescription: String? {
        switch self {
        case .rateLimited: return "rate limited (429)"
        case .http(let code): return "HTTP \(code)"
        case .badResponse: return "bad response"
        }
    }
}

/// Fetches usage for every discovered profile.
///
/// ⚠️ The `/api/oauth/usage` endpoint is aggressively rate-limited and has **no**
/// `Retry-After`. Do NOT poll it tightly — refresh on demand or on a generous
/// interval (≥5 min). See README.
@MainActor
@Observable
final class UsageClient {
    var rows: [ProfileUsage] = []
    var lastUpdated: Date?
    var isLoading = false

    /// Sent so requests land in the normal (not the punitive) rate-limit bucket.
    /// Community tools report the endpoint requires a `claude-code/<version>`
    /// User-Agent; without it you get persistent 429s.
    private let userAgent = "claude-code/2.1.0 (Claudometer)"

    func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        var results: [ProfileUsage] = []
        for profile in Credentials.discoverProfiles() {
            guard let token = Credentials.accessToken(service: profile.id) else {
                results.append(ProfileUsage(profile: profile, usage: nil, error: "no token"))
                continue
            }
            do {
                let usage = try await fetchUsage(token: token)
                results.append(ProfileUsage(profile: profile, usage: usage, error: nil))
            } catch {
                results.append(ProfileUsage(profile: profile, usage: nil,
                                            error: error.localizedDescription))
            }
        }
        rows = results
        lastUpdated = Date()
    }

    private func fetchUsage(token: String) async throws -> UsageResponse {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw UsageError.badResponse }
        switch http.statusCode {
        case 200: return try JSONDecoder().decode(UsageResponse.self, from: data)
        case 429: throw UsageError.rateLimited
        default: throw UsageError.http(http.statusCode)
        }
    }
}
