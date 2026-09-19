import Foundation
import Testing
@testable import MimoMatrix

private let policy = BridgeInvitePolicy.forBridges(
    ids: ["instagram", "whatsapp"],
    serverName: "mimo.localhost"
)

@Test func aBridgeGhostAndItsBotMayInvite() {
    // A bridge creates a portal and invites the user; refusing these means an account can be fully
    // connected and still show nothing.
    #expect(policy.trusts(inviterUserID: "@instagram_17841400000000000:mimo.localhost"))
    #expect(policy.trusts(inviterUserID: "@instagrambot:mimo.localhost"))
    #expect(policy.trusts(inviterUserID: "@whatsapp_15551234567:mimo.localhost"))
}

@Test func anOrdinaryLocalUserMayNotPutARoomInTheInbox() {
    #expect(!policy.trusts(inviterUserID: "@mallory:mimo.localhost"))
    #expect(!policy.trusts(inviterUserID: "@mimo:mimo.localhost"))
}

@Test func aBridgeThatIsNotPreparedIsNotTrusted() {
    #expect(!policy.trusts(inviterUserID: "@telegram_777000:mimo.localhost"))
    #expect(!policy.trusts(inviterUserID: "@telegrambot:mimo.localhost"))
}

@Test func aLocalpartThatMerelyLooksLikeABridgeIsRejected() {
    // `instagramy` shares a prefix with the bridge id but not with its namespace.
    #expect(!policy.trusts(inviterUserID: "@instagram:mimo.localhost"))
    #expect(!policy.trusts(inviterUserID: "@instagramy:mimo.localhost"))
}

@Test func anInviterFromAnotherServerIsRejected() {
    // Federation is off, so this cannot happen today; pinning the server name keeps the rule true
    // rather than true by accident.
    #expect(!policy.trusts(inviterUserID: "@instagram_1:evil.example"))
    #expect(!policy.trusts(inviterUserID: "@instagrambot:mimo.localhost.evil.example"))
}

@Test(arguments: ["", "instagram_1:mimo.localhost", "@instagram_1", "@", "@:", "not-a-user"])
func amalformedInviterIsRejectedRatherThanParsedLoosely(_ inviter: String) {
    #expect(!policy.trusts(inviterUserID: inviter))
}

@Test func aProfileWithNoBridgesTrustsNobody() {
    let none = BridgeInvitePolicy.forBridges(ids: [], serverName: "mimo.localhost")
    #expect(!none.trusts(inviterUserID: "@instagrambot:mimo.localhost"))
    #expect(!BridgeInvitePolicy.trustingNobody.trusts(inviterUserID: "@instagrambot:mimo.localhost"))
}

// MARK: - Attribution

@Test func aRoomIsAttributedToTheBridgeWhoseGhostIsInIt() {
    // A portal room always contains the bridge's own ghost or bot, and that membership is the only
    // reliable statement of which network the conversation actually is. Reporting Matrix reports
    // the transport rather than what the user is looking at.
    #expect(policy.bridgeID(owning: "@instagram_17841400000000000:mimo.localhost") == "instagram")
    #expect(policy.bridgeID(owning: "@instagrambot:mimo.localhost") == "instagram")
    #expect(policy.bridgeID(owning: "@whatsapp_15551234567:mimo.localhost") == "whatsapp")
}

@Test func anOrdinaryUserAttributesToNoBridge() {
    #expect(policy.bridgeID(owning: "@mimo:mimo.localhost") == nil)
    #expect(policy.bridgeID(owning: "@maya:mimo.localhost") == nil)
    // Same prefix, different namespace — `instagram` alone is not a ghost.
    #expect(policy.bridgeID(owning: "@instagram:mimo.localhost") == nil)
    #expect(policy.bridgeID(owning: "@instagramy:mimo.localhost") == nil)
}

@Test func attributionIsPinnedToTheLocalServer() {
    // Federation is off, but a remote user must never be able to claim a bridge's namespace.
    #expect(policy.bridgeID(owning: "@instagram_1:evil.example") == nil)
    #expect(policy.bridgeID(owning: "@instagrambot:mimo.localhost.evil.example") == nil)
}

@Test func theLongerBridgeIdentifierWinsWhenTwoCouldMatch() {
    // `whatsapp` is a prefix of `whatsappbusiness`, so a shortest-first match would file every
    // business conversation under the wrong account.
    let overlapping = BridgeInvitePolicy.forBridges(
        ids: ["whatsapp", "whatsappbusiness"],
        serverName: "mimo.localhost"
    )
    #expect(overlapping.bridgeID(owning: "@whatsappbusiness_1:mimo.localhost") == "whatsappbusiness")
    #expect(overlapping.bridgeID(owning: "@whatsapp_1:mimo.localhost") == "whatsapp")
}

@Test func aProfileWithNoBridgesAttributesNothing() {
    #expect(BridgeInvitePolicy.trustingNobody.bridgeID(owning: "@instagram_1:mimo.localhost") == nil)
}

@Test(arguments: ["", "instagram_1:mimo.localhost", "@instagram_1", "@", "@:", "not-a-user"])
func amalformedUserAttributesToNothing(_ userID: String) {
    #expect(policy.bridgeID(owning: userID) == nil)
}
