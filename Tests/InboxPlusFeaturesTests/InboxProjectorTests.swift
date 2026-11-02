import Foundation
import Testing
@testable import InboxPlusCore
@testable import InboxPlusFeatures

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

@Test func equalActivityUsesRoutesForStableOrderingAcrossInputPermutations() throws {
    let accounts = [
        ConnectedAccount(id: "account-b", platform: .whatsApp, displayName: "Personal"),
        ConnectedAccount(id: "account-a", platform: .instagram, displayName: "Personal"),
        ConnectedAccount(id: "account-c", platform: .telegram, displayName: "Personal")
    ]
    let identities = [
        RemoteIdentity(id: "maya-b", accountID: "account-b", displayName: "Maya"),
        RemoteIdentity(id: "maya-a", accountID: "account-a", displayName: "Maya"),
        RemoteIdentity(id: "family", accountID: "account-c", displayName: "Family")
    ]
    let conversations = [
        RemoteConversation(id: "chat-b", accountID: "account-b", identityID: "maya-b", title: "Maya", latestActivity: .distantPast, unreadCount: 1),
        RemoteConversation(id: "family-chat", accountID: "account-c", identityID: "family", title: "Family", latestActivity: .distantPast, unreadCount: 1),
        RemoteConversation(id: "chat-a", accountID: "account-a", identityID: "maya-a", title: "Maya", latestActivity: .distantPast, unreadCount: 1)
    ]
    var directory = ContactDirectory()
    try directory.createPerson(id: "maya", displayName: "Maya")
    try directory.link(remoteIdentityID: "maya-a", to: "maya")
    try directory.link(remoteIdentityID: "maya-b", to: "maya")

    let original = InboxProjector.project(accounts: accounts, identities: identities, conversations: conversations, directory: directory)
    let permuted = InboxProjector.project(accounts: accounts, identities: identities, conversations: conversations.reversed(), directory: directory)
    let expectedInboxIDs: [InboxItem.ID] = [
        .conversation(ConversationRoute(accountID: "account-c", conversationID: "family-chat")),
        .person("maya")
    ]
    let expectedMayaRoutes = [
        ConversationRoute(accountID: "account-a", conversationID: "chat-a"),
        ConversationRoute(accountID: "account-b", conversationID: "chat-b")
    ]

    #expect(original.map(\.id) == expectedInboxIDs)
    #expect(permuted.map(\.id) == expectedInboxIDs)
    #expect(original[1].conversationSummaries.map(\.route) == expectedMayaRoutes)
    #expect(permuted[1].conversationSummaries.map(\.route) == expectedMayaRoutes)
}

@Test func crossAccountIdentityReferenceCannotAggregateIntoALinkedPerson() throws {
    let accounts = [
        ConnectedAccount(id: "wa", platform: .whatsApp, displayName: "Personal"),
        ConnectedAccount(id: "ig", platform: .instagram, displayName: "Personal"),
    ]
    let identities = [
        RemoteIdentity(id: "maya-wa", accountID: "wa", displayName: "Maya"),
        RemoteIdentity(id: "maya-ig", accountID: "ig", displayName: "@maya"),
    ]
    let validRoute = ConversationRoute(accountID: "wa", conversationID: "wa-chat")
    let malformedRoute = ConversationRoute(accountID: "ig", conversationID: "malformed-chat")
    let conversations = [
        RemoteConversation(
            id: validRoute.conversationID,
            accountID: validRoute.accountID,
            identityID: "maya-wa",
            title: "Maya",
            latestActivity: Date(timeIntervalSince1970: 10),
            unreadCount: 1
        ),
        RemoteConversation(
            id: malformedRoute.conversationID,
            accountID: malformedRoute.accountID,
            identityID: "maya-wa",
            title: "Malformed cross-account reference",
            latestActivity: Date(timeIntervalSince1970: 20),
            unreadCount: 9
        ),
    ]
    var directory = ContactDirectory()
    try directory.createPerson(id: "maya", displayName: "Maya")
    try directory.link(remoteIdentityID: "maya-wa", to: "maya")

    let result = InboxProjector.project(
        accounts: accounts,
        identities: identities,
        conversations: conversations,
        directory: directory
    )

    #expect(result.map(\.id) == [.person("maya")])
    #expect(result[0].conversationSummaries.map(\.route) == [validRoute])
    #expect(result[0].unreadCount == 1)
    #expect(result.flatMap(\.conversationSummaries).contains { $0.route == malformedRoute } == false)
}

