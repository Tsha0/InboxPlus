import Foundation
import Testing
@testable import InboxPlusCore
@testable import InboxPlusGateway

@Test func memoryGatewayPublishesAcknowledgedMessagesAndStopsWithoutErasingHistory() async throws {
    let expected = ConversationRoute(accountID: "instagram-primary", conversationID: "maya-ig")
    let gateway = InMemoryMessagingGateway(seed: .empty)
    var events = await gateway.events().makeAsyncIterator()

    let receipt = try await gateway.sendText("Hello", to: expected)
    #expect(receipt.route == expected)
    #expect(receipt.deliveryState == .acknowledged)
    let event = try #require(await events.next())
    guard case let .messageUpserted(message) = event else {
        Issue.record("Expected a message event after sending")
        return
    }
    #expect(message.route == expected)
    #expect(message.body == "Hello")
    await gateway.stop()
    #expect(await events.next() == nil)
    #expect(try await gateway.loadSnapshot().messagesByRoute[expected]?.first == message)
}

private actor LifecycleGateway: MessagingGateway {
    let accountID: String
    private(set) var stops = 0
    init(_ accountID: String) { self.accountID = accountID }
    func loadSnapshot() async throws -> MessagingSnapshot {
        MessagingSnapshot(accounts: [ConnectedAccount(id: accountID, platform: .matrix, displayName: accountID)],
                          identities: [], conversations: [], messagesByRoute: [:])
    }
    func events() async -> AsyncStream<GatewayEvent> { AsyncStream { $0.finish() } }
    func sendText(_ body: String, to route: ConversationRoute) async throws -> SendReceipt {
        SendReceipt(messageID: body, route: route, deliveryState: .acknowledged)
    }
    func send(_ attachment: OutgoingAttachment, to route: ConversationRoute) async throws -> SendReceipt {
        SendReceipt(messageID: attachment.filename, route: route, deliveryState: .acknowledged)
    }
    func stop() async { stops += 1 }
}

@Test func compositeShutdownReachesEverySourceAndSupportsRestart() async throws {
    let first = LifecycleGateway("first"), second = LifecycleGateway("second")
    let gateway = CompositeMessagingGateway([first, second])
    _ = try await gateway.loadSnapshot()
    var events = await gateway.events().makeAsyncIterator()
    await gateway.stop()
    #expect(await first.stops == 1)
    #expect(await second.stops == 1)
    #expect(await events.next() == nil)
    let restarted = try await gateway.loadSnapshot()
    #expect(restarted.accounts.map(\.id) == ["first", "second"])
    let receipt = try await gateway.sendText("after restart", to: ConversationRoute(accountID: "second", conversationID: "chat"))
    #expect(receipt.messageID == "after restart")
    await gateway.stop()
}
