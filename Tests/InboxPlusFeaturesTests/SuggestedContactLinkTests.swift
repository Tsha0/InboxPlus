import Foundation
import Testing
import InboxPlusCore
import InboxPlusGateway
@testable import InboxPlusFeatures

private let suggestionAccounts = [
    ConnectedAccount(id: "imessage", platform: .iMessage, displayName: "iMessage"),
    ConnectedAccount(id: "instagram", platform: .instagram, displayName: "Instagram")
]

private func suggestionConversation(_ id: String, account: String, name: String = "Alex Chen", group: Bool = false) -> RemoteConversation {
    RemoteConversation(id: id, accountID: account, identityID: id, title: name,
                       latestActivity: Date(timeIntervalSince1970: 1), unreadCount: 0, isGroup: group)
}

@Test func suggestionsRequireUnambiguousNamesAcrossNetworksAndSkipGroups() {
    let first = suggestionConversation("a", account: "imessage")
    let second = suggestionConversation("b", account: "instagram", name: " alex chen ")
    #expect(SuggestedContactLink.matches(conversations: [first, second], accounts: suggestionAccounts).count == 1)
    let group = suggestionConversation("group", account: "instagram", group: true)
    #expect(SuggestedContactLink.matches(conversations: [first, group], accounts: suggestionAccounts).isEmpty)
    let duplicate = suggestionConversation("other", account: "imessage")
    #expect(SuggestedContactLink.matches(conversations: [first, second, duplicate], accounts: suggestionAccounts).isEmpty)
    let different = suggestionConversation("different", account: "instagram", name: "Alex Smith")
    #expect(SuggestedContactLink.matches(conversations: [first, different], accounts: suggestionAccounts).isEmpty)
}

@MainActor
@Test func acceptedSuggestionLinksBothNetworksAndCanNavigateEachConversation() async throws {
    let conversations = [suggestionConversation("a", account: "imessage"), suggestionConversation("b", account: "instagram")]
    let snapshot = MessagingSnapshot(accounts: suggestionAccounts,
        identities: conversations.map { RemoteIdentity(id: $0.identityID, accountID: $0.accountID, displayName: $0.title) },
        conversations: conversations, messagesByRoute: [:])
    let model = InboxPlusAppModel(gateway: InMemoryMessagingGateway(seed: snapshot))
    try await model.start()
    #expect(model.people.isEmpty)
    let suggestion = try #require(model.suggestedContactLinks.first)
    try model.acceptSuggestedContactLink(suggestion)
    let person = try #require(model.people.first)
    #expect(model.people.count == 1)
    #expect(model.suggestedContactLinks.isEmpty)
    #expect(model.summaries(for: person.id).count == 2)
    for conversation in conversations {
        #expect(model.personID(for: conversation.route) == person.id)
        model.openConversation(conversation.route)
        #expect(model.openRoute == conversation.route)
    }
    try model.acceptSuggestedContactLink(suggestion)
    #expect(model.people.count == 1)
}

@MainActor
@Test func groupsCannotBeManuallyLinkedToPeople() async throws {
    let group = suggestionConversation("group", account: "imessage", group: true)
    let snapshot = MessagingSnapshot(accounts: suggestionAccounts,
        identities: [.init(id: group.identityID, accountID: group.accountID, displayName: group.title)],
        conversations: [group], messagesByRoute: [:])
    let model = InboxPlusAppModel(gateway: InMemoryMessagingGateway(seed: snapshot))
    try await model.start()
    #expect(!model.canLinkConversation(group.route))
    model.openConversation(group.route)
    #expect(throws: InboxPlusAppModelError.missingOpenConversation) {
        try model.createPersonAndLinkOpenConversation(displayName: group.title)
    }
    #expect(model.people.isEmpty)
}
