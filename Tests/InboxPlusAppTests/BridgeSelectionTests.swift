import Foundation
import InboxPlusBridgeService
import InboxPlusRuntime
import InboxPlusTestSupport
import InboxPlusUI
import Testing
@testable import InboxPlusApp

private func runningSession() throws -> BridgeProvisioningClient {
    try BridgeProvisioningClient(
        baseURL: URL(string: "http://127.0.0.1:29337")!,
        provisioningToken: "provisioning-secret", userID: "@inboxplus:inboxplus.localhost",
        transport: DummyBridge(script: .instagram)
    )
}

private func stoppedSession() throws -> BridgeProvisioningClient {
    try BridgeProvisioningClient(
        baseURL: URL(string: "http://127.0.0.1:\(try LoopbackPortAllocator().allocate())")!,
        provisioningToken: "provisioning-secret", userID: "@inboxplus:inboxplus.localhost"
    )
}

@MainActor
@Test func aNewBridgeRefreshesOwnedServicesAndContinuesToLogin() async throws {
    var refreshes = 0
    let preparation = try await BridgeSelection.loginPreparation(
        for: .instagram, profileName: "default", session: runningSession(),
        requiresRefresh: true, canRefresh: true,
        refreshRuntime: { refreshes += 1 }
    )
    guard case .ready = preparation else { Issue.record("expected login after refresh"); return }
    #expect(refreshes == 1)
}

@MainActor
@Test func aRunningBridgeOpensItsLoginWithoutRefreshingServices() async throws {
    let preparation = try await BridgeSelection.loginPreparation(
        for: .instagram, profileName: "default", session: runningSession(),
        requiresRefresh: false, canRefresh: true,
        refreshRuntime: { Issue.record("an already running bridge must not interrupt other networks") }
    )
    guard case .ready = preparation else { Issue.record("expected a login session"); return }
}

@MainActor
@Test func aNewBridgeNeverRestartsAnExternalRuntime() async throws {
    let preparation = try await BridgeSelection.loginPreparation(
        for: .instagram, profileName: "work", session: runningSession(),
        requiresRefresh: true, canRefresh: false,
        refreshRuntime: { Issue.record("external runtime was taken over") }
    )
    guard case let .waitingForExternalRuntime(outcome) = preparation else {
        Issue.record("expected the specific external runtime action"); return
    }
    #expect(outcome.profile == "work")
    #expect(outcome.message.contains("leave Inbox+ open"))
}

@MainActor
@Test func choosingAPreparedBridgeThatIsNotRunningWaitsForItsOwner() async throws {
    let preparation = try await BridgeSelection.loginPreparation(
        for: .instagram, profileName: "default", session: stoppedSession(),
        requiresRefresh: false, canRefresh: false, readinessTimeout: .zero,
        refreshRuntime: { Issue.record("external runtime was restarted") }
    )
    guard case .waitingForExternalRuntime = preparation else {
        Issue.record("must not open a login against a closed port"); return
    }
}

@MainActor
@Test func bridgeStartupFailureDoesNotPretendSetupCompleted() async throws {
    var refreshes = 0
    await #expect(throws: (any Error).self) {
        _ = try await BridgeSelection.loginPreparation(
            for: .instagram, profileName: "default", session: stoppedSession(),
            requiresRefresh: true, canRefresh: true, readinessTimeout: .zero,
            refreshRuntime: { refreshes += 1 }
        )
    }
    #expect(refreshes == 1)
}

@MainActor
@Test func failedRuntimeRefreshNeverContinuesToLogin() async throws {
    struct StopTimeout: Error {}
    await #expect(throws: StopTimeout.self) {
        _ = try await BridgeSelection.loginPreparation(
            for: .instagram, profileName: "default", session: runningSession(),
            requiresRefresh: true, canRefresh: true,
            refreshRuntime: { throw StopTimeout() }
        )
    }
}
