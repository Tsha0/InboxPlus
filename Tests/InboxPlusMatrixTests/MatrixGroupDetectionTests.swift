import Testing
@testable import InboxPlusMatrix

@Test func aBridgedDirectChatIsNotAGroupWithoutTheDirectFlag() {
    // This account, the bridge bot, the other person and this account's own network identity.
    #expect(!MatrixMessagingGateway.isGroup(
        isDirect: false, joinedMembers: 4,
        serviceMembers: ["@instagrambot:local", "@instagram_other:local"],
        ownIdentities: ["@instagram_me:local", "$event"]
    ))
    #expect(!MatrixMessagingGateway.isGroup(
        isDirect: false, joinedMembers: 4,
        serviceMembers: ["@instagrambot:local"],
        ownIdentities: ["@instagram_me:local"]
    ))
}

@Test func aBridgedRoomWithSeveralOtherPeopleIsAGroup() {
    #expect(MatrixMessagingGateway.isGroup(
        isDirect: false, joinedMembers: 27,
        serviceMembers: ["@instagrambot:local", "@instagram_admin:local"],
        ownIdentities: ["@instagram_me:local"]
    ))
    #expect(MatrixMessagingGateway.isGroup(
        isDirect: false, joinedMembers: 4,
        serviceMembers: [],
        ownIdentities: []
    ))
}

@Test func aRoomMarkedDirectIsNeverAGroup() {
    #expect(!MatrixMessagingGateway.isGroup(
        isDirect: true, joinedMembers: 50, serviceMembers: [], ownIdentities: []
    ))
}
