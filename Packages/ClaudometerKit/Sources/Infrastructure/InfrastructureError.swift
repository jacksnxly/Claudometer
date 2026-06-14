import Foundation

public enum InfrastructureError: LocalizedError, Equatable {
    case tokenUnavailable
    case badCredentialFormat
    case rateLimited
    case http(Int)
    case badResponse
    /// The OAuth refresh request itself failed (carries its HTTP status).
    case refreshFailed(Int)
    /// The access token is stale and there is no usable refresh token — the user
    /// needs to sign in again via Claude Code.
    case sessionExpired

    public var errorDescription: String? {
        switch self {
        case .tokenUnavailable: return "no token in Keychain"
        case .badCredentialFormat: return "Keychain credential has an unexpected format"
        case .rateLimited: return "rate limited (429) — try later"
        case .http(let code): return "HTTP \(code)"
        case .badResponse: return "unexpected response"
        case .refreshFailed(let code): return "token refresh failed (HTTP \(code))"
        case .sessionExpired: return "session expired — open Claude Code to sign in"
        }
    }
}
