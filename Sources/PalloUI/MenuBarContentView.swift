import AppKit
import SwiftUI
import PalloCore
import PalloFeatures

/// The menu bar panel: service health up top, every network's connection state in the middle,
/// and window/app controls at the bottom.
public struct MenuBarContentView: View {
    let health: ServiceHealth
    let accounts: [ConnectedAccount]
    let isAccountConnected: (String) -> Bool
    let openWindow: () -> Void
    let onConnect: (Platform) -> Void

    public init(
        health: ServiceHealth,
        accounts: [ConnectedAccount],
        isAccountConnected: @escaping (String) -> Bool,
        openWindow: @escaping () -> Void,
        onConnect: @escaping (Platform) -> Void
    ) {
        self.health = health
        self.accounts = accounts
        self.isAccountConnected = isAccountConnected
        self.openWindow = openWindow
        self.onConnect = onConnect
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Label(health.menuBarTitle, systemImage: health.symbolName)
                .font(.headline)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

            Divider()

            PlatformConnectionsView(
                accounts: accounts,
                isAccountConnected: isAccountConnected,
                onConnect: onConnect
            )

            Divider()

            HStack {
                Button("Open Pallo", action: openWindow)
                Spacer()
                Button("Quit Pallo") { NSApplication.shared.terminate(nil) }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .frame(width: 320)
        .accessibilityIdentifier("menu-bar-panel")
    }
}
