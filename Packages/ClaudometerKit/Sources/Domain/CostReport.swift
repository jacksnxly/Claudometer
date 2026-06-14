import Foundation

/// Value object: a trailing window over which usage is summed.
public enum CostWindow: Int, Sendable, CaseIterable, Hashable, Comparable, Identifiable {
    case sevenDays = 7
    case fourteenDays = 14
    case thirtyDays = 30

    public var id: Int { rawValue }
    public var days: Int { rawValue }
    public var label: String { "\(rawValue)d" }

    public static func < (lhs: CostWindow, rhs: CostWindow) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Port DTO: usage attributed to one (window, model, speed) slice. Produced by a
/// `UsageLedger` adapter; the same tokens appear in every window whose span
/// contains them (7-day tokens also count toward 14- and 30-day).
public struct LedgerEntry: Hashable, Sendable {
    public let window: CostWindow
    public let modelID: String
    public let fast: Bool
    public let usage: TokenUsage

    public init(window: CostWindow, modelID: String, fast: Bool, usage: TokenUsage) {
        self.window = window
        self.modelID = modelID
        self.fast = fast
        self.usage = usage
    }
}

/// One model's line within a window: its tokens and computed cost (`nil` = the
/// model has no list price, e.g. `<synthetic>`).
public struct ModelUsageLine: Hashable, Sendable, Identifiable {
    public let modelID: String
    public let fast: Bool
    public let usage: TokenUsage
    public let cost: Money?

    public init(modelID: String, fast: Bool, usage: TokenUsage, cost: Money?) {
        self.modelID = modelID
        self.fast = fast
        self.usage = usage
        self.cost = cost
    }

    public var id: String { fast ? "\(modelID) (fast)" : modelID }
    public var isPriced: Bool { cost != nil }
}

/// Aggregate of one window's per-model lines plus rolled-up totals.
public struct WindowCost: Hashable, Sendable, Identifiable {
    public let window: CostWindow
    public let lines: [ModelUsageLine]
    public let totalCost: Money
    public let totalUsage: TokenUsage
    /// True when some tokens came from a model with no list price (so `totalCost`
    /// understates true usage).
    public let hasUnpricedTokens: Bool

    public var id: CostWindow { window }

    public init(
        window: CostWindow,
        lines: [ModelUsageLine],
        totalCost: Money,
        totalUsage: TokenUsage,
        hasUnpricedTokens: Bool
    ) {
        self.window = window
        self.lines = lines
        self.totalCost = totalCost
        self.totalUsage = totalUsage
        self.hasUnpricedTokens = hasUnpricedTokens
    }
}

/// Aggregate: the full cost report for one profile across all windows.
public struct CostReport: Hashable, Sendable {
    public let windows: [WindowCost]

    public init(windows: [WindowCost]) {
        self.windows = windows
    }

    public func window(_ window: CostWindow) -> WindowCost? {
        windows.first { $0.window == window }
    }

    public var isEmpty: Bool { windows.allSatisfy { $0.totalUsage.total == 0 } }
}

/// Domain service: assembles a `CostReport` from raw ledger entries, applying the
/// `PricingPolicy`. Pure — no I/O — so it is trivially unit-testable.
public struct CostReportBuilder: Sendable {
    private let pricing: PricingPolicy

    public init(pricing: PricingPolicy = PricingPolicy()) {
        self.pricing = pricing
    }

    private struct Key: Hashable { let window: CostWindow; let modelID: String; let fast: Bool }

    public func build(from entries: [LedgerEntry]) -> CostReport {
        // Merge any duplicate (window, model, speed) slices the adapter emitted.
        var merged: [Key: TokenUsage] = [:]
        for entry in entries {
            let key = Key(window: entry.window, modelID: entry.modelID, fast: entry.fast)
            merged[key] = (merged[key] ?? .zero) + entry.usage
        }

        var windows: [WindowCost] = []
        for window in CostWindow.allCases {
            let lines = merged
                .filter { $0.key.window == window }
                .map { key, usage in
                    ModelUsageLine(
                        modelID: key.modelID,
                        fast: key.fast,
                        usage: usage,
                        cost: pricing.cost(of: usage, modelID: key.modelID, fast: key.fast)
                    )
                }
                .sorted(by: Self.byCostThenVolume)

            guard !lines.isEmpty else { continue }

            let totalCost = lines.compactMap(\.cost).reduce(Money.zero, +)
            let totalUsage = lines.map(\.usage).reduce(TokenUsage.zero, +)
            let hasUnpriced = lines.contains { !$0.isPriced && $0.usage.total > 0 }

            windows.append(
                WindowCost(
                    window: window,
                    lines: lines,
                    totalCost: totalCost,
                    totalUsage: totalUsage,
                    hasUnpricedTokens: hasUnpriced
                )
            )
        }
        return CostReport(windows: windows.sorted { $0.window < $1.window })
    }

    /// Priced lines first (most expensive first); unpriced lines last, by volume.
    private static func byCostThenVolume(_ lhs: ModelUsageLine, _ rhs: ModelUsageLine) -> Bool {
        switch (lhs.cost, rhs.cost) {
        case let (l?, r?): return l > r
        case (_?, nil): return true
        case (nil, _?): return false
        case (nil, nil): return lhs.usage.total > rhs.usage.total
        }
    }
}
