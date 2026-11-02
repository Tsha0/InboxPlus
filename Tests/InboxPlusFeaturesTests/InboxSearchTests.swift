import InboxPlusTestSupport
import Foundation
import Testing
@testable import InboxPlusCore
@testable import InboxPlusGateway
@testable import InboxPlusFeatures

@MainActor
private func settle(until condition: @MainActor () -> Bool) async -> Bool {
    for _ in 0..<200 {
        if condition() { return true }
        await Task.yield()
    }
    return condition()
}

/// The fixture inbox, with a WhatsApp message from before the one its preview shows.
private var seedWithEarlierHistory: MessagingSnapshot {
    var seed = Fixtures.snapshot
    seed.messagesByRoute[Fixtures.whatsAppRoute]?.insert(
        Message(
            id: "wa-0", route: Fixtures.whatsAppRoute, senderIdentityID: "maya-whatsapp-identity",
            body: "The gate code is 4512", timestamp: Date(timeIntervalSince1970: 150), deliveryState: .acknowledged
        ),
        at: 0
    )
    return seed
}

@MainActor
@Test func searchFindsAMessageTheConversationListCannot() async throws {
    let model = InboxPlusAppModel(gateway: InMemoryMessagingGateway(seed: seedWithEarlierHistory), directory: Fixtures.directory)
    try await model.start()

    #expect(InboxProjector.filtered(model.inboxItems, query: "gate code").isEmpty)
    #expect(model.messageMatches(query: "gate code", filter: InboxFilter()).map(\.id) == [
        MessageReference(route: Fixtures.whatsAppRoute, messageID: "wa-0"),
    ])
    #expect(model.messageMatches(query: "gate code", filter: InboxFilter(platforms: [.instagram])).isEmpty)
    #expect(model.messageMatches(query: "", filter: InboxFilter()).isEmpty)
}

@MainActor
@Test func aSearchResultOpensItsConversationMarkedUntilTheUserMovesOn() async throws {
    let model = InboxPlusAppModel(gateway: InMemoryMessagingGateway(seed: seedWithEarlierHistory), directory: Fixtures.directory)
    try await model.start()
    let match = MessageReference(route: Fixtures.whatsAppRoute, messageID: "wa-0")

    model.openMessage(match)
    #expect(model.openRoute == Fixtures.whatsAppRoute)
    #expect(model.highlightedMessage == match)

    model.openConversation(Fixtures.telegramRoute)
    #expect(model.highlightedMessage == nil)

    model.openMessage(match)
    _ = model.captureDraft(to: Fixtures.telegramRoute)
    #expect(model.highlightedMessage == match)
    // A reply belongs at the bottom of the transcript, so sending lets go of the search result.
    _ = model.captureDraft(to: Fixtures.whatsAppRoute)
    #expect(model.highlightedMessage == nil)
}

@MainActor
@Test func replyingToAnUnknownSenderBringsThemIntoTheInbox() async throws {
    var seed = Fixtures.snapshot
    let index = try #require(seed.conversations.firstIndex { $0.route == Fixtures.telegramRoute })
    seed.conversations[index].isFromUnknownSender = true
    let model = InboxPlusAppModel(gateway: InMemoryMessagingGateway(seed: seed), directory: Fixtures.directory)
    try await model.start()
    let stranger = InboxItem.ID.conversation(Fixtures.telegramRoute)
    #expect(!InboxProjector.filtered(model.inboxItems, query: "", filter: InboxFilter()).contains { $0.id == stranger })
    #expect(InboxProjector.filtered(model.inboxItems, query: "", filter: InboxFilter(scope: .unknownSenders)).map(\.id) == [stranger])

    model.openConversation(Fixtures.telegramRoute)
    model.setDraft("Who is this?", for: Fixtures.telegramRoute)
    try await model.sendDraft(model.captureDraft(to: Fixtures.telegramRoute))

    let moved = await settle {
        InboxProjector.filtered(model.inboxItems, query: "", filter: InboxFilter()).contains { $0.id == stranger }
    }
    #expect(moved)
    #expect(InboxProjector.filtered(model.inboxItems, query: "", filter: InboxFilter(scope: .unknownSenders)).isEmpty)
}

@MainActor
@Test func conversationNavigationStaysOnTheChosenNetwork() async throws {
    let model = InboxPlusAppModel(gateway: InMemoryMessagingGateway(seed: Fixtures.snapshot), directory: Fixtures.directory)
    try await model.start()

    // Maya is one row across WhatsApp and Instagram; on WhatsApp alone only that chat is visited.
    model.navigateConversation(forward: true, query: "", filter: InboxFilter(platforms: [.whatsApp]))
    #expect(model.openRoute == Fixtures.whatsAppRoute)
    model.navigateConversation(forward: true, query: "", filter: InboxFilter(platforms: [.whatsApp]))
    #expect(model.openRoute == Fixtures.whatsAppRoute)
    model.navigateConversation(forward: false, query: "", filter: InboxFilter(platforms: [.telegram]))
    #expect(model.openRoute == Fixtures.telegramRoute)
}

@MainActor
@Test func searchAndConversationNavigationUseTheSelectedNetworkUnion() async throws {
    let model = InboxPlusAppModel(gateway: InMemoryMessagingGateway(seed: seedWithEarlierHistory), directory: Fixtures.directory)
    try await model.start()
    let selected = InboxFilter(platforms: [.whatsApp, .telegram])
    #expect(model.messageMatches(query: "gate code", filter: selected).map(\.id.messageID) == ["wa-0"])
    #expect(model.messageMatches(query: "address", filter: selected).isEmpty)
    #expect(model.messageMatches(query: "Dinner", filter: selected).map(\.id.route) == [Fixtures.telegramRoute])

    model.navigateConversation(forward: true, query: "", filter: selected)
    #expect(model.openRoute == Fixtures.whatsAppRoute)
    model.navigateConversation(forward: true, query: "", filter: selected)
    #expect(model.openRoute == Fixtures.telegramRoute)
    model.navigateConversation(forward: false, query: "", filter: selected)
    #expect(model.openRoute == Fixtures.whatsAppRoute)
}