// MARK: - Filters

/// Maya is linked across WhatsApp and Instagram, where she wrote last; Sam is only on WhatsApp.
private func mayaAndSam() throws -> [InboxItem] {
    let accounts = [
        ConnectedAccount(id: "wa", platform: .whatsApp, displayName: "Personal"),
        ConnectedAccount(id: "ig", platform: .instagram, displayName: "Personal"),
    ]
    let identities = [
        RemoteIdentity(id: "maya-wa", accountID: "wa", displayName: "Maya"),
        RemoteIdentity(id: "maya-ig", accountID: "ig", displayName: "@maya"),
        RemoteIdentity(id: "sam-wa", accountID: "wa", displayName: "Sam"),
    ]
    let conversations = [
        RemoteConversation(id: "maya-wa", accountID: "wa", identityID: "maya-wa", title: "Maya", latestPreview: "On WhatsApp", latestActivity: Date(timeIntervalSince1970: 200), unreadCount: 1),
        RemoteConversation(id: "maya-ig", accountID: "ig", identityID: "maya-ig", title: "@maya", latestPreview: "On Instagram", latestActivity: Date(timeIntervalSince1970: 300), unreadCount: 2),
        RemoteConversation(id: "sam-wa", accountID: "wa", identityID: "sam-wa", title: "Sam", latestActivity: Date(timeIntervalSince1970: 250), unreadCount: 0),
    ]
    var directory = ContactDirectory()
    try directory.createPerson(id: "maya", displayName: "Maya")
    try directory.link(remoteIdentityID: "maya-wa", to: "maya")
    try directory.link(remoteIdentityID: "maya-ig", to: "maya")
    return InboxProjector.project(accounts: accounts, identities: identities, conversations: conversations, directory: directory)
}

@Test func aNetworkFilterShowsAPersonOnlyThroughThatNetwork() throws {
    let items = try mayaAndSam()
    let mayaOnWhatsApp = ConversationRoute(accountID: "wa", conversationID: "maya-wa")
    let sam = InboxItem.ID.conversation(ConversationRoute(accountID: "wa", conversationID: "sam-wa"))
    #expect(items.map(\.id) == [.person("maya"), sam])

    let whatsApp = InboxProjector.filtered(items, query: "", filter: InboxFilter(platforms: [.whatsApp]))

    // Maya's newest message is on Instagram, so on WhatsApp alone Sam is the more recent.
    #expect(whatsApp.map(\.id) == [sam, .person("maya")])
    let maya = try #require(whatsApp.last)
    #expect(maya.conversationSummaries.map(\.route) == [mayaOnWhatsApp])
    #expect(maya.conversationSummaries.first?.latestPreview == "On WhatsApp")
    #expect(maya.unreadCount == 1)
    #expect(maya.latestActivity == Date(timeIntervalSince1970: 200))
    #expect(InboxProjector.filtered(items, query: "", filter: InboxFilter(platforms: [.telegram])).isEmpty)
    #expect(
        InboxProjector.filtered(items, query: "", filter: InboxFilter(scope: .unread, platforms: [.whatsApp])).map(\.id)
            == [.person("maya")]
    )
}

@Test func theNetworkChipsAreTheNetworksTheInboxHasConversationsOn() throws {
    #expect(InboxProjector.platforms(in: try mayaAndSam()) == [.whatsApp, .instagram])
    #expect(InboxProjector.platforms(in: []).isEmpty)
    #expect(InboxProjector.platforms(in: [], including: [.instagram, .iMessage]) == [.instagram, .iMessage])
    #expect(InboxProjector.platforms(in: try mayaAndSam(), including: [.iMessage, .whatsApp]) == [.whatsApp, .instagram, .iMessage])
}

