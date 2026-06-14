import Foundation

/// Value object: the base per-million-token (MTok) rates for a model. Cache
/// rates are not stored — they are derived from the base input rate via the
/// universal multipliers on `PricingPolicy`.
public struct ModelRate: Hashable, Sendable {
    public let inputPerMTok: Decimal
    public let outputPerMTok: Decimal

    public init(inputPerMTok: Decimal, outputPerMTok: Decimal) {
        self.inputPerMTok = inputPerMTok
        self.outputPerMTok = outputPerMTok
    }
}

/// Domain policy: how to value token usage in dollars.
///
/// Encodes Anthropic's published list prices (per MTok) and the prompt-caching
/// multipliers (cache read = 0.1× input, 5-min write = 1.25×, 1-hour write =
/// 2×). Rates are verified against platform.claude.com/docs/en/about-claude/pricing
/// (2026-06). Unknown / `<synthetic>` models return `nil` so the caller can show
/// their tokens as "unpriced" rather than silently valuing them at zero.
public struct PricingPolicy: Sendable {
    // Cache multipliers, expressed as exact base-10 ratios (avoids Double→Decimal
    // rounding, e.g. `Decimal(0.1)` is *not* exactly 0.1).
    public static let cacheReadMultiplier = Decimal(1) / Decimal(10)   // 0.10×
    public static let cacheWrite5mMultiplier = Decimal(5) / Decimal(4) // 1.25×
    public static let cacheWrite1hMultiplier = Decimal(2)              // 2.00×

    public init() {}

    /// Resolve a model id (e.g. `"claude-opus-4-8"`, `"claude-opus-4-8[1m]"`) and
    /// its speed to base rates. `fast` selects Fast-mode pricing where it exists.
    /// Returns `nil` for models with no list price (synthetic/unknown).
    public func rate(forModelID id: String, fast: Bool) -> ModelRate? {
        let m = id.lowercased()
        // Fable 5 / Mythos 5 (no Fast-mode variant).
        if m.contains("fable") || m.contains("mythos") {
            return ModelRate(inputPerMTok: 10, outputPerMTok: 50)
        }
        if m.contains("opus") {
            if fast {
                // Fast mode exists for Opus 4.6/4.7 (30/150) and 4.8 (10/50).
                if m.contains("4-6") || m.contains("4-7") {
                    return ModelRate(inputPerMTok: 30, outputPerMTok: 150)
                }
                return ModelRate(inputPerMTok: 10, outputPerMTok: 50)
            }
            return ModelRate(inputPerMTok: 5, outputPerMTok: 25)
        }
        if m.contains("sonnet") { return ModelRate(inputPerMTok: 3, outputPerMTok: 15) }
        if m.contains("haiku") { return ModelRate(inputPerMTok: 1, outputPerMTok: 5) }
        return nil
    }

    /// Equivalent API list-price cost of `usage` for the given model, or `nil`
    /// when the model has no list price.
    public func cost(of usage: TokenUsage, modelID: String, fast: Bool) -> Money? {
        guard let rate = rate(forModelID: modelID, fast: fast) else { return nil }
        let perMTok =
            Decimal(usage.input) * rate.inputPerMTok
            + Decimal(usage.output) * rate.outputPerMTok
            + Decimal(usage.cacheRead) * (rate.inputPerMTok * Self.cacheReadMultiplier)
            + Decimal(usage.cacheWrite5m) * (rate.inputPerMTok * Self.cacheWrite5mMultiplier)
            + Decimal(usage.cacheWrite1h) * (rate.inputPerMTok * Self.cacheWrite1hMultiplier)
        return Money(usd: perMTok / Decimal(1_000_000))
    }
}
