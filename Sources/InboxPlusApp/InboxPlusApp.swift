import AppKit
import SwiftUI
import InboxPlusFeatures
import InboxPlusGateway
import InboxPlusUI

/// `swift run Inbox+` produces a bare executable rather than an `.app` bundle, and macOS
/// starts unbundled processes as background-only: the window draws but can never become
/// key, so it takes no clicks, no keyboard focus, and gets no menu bar. Promoting the
/// process to a regular app at launch is what makes the UI usable.
@MainActor
final class InboxPlusAppDelegate: NSObject, NSApplicationDelegate {
    /// Held for the process lifetime; a cancelled source stops delivering.
    private var terminationSignals: [DispatchSourceSignal] = []
    var shutdown: (@MainActor () async -> Void)?
    private var terminationDeadline: Task<Void, Never>?
    private var hasRepliedToTermination = false
    private var isTerminating = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        watchForTerminationSignals()
    }

    /// Routes `SIGTERM` and `SIGINT` through the normal quit path.
    ///
    /// Their default behaviour kills the process outright, which skips `applicationShouldTerminate`
    /// and leaves the runtime running with nothing attached to it. Anyone stopping Inbox+ from a
    /// terminal — or any tool that does — should get the same clean shutdown as ⌘Q.
    ///
    /// `SIGKILL` cannot be caught, so a runtime can still be orphaned by one; the next launch
    /// attaches to it rather than failing, which is what makes that survivable.
    private func watchForTerminationSignals() {
        for number in [SIGTERM, SIGINT] {
            // The default action has to be ignored, or it fires before the source is handled.
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
            source.setEventHandler { NSApplication.shared.terminate(nil) }
            source.resume()
            terminationSignals.append(source)
        }
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

    /// Disconnect clients before exit, with a bounded wait so quitting always completes.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !isTerminating else { return .terminateLater }
        ManagedRuntime.shared.requestStop()
        guard let shutdown else { return .terminateNow }
        isTerminating = true
        terminationDeadline = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.finishTermination(sender)
        }
        Task { [weak self] in
            await shutdown()
            self?.finishTermination(sender)
        }
        return .terminateLater
    }

    private func finishTermination(_ sender: NSApplication) {
        guard !hasRepliedToTermination else { return }
        hasRepliedToTermination = true
        terminationDeadline?.cancel()
        sender.reply(toApplicationShouldTerminate: true)
    }

}

@main
struct InboxPlusApp: App {
    @NSApplicationDelegateAdaptor(InboxPlusAppDelegate.self) private var appDelegate
    @Environment(\.openWindow) private var openWindow
    @State private var model = {
        let services = GatewaySelection.makeServices()
        return InboxPlusAppModel(
            gateway: services.gateway,
            directory: services.directory,
            media: services.media
        )
    }()

    var body: some Scene {
        WindowGroup("Inbox+", id: "main") {
            RootView(model: model, makeLoginSession: BridgeSelection.makeProvider())
                .task {
                    appDelegate.shutdown = { await model.shutdown() }
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
            MenuBarContentView(
                health: model.health,
                accounts: model.accounts,
                isAccountConnected: model.isConnected,
                openWindow: showMainWindow,
                onConnect: { platform in
                    // The login sheet presents from the main window, so hand the request over
                    // and raise the window for RootView to pick it up.
                    model.requestConnection(to: platform)
                    showMainWindow()
                }
            )
        } label: {
            Image(systemName: model.health.symbolName)
                .accessibilityLabel(model.health.menuBarTitle)
        }
        // A window-style panel, not a menu: the connections list needs rows with status dots
        // and Connect buttons, which a flattened menu cannot render.
        .menuBarExtraStyle(.window)
    }

    /// Reopening from the menu bar has to raise the app too — the click activates the
    /// status item, not Inbox+, so without this the restored window stays behind whatever
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
