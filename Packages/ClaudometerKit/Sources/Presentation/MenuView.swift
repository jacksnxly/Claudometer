import SwiftUI
import AppKit
import Domain
import Application

/// The menu-bar popover. A segmented control switches between two compact panes:
/// **Usage** (live quota meters per account) and **Spend** (a cross-account total
/// plus per-account estimated value — the share-friendly view).
public struct MenuView: View {
    private let viewModel: MenuBarViewModel

    public init(viewModel: MenuBarViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            panePicker
            Divider()
            pane
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 460)
        .task {
            if viewModel.results.isEmpty { await viewModel.refresh() }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "gauge.with.dots.needle.50percent")
                .foregroundStyle(.tint)
            Text("Claudometer").font(.headline)
            Spacer()
            if viewModel.isLoading || viewModel.isLoadingCost {
                ProgressView().controlSize(.small)
            }
            Button {
                viewModel.togglePrivacyMode()
            } label: {
                Image(systemName: viewModel.isPrivacyMode ? "eye.slash" : "eye")
            }
            .buttonStyle(.borderless)
            .help(viewModel.isPrivacyMode ? "Show emails" : "Hide emails for sharing")
            Button {
                Task { await viewModel.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(viewModel.isLoading)
            .help("Refresh")
        }
    }

    private var panePicker: some View {
        Picker("", selection: Binding(
            get: { viewModel.selectedPane },
            set: { viewModel.selectedPane = $0 }
        )) {
            ForEach(DashboardPane.allCases) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
    }

    @ViewBuilder
    private var pane: some View {
        if viewModel.results.isEmpty {
            Text(viewModel.isLoading ? "Loading…" : "No Claude profiles found")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
        } else {
            switch viewModel.selectedPane {
            case .usage: usagePane
            case .spend: spendPane
            }
        }
    }

    // MARK: - Usage pane

    private var usagePane: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Array(viewModel.results.enumerated()), id: \.element.id) { index, result in
                if index > 0 { Divider().opacity(0.4) }
                ProfileMetersView(result: result, privacy: viewModel.isPrivacyMode)
            }
        }
    }

    // MARK: - Spend pane

    @ViewBuilder
    private var spendPane: some View {
        let cumulative = viewModel.cumulativeSpend()
        VStack(alignment: .leading, spacing: 12) {
            if cumulative.isEmpty {
                Text(viewModel.isLoadingCost ? "Calculating spend…" : "No local Claude Code usage on this Mac")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                CumulativeHero(items: cumulative, accounts: viewModel.accountsWithSpend)
                VStack(alignment: .leading, spacing: 9) {
                    HStack(spacing: 0) {
                        Text("by account").font(.caption2).foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        ForEach(CostWindow.allCases) { window in
                            Text(window.label)
                                .font(.system(size: 9).monospaced())
                                .foregroundStyle(.tertiary)
                                .frame(width: SpendRow.columnWidth, alignment: .trailing)
                        }
                    }
                    ForEach(spendSorted) { result in
                        SpendRow(result: result, cost: viewModel.cost(for: result.id), privacy: viewModel.isPrivacyMode)
                    }
                }
            }
        }
    }

    /// Most-valuable account first (by 30-day estimated spend).
    private var spendSorted: [ProfileUsageResult] {
        viewModel.results.sorted { lhs, rhs in
            let l = viewModel.cost(for: lhs.id)?.report?.window(.thirtyDays)?.totalCost ?? .zero
            let r = viewModel.cost(for: rhs.id)?.report?.window(.thirtyDays)?.totalCost ?? .zero
            return l > r
        }
    }

    private var footer: some View {
        HStack {
            if let lastUpdated = viewModel.lastUpdated {
                Text("Updated \(lastUpdated.formatted(date: .omitted, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.borderless)
        }
    }
}

// MARK: - Usage: one profile's quota meters

private struct ProfileMetersView: View {
    let result: ProfileUsageResult
    let privacy: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ProfileIdentity(profile: result.profile, rank: result.rank, privacy: privacy)
            if let recommendation {
                Text(recommendation.text)
                    .font(.caption2)
                    .foregroundStyle(recommendation.color)
            }
            if let snapshot = result.snapshot {
                if snapshot.windows.isEmpty {
                    Text("No usage data").font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(snapshot.windows) { WindowMeter(window: $0) }
                }
            } else {
                Label(result.failure ?? "unavailable", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var recommendation: (text: String, color: Color)? {
        guard result.snapshot != nil else { return nil }
        if !result.availableNow { return ("5-hour limit reached — use later", .orange) }
        let free = Int((result.weeklyRemaining ?? 0).rounded())
        if result.rank == 1 { return ("Use next · \(free)% weekly credit at risk", .green) }
        return ("\(free)% weekly credit free", .secondary)
    }
}

// MARK: - Spend: cross-account total + per-account rows

/// The headline figure: estimated value summed across every account.
private struct CumulativeHero: View {
    let items: [CumulativeSpend]
    let accounts: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                Image(systemName: "dollarsign.circle.fill").foregroundStyle(.tint)
                Text("Total est. API value").font(.subheadline.bold())
                Spacer()
                Text("\(accounts) account\(accounts == 1 ? "" : "s")")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 20) {
                ForEach(items) { item in
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 2) {
                            Text(item.window.label).font(.caption2.monospaced()).foregroundStyle(.secondary)
                            if item.hasUnpriced {
                                Text("+").font(.caption2).foregroundStyle(.tertiary)
                                    .help("Includes tokens from a model with no list price — treat as a floor.")
                            }
                        }
                        Text(CostFormat.short(item.cost))
                            .font(.title3.bold().monospacedDigit())
                        Text("\(TokenFormat.short(item.freshTokens)) tok")
                            .font(.system(size: 9).monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer(minLength: 0)
            }
            Text("≈ pay-as-you-go API list price of tokens run locally — not what a Pro/Max subscription is billed. Mostly cached-context reads.")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.35)))
    }
}

