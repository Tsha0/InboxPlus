import Foundation
import Testing
import InboxPlusCore
import InboxPlusRuntime
@testable import InboxPlusMatrix

private let policy = BridgeInvitePolicy.forBridges(ids: ["instagram", "whatsapp"], serverName: "inboxplus.local")
private let me = "@inboxplus:inboxplus.local"

@Test func aRoomWithOnlyABridgeBotIsTheBridgesManagementRoom() {
    #expect(MatrixMessagingGateway.isManagementRoom(
        memberIDs: [me, "@instagrambot:inboxplus.local"], ownUserID: me, policy: policy
    ))
}

@Test func aRoomWithAPersonInItIsAConversation() {
    // A portal holds the bot, the other person's ghost and this account's own ghost.
    #expect(!MatrixMessagingGateway.isManagementRoom(
        memberIDs: [me, "@instagrambot:inboxplus.local", "@instagram_123:inboxplus.local"],
        ownUserID: me, policy: policy
    ))
    #expect(!MatrixMessagingGateway.isManagementRoom(
        memberIDs: [me, "@instagram_123:inboxplus.local"], ownUserID: me, policy: policy
    ))
}

@Test func aRoomWithNobodyElseOrAStrangerIsNotAManagementRoom() {
    #expect(!MatrixMessagingGateway.isManagementRoom(memberIDs: [me], ownUserID: me, policy: policy))
    #expect(!MatrixMessagingGateway.isManagementRoom(
        memberIDs: [me, "@instagrambot:elsewhere.example"], ownUserID: me, policy: policy
    ))
    #expect(!MatrixMessagingGateway.isManagementRoom(
        memberIDs: [me, "@friend:inboxplus.local"], ownUserID: me, policy: policy
    ))
}

@Test func onlyABridgesOwnBotCountsAsItsBot() {
    #expect(policy.isBridgeBot("@instagrambot:inboxplus.local"))
    #expect(policy.isBridgeBot("@whatsappbot:inboxplus.local"))
    #expect(!policy.isBridgeBot("@instagram_bot:inboxplus.local"))
    #expect(!policy.isBridgeBot("@telegrambot:inboxplus.local"))
    #expect(!policy.isBridgeBot("@instagrambot:elsewhere.example"))
}

