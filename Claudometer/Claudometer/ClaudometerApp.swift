//
//  ClaudometerApp.swift
//  Claudometer
//
//  Created by Jackson Ly on 13.06.26.
//

import SwiftUI
import Application
import Infrastructure
import Presentation

/// Composition root.
///
/// This is the ONLY place allowed to import `Infrastructure`: it wires the
/// concrete Keychain + HTTP adapters into the use case, then hands the
/// presentation layer a view model that knows nothing about either.
@main
struct ClaudometerApp: App {
    @State private var viewModel = MenuBarViewModel(
        refreshUsage: RefreshUsageUseCase(
            directory: KeychainProfileDirectory(),
            provider: AnthropicUsageProvider()
        )
    )

    var body: some Scene {
        MenuBarExtra("Claudometer", systemImage: "gauge.with.dots.needle.50percent") {
            MenuView(viewModel: viewModel)
        }
        .menuBarExtraStyle(.window)
    }
}
