import Foundation
import Testing
@testable import InboxPlusCore
@testable import InboxPlusGateway

private let route = ConversationRoute(accountID: "instagram-primary", conversationID: "maya-ig")

private func seededGateway() -> InMemoryMessagingGateway {
    let original = Message(
        id: "original", route: route, senderIdentityID: "maya", body: "Dinner at 8?",
        timestamp: Date(timeIntervalSince1970: 100), deliveryState: .acknowledged, senderDisplayName: "Maya"
    )
    return InMemoryMessagingGateway(seed: MessagingSnapshot(
        accounts: [ConnectedAccount(id: route.accountID, platform: .instagram, displayName: "Instagram")],
        identities: [], conversations: [], messagesByRoute: [route: [original]]
    ))
}

private actor TextOnlySource: MessagingGateway {
    let account: ConnectedAccount
    init(account: ConnectedAccount) { self.account = account }
    func loadSnapshot() async throws -> MessagingSnapshot {
        MessagingSnapshot(accounts: [account], identities: [], conversations: [], messagesByRoute: [:])
    }
    func events() async -> AsyncStream<GatewayEvent> { AsyncStream { $0.finish() } }
    func sendText(_ body: String, to route: ConversationRoute) async throws -> SendReceipt {
        SendReceipt(messageID: "sent", route: route, deliveryState: .acknowledged)
    }
    func send(_ attachment: OutgoingAttachment, to route: ConversationRoute) async throws -> SendReceipt {
        SendReceipt(messageID: "sent", route: route, deliveryState: .acknowledged)
    }
    func markRead(_ route: ConversationRoute) async throws {}
}

@Test(.timeLimit(.minutes(1))) func aReplyQuotesTheMessageItAnswers() async throws {
    let gateway = seededGateway()
    let stream = await gateway.events()
    _ = try await gateway.sendText("Yes", to: route, replyingTo: "original")
    for await event in stream {
        guard case let .messageUpserted(message) = event else { continue }
        #expect(message.body == "Yes")
        #expect(message.replyTo == MessageReply(messageID: "original", senderDisplayName: "Maya", body: "Dinner at 8?"))
        break
    }
}

@Test(.timeLimit(.minutes(1))) func reactingTwiceWithTheSameEmojiTakesItBack() async throws {
    let gateway = seededGateway()
    let stream = await gateway.events()
    var updates = stream.makeAsyncIterator()
    try await gateway.toggleReaction("👍", to: "original", in: route)
    guard case let .historicalMessageUpserted(added) = await updates.next() else {
        Issue.record("A reaction must update the message without alerting anyone")
        return
    }
    #expect(added.reactions == [MessageReaction(key: "👍", count: 1, includesMe: true)])
    try await gateway.toggleReaction("👍", to: "original", in: route)
    guard case let .historicalMessageUpserted(removed) = await updates.next() else {
        Issue.record("Taking a reaction back must update the message")
        return
    }
    #expect(removed.reactions.isEmpty)
}

@Test func theCompositeAnswersThroughTheOwningSourceAndRefusesOneThatCannot() async throws {
    let imessage = TextOnlySource(account: ConnectedAccount(id: "imessage-local", platform: .iMessage, displayName: "iMessage"))
    let composite = CompositeMessagingGateway([seededGateway(), imessage])
    _ = try await composite.loadSnapshot()

    let receipt = try await composite.sendText("Yes", to: route, replyingTo: "original")
    #expect(receipt.route == route)
    try await composite.toggleReaction("❤️", to: "original", in: route)

    let imessageRoute = ConversationRoute(accountID: "imessage-local", conversationID: "chat")
    await #expect(throws: MessageInteractionError.unsupported) {
        try await composite.toggleReaction("❤️", to: "message", in: imessageRoute)
    }
    await #expect(throws: CompositeGatewayError.unknownAccount("nobody")) {
        _ = try await composite.sendText("Yes", to: ConversationRoute(accountID: "nobody", conversationID: "x"), replyingTo: "m")
    }
}
