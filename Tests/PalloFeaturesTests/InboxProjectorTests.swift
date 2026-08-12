import Foundation
import Testing
@testable import PalloCore
@testable import PalloFeatures

@Test func linkedIdentitiesBecomeOneInboxPersonWithSummedUnread() throws {
    let accounts = [
        ConnectedAccount(id: "wa", platform: .whatsApp, displayName: "Personal"),
        ConnectedAccount(id: "ig", platform: .instagram, displayName: "Personal")
    ]
    let identities = [
        RemoteIdentity(id: "maya-wa", accountID: "wa", displayName: "Maya"),
        RemoteIdentity(id: "maya-ig", accountID: "ig", displayName: "@maya")
    ]
    let conversations = [
        RemoteConversation(id: "wa-chat", accountID: "wa", identityID: "maya-wa", title: "Maya", latestActivity: Date(timeIntervalSince1970: 10), unreadCount: 2),
        RemoteConversation(id: "ig-chat", accountID: "ig", identityID: "maya-ig", title: "@maya", latestActivity: Date(timeIntervalSince1970: 20), unreadCount: 3)
    ]
    var directory = ContactDirectory()
    try directory.createPerson(id: "maya", displayName: "Maya")
    try directory.link(remoteIdentityID: "maya-wa", to: "maya")
    try directory.link(remoteIdentityID: "maya-ig", to: "maya")

    let result = InboxProjector.project(accounts: accounts, identities: identities, conversations: conversations, directory: directory)

    #expect(result.count == 1)
    #expect(result[0].id == .person("maya"))
    #expect(result[0].unreadCount == 5)
    #expect(result[0].conversationSummaries.map(\.route) == [
        ConversationRoute(accountID: "ig", conversationID: "ig-chat"),
        ConversationRoute(accountID: "wa", conversationID: "wa-chat")
    ])
}

@Test func unlinkedConversationRemainsStandalone() {
    let account = ConnectedAccount(id: "tg", platform: .telegram, displayName: "Personal")
    let identity = RemoteIdentity(id: "family", accountID: "tg", displayName: "Family")
    let conversation = RemoteConversation(id: "family-chat", accountID: "tg", identityID: "family", title: "Family", latestActivity: .distantPast, unreadCount: 1)

    let result = InboxProjector.project(accounts: [account], identities: [identity], conversations: [conversation], directory: ContactDirectory())

    #expect(result.map(\.id) == [.conversation(conversation.route)])
}
