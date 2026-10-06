import AppKit
import Combine
import Observation
import Sparkle
import InboxPlusUI

/// One process-lifetime Sparkle owner. Scheduled reminders appear in the rail;
/// clicking one brings Sparkle's signed download/install flow into focus.
@MainActor
@Observable
final class AppUpdateController: NSObject, SPUUpdaterDelegate, @preconcurrency SPUStandardUserDriverDelegate {
    static let shared = AppUpdateController()

    private(set) var presentation: AppUpdatePresentation?
    private(set) var canCheckForUpdates = false
    private(set) var installationScheduled = false
    private(set) var configurationError: String?

    @ObservationIgnored private var controller: SPUStandardUpdaterController?
    @ObservationIgnored private var checkObservation: AnyCancellable?
    @ObservationIgnored var installationPreflight: (() throws -> Void)?
    @ObservationIgnored var installationCancelled: (() -> Void)?
    @ObservationIgnored private var started = false

    /// Unbundled and unconfigured development runs never try to replace themselves.
    func start(bundle: Bundle = .main) {
        guard !started else { return }
        started = true
        #if DEBUG
        if let version = ProcessInfo.processInfo.environment["INBOXPLUS_UPDATE_PREVIEW_VERSION"] {
            found(version: version)
            return
        }
        #endif
        guard AppUpdateConfiguration.isEnabled(in: bundle) else { return }
        let controller = SPUStandardUpdaterController(
            startingUpdater: false, updaterDelegate: self, userDriverDelegate: self
        )
        self.controller = controller
        checkObservation = controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: RunLoop.main)
            .sink { [weak self] value in self?.canCheckForUpdates = value }
        do { try controller.updater.start() }
        catch { configurationError = error.localizedDescription }
    }

    func checkForUpdates() {
        // Sparkle also uses this call to focus an update session already in progress.
        guard let controller else { return }
        controller.checkForUpdates(nil)
    }

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        // Critical and information-only notices still need Sparkle's full explanation.
        update.isCriticalUpdate || update.isInformationOnlyUpdate
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState
    ) {
        found(version: update.displayVersionString, ready: state.stage != .notDownloaded)
    }

    // Dismissing the standard window keeps the rail reminder available for a later click.
    func updater(
        _ updater: SPUUpdater, userDidMake choice: SPUUserUpdateChoice,
        forUpdate item: SUAppcastItem, state: SPUUserUpdateState
    ) {
        if choice == .skip {
            presentation = nil
            installationScheduled = false
        }
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        found(version: item.displayVersionString)
    }

    func updater(_ updater: SPUUpdater, didNotFindUpdateWithError error: Error) {
        presentation = nil
    }

    func validateInstallation() throws {
        guard let installationPreflight else {
            throw NSError(domain: "InboxPlus.Update", code: 3, userInfo: [
                NSLocalizedDescriptionKey: "Inbox+ is still starting. Try the update again in a moment."
            ])
        }
        try installationPreflight()
    }

    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) {
        installationScheduled = true
    }

    func updater(
        _ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
        immediateInstallationBlock immediateInstallHandler: @escaping () -> Void
    ) -> Bool {
        installationScheduled = true
        found(version: item.displayVersionString, ready: true)
        // Let Sparkle keep scheduling; the app's normal termination gate covers installation on quit.
        return false
    }

    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        installationScheduled = false
        presentation = nil
    }

    func found(version: String, ready: Bool = false) {
        presentation = AppUpdatePresentation(version: version, isReadyToInstall: ready)
    }
}

enum AppUpdateConfiguration {
    static func isEnabled(in bundle: Bundle) -> Bool {
        isEnabled(bundleURL: bundle.bundleURL, info: bundle.infoDictionary ?? [:])
    }

    static func isEnabled(bundleURL: URL, info: [String: Any]) -> Bool {
        guard bundleURL.pathExtension == "app",
              info["InboxPlusUpdatesEnabled"] as? Bool == true,
              let feed = info["SUFeedURL"] as? String,
              let url = URL(string: feed), url.scheme == "https", url.host != nil,
              let key = info["SUPublicEDKey"] as? String,
              Data(base64Encoded: key)?.count == 32 else { return false }
        return true
    }
}
