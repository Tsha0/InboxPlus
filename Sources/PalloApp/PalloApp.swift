import SwiftUI
import PalloFeatures
import PalloGateway
import PalloUI

@main
struct PalloApp: App {
    @Environment(\.openWindow) private var openWindow
    @State private var model = PalloAppModel(
        gateway: InMemoryMessagingGateway(seed: Fixtures.snapshot),
        directory: Fixtures.directory
    )

    var body: some Scene {
        WindowGroup(id: "main") {
            RootView(model: model)
                .task {
                    do { try await model.start() }
                    catch { model.reportStartupFailure(error) }
                }
        }
        .windowResizability(.contentMinSize)

        MenuBarExtra {
            MenuBarContentView(health: model.health) { openWindow(id: "main") }
        } label: {
            Image(systemName: model.health.symbolName)
                .accessibilityLabel(model.health.menuBarTitle)
        }
    }
}
