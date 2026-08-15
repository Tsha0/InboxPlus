import AppKit
import SwiftUI
import PalloFeatures
import PalloGateway
import PalloUI

/// `swift run Pallo` produces a bare executable rather than an `.app` bundle, and macOS
/// starts unbundled processes as background-only: the window draws but can never become
/// key, so it takes no clicks, no keyboard focus, and gets no menu bar. Promoting the
/// process to a regular app at launch is what makes the UI usable.
final class PalloAppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Launched from a terminal the shell owns the foreground, and cooperative
        // activation will not hand it over, so this has to ignore other apps to come up
        // in front rather than behind the window the user launched it from.
        NSApplication.shared.activate(ignoringOtherApps: true)
        NSApplication.shared.windows.first { $0.canBecomeKey }?.makeKeyAndOrderFront(nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

@main
struct PalloApp: App {
    @NSApplicationDelegateAdaptor(PalloAppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow
    @State private var model = {
        let services = GatewaySelection.makeServices()
        return PalloAppModel(
            gateway: services.gateway,
            directory: services.directory,
            media: services.media
        )
    }()

    var body: some Scene {
        WindowGroup("Pallo", id: "main") {
            RootView(model: model, makeLoginSession: BridgeSelection.makeProvider())
                .task {
                    do { try await model.start() }
                    catch is CancellationError {}
                    catch { model.reportStartupFailure(error) }
                }
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }

        MenuBarExtra {
            MenuBarContentView(health: model.health, openWindow: showMainWindow)
        } label: {
            Image(systemName: model.health.symbolName)
                .accessibilityLabel(model.health.menuBarTitle)
        }
    }

    /// Reopening from the menu bar has to raise the app too — the click activates the
    /// status item, not Pallo, so without this the restored window stays behind whatever
    /// the user was last in.
    private func showMainWindow() {
        if let existing = NSApplication.shared.windows.first(where: { $0.canBecomeKey }) {
            existing.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: "main")
        }
        NSApplication.shared.activate()
    }
}
