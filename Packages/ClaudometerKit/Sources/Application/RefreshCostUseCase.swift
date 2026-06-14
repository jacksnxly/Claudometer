import Foundation
import Domain

/// Application service: for each known profile, read its local token ledger and
/// build a dollar-valued `CostReport`.
///
/// Takes already-discovered `profiles` (rather than the `ProfileDirectory`) so it
/// can share one Keychain scan with `RefreshUsageUseCase` instead of triggering a
/// second batch of Keychain prompts. Never throws — each profile's failure is
/// captured individually. Profiles are read concurrently since each maps to an
/// independent config directory.
public struct RefreshCostUseCase: Sendable {
    private let ledger: any UsageLedger
    private let builder = CostReportBuilder()

    public init(ledger: any UsageLedger) {
        self.ledger = ledger
    }

    public func execute(profiles: [Profile], now: Date = Date()) async -> [ProfileCostResult] {
        await withTaskGroup(of: (Int, ProfileCostResult).self) { group in
            for (index, profile) in profiles.enumerated() {
                group.addTask {
                    do {
                        let entries = try await ledger.entries(for: profile, now: now)
                        return (index, ProfileCostResult(
                            profile: profile,
                            report: builder.build(from: entries),
                            failure: nil
                        ))
                    } catch {
                        return (index, ProfileCostResult(
                            profile: profile,
                            report: nil,
                            failure: error.localizedDescription
                        ))
                    }
                }
            }

            // Preserve the caller's profile order (the use case doesn't re-rank).
            var collected = Array<ProfileCostResult?>(repeating: nil, count: profiles.count)
            for await (index, result) in group {
                collected[index] = result
            }
            return collected.compactMap { $0 }
        }
    }
}
