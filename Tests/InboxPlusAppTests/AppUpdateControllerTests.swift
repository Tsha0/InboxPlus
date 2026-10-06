import Foundation
import Testing
import Sparkle
@testable import InboxPlusApp

@MainActor
@Test func sparklesOptionalObjectiveCCallbacksAreActuallyExported() {
    let controller = AppUpdateController()
    for selector in [
        "updater:didFindValidUpdate:",
        "updater:willInstallUpdate:",
        "updater:willInstallUpdateOnQuit:immediateInstallationBlock:",
        "updater:userDidMakeChoice:forUpdate:state:",
        "updater:didAbortWithError:",
        "standardUserDriverShouldHandleShowingScheduledUpdate:andInImmediateFocus:",
        "standardUserDriverWillHandleShowingUpdate:forUpdate:state:",
    ] {
        #expect(controller.responds(to: NSSelectorFromString(selector)))
    }
}

@Test func updatesRequireAnAppBundleHTTPSAndARealPublicKey() {
    let key = Data(repeating: 1, count: 32).base64EncodedString()
    var info: [String: Any] = [
        "InboxPlusUpdatesEnabled": true,
        "SUFeedURL": "https://example.com/appcast.xml",
        "SUPublicEDKey": key,
    ]
    let app = URL(fileURLWithPath: "/Applications/Inbox+.app")
    #expect(AppUpdateConfiguration.isEnabled(bundleURL: app, info: info))
    #expect(!AppUpdateConfiguration.isEnabled(bundleURL: app.deletingLastPathComponent(), info: info))
    info["SUFeedURL"] = "http://example.com/appcast.xml"
    #expect(!AppUpdateConfiguration.isEnabled(bundleURL: app, info: info))
    info["SUFeedURL"] = "https://example.com/appcast.xml"
    info["SUPublicEDKey"] = "placeholder"
    #expect(!AppUpdateConfiguration.isEnabled(bundleURL: app, info: info))
    info["SUPublicEDKey"] = key
    info["InboxPlusUpdatesEnabled"] = false
    #expect(!AppUpdateConfiguration.isEnabled(bundleURL: app, info: info))
}

@MainActor
@Test func discoveredUpdateBecomesAReadyReminderAndFailuresClearIt() {
    let controller = AppUpdateController()
    #expect(controller.presentation == nil)
    #expect(throws: NSError.self) { try controller.validateInstallation() }
    controller.found(version: "0.6.0")
    #expect(controller.presentation?.version == "0.6.0")
    #expect(controller.presentation?.isReadyToInstall == false)
    controller.found(version: "0.6.0", ready: true)
    #expect(controller.presentation?.help == "Restart to update to Inbox+ 0.6.0")
    // A failed update should never leave a button advertising a staged installation.
    let error = NSError(domain: "test", code: 1)
    let updater = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil).updater
    controller.updater(updater, didAbortWithError: error)
    #expect(controller.presentation == nil)
    // No updater starts and no network is contacted in an unbundled development run.
    controller.start(bundle: .main)
    #expect(!controller.canCheckForUpdates)
    #expect(controller.supportsGentleScheduledUpdateReminders)
    controller.installationPreflight = { throw error }
    #expect(throws: NSError.self) { try controller.validateInstallation() }
}

@Test func updateShutdownWaitsForAProcessToExit() async throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sleep")
    process.arguments = ["0.15"]
    try process.run()
    try await RuntimeExitWaiter.wait(timeout: .seconds(5)) { process.isRunning }
    #expect(!process.isRunning)
}

@Test func updateShutdownTimeoutDoesNotKillTheProcess() async throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/bin/sleep")
    process.arguments = ["10"]
    try process.run()
    defer { process.terminate(); process.waitUntilExit() }
    await #expect(throws: NSError.self) {
        try await RuntimeExitWaiter.wait(timeout: .zero) { process.isRunning }
    }
    #expect(process.isRunning)
}
