import Foundation

/// Value object: a bucket of token counts as reported by Claude in a message's
/// `usage` block. The four cache-related buckets are kept distinct because they
/// price very differently (a cache *read* is 0.1× input; a 1-hour cache *write*
/// is 2× input).
public struct TokenUsage: Hashable, Sendable {
    public let input: Int
    public let output: Int
    public let cacheRead: Int
    public let cacheWrite5m: Int
    public let cacheWrite1h: Int

    public init(
        input: Int = 0,
        output: Int = 0,
        cacheRead: Int = 0,
        cacheWrite5m: Int = 0,
        cacheWrite1h: Int = 0
    ) {
        self.input = input
        self.output = output
        self.cacheRead = cacheRead
        self.cacheWrite5m = cacheWrite5m
        self.cacheWrite1h = cacheWrite1h
    }

    public static let zero = TokenUsage()

    /// All tokens across every bucket. Dominated by `cacheRead` in practice, so
    /// treat this as a volume metric, not a cost proxy — use pricing for that.
    public var total: Int { input + output + cacheRead + cacheWrite5m + cacheWrite1h }

    /// "Fresh" tokens that actually moved through the model, excluding cache
    /// reads/writes — a more intuitive headline number than `total`.
    public var freshTokens: Int { input + output }

    public static func + (lhs: TokenUsage, rhs: TokenUsage) -> TokenUsage {
        TokenUsage(
            input: lhs.input + rhs.input,
            output: lhs.output + rhs.output,
            cacheRead: lhs.cacheRead + rhs.cacheRead,
            cacheWrite5m: lhs.cacheWrite5m + rhs.cacheWrite5m,
            cacheWrite1h: lhs.cacheWrite1h + rhs.cacheWrite1h
        )
    }
}
