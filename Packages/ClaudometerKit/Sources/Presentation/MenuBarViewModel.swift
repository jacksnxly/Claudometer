import Foundation
import Observation
import Domain
import Application

/// Which pane the dashboard is showing.
public enum DashboardPane: String, CaseIterable, Sendable, Identifiable {
    case usage, spend
    public var id: String { rawValue }
    public var label: String { self == .usage ? "Usage" : "Spend" }
}

/// One row of the cross-account spend total.
public struct CumulativeSpend: Identifiable, Sendable {
    public let window: CostWindow
    public let cost: Money
    public let freshTokens: Int
    public let hasUnpriced: Bool
    public var id: CostWindow { window }
}

/// Presentation state for the menu-bar UI. Talks only to the application layer
/// (`RefreshUsageUseCase` for live quota %, `RefreshCostUseCase` for local token
/// spend) — it has no knowledge of Keychain, HTTP, or the transcript files.
@MainActor
@Observable
public final class MenuBarViewModel {
    public private(set) var results: [ProfileUsageResult] = []
    public private(set) var costResults: [ProfileCostResult] = []
    public private(set) var lastUpdated: Date?
    public private(set) var isLoading = false
    public private(set) var isLoadingCost = false

    /// Which pane is visible. Persisted on the model so it survives re-renders.
    public var selectedPane: DashboardPane = .usage

    /// When true, the UI blurs account emails so usage stats can be screenshotted
    /// for sharing without leaking identity. Pure presentation state.
    public var isPrivacyMode = false

    private let refreshUsage: RefreshUsageUseCase
    private let refreshCost: RefreshCostUseCase

    public init(refreshUsage: RefreshUsageUseCase, refreshCost: RefreshCostUseCase) {
        self.refreshUsage = refreshUsage
        self.refreshCost = refreshCost
    }

    public func togglePrivacyMode() { isPrivacyMode.toggle() }

    /// The cost report for a profile, matched by id.
    public func cost(for id: ProfileID) -> ProfileCostResult? {
        costResults.first { $0.id == id }
    }

    /// Number of accounts that contributed any priced spend.
    public var accountsWithSpend: Int {
        costResults.filter { ($0.report?.isEmpty == false) }.count
    }

    /// Spend summed across every account, per window — the headline figure.
    public func cumulativeSpend() -> [CumulativeSpend] {
        var byWindow: [CostWindow: (cost: Money, tokens: Int, unpriced: Bool)] = [:]
        for result in costResults {
            guard let report = result.report else { continue }
            for windowCost in report.windows {
                let current = byWindow[windowCost.window] ?? (.zero, 0, false)
                byWindow[windowCost.window] = (
                    current.cost + windowCost.totalCost,
                    current.tokens + windowCost.totalUsage.freshTokens,
                    current.unpriced || windowCost.hasUnpricedTokens
                )
            }
        }
        return CostWindow.allCases.compactMap { window in
            byWindow[window].map {
                CumulativeSpend(window: window, cost: $0.cost, freshTokens: $0.tokens, hasUnpriced: $0.unpriced)
            }
        }
    }

    public func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        let newResults = await refreshUsage.execute()
        // A cancelled refresh (e.g. the popover closed mid-flight) must not commit
        // partial results: otherwise `results` stops being empty and the view's
        // `.task` never auto-refreshes again. Cancellation is cooperative (SE-0304).
        guard !Task.isCancelled else { return }
        results = newResults
        lastUpdated = Date()

        // Token/cost comes from parsing local transcripts — slower than the quota
        // call, so it loads as a second phase against the profiles just discovered
        // (sharing that single Keychain scan rather than triggering a second one).
        isLoadingCost = true
        defer { isLoadingCost = false }
        let costs = await refreshCost.execute(profiles: newResults.map(\.profile))
        guard !Task.isCancelled else { return }
        costResults = costs
    }
}
