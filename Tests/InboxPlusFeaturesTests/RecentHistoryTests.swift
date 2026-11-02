import InboxPlusTestSupport
import Foundation
import Observation
import Testing
@testable import InboxPlusCore
@testable import InboxPlusGateway
@testable import InboxPlusFeatures

/// Holds history back from the snapshot, as iMessage does, until a conversation asks for it.
private actor HistoryOnOpenGateway: TextOnlyTestGateway {
    private let snapshot: MessagingSnapshot
    private let history: [Message]
    private var continuations: [UUID: AsyncStream<GatewayEvent>.Continuation] = [:]
    private var holdsHistory: Bool
    private var heldLoads: [ConversationRoute: CheckedContinuation<Void, any Error>] = [:]
    private(set) var requestedRoutes: [ConversationRoute] = []

    init(snapshot: MessagingSnapshot, history: [Message], holdsHistory: Bool = false) {
        self.snapshot = snapshot
        self.history = history
        self.holdsHistory = holdsHistory
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
        if holdsHistory {
            try await withCheckedThrowingContinuation { heldLoads[route] = $0 }
        }
        for message in history where message.route == route {
            continuations.values.forEach { $0.yield(.historicalMessageUpserted(message)) }
        }
    }

    func releaseHistory(in route: ConversationRoute, failing: Bool = false) {
        holdsHistory = false
        if failing {
            heldLoads.removeValue(forKey: route)?.resume(throwing: CocoaError(.fileReadUnknown))
        } else {
            heldLoads.removeValue(forKey: route)?.resume()
        }
    }

    func waitForRequests(_ count: Int) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while requestedRoutes.count < count, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(1))
        }
        return requestedRoutes.count == count
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

@MainActor
private final class TranscriptMutationCounter {
    private let model: InboxPlusAppModel
    private(set) var changes = 0

    init(_ model: InboxPlusAppModel) {
        self.model = model
        observe()
    }

    private func observe() {
        withObservationTracking {
            _ = model.messagesByRoute
        } onChange: { [weak self] in
            MainActor.assumeIsolated {
                self?.changes += 1
                self?.observe()
            }
        }
    }
}

@MainActor
@Test(arguments: [false, true])
func aHistoryBurstCoalescesTranscriptUpdates(withMedia: Bool) async throws {
    var messages = history(50, in: Fixtures.telegramRoute, prefix: "batch")
    if withMedia {
        for index in messages.indices {
            messages[index].attachments = [MessageAttachment(
                id: "photo-\(index)", kind: .image,
                source: MediaHandle(source: "mxc://fixture/photo-\(index)", mimeType: "image/png")
            )]
        }
    }
    let gateway = HistoryOnOpenGateway(snapshot: Fixtures.snapshot, history: messages)
    let model = InboxPlusAppModel(gateway: gateway, directory: Fixtures.directory)
    try await model.start()
    let counter = TranscriptMutationCounter(model)
    let start = ContinuousClock.now

    model.openConversation(Fixtures.telegramRoute)

    #expect(await settle { model.messagesByRoute[Fixtures.telegramRoute]?.count == 51 })
    let elapsed = start.duration(to: .now)
    print("History fixture media=\(withMedia): \(counter.changes) transcript writes, \(elapsed)")
    #expect(counter.changes < messages.count / 2)
}

@MainActor
@Test func historyLoadingDoesNotBlockSwitchingOrDuplicateRequests() async throws {
    let gateway = HistoryOnOpenGateway(
        snapshot: Fixtures.snapshot,
        history: history(50, in: Fixtures.telegramRoute, prefix: "held"),
        holdsHistory: true
    )
    let model = InboxPlusAppModel(gateway: gateway, directory: Fixtures.directory)
    try await model.start()
    model.openConversation(Fixtures.telegramRoute)
    model.openConversation(Fixtures.telegramRoute)
    #expect(model.loadingMessageRoutes == [Fixtures.telegramRoute])
    model.openConversation(Fixtures.whatsAppRoute)
    #expect(await gateway.waitForRequests(2))
    #expect(model.openRoute == Fixtures.whatsAppRoute)
    await gateway.deliver(.messageUpserted(Message(
        id: "live-during-load", route: Fixtures.whatsAppRoute, senderIdentityID: "maya-whatsapp",
        body: "fixture", timestamp: .now, deliveryState: .acknowledged
    )))
    #expect(await settle { model.messagesByRoute[Fixtures.whatsAppRoute]?.last?.id == "live-during-load" })
    await gateway.releaseHistory(in: Fixtures.telegramRoute)
    #expect(await settle { !model.loadingMessageRoutes.contains(Fixtures.telegramRoute) })
    #expect(model.loadingMessageRoutes.contains(Fixtures.whatsAppRoute))
    #expect(model.messagesByRoute[Fixtures.telegramRoute]?.count == RecentHistory.messageCount)
    await gateway.releaseHistory(in: Fixtures.whatsAppRoute)
    #expect(await settle { model.loadingMessageRoutes.isEmpty })
}

