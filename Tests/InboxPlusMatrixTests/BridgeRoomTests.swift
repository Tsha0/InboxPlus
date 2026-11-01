import Foundation
import Testing
import InboxPlusCore
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
