import InboxPlusTestSupport
import Foundation
import Testing
@testable import InboxPlusCore
@testable import InboxPlusGateway
@testable import InboxPlusFeatures

/// Holds history back from the snapshot, as iMessage does, until a conversation asks for it.
private actor HistoryOnOpenGateway: TextOnlyTestGateway {
    private let snapshot: MessagingSnapshot
    private let history: [Message]
    private var continuations: [UUID: AsyncStream<GatewayEvent>.Continuation] = [:]
    private(set) var requestedRoutes: [ConversationRoute] = []

    init(snapshot: MessagingSnapshot, history: [Message]) {
        self.snapshot = snapshot
        self.history = history
    }

    func loadSnapshot() async throws -> MessagingSnapshot { snapshot }

    func events() async -> AsyncStream<GatewayEvent> {
        let id = UUID()
        let pair = AsyncStream<GatewayEvent>.makeStream()
        continuations[id] = pair.continuation
        pair.continuation.onTermination = { [weak self] _ in
            Task { await self?.removeContinuation(id) }
        }
        return pair.stream
    }

    func sendText(_ body: String, to route: ConversationRoute) async throws -> SendReceipt {
        SendReceipt(messageID: UUID().uuidString, route: route, deliveryState: .acknowledged)
    }

    func loadRecentMessages(in route: ConversationRoute) async throws {
        requestedRoutes.append(route)
        for message in history where message.route == route {
            continuations.values.forEach { $0.yield(.historicalMessageUpserted(message)) }
        }
    }

    func deliver(_ event: GatewayEvent) {
        continuations.values.forEach { $0.yield(event) }
    }

    private func removeContinuation(_ id: UUID) { continuations[id] = nil }
}

@MainActor
private func settle(until condition: @MainActor () -> Bool) async -> Bool {
    for _ in 0..<200 {
        if condition() { return true }
        await Task.yield()
    }
    let deadline = ContinuousClock.now.advanced(by: .seconds(10))
    while ContinuousClock.now < deadline {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return condition()
}

private func history(_ count: Int, in route: ConversationRoute, prefix: String) -> [Message] {
    (1...count).map { index in
        Message(
            id: "\(prefix)-\(index)", route: route, senderIdentityID: "family-telegram-identity",
            body: "message \(index)", timestamp: Date(timeIntervalSince1970: Double(index)),
            deliveryState: .acknowledged
        )
    }
}

@MainActor
@Test func openingAConversationLoadsItsRecentHistory() async throws {
    let earlier = Message(
        id: "tg-earlier",
        route: Fixtures.telegramRoute,
        senderIdentityID: "family-telegram-identity",
        body: "Who is bringing dessert?",
        timestamp: Date(timeIntervalSince1970: 50),
        deliveryState: .acknowledged
    )
    let gateway = HistoryOnOpenGateway(snapshot: Fixtures.snapshot, history: [earlier])
    let model = InboxPlusAppModel(gateway: gateway, directory: Fixtures.directory)
    try await model.start()
    #expect(model.messagesByRoute[Fixtures.telegramRoute]?.map(\.id) == ["tg-1"])

    model.openConversation(Fixtures.telegramRoute)

    #expect(await settle { model.messagesByRoute[Fixtures.telegramRoute]?.map(\.id) == ["tg-earlier", "tg-1"] })
    #expect(await gateway.requestedRoutes == [Fixtures.telegramRoute])
    // History is older than the preview, which stays on the newest message.
    #expect(model.conversations.first { $0.route == Fixtures.telegramRoute }?.latestPreview == "Dinner this weekend?")
}

@MainActor
@Test func closingAConversationTrimsItBackToTheRecentWindow() async throws {
    let unsent = Message(
        id: "unsent", route: Fixtures.telegramRoute, senderIdentityID: nil, body: "still sending",
        timestamp: Date(timeIntervalSince1970: 0.5), deliveryState: .pending
    )
    let gateway = HistoryOnOpenGateway(
        snapshot: Fixtures.snapshot,
        history: [unsent] + history(60, in: Fixtures.telegramRoute, prefix: "tg-history")
    )
    let model = InboxPlusAppModel(gateway: gateway, directory: Fixtures.directory)
    try await model.start()

    model.openConversation(Fixtures.telegramRoute)
    // Everything that arrives while the conversation is open stays on screen.
    #expect(await settle { model.messagesByRoute[Fixtures.telegramRoute]?.count == 62 })

    model.openConversation(Fixtures.whatsAppRoute)

    let kept = try #require(model.messagesByRoute[Fixtures.telegramRoute])
    #expect(kept.filter { $0.deliveryState == .acknowledged }.count == RecentHistory.messageCount)
    #expect(kept.last?.id == "tg-1")
    #expect(kept.contains { $0.id == "tg-history-12" })
    #expect(!kept.contains { $0.id == "tg-history-11" })
    // A send that has not been confirmed is never dropped, however old it is.
    #expect(kept.first?.id == "unsent")
}

@MainActor
@Test func aClosedConversationNeverHoldsMoreThanTheRecentWindow() async throws {
    let gateway = HistoryOnOpenGateway(snapshot: Fixtures.snapshot, history: [])
    let model = InboxPlusAppModel(gateway: gateway, directory: Fixtures.directory)
    try await model.start()

    for message in history(60, in: Fixtures.telegramRoute, prefix: "tg-history") {
        await gateway.deliver(.historicalMessageUpserted(message))
    }

    #expect(await settle { model.messagesByRoute[Fixtures.telegramRoute]?.last?.id == "tg-1"
        && model.messagesByRoute[Fixtures.telegramRoute]?.first?.id == "tg-history-12" })
    #expect(model.messagesByRoute[Fixtures.telegramRoute]?.count == RecentHistory.messageCount)
}