@Test func selectedNetworksAggregateALinkedPersonOnceAndExcludeOtherActivity() throws {
    let items = try mayaAndSam()
    let maya = try #require(items.first)
    let telegram = ConversationSummary(
        route: ConversationRoute(accountID: "tg", conversationID: "maya-tg"),
        platform: .telegram, title: "Maya", latestPreview: "On Telegram",
        latestActivity: Date(timeIntervalSince1970: 150), unreadCount: 4
    )
    let linked = InboxItem(
        id: maya.id, title: maya.title, latestActivity: maya.latestActivity,
        unreadCount: maya.unreadCount + telegram.unreadCount,
        conversationSummaries: maya.conversationSummaries + [telegram]
    )
    let selected = InboxFilter(platforms: [.whatsApp, .telegram])
    let result = InboxProjector.filtered([linked] + items.dropFirst(), query: "", filter: selected)

    #expect(result.map(\.id) == [items[1].id, .person("maya")])
    let narrowed = try #require(result.last)
    #expect(narrowed.conversationSummaries.map(\.platform) == [.whatsApp, .telegram])
    #expect(narrowed.conversationSummaries.first?.latestPreview == "On WhatsApp")
    #expect(narrowed.unreadCount == 5)
    #expect(narrowed.latestActivity == Date(timeIntervalSince1970: 200))
    #expect(InboxProjector.filtered([linked], query: "On Instagram", filter: selected).isEmpty)
    #expect(InboxProjector.filtered([linked], query: "On Telegram", filter: selected).map(\.id) == [maya.id])
    #expect(InboxProjector.filtered([linked], query: "", filter: InboxFilter()) == [linked])
    #expect(InboxProjector.filtered(result, query: "", filter: InboxFilter(scope: .unread, platforms: selected.platforms)).map(\.id) == [maya.id])
}

@Test func narrowingPlatformsPreservesFavouriteMutedAndHiddenRows() throws {
    let maya = try #require(mayaAndSam().first)
    let saved = InboxItem(
        id: maya.id, title: maya.title, latestActivity: maya.latestActivity,
        unreadCount: maya.unreadCount, conversationSummaries: maya.conversationSummaries,
        isFavourite: true, isMuted: true, isHidden: true
    )
    let result = try #require(InboxProjector.filtered(
        [saved], query: "", filter: InboxFilter(platforms: [.whatsApp, .telegram])
    ).first)
    #expect(result.isFavourite)
    #expect(result.isMuted)
    #expect(result.isHidden)
}

@Test func unknownSendersAreKeptOutOfTheInboxAndListedOnTheirOwn() throws {
    let account = ConnectedAccount(id: "im", platform: .iMessage, displayName: "iMessage")
    let identities = ["friend", "stranger", "courier"].map { RemoteIdentity(id: $0, accountID: "im", displayName: $0) }
    let conversations = [
        RemoteConversation(id: "friend", accountID: "im", identityID: "friend", title: "Friend", latestActivity: Date(timeIntervalSince1970: 10), unreadCount: 1),
        RemoteConversation(id: "stranger", accountID: "im", identityID: "stranger", title: "+1 (555) 010-0150", latestPreview: "You have won", latestActivity: Date(timeIntervalSince1970: 30), unreadCount: 2, isFromUnknownSender: true),
        RemoteConversation(id: "courier", accountID: "im", identityID: "courier", title: "+1 (555) 010-0160", latestActivity: Date(timeIntervalSince1970: 20), unreadCount: 0, isFromUnknownSender: true),
    ]
    // Linking a stranger to a person in Inbox+ is a way of saying who they are.
    var directory = ContactDirectory()
    try directory.createPerson(id: "courier", displayName: "Courier")
    try directory.link(remoteIdentityID: "courier", to: "courier")
    let items = InboxProjector.project(accounts: [account], identities: identities, conversations: conversations, directory: directory)
    let stranger = InboxItem.ID.conversation(ConversationRoute(accountID: "im", conversationID: "stranger"))
    let friend = InboxItem.ID.conversation(ConversationRoute(accountID: "im", conversationID: "friend"))

    #expect(InboxProjector.filtered(items, query: "", filter: InboxFilter()).map(\.id) == [.person("courier"), friend])
    #expect(InboxProjector.filtered(items, query: "", filter: InboxFilter(scope: .unread)).map(\.id) == [friend])
    #expect(InboxProjector.filtered(items, query: "", filter: InboxFilter(scope: .unknownSenders)).map(\.id) == [stranger])
    #expect(InboxProjector.filtered(items, query: "won", filter: InboxFilter()).isEmpty)
    #expect(InboxProjector.filtered(items, query: "won", filter: InboxFilter(scope: .unknownSenders)).map(\.id) == [stranger])
    #expect(InboxProjector.filtered(items, query: "won", filter: InboxFilter(scope: .unknownSenders, platforms: [.iMessage, .whatsApp])).map(\.id) == [stranger])
    #expect(InboxProjector.filtered(items, query: "", filter: InboxFilter(scope: .unknownSenders, platforms: [.instagram, .whatsApp])).isEmpty)
}

