import Foundation
import Testing
import InboxPlusCore
import InboxPlusGateway
@testable import InboxPlusFeatures

private actor NotificationGateway: TextOnlyTestGateway {
    let stream = AsyncStream<GatewayEvent>.makeStream()
    var snapshot: MessagingSnapshot
    init(snapshot: MessagingSnapshot = .empty) { self.snapshot = snapshot }
    func loadSnapshot() async throws -> MessagingSnapshot { snapshot }
    func events() async -> AsyncStream<GatewayEvent> { stream.stream }
    func publish(_ event: GatewayEvent) { stream.continuation.yield(event) }
    func sendText(_ body: String, to route: ConversationRoute) async throws -> SendReceipt {
        .init(messageID: "sent", route: route, deliveryState: .acknowledged)
    }
}

@MainActor
@Test func notificationsExcludeHistoryOutgoingAndDuplicateUpdates() async throws {
    let route = ConversationRoute(accountID: "account", conversationID: "room")
    func message(_ id: String, outgoing: Bool = false, date: Date = Date()) -> Message {
        .init(id: id, route: route, senderIdentityID: outgoing ? nil : "sender",
              body: id, timestamp: date, deliveryState: .acknowledged)
    }
    let initial = message("initial", date: .distantFuture)
    let gateway = NotificationGateway(snapshot: .init(accounts: [], identities: [], conversations: [], messagesByRoute: [route: [initial]]))
    let model = InboxPlusAppModel(gateway: gateway)
    var delivered: [String] = []
    model.onIncomingMessage = { message, _ in delivered.append(message.id) }
    try await model.start()
    #expect(delivered.isEmpty)
    await gateway.publish(.messageUpserted(initial))
    await gateway.publish(.historicalMessageUpserted(message("backfill")))
    await gateway.publish(.messageUpserted(message("old", date: .distantPast)))
    await gateway.publish(.messageUpserted(message("outgoing", outgoing: true)))
    let live = message("live")
    await gateway.publish(.messageUpserted(live))
    await gateway.publish(.messageUpserted(live))
    var edited = live
    edited.body = "edited"
    await gateway.publish(.messageUpserted(edited))
    await gateway.publish(.messageUpserted(message("backfill")))
    await gateway.publish(.historicalMessageUpserted(message("sentinel")))
    for _ in 0..<1000 {
        if model.messagesByRoute[route]?.contains(where: { $0.id == "sentinel" }) == true { break }
        await Task.yield()
    }
    #expect(model.messagesByRoute[route]?.contains(where: { $0.id == "sentinel" }) == true)
    #expect(delivered == ["live"])
    model.stop()
}
