import AppKit
import Observation
import ServiceManagement
import InboxPlusUI

/// Opening at login is owned by macOS, so the state is read back from it rather than remembered.
@MainActor
@Observable
final class LaunchAtLoginController {
    static let shared = LaunchAtLoginController()

    private(set) var status: LaunchAtLoginStatus = .unavailable

    func refresh(bundle: Bundle = .main) {
        status = Self.status(of: SMAppService.mainApp.status, isAppBundle: bundle.bundleURL.pathExtension == "app")
    }

    func setEnabled(_ enabled: Bool) throws {
        defer { refresh() }
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    /// A bare `swift run` executable is not an app macOS can open at login.
    static func status(of service: SMAppService.Status, isAppBundle: Bool) -> LaunchAtLoginStatus {
        guard isAppBundle else { return .unavailable }
        switch service {
        case .enabled: return .on
        case .requiresApproval: return .needsApproval
        case .notRegistered, .notFound: return .off
        @unknown default: return .off
        }
    }
}

/// Keeps the Dock icon's badge on the unread count, whether or not a window is open.
@MainActor
final class DockBadgeController {
    static let shared = DockBadgeController()
    private var count: (@MainActor () -> Int)?

    func start(count: @escaping @MainActor () -> Int) {
        guard self.count == nil else { return }
        self.count = count
        update()
    }

    private func update() {
        guard let count else { return }
        let current = withObservationTracking {
            count()
        } onChange: {
            Task { @MainActor [weak self] in self?.update() }
        }
        NSApplication.shared.dockTile.badgeLabel = UnreadBadge.label(for: current)
    }
}