/// One account's spend, compact: identity on the left, per-window $ on the right.
private struct SpendRow: View {
    let result: ProfileUsageResult
    let cost: ProfileCostResult?
    let privacy: Bool

    /// Shared by the spend-pane header so columns line up.
    static let columnWidth: CGFloat = 74

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    if let tag = result.profile.tag {
                        Text(tag)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Capsule().fill(.quaternary))
                    }
                    Text(result.profile.displayName)
                        .font(.caption.bold())
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .blur(radius: privacy ? 4 : 0)
                        .animation(.easeInOut(duration: 0.15), value: privacy)
                        .help(privacy ? "Hidden for sharing" : result.profile.displayName)
                }
                if let plan = result.profile.plan {
                    Text(plan).font(.system(size: 9)).foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 8)
            if let report = cost?.report, !report.isEmpty {
                ForEach(CostWindow.allCases) { window in
                    Group {
                        if let windowCost = report.window(window) {
                            Text(CostFormat.short(windowCost.totalCost))
                                .font(.caption.bold().monospacedDigit())
                                .help(Self.tooltip(for: windowCost))
                        } else {
                            Text("—").font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                    .frame(width: Self.columnWidth, alignment: .trailing)
                }
            } else {
                Text(cost?.failure == nil ? "…" : "no data")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private static func tooltip(for windowCost: WindowCost) -> String {
        let lines = windowCost.lines.prefix(6).map { "\($0.id): \($0.cost.map(CostFormat.short) ?? "unpriced")" }
        return "Last \(windowCost.window.days) days · \(TokenFormat.short(windowCost.totalUsage.freshTokens)) tok\n"
            + lines.joined(separator: "\n")
    }
}

// MARK: - Shared bits

/// Rank badge · slot tag · email (blurred in privacy mode) · plan.
private struct ProfileIdentity: View {
    let profile: Profile
    let rank: Int?
    let privacy: Bool

    var body: some View {
        HStack(spacing: 7) {
            if let rank {
                Image(systemName: "\(rank).circle.fill")
                    .foregroundStyle(rank == 1 ? Color.green : Color.secondary)
                    .help(rank == 1 ? "Use this account next" : "Recommended use order: #\(rank)")
            }
            if let tag = profile.tag {
                Text(tag)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(.quaternary))
            }
            Text(profile.displayName)
                .font(.subheadline.bold())
                .lineLimit(1)
                .truncationMode(.middle)
                .blur(radius: privacy ? 4.5 : 0)
                .animation(.easeInOut(duration: 0.15), value: privacy)
                .help(privacy ? "Hidden for sharing" : profile.displayName)
            Spacer(minLength: 8)
            if let plan = profile.plan {
                Text(plan)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Capsule().fill(.quaternary.opacity(0.6)))
            }
        }
    }
}

