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
        .padding(14)
        .frame(width: 320)
        .task {
            if viewModel.results.isEmpty { await viewModel.refresh() }
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "gauge.with.dots.needle.50percent")
            Text("Claudometer").font(.headline)
            Spacer()
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
            ForEach(viewModel.results) { result in
                ProfileUsageView(result: result)
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

/// One profile's block: name + a meter per usage window (or a failure note).
private struct ProfileUsageView: View {
    let result: ProfileUsageResult

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(result.profile.name)
                .font(.subheadline.bold())

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
}

/// A single labelled progress bar for one usage window.
private struct WindowMeter: View {
    let window: UsageWindow

    var body: some View {
        HStack(spacing: 8) {
            Text(window.period.label)
                .font(.caption.monospaced())
                .frame(width: 88, alignment: .leading)
                .foregroundStyle(.secondary)
            ProgressView(value: window.utilization.percentage, total: 100)
                .tint(color)
            Text("\(Int(window.utilization.percentage))%")
                .font(.caption.monospaced())
                .frame(width: 38, alignment: .trailing)
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
