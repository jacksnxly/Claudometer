import SwiftUI
import AppKit
import Domain
import Application

/// The menu-bar popover: one section per profile, each showing its quota meters.
public struct MenuView: View {
    private let viewModel: MenuBarViewModel

    public init(viewModel: MenuBarViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .padding(16)
        .frame(width: 420)
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
            if viewModel.isLoading {
                ProgressView().controlSize(.small)
            }
            Button {
                Task { await viewModel.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .disabled(viewModel.isLoading)
            .help("Refresh usage")
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.results.isEmpty {
            Text(viewModel.isLoading ? "Loading…" : "No Claude profiles found")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(Array(viewModel.results.enumerated()), id: \.element.id) { index, result in
                    if index > 0 {
                        Divider().opacity(0.4)
                    }
                    ProfileUsageView(result: result)
                }
            }
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

/// One profile's block: header (slot · email · plan) + a meter per usage window.
private struct ProfileUsageView: View {
    let result: ProfileUsageResult

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            header
            if let recommendation {
                Text(recommendation.text)
                    .font(.caption2)
                    .foregroundStyle(recommendation.color)
            }
            if let snapshot = result.snapshot {
                if snapshot.windows.isEmpty {
                    Text("No usage data")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(snapshot.windows) { window in
                        WindowMeter(window: window)
                    }
                }
            } else {
                Label(result.failure ?? "unavailable", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        HStack(spacing: 7) {
            if let rank = result.rank {
                Image(systemName: "\(rank).circle.fill")
                    .foregroundStyle(rank == 1 ? Color.green : Color.secondary)
                    .help(rank == 1 ? "Use this account next" : "Recommended use order: #\(rank)")
            }
            if let tag = result.profile.tag {
                Text(tag)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.quaternary))
            }
            Text(result.profile.displayName)
                .font(.subheadline.bold())
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            if let plan = result.profile.plan {
                Text(plan)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.quaternary.opacity(0.6)))
            }
        }
    }

    /// Short rationale for this account's rank.
    private var recommendation: (text: String, color: Color)? {
        guard result.snapshot != nil else { return nil }
        if !result.availableNow {
            return ("5-hour limit reached — use later", .orange)
        }
        let free = Int((result.weeklyRemaining ?? 0).rounded())
        if result.rank == 1 {
            return ("Use next · \(free)% weekly credit at risk", .green)
        }
        return ("\(free)% weekly credit free", .secondary)
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