@Test func bridgeStatusNoticesBecomeNetworkStates() {
    #expect(BridgeStateNotice.state(in: "State update for Alex Rivera: CONNECTED") == .connected)
    #expect(BridgeStateNotice.state(in: """
    State update for Alex Rivera: TRANSIENT_DISCONNECT (ig-dgw-connection-error) not resolved after \
    waiting 3 minutes: Disconnected from server, trying to reconnect
    """) == .reconnecting)
    #expect(BridgeStateNotice.state(in: "State update for Alex: BAD_CREDENTIALS (session expired)") == .badCredentials)
    #expect(BridgeStateNotice.state(in: "State update for Alex: LOGGED_OUT") == .signedOut)
}

@Test func otherNoticesAreNotNetworkStates() {
    #expect(BridgeStateNotice.state(in: "Successfully logged in as alex") == nil)
    #expect(BridgeStateNotice.state(in: "State update for Alex: SOMETHING_NEW") == nil)
    #expect(BridgeStateNotice.state(in: "State update for Alex") == nil)
    #expect(BridgeStateNotice.state(in: "") == nil)
}

private actor BridgeAvailabilityFixture {
    var available = true
    func setAvailable(_ value: Bool) { available = value }
    func check() -> [String: Bool] { ["instagram": available] }
}

@Test func bridgeAvailabilityIsDebouncedAndPublishesRecoveryWithoutNewNotices() async throws {
    let fixture = BridgeAvailabilityFixture()
    let paths = try RuntimePaths(
        root: URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Caches/bridge-status-test"),
        profileName: "isolated"
    )
    let url = URL(string: "http://127.0.0.1:18008")!
    let client = InboxPlusMatrixClient(
        homeserverURL: url,
        store: MatrixClientStore(profile: paths),
        provisioner: try MatrixAccountProvisioner(baseURL: url, serverName: "test.local", registrationSecret: "fixture")
    )
    let gateway = MatrixMessagingGateway(
        client: client,
        bridgeAccounts: [BridgeAccountDescriptor(bridgeID: "instagram", platform: .instagram, displayName: "Instagram")],
        bridgeAvailabilityProvider: { await fixture.check() }
    )
    _ = await gateway.accounts(owning: ["instagram"])
    let stream = await gateway.events()
    var events = stream.makeAsyncIterator()
    await gateway.refreshBridgeAvailability()
    guard case let .accountUpserted(initial) = await events.next() else {
        Issue.record("Missing initial availability event"); return
    }
    #expect(initial.bridgeAvailable == true)
    await fixture.setAvailable(false)
    await gateway.refreshBridgeAvailability()
    #expect(await gateway.bridgeAccount("instagram")?.bridgeAvailable == true)
    await gateway.refreshBridgeAvailability()
    guard case let .accountUpserted(unavailable) = await events.next() else {
        Issue.record("Missing unavailable event"); return
    }
    #expect(unavailable.bridgeAvailable == false)
    await fixture.setAvailable(true)
    await gateway.refreshBridgeAvailability()
    guard case let .accountUpserted(recovered) = await events.next() else {
        Issue.record("Missing recovery event"); return
    }
    #expect(recovered.bridgeAvailable == true)
}

@Test func aRespondingPreparedBridgeDoesNotCreateAConnectedAccount() async throws {
    let fixture = BridgeAvailabilityFixture()
    let paths = try RuntimePaths(
        root: URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Caches/bridge-status-test"),
        profileName: "isolated"
    )
    let url = URL(string: "http://127.0.0.1:18008")!
    let client = InboxPlusMatrixClient(
        homeserverURL: url,
        store: MatrixClientStore(profile: paths),
        provisioner: try MatrixAccountProvisioner(baseURL: url, serverName: "test.local", registrationSecret: "fixture")
    )
    let gateway = MatrixMessagingGateway(
        client: client,
        bridgeAccounts: [BridgeAccountDescriptor(bridgeID: "instagram", platform: .instagram, displayName: "Instagram")],
        bridgeAvailabilityProvider: { await fixture.check() }
    )
    let stream = await gateway.events()
    let collected = Task {
        var count = 0
        for await _ in stream { count += 1 }
        return count
    }
    await gateway.refreshBridgeAvailability()
    #expect(await gateway.accounts(owning: [String]()).map(\.id) == [MatrixMessagingGateway.defaultAccountID])
    await gateway.stop()
    #expect(await collected.value == 0)
}

@Test func removingAnAccountPreventsLaterProbesFromBringingItBack() async throws {
    let fixture = BridgeAvailabilityFixture()
    let paths = try RuntimePaths(
        root: URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Caches/bridge-status-test"),
        profileName: "isolated"
    )
    let url = URL(string: "http://127.0.0.1:18008")!
    let client = InboxPlusMatrixClient(
        homeserverURL: url,
        store: MatrixClientStore(profile: paths),
        provisioner: try MatrixAccountProvisioner(baseURL: url, serverName: "test.local", registrationSecret: "fixture")
    )
    let gateway = MatrixMessagingGateway(
        client: client,
        bridgeAccounts: [BridgeAccountDescriptor(bridgeID: "instagram", platform: .instagram, displayName: "Instagram")],
        bridgeAvailabilityProvider: { await fixture.check() }
    )
    _ = await gateway.accounts(owning: ["instagram"])
    await gateway.refreshBridgeAvailability()
    let stream = await gateway.events()
    let collected = Task {
        var count = 0
        for await _ in stream { count += 1 }
        return count
    }
    await gateway.forgetBridgeAccount("instagram")
    await fixture.setAvailable(false)
    await gateway.refreshBridgeAvailability()
    await gateway.refreshBridgeAvailability()
    await fixture.setAvailable(true)
    await gateway.refreshBridgeAvailability()
    await gateway.stop()
    #expect(await collected.value == 0)
}
