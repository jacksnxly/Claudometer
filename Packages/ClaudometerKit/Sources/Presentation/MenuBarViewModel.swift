import Foundation
import Observation
import Application

/// Presentation state for the menu-bar UI. Talks only to the application layer
/// (`RefreshUsageUseCase`) — it has no knowledge of Keychain or HTTP.
@MainActor
@Observable
public final class MenuBarViewModel {
    public private(set) var results: [ProfileUsageResult] = []
    public private(set) var lastUpdated: Date?
    public private(set) var isLoading = false

    private let refreshUsage: RefreshUsageUseCase

    public init(refreshUsage: RefreshUsageUseCase) {
        self.refreshUsage = refreshUsage
    }

    public func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        let newResults = await refreshUsage.execute()
        // A cancelled refresh (e.g. the menu-bar popover closed mid-flight) must not
        // commit partial/cancelled results: otherwise `results` stops being empty and
        // the view's `.task` never auto-refreshes again. Cancellation is cooperative
        // (SE-0304) — respond by returning promptly without committing stale work.
        guard !Task.isCancelled else { return }
        results = newResults
        lastUpdated = Date()
    }
}
