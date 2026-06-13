import Foundation
import Domain

/// Application service: load every profile, fetch its usage, and rank the
/// accounts into a recommended use order (most-at-risk credit first).
///
/// Never throws — each profile's failure is captured individually so one bad
/// token (or a 429) can't sink the whole dashboard.
public struct RefreshUsageUseCase: Sendable {
    private let directory: any ProfileDirectory
    private let provider: any UsageProvider
    private let ranking = AccountRankingPolicy()

    public init(directory: any ProfileDirectory, provider: any UsageProvider) {
        self.directory = directory
        self.provider = provider
    }

    public func execute(now: Date = Date()) async -> [ProfileUsageResult] {
        let profiles: [Profile]
        do {
            profiles = try await directory.profiles()
        } catch {
            return []
        }

        var fetched: [(profile: Profile, snapshot: UsageSnapshot?, failure: String?)] = []
        for profile in profiles {
            do {
                fetched.append((profile, try await provider.usage(for: profile), nil))
            } catch {
                fetched.append((profile, nil, error.localizedDescription))
            }
        }

        // Rank the accounts that returned usage; failures sink to the bottom.
        let ranked = fetched
            .compactMap { item in item.snapshot.map { (item.profile, $0) } }
            .map { (profile, snapshot) in
                (profile, snapshot, ranking.priority(for: snapshot, now: now))
            }
            .sorted { ranking.isHigherPriority($0.2, than: $1.2) }

        var results: [ProfileUsageResult] = ranked.enumerated().map { index, entry in
            ProfileUsageResult(
                profile: entry.0,
                snapshot: entry.1,
                failure: nil,
                rank: index + 1,
                availableNow: entry.2.availableNow,
                weeklyRemaining: entry.2.weeklyRemaining
            )
        }

        for item in fetched where item.snapshot == nil {
            results.append(
                ProfileUsageResult(profile: item.profile, snapshot: nil, failure: item.failure)
            )
        }
        return results
    }
}
