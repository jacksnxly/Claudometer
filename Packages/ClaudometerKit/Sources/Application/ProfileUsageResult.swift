import Domain

/// Application DTO: the per-profile outcome of a refresh — either a usage
/// snapshot or a human-readable failure. Keeps infrastructure error types from
/// leaking into the presentation layer.
public struct ProfileUsageResult: Identifiable, Sendable {
    public let profile: Profile
    public let snapshot: UsageSnapshot?
    public let failure: String?
    /// 1-based recommended use order (1 = use first). Nil when usage is unavailable.
    public let rank: Int?
    /// Whether the account can be used right now (5-hour window not exhausted).
    public let availableNow: Bool
    /// Percentage of weekly (7-day) credit still unused (0–100), when known.
    public let weeklyRemaining: Double?

    public var id: ProfileID { profile.id }

    public init(
        profile: Profile,
        snapshot: UsageSnapshot?,
        failure: String?,
        rank: Int? = nil,
        availableNow: Bool = false,
        weeklyRemaining: Double? = nil
    ) {
        self.profile = profile
        self.snapshot = snapshot
        self.failure = failure
        self.rank = rank
        self.availableNow = availableNow
        self.weeklyRemaining = weeklyRemaining
    }
}
