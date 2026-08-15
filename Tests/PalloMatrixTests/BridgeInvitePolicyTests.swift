import Foundation
import Testing
@testable import PalloMatrix

private let policy = BridgeInvitePolicy.forBridges(
    ids: ["instagram", "whatsapp"],
    serverName: "pallo.localhost"
)

@Test func aBridgeGhostAndItsBotMayInvite() {
    // A bridge creates a portal and invites the user; refusing these means an account can be fully
    // connected and still show nothing.
    #expect(policy.trusts(inviterUserID: "@instagram_17841400000000000:pallo.localhost"))
    #expect(policy.trusts(inviterUserID: "@instagrambot:pallo.localhost"))
    #expect(policy.trusts(inviterUserID: "@whatsapp_15551234567:pallo.localhost"))
}

@Test func anOrdinaryLocalUserMayNotPutARoomInTheInbox() {
    #expect(!policy.trusts(inviterUserID: "@mallory:pallo.localhost"))
    #expect(!policy.trusts(inviterUserID: "@pallo:pallo.localhost"))
}

@Test func aBridgeThatIsNotPreparedIsNotTrusted() {
    #expect(!policy.trusts(inviterUserID: "@telegram_777000:pallo.localhost"))
    #expect(!policy.trusts(inviterUserID: "@telegrambot:pallo.localhost"))
}

@Test func aLocalpartThatMerelyLooksLikeABridgeIsRejected() {
    // `instagramy` shares a prefix with the bridge id but not with its namespace.
    #expect(!policy.trusts(inviterUserID: "@instagram:pallo.localhost"))
    #expect(!policy.trusts(inviterUserID: "@instagramy:pallo.localhost"))
}

@Test func anInviterFromAnotherServerIsRejected() {
    // Federation is off, so this cannot happen today; pinning the server name keeps the rule true
    // rather than true by accident.
    #expect(!policy.trusts(inviterUserID: "@instagram_1:evil.example"))
    #expect(!policy.trusts(inviterUserID: "@instagrambot:pallo.localhost.evil.example"))
}

@Test(arguments: ["", "instagram_1:pallo.localhost", "@instagram_1", "@", "@:", "not-a-user"])
func amalformedInviterIsRejectedRatherThanParsedLoosely(_ inviter: String) {
    #expect(!policy.trusts(inviterUserID: inviter))
}

@Test func aProfileWithNoBridgesTrustsNobody() {
    let none = BridgeInvitePolicy.forBridges(ids: [], serverName: "pallo.localhost")
    #expect(!none.trusts(inviterUserID: "@instagrambot:pallo.localhost"))
    #expect(!BridgeInvitePolicy.trustingNobody.trusts(inviterUserID: "@instagrambot:pallo.localhost"))
}

// MARK: - Attribution

@Test func aRoomIsAttributedToTheBridgeWhoseGhostIsInIt() {
    // A portal room always contains the bridge's own ghost or bot, and that membership is the only
    // reliable statement of which network the conversation actually is. Reporting Matrix reports
    // the transport rather than what the user is looking at.
    #expect(policy.bridgeID(owning: "@instagram_17841400000000000:pallo.localhost") == "instagram")
    #expect(policy.bridgeID(owning: "@instagrambot:pallo.localhost") == "instagram")
    #expect(policy.bridgeID(owning: "@whatsapp_15551234567:pallo.localhost") == "whatsapp")
}

@Test func anOrdinaryUserAttributesToNoBridge() {
    #expect(policy.bridgeID(owning: "@pallo:pallo.localhost") == nil)
    #expect(policy.bridgeID(owning: "@maya:pallo.localhost") == nil)
    // Same prefix, different namespace — `instagram` alone is not a ghost.
    #expect(policy.bridgeID(owning: "@instagram:pallo.localhost") == nil)
    #expect(policy.bridgeID(owning: "@instagramy:pallo.localhost") == nil)
}

@Test func attributionIsPinnedToTheLocalServer() {
    // Federation is off, but a remote user must never be able to claim a bridge's namespace.
    #expect(policy.bridgeID(owning: "@instagram_1:evil.example") == nil)
    #expect(policy.bridgeID(owning: "@instagrambot:pallo.localhost.evil.example") == nil)
}

@Test func theLongerBridgeIdentifierWinsWhenTwoCouldMatch() {
    // `whatsapp` is a prefix of `whatsappbusiness`, so a shortest-first match would file every
    // business conversation under the wrong account.
    let overlapping = BridgeInvitePolicy.forBridges(
        ids: ["whatsapp", "whatsappbusiness"],
        serverName: "pallo.localhost"
    )
    #expect(overlapping.bridgeID(owning: "@whatsappbusiness_1:pallo.localhost") == "whatsappbusiness")
    #expect(overlapping.bridgeID(owning: "@whatsapp_1:pallo.localhost") == "whatsapp")
}

@Test func aProfileWithNoBridgesAttributesNothing() {
    #expect(BridgeInvitePolicy.trustingNobody.bridgeID(owning: "@instagram_1:pallo.localhost") == nil)
}

@Test(arguments: ["", "instagram_1:pallo.localhost", "@instagram_1", "@", "@:", "not-a-user"])
func amalformedUserAttributesToNothing(_ userID: String) {
    #expect(policy.bridgeID(owning: userID) == nil)
}
