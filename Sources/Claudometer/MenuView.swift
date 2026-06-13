import SwiftUI
import AppKit

struct MenuView: View {
    @Bindable var client: UsageClient

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Claudometer").font(.headline)
                Spacer()
                Button {
                    Task { await client.refresh() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .disabled(client.isLoading)
                .help("Refresh now")
            }

            if client.rows.isEmpty {
                Text(client.isLoading ? "Loading…" : "No Claude profiles found")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            } else {
                ForEach(client.rows) { row in
                    ProfileRowView(row: row)
                }
            }

            Divider()

            HStack {
                if let updated = client.lastUpdated {
                    Text("Updated \(updated.formatted(date: .omitted, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .buttonStyle(.borderless)
            }
        }
        .padding(14)
        .frame(width: 300)
        .task {
            if client.rows.isEmpty { await client.refresh() }
        }
    }
}

private struct ProfileRowView: View {
    let row: ProfileUsage

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(row.profile.displayName)
                .font(.subheadline.bold())

            if let usage = row.usage {
                meter("5h", usage.fiveHour)
                meter("7d", usage.sevenDay)
            } else {
                Text(row.error ?? "unavailable")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private func meter(_ label: String, _ window: UsageWindow?) -> some View {
        if let window {
            let pct = min(max(window.utilization, 0), 100)
            HStack(spacing: 8) {
                Text(label)
                    .font(.caption.monospaced())
                    .frame(width: 22, alignment: .leading)
                    .foregroundStyle(.secondary)
                ProgressView(value: pct, total: 100)
                    .tint(tint(for: pct))
                Text("\(Int(pct))%")
                    .font(.caption.monospaced())
                    .frame(width: 36, alignment: .trailing)
            }
        }
    }

    private func tint(for pct: Double) -> Color {
        switch pct {
        case ..<60: return .green
        case ..<85: return .yellow
        default: return .red
        }
    }
}
