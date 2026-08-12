import AppKit
import SwiftUI
import PalloFeatures

public struct MenuBarContentView: View {
    let health: ServiceHealth
    let openWindow: () -> Void

    public init(health: ServiceHealth, openWindow: @escaping () -> Void) {
        self.health = health
        self.openWindow = openWindow
    }

    public var body: some View {
        Text(health.menuBarTitle)
        Divider()
        Button("Open Pallo", action: openWindow)
        Button("Quit Pallo") { NSApplication.shared.terminate(nil) }
    }
}
