import AppKit
import SwiftUI
import InboxPlusBridge
import Testing
@testable import InboxPlusCore
@testable import InboxPlusUI

@Test func installOutcomeNamesTheNetworkItInstalled() {
    for platform in Platform.allCases {
        let outcome = BridgeInstallOutcome(platform: platform, profile: "demo")
        #expect(outcome.title.contains(platform.accessibilityLabel))
        #expect(outcome.message.contains(platform.accessibilityLabel))
    }
}

@Test func installOutcomeNamesTheExternalOwnersActionWithoutAnAppRelaunch() {
    let outcome = BridgeInstallOutcome(platform: .telegram, profile: "work")
    #expect(outcome.message.contains("Restart the runtime"))
    #expect(outcome.message.contains("'work'"))
    #expect(outcome.message.contains("leave Inbox+ open"))
    #expect(!outcome.message.contains("Quit"))
}

@MainActor
@Test func removingAnAccountPromisesOnlyWhatRemovalDoes() {
    let explanation = AccountsListView.removalExplanation(for: "Telegram")
    // Removal cannot delete what the network itself keeps, so it must not claim every message is gone.
    #expect(!explanation.contains("Every conversation and message"))
    #expect(explanation.contains("signs out of Telegram"))
    #expect(explanation.contains("Your messages stay on Telegram itself"))
}

@Test func bridgeDownloadProgressUsesRealByteCountsAndHandlesUnknownSizes() {
    #expect(BridgeSetupProgress.downloading(received: 40, total: 100).fractionCompleted == 0.4)
    #expect(BridgeSetupProgress.downloading(received: 40, total: nil).fractionCompleted == nil)
    #expect(BridgeSetupProgress.downloading(received: 40, total: 0).fractionCompleted == nil)
    #expect(BridgeSetupProgress.downloading(received: 120, total: 100).fractionCompleted == 1)
    #expect(BridgeSetupProgress.configuring.fractionCompleted == nil)
}

@MainActor
@Test func bridgeSetupProgressLayoutsRenderWithAndWithoutADownloadSize() throws {
    let phases: [BridgeSetupProgress] = [
        .downloading(received: 40, total: 100), .downloading(received: 40, total: nil), .restarting, .syncing
    ]
    for (index, phase) in phases.enumerated() {
        let view = NSHostingView(rootView: BridgeInstallProgressView(platform: .instagram, progress: phase))
        view.frame = NSRect(x: 0, y: 0, width: 476, height: 276)
        view.layoutSubtreeIfNeeded()
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        #expect(bitmap.pixelsWide > 0 && bitmap.pixelsHigh > 0)
        if let directory = ProcessInfo.processInfo.environment["INBOXPLUS_SETUP_SCREENSHOTS"] {
            let url = URL(fileURLWithPath: directory, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try #require(bitmap.representation(using: .png, properties: [:]))
                .write(to: url.appendingPathComponent("setup-\(index).png"))
        }
    }
}
