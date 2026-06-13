import Foundation

public enum InfrastructureError: LocalizedError, Equatable {
    case tokenUnavailable
    case badCredentialFormat
    case rateLimited
    case http(Int)
    case badResponse

    public var errorDescription: String? {
        switch self {
        case .tokenUnavailable: return "no token in Keychain"
        case .badCredentialFormat: return "Keychain credential has an unexpected format"
        case .rateLimited: return "rate limited (429) — try later"
        case .http(let code): return "HTTP \(code)"
        case .badResponse: return "unexpected response"
        }
    }
}
