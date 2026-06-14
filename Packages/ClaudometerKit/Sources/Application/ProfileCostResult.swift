import Domain

/// Application DTO: the per-profile outcome of a cost refresh — either a cost
/// report or a human-readable failure. Mirrors `ProfileUsageResult`, keeping
/// infrastructure error types out of the presentation layer.
public struct ProfileCostResult: Identifiable, Sendable {
    public let profile: Profile
    public let report: CostReport?
    public let failure: String?

    public var id: ProfileID { profile.id }

    public init(profile: Profile, report: CostReport?, failure: String?) {
        self.profile = profile
        self.report = report
        self.failure = failure
    }
}
