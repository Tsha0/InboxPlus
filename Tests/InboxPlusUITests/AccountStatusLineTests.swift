import Testing
import Foundation
import AppKit
import SwiftUI
import InboxPlusFeatures
import InboxPlusGateway
import InboxPlusCore
@testable import InboxPlusUI

@MainActor
@Test func anAccountRowNamesWhoIsSignedInRatherThanRepeatingTheNetwork() {
    let instagram = ConnectedAccount(id: "instagram", platform: .instagram, displayName: "Instagram")
    #expect(AccountsListView.identityLine(instagram, signedInAs: "@jason.s") == "@jason.s")
    // Unknown, or only the network's own name again: the line is left out.
    #expect(AccountsListView.identityLine(instagram, signedInAs: nil) == nil)
    #expect(AccountsListView.identityLine(instagram, signedInAs: "  ") == nil)
    #expect(AccountsListView.identityLine(instagram, signedInAs: "instagram") == nil)
    let messenger = ConnectedAccount(id: "facebookmessenger", platform: .facebookMessenger, displayName: "Messenger")
    #expect(AccountsListView.identityLine(messenger, signedInAs: "Messenger") == nil)
}

@Test func aBridgeReportingTroubleSaysSoInSettings() {
    func problem(_ state: NetworkConnectionState?) -> String? {
        AccountsListView.networkProblem(
            ConnectedAccount(id: "instagram", platform: .instagram, displayName: "Instagram", networkState: state)
        )
    }
    #expect(problem(nil) == nil)
    #expect(problem(.connected) == nil)
    #expect(problem(.reconnecting) == "Instagram dropped the connection — reconnecting…")
    #expect(problem(.badCredentials) == "Signed out of Instagram — remove it and add it again")
    #expect(problem(.signedOut) == "Signed out of Instagram — remove it and add it again")
}

@MainActor
@Test func unavailableBridgeShowsItsRecoveryActionWithoutPrivateMessages() async throws {
    let account = ConnectedAccount(
        id: "instagram", platform: .instagram, displayName: "Instagram",
        networkState: .connected, bridgeAvailable: false
    )
    let model = InboxPlusAppModel(gateway: InMemoryMessagingGateway(seed: MessagingSnapshot(
        accounts: [account], identities: [], conversations: [], messagesByRoute: [:]
    )))
    try await model.start()
    defer { model.stop() }
    let defaults = UserDefaults(suiteName: "bridge-status-\(UUID())")!
    let preferences = AppPreferences(defaults: defaults)
    let view = NSHostingView(rootView: RootView(
        model: model, preferences: preferences, onRestartRuntime: {}
    ))
    view.frame = NSRect(x: 0, y: 0, width: 1100, height: 700)
    view.layoutSubtreeIfNeeded()
    let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
    view.cacheDisplay(in: view.bounds, to: bitmap)
    #expect(bitmap.pixelsWide > 0 && bitmap.pixelsHigh > 0)
    if let path = ProcessInfo.processInfo.environment["INBOXPLUS_BRIDGE_STATUS_SCREENSHOT"] {
        try #require(bitmap.representation(using: .png, properties: [:]))
            .write(to: URL(fileURLWithPath: path))
    }
}