// MARK: - Message search

@Test func messageSearchFindsEarlierMessagesNewestFirst() throws {
    let items = try mayaAndSam()
    let mayaOnWhatsApp = ConversationRoute(accountID: "wa", conversationID: "maya-wa")
    let mayaOnInstagram = ConversationRoute(accountID: "ig", conversationID: "maya-ig")
    let sam = ConversationRoute(accountID: "wa", conversationID: "sam-wa")
    func message(_ id: String, _ route: ConversationRoute, _ body: String, at seconds: TimeInterval, kind: MessageKind = .text) -> Message {
        Message(id: id, route: route, senderIdentityID: "someone", body: body, timestamp: Date(timeIntervalSince1970: seconds), deliveryState: .acknowledged, kind: kind)
    }
    let messages = [
        mayaOnWhatsApp: [message("wa-0", mayaOnWhatsApp, "The gate code is 4512", at: 150), message("wa-1", mayaOnWhatsApp, "On WhatsApp", at: 200)],
        mayaOnInstagram: [message("ig-0", mayaOnInstagram, "Did you get the GATE code?", at: 280), message("ig-1", mayaOnInstagram, "On Instagram", at: 300)],
        sam: [message("sam-0", sam, "Gate Code joined", at: 260, kind: .membership)],
    ]

    let results = InboxProjector.messageMatches(messages, in: items, query: "  gate code ")

    #expect(results.map(\.id) == [
        MessageReference(route: mayaOnInstagram, messageID: "ig-0"),
        MessageReference(route: mayaOnWhatsApp, messageID: "wa-0"),
    ])
    // The conversation list alone finds nothing: neither preview says it.
    #expect(InboxProjector.filtered(items, query: "gate code").isEmpty)
    #expect(results.map(\.title) == ["Maya", "Maya"])
    #expect(results.map(\.platform) == [.instagram, .whatsApp])
    #expect(results.last?.snippet == "The gate code is 4512")
    #expect(results.last?.timestamp == Date(timeIntervalSince1970: 150))

    let whatsAppOnly = InboxProjector.filtered(items, query: "", filter: InboxFilter(platforms: [.whatsApp]))
    #expect(InboxProjector.messageMatches(messages, in: whatsAppOnly, query: "gate code").map(\.id.messageID) == ["wa-0"])
    #expect(InboxProjector.messageMatches(messages, in: items, query: "gate code", limit: 1).map(\.id.messageID) == ["ig-0"])
    #expect(InboxProjector.messageMatches(messages, in: items, query: " ").isEmpty)
}

@Test func aSnippetIsOneLineAndStartsNearAMatchFarIntoTheMessage() {
    #expect(InboxProjector.snippet(of: "Line one\nline two", matching: "TWO") == "Line one line two")
    #expect(InboxProjector.snippet(of: "Line one\nline two", matching: "three") == nil)
    #expect(
        InboxProjector.snippet(
            of: "Your order has shipped and is on its way to you, the parcel will arrive Tuesday",
            matching: "parcel"
        ) == "…way to you, the parcel will arrive Tuesday"
    )
}
