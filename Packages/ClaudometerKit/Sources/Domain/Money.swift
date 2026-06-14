import Foundation

/// Value object: a USD amount, held as `Decimal` to avoid binary-float rounding
/// drift when summing thousands of per-message costs.
///
/// Note: in Claudometer this represents an *equivalent API list price* — what the
/// metered tokens would cost on the pay-as-you-go API — not money actually billed
/// to a flat-rate Pro/Max subscription. The presentation layer is responsible for
/// labelling it as an estimate.
public struct Money: Hashable, Sendable, Comparable {
    public let usd: Decimal

    public init(usd: Decimal) {
        self.usd = usd
    }

    public static let zero = Money(usd: 0)

    public static func + (lhs: Money, rhs: Money) -> Money {
        Money(usd: lhs.usd + rhs.usd)
    }

    public static func < (lhs: Money, rhs: Money) -> Bool {
        lhs.usd < rhs.usd
    }
}
