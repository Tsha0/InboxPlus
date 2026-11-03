import Testing
@testable import InboxPlusMatrix

private let me = "@inboxplus:local"
private let bot = "@whatsappbot:local"
private let myPhoneGhost = "@whatsapp_15550000001:local"
private let myLIDGhost = "@whatsapp_lid-100000000000001:local"
/// The bridge lists the phone-number ghost as a service member, but not the LID one.
private let excluded: Set<String> = [me, bot, myPhoneGhost, myLIDGhost]

private func member(_ userID: String, _ displayName: String?) -> (userID: String, displayName: String?) {
    (userID, displayName)
}

@Test func anUnnamedOneToOneChatIsCalledAfterTheOtherPersonAlone() {
    let members = [
        member(me, "Jordan"),
        member(bot, "WhatsApp bridge bot"),
        member(myPhoneGhost, "Jordan (WA)"),
        member(myLIDGhost, "Jordan (WA)"),
        member("@whatsapp_15550000002:local", "Riley (WA)"),
    ]
    #expect(MatrixMessagingGateway.memberListTitle(members: members, excluding: excluded, platform: .whatsApp) == "Riley")
}

@Test func anUnnamedGroupListsAFewPeopleByNameAndCountsTheRest() {
    let others = ["Sam", "alex", "Taylor", "Casey", "Morgan"].enumerated().map { index, name in
        member("@whatsapp_1555000010\(index):local", "\(name) (WA)")
    }
    let members = [member(me, "Jordan"), member(myLIDGhost, "Jordan (WA)"), member(bot, nil)] + others
    #expect(MatrixMessagingGateway.memberListTitle(members: members, excluding: excluded, platform: .whatsApp) == "alex, Casey, Morgan and 2 others")
    #expect(MatrixMessagingGateway.memberListTitle(members: Array(members.prefix(7)), excluding: excluded, platform: .whatsApp) == "alex, Casey, Sam and 1 other")
    #expect(MatrixMessagingGateway.memberListTitle(members: Array(members.prefix(6)), excluding: excluded, platform: .whatsApp) == "alex, Sam, Taylor")
}

@Test func peopleWithoutANameAreCountedButNotNamed() {
    let members = [
        member(me, "Jordan"),
        member("@whatsapp_15550000002:local", "Riley"),
        member("@whatsapp_15550000003:local", nil),
        member("@whatsapp_15550000004:local", ""),
    ]
    #expect(MatrixMessagingGateway.memberListTitle(members: members, excluding: excluded, platform: .whatsApp) == "Riley and 2 others")
}

@Test func aRoomWithNobodyElseNamedHasNoMemberTitle() {
    #expect(MatrixMessagingGateway.memberListTitle(members: [], excluding: excluded, platform: .whatsApp) == nil)
    #expect(MatrixMessagingGateway.memberListTitle(
        members: [member(me, "Jordan"), member(myLIDGhost, "Jordan (WA)"), member("@whatsapp_15550000002:local", nil)],
        excluding: excluded, platform: .whatsApp
    ) == nil)
}

@Test func namesFromOtherNetworksKeepTheirSuffixesInMemberTitles() {
    let members = [member("@matrix_riley:local", "Riley (WA)")]
    #expect(MatrixMessagingGateway.memberListTitle(members: members, excluding: [], platform: .matrix) == "Riley (WA)")
}
