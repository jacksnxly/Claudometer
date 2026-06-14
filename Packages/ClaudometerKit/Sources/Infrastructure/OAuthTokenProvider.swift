import Foundation
import Domain

/// Supplies a valid OAuth access token for a profile, refreshing it when stale.
///
/// **Why this exists (the 401 fix):** `/api/oauth/usage` returns `401` when the
/// cached access token has expired. Claude Code keeps that token fresh, but if it
/// hasn't run recently the Keychain copy goes stale and Claudometer gets a 401.
/// This actor does what Claude Code does — exchanges the stored `refreshToken` for
/// a new access token at the OAuth token endpoint — proactively (just before the
/// stored `expiresAt`) and reactively (forced on a 401).
///
/// Refreshed tokens are cached in memory for the app's lifetime. We deliberately
/// do **not** write them back to the Keychain: that would risk clobbering Claude
/// Code's credential format and could trigger a Keychain-access prompt. On a cold
/// start we simply refresh once more from the stored refresh token.
actor OAuthTokenProvider {
    private let store = KeychainTokenStore()
    private let session: URLSession

    /// Claude Code's public OAuth client id (same client the CLI authenticates
    /// with). Refresh-token grants are public-client, so no secret is required.
    private let clientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    private let tokenEndpoint = URL(string: "https://console.anthropic.com/v1/oauth/token")!
    /// Refresh this many seconds before the stated expiry.
    private let refreshSkew: TimeInterval = 300

    private var cache: [String: KeychainTokenStore.Credential] = [:]

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// A usable access token for `id`. Pass `forceRefresh` after a 401 to bypass
    /// every cache and exchange the refresh token for a new access token.
    func accessToken(for id: ProfileID, forceRefresh: Bool = false) async throws -> String {
        let key = id.rawValue

        if !forceRefresh, let cached = cache[key], !isStale(cached.expiresAt) {
            return cached.accessToken
        }

        let stored = try store.credential(for: id)
        if !forceRefresh, !isStale(stored.expiresAt) {
            cache[key] = stored
            return stored.accessToken
        }

        // Token is stale (or a refresh was forced). Exchange the refresh token.
        guard let refreshToken = cache[key]?.refreshToken ?? stored.refreshToken else {
            // No way to refresh. On a forced retry surface a clear error; otherwise
            // hand back the stored token and let the caller's 401 path react.
            if forceRefresh { throw InfrastructureError.sessionExpired }
            return stored.accessToken
        }

        let refreshed = try await refresh(using: refreshToken)
        cache[key] = refreshed
        return refreshed.accessToken
    }

    private func isStale(_ expiresAt: Date?) -> Bool {
        guard let expiresAt else { return false } // unknown expiry → trust it; rely on 401 retry
        return Date() >= expiresAt.addingTimeInterval(-refreshSkew)
    }

    private func refresh(using refreshToken: String) async throws -> KeychainTokenStore.Credential {
        var request = URLRequest(url: tokenEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID,
        ])

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw InfrastructureError.badResponse }
        guard http.statusCode == 200 else { throw InfrastructureError.refreshFailed(http.statusCode) }

        struct TokenResponse: Decodable {
            let access_token: String
            let refresh_token: String?
            let expires_in: Double?
        }
        guard let decoded = try? JSONDecoder().decode(TokenResponse.self, from: data) else {
            throw InfrastructureError.badResponse
        }
        return KeychainTokenStore.Credential(
            accessToken: decoded.access_token,
            // Refresh tokens may rotate; keep the new one (fall back to the old).
            refreshToken: decoded.refresh_token ?? refreshToken,
            expiresAt: decoded.expires_in.map { Date().addingTimeInterval($0) }
        )
    }
}