/// A single labelled progress bar for one usage window.
private struct WindowMeter: View {
    let window: UsageWindow

    /// Fixed schedule anchor so the 1-minute tick lands on consistent absolute
    /// boundaries instead of restarting from "now" on every re-render.
    private static let tickAnchor = Date(timeIntervalSince1970: 0)

    var body: some View {
        HStack(spacing: 10) {
            Text(window.period.label)
                .font(.caption.monospaced())
                .frame(width: 86, alignment: .leading)
                .foregroundStyle(.secondary)
            ProgressView(value: window.utilization.percentage, total: 100)
                .tint(color)
            Text("\(Int(window.utilization.percentage.rounded()))%")
                .font(.caption.monospaced())
                .frame(width: 38, alignment: .trailing)
            reset
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(width: 74, alignment: .trailing)
        }
    }

    @ViewBuilder
    private var reset: some View {
        if let resetsAt = window.resetsAt {
            // Re-evaluate once a minute so the countdown stays live.
            TimelineView(.periodic(from: Self.tickAnchor, by: 60)) { context in
                Text(ResetCountdown.text(to: resetsAt, from: context.date))
                    .help("Resets \(resetsAt.formatted(date: .abbreviated, time: .shortened))")
            }
        } else {
            Text("—")
        }
    }

    private var color: Color {
        switch window.utilization.level {
        case .normal: return .green
        case .warning: return .yellow
        case .critical: return .red
        }
    }
}

/// Compact relative-countdown formatting for a usage window's reset time.
/// Pure and testable — kept out of the SwiftUI view body.
enum ResetCountdown {
    /// The two most significant units, e.g. "in 21m", "in 2h 41m", "in 1d 23h",
    /// "in 5d". A reset less than a minute away renders "<1m" rather than the
    /// misleading "in 0m"; an elapsed reset renders "now".
    static func text(to date: Date, from now: Date) -> String {
        let seconds = Int(date.timeIntervalSince(now))
        guard seconds > 0 else { return "now" }
        let minutes = seconds / 60
        let hours = minutes / 60
        let days = hours / 24
        if days >= 1 {
            let h = hours % 24
            return h > 0 ? "in \(days)d \(h)h" : "in \(days)d"
        }
        if hours >= 1 {
            let m = minutes % 60
            return m > 0 ? "in \(hours)h \(m)m" : "in \(hours)h"
        }
        if minutes < 1 { return "<1m" }
        return "in \(minutes)m"
    }
}

/// Compact USD formatting for an estimated cost: no cents at/above $100.
enum CostFormat {
    static func short(_ money: Money) -> String {
        let value = money.usd
        let magnitude = value < 0 ? -value : value
        let fraction = magnitude >= 100 ? 0 : 2
        return value.formatted(.currency(code: "USD").precision(.fractionLength(fraction)))
    }
}

/// Compact token-count formatting: 1.2B / 845M / 65K.
enum TokenFormat {
    static func short(_ count: Int) -> String {
        let value = Double(count)
        switch value {
        case 1_000_000_000...: return String(format: "%.1fB", value / 1e9)
        case 1_000_000...: return String(format: "%.0fM", value / 1e6)
        case 1_000...: return String(format: "%.0fK", value / 1e3)
        default: return "\(count)"
        }
    }
}
