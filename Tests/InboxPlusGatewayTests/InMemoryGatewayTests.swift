import Foundation
import Testing
@testable import InboxPlusCore
@testable import InboxPlusGateway

@Test func snapshotReturnsSeededRecords() async throws {
    let route = ConversationRoute(accountID: "telegram-primary", conversationID: "family")
    let gateway = InMemoryMessagingGateway(seed: .init(
        accounts: [.init(id: route.accountID, platform: .telegram, displayName: "Personal")],
        identities: [.init(id: "family-id", accountID: route.accountID, displayName: "Family")],
        conversations: [.init(id: route.conversationID, accountID: route.accountID, identityID: "family-id", title: "Family", latestActivity: .distantPast, unreadCount: 1)],
        messagesByRoute: [route: []]
    ))

    let snapshot = try await gateway.loadSnapshot()
    #expect(snapshot.accounts.count == 1)
    #expect(snapshot.conversations.first?.route == route)
}

@Test func sendAcknowledgesTheExactRouteAndPublishesEvent() async throws {
    let expected = ConversationRoute(accountID: "instagram-primary", conversationID: "maya-ig")
    let gateway = InMemoryMessagingGateway(seed: .empty)
    let stream = await gateway.events()

    let receipt = try await gateway.sendText("Hello", to: expected)
    #expect(receipt.route == expected)
    #expect(receipt.deliveryState == .acknowledged)

    for await event in stream {
        guard case let .messageUpserted(message) = event else { continue }
        #expect(message.route == expected)
        #expect(message.body == "Hello")
        break
    }
}

@Test func stoppingMemoryGatewayFinishesSubscriptionsWithoutErasingHistory() async throws {
    let gateway = InMemoryMessagingGateway(seed: .empty)
    var events = await gateway.events().makeAsyncIterator()
    let route = ConversationRoute(accountID: "test", conversationID: "chat")
    _ = try await gateway.sendText("keep this history", to: route)
    _ = await events.next()
    await gateway.stop()
    #expect(await events.next() == nil)
    #expect(try await gateway.loadSnapshot().messagesByRoute[route]?.first?.body == "keep this history")
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
