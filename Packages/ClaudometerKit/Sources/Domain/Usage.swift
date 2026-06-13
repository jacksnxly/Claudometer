import Foundation

/// Value object: a usage percentage, always clamped to `0...100`.
public struct Utilization: Hashable, Sendable, Comparable {
    public let percentage: Double

    public init(_ value: Double) {
        self.percentage = Swift.min(Swift.max(value, 0), 100)
    }

    public static func < (lhs: Utilization, rhs: Utilization) -> Bool {
        lhs.percentage < rhs.percentage
    }

    public enum Level: Sendable { case normal, warning, critical }

    /// Domain rule for how close a window is to exhaustion.
    public var level: Level {
        switch percentage {
        case ..<60: return .normal
        case ..<85: return .warning
        default: return .critical
        }
    }
}

/// Value object: which quota window a measurement belongs to.
public enum UsagePeriod: String, Hashable, Sendable, CaseIterable {
    case fiveHour
    case sevenDay
    case sevenDayOpus
    case sevenDaySonnet

    public var label: String {
        switch self {
        case .fiveHour: return "5-hour"
        case .sevenDay: return "7-day"
        case .sevenDayOpus: return "7-day Opus"
        case .sevenDaySonnet: return "7-day Sonnet"
        }
    }
}

/// Value object: one quota window's utilization and reset time.
public struct UsageWindow: Hashable, Sendable, Identifiable {
    public let period: UsagePeriod
    public let utilization: Utilization
    public let resetsAt: Date?

    public var id: UsagePeriod { period }

    public init(period: UsagePeriod, utilization: Utilization, resetsAt: Date?) {
        self.period = period
        self.utilization = utilization
        self.resetsAt = resetsAt
    }
}

/// Aggregate: the usage snapshot for one profile at a moment in time.
public struct UsageSnapshot: Hashable, Sendable {
    public let profile: Profile
    public let windows: [UsageWindow]

    public init(profile: Profile, windows: [UsageWindow]) {
        self.profile = profile
        self.windows = windows
    }

    public func window(_ period: UsagePeriod) -> UsageWindow? {
        windows.first { $0.period == period }
    }
}
