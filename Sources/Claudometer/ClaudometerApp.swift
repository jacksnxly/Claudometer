import SwiftUI

@main
struct ClaudometerApp: App {
    @State private var client = UsageClient()

    var body: some Scene {
        MenuBarExtra("Claudometer", systemImage: "gauge.with.dots.needle.50percent") {
            MenuView(client: client)
        }
        .menuBarExtraStyle(.window)
    }
}
