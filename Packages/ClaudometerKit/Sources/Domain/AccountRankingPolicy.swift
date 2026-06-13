import Foundation

/// The recommendation for when to use an account, derived from its usage.
public struct UsagePriority: Hashable, Sendable {
    /// Higher = use sooner. Lower = keep in reserve.
    public let score: Double
    /// Whether the 5-hour window currently has capacity (usable right now).
    public let availableNow: Bool
    /// Percentage of the weekly (7-day) allowance still unused (0–100).
    public let weeklyRemaining: Double

    public init(score: Double, availableNow: Bool, weeklyRemaining: Double) {
        self.score = score
        self.availableNow = availableNow
        self.weeklyRemaining = weeklyRemaining
    }
}

/// Domain policy that ranks accounts so the credit most at risk of resetting
/// unused is spent first ("use-it-or-lose-it").
///
/// `score = (weekly credit still unused) ÷ (hours until the 7-day window resets)`
/// — i.e. the burn rate required to avoid wasting that account's weekly
/// allowance. Higher means more urgent. An account whose 5-hour window is
/// exhausted is flagged `availableNow == false` so callers can rank it after
/// accounts that can be used right now.
public struct AccountRankingPolicy: Sendable {
    /// At/above this 5-hour utilization the account can't meaningfully be used now.
    private let fiveHourExhausted = 99.0
    /// Used when a window has no reset timestamp: assume a full week remains.
    private let fallbackHours = 168.0

    public init() {}

    public func priority(for snapshot: UsageSnapshot, now: Date) -> UsagePriority {
        let fiveHourUtil = snapshot.window(.fiveHour)?.utilization.percentage ?? 0
        let availableNow = fiveHourUtil < fiveHourExhausted

        let week = snapshot.window(.sevenDay)
        let weeklyRemaining = 100 - (week?.utilization.percentage ?? 100)
        let hours: Double = {
            guard let reset = week?.resetsAt else { return fallbackHours }
            return max(reset.timeIntervalSince(now) / 3600, 0.01)
        }()

        return UsagePriority(
            score: weeklyRemaining / hours,
            availableNow: availableNow,
            weeklyRemaining: weeklyRemaining
        )
    }

    /// Order whose element should be used first: available accounts before
    /// cooling-down ones, then by descending score.
    public func isHigherPriority(_ lhs: UsagePriority, than rhs: UsagePriority) -> Bool {
        if lhs.availableNow != rhs.availableNow { return lhs.availableNow }
        return lhs.score > rhs.score
    }
}
