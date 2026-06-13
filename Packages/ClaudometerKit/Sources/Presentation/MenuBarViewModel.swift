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
        results = await refreshUsage.execute()
        lastUpdated = Date()
    }
}
