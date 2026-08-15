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
