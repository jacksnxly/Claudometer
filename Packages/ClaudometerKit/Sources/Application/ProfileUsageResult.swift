import Domain

/// Application DTO: the per-profile outcome of a refresh — either a usage
/// snapshot or a human-readable failure. Keeps infrastructure error types from
/// leaking into the presentation layer.
public struct ProfileUsageResult: Identifiable, Sendable {
    public let profile: Profile
    public let snapshot: UsageSnapshot?
    public let failure: String?

    public var id: ProfileID { profile.id }

    public init(profile: Profile, snapshot: UsageSnapshot?, failure: String?) {
        self.profile = profile
        self.snapshot = snapshot
        self.failure = failure
    }
}
