import Foundation
import InboxPlusBridgeService
import InboxPlusRuntime
import InboxPlusTestSupport
import InboxPlusUI
import Testing
@testable import InboxPlusApp

@MainActor
@Test func choosingANetworkInstalledSinceTheRuntimeStartedAsksForTheRestartAgain() async throws {
    // Break caught: picking Instagram again right after installing it opened a login against a
    // bridge the running runtime never launched, which failed as "MatrixHTTPError error 0".
    let session = try BridgeProvisioningClient(
        baseURL: URL(string: "http://127.0.0.1:\(try LoopbackPortAllocator().allocate())")!,
        provisioningToken: "provisioning-secret",
        userID: "@inboxplus:inboxplus.localhost"
    )

    let preparation = await BridgeSelection.loginPreparation(
        for: .instagram,
        profileName: "default",
        session: session
    )

    guard case let .installedPendingRuntimeRestart(outcome) = preparation else {
        Issue.record("expected the pending restart, got a login session")
        return
    }
    #expect(outcome == BridgeInstallOutcome(platform: .instagram, profile: "default"))
}

@MainActor
@Test func aRunningBridgeOpensItsLogin() async throws {
    let session = try BridgeProvisioningClient(
        baseURL: URL(string: "http://127.0.0.1:29337")!,
        provisioningToken: "provisioning-secret",
        userID: "@inboxplus:inboxplus.localhost",
        transport: DummyBridge(script: .instagram)
    )

    let preparation = await BridgeSelection.loginPreparation(
        for: .instagram,
        profileName: "default",
        session: session
    )

    guard case .ready = preparation else {
        Issue.record("expected a login session for a bridge that answers")
        return
    }
}