@MainActor
@Test func aFailedHistoryLoadCanBeRetried() async throws {
    let gateway = HistoryOnOpenGateway(snapshot: Fixtures.snapshot, history: [], holdsHistory: true)
    let model = InboxPlusAppModel(gateway: gateway)
    try await model.start()
    model.openConversation(Fixtures.telegramRoute)
    #expect(await gateway.waitForRequests(1))
    await gateway.releaseHistory(in: Fixtures.telegramRoute, failing: true)
    #expect(await settle { model.failedMessageRoutes.contains(Fixtures.telegramRoute) })
    #expect(!model.loadingMessageRoutes.contains(Fixtures.telegramRoute))
    model.loadRecentMessages(in: Fixtures.telegramRoute)
    #expect(model.failedMessageRoutes.isEmpty)
    #expect(await gateway.waitForRequests(2))
    #expect(await settle { model.loadingMessageRoutes.isEmpty })
}

@MainActor
@Test func stoppingDuringHistoryLoadingDoesNotRestoreStaleLoadingState() async throws {
    let gateway = HistoryOnOpenGateway(snapshot: Fixtures.snapshot, history: [], holdsHistory: true)
    let model = InboxPlusAppModel(gateway: gateway)
    try await model.start()
    model.openConversation(Fixtures.telegramRoute)
    #expect(await gateway.waitForRequests(1))
    model.stop()
    #expect(model.loadingMessageRoutes.isEmpty)
    try await model.start()
    model.openConversation(Fixtures.whatsAppRoute)
    #expect(await gateway.waitForRequests(2))
    await gateway.releaseHistory(in: Fixtures.telegramRoute, failing: true)
    #expect(model.loadingMessageRoutes == [Fixtures.whatsAppRoute])
    await gateway.releaseHistory(in: Fixtures.whatsAppRoute)
    #expect(await settle { model.loadingMessageRoutes.isEmpty })
    #expect(model.failedMessageRoutes.isEmpty)
}

@MainActor
@Test func historyBatchPreservesArrivalOrderWhenTimestampsMatch() async throws {
    let messages = ["z-first", "a-second"].map { id in
        Message(id: id, route: Fixtures.telegramRoute, senderIdentityID: "family-telegram-identity",
                body: id, timestamp: Date(timeIntervalSince1970: 1), deliveryState: .acknowledged)
    }
    let gateway = HistoryOnOpenGateway(snapshot: Fixtures.snapshot, history: messages)
    let model = InboxPlusAppModel(gateway: gateway)
    try await model.start()
    model.openConversation(Fixtures.telegramRoute)
    #expect(await settle { model.messagesByRoute[Fixtures.telegramRoute]?.count == 3 })
    #expect(model.messagesByRoute[Fixtures.telegramRoute]?.map(\.id) == ["z-first", "a-second", "tg-1"])
}

@MainActor
@Test func stoppingDiscardsQueuedHistoryBeforeRestart() async throws {
    let gateway = HistoryOnOpenGateway(snapshot: Fixtures.snapshot, history: [])
    let model = InboxPlusAppModel(gateway: gateway)
    try await model.start()
    await gateway.deliver(.historicalMessageUpserted(Message(
        id: "old-subscription", route: Fixtures.telegramRoute, senderIdentityID: nil,
        body: "fixture", timestamp: Date(timeIntervalSince1970: 50), deliveryState: .acknowledged
    )))
    await Task.yield()
    model.stop()
    try await model.start()
    try await Task.sleep(for: .milliseconds(50))
    #expect(model.messagesByRoute[Fixtures.telegramRoute]?.map(\.id) == ["tg-1"])
}
