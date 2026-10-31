import InboxPlusTestSupport
import Foundation
import Testing
@testable import InboxPlusCore
@testable import InboxPlusGateway
@testable import InboxPlusFeatures

private actor OrderingTestGateway: TextOnlyTestGateway {
    private let snapshot: MessagingSnapshot
    private var continuations: [UUID: AsyncStream<GatewayEvent>.Continuation] = [:]
    private(set) var readRoutes: [ConversationRoute] = []

    init(snapshot: MessagingSnapshot) {
        self.snapshot = snapshot
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

    func markRead(_ route: ConversationRoute) async throws {
        readRoutes.append(route)
    }

    func publish(_ event: GatewayEvent) {
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
    return condition()
}

/// For state that lives behind an actor, which the model reaches through an unstructured task.
@MainActor
private func eventually(_ condition: @MainActor () async throws -> Bool) async rethrows -> Bool {
    for _ in 0..<200 {
        if try await condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return try await condition()
}

@MainActor
@Test func openingAConversationClearsOnlyItsUnreadBadge() async throws {
    let model = InboxPlusAppModel(
        gateway: InMemoryMessagingGateway(seed: Fixtures.snapshot),
        directory: Fixtures.directory
    )
    try await model.start()
    let instagramBefore = try #require(
        model.conversations.first { $0.route == Fixtures.instagramRoute }?.unreadCount
    )
    #expect(instagramBefore == 2)

    model.openConversation(Fixtures.instagramRoute)

    #expect(model.conversations.first { $0.route == Fixtures.instagramRoute }?.unreadCount == 0)
    #expect(model.conversations.first { $0.route == Fixtures.whatsAppRoute }?.unreadCount == 1)
    let maya = try #require(model.inboxItems.first { $0.id == .person("maya") })
    #expect(maya.unreadCount == 1)
}

@MainActor
@Test func selectingAStandaloneInboxConversationMarksItRead() async throws {
    let unreadFamily = Fixtures.makeSnapshot(
        familyActivity: Date(timeIntervalSince1970: 100),
        whatsAppActivity: Date(timeIntervalSince1970: 200),
        instagramActivity: Date(timeIntervalSince1970: 300)
    )
    var seeded = unreadFamily
    seeded.conversations = seeded.conversations.map { conversation in
        var copy = conversation
        if copy.route == Fixtures.telegramRoute { copy.unreadCount = 4 }
        return copy
    }
    let model = InboxPlusAppModel(
        gateway: InMemoryMessagingGateway(seed: seeded),
        directory: Fixtures.directory
    )
    try await model.start()
    let item = try #require(
        model.inboxItems.first { $0.id == .conversation(Fixtures.telegramRoute) }
    )
    #expect(item.unreadCount == 4)

    model.selectInboxItem(item)

    #expect(model.detailSelection == .conversation(Fixtures.telegramRoute))
    #expect(model.conversations.first { $0.route == Fixtures.telegramRoute }?.unreadCount == 0)
}

@MainActor
@Test func markingAnAlreadyReadConversationIsANoOp() async throws {
    let model = InboxPlusAppModel(
        gateway: InMemoryMessagingGateway(seed: Fixtures.snapshot),
        directory: Fixtures.directory
    )
    try await model.start()
    model.markConversationRead(Fixtures.telegramRoute)
    let itemsAfterFirst = model.inboxItems

    model.markConversationRead(Fixtures.telegramRoute)

    #expect(model.inboxItems == itemsAfterFirst)
}

@MainActor
@Test func lateArrivingOlderMessageIsPlacedInTimestampOrder() async throws {
    let gateway = OrderingTestGateway(snapshot: Fixtures.snapshot)
    let model = InboxPlusAppModel(gateway: gateway, directory: Fixtures.directory)
    try await model.start()

    let older = Message(
        id: "tg-older",
        route: Fixtures.telegramRoute,
        senderIdentityID: "family-telegram-identity",
        body: "Arrived late, happened first",
        timestamp: Date(timeIntervalSince1970: 50),
        deliveryState: .acknowledged
    )
    let newer = Message(
        id: "tg-newer",
        route: Fixtures.telegramRoute,
        senderIdentityID: nil,
        body: "Newest",
        timestamp: Date(timeIntervalSince1970: 500),
        deliveryState: .acknowledged
    )

    await gateway.publish(.messageUpserted(newer))
    await gateway.publish(.messageUpserted(older))

    let applied = await settle {
        (model.messagesByRoute[Fixtures.telegramRoute] ?? []).count == 3
    }
    #expect(applied)

    let timestamps = (model.messagesByRoute[Fixtures.telegramRoute] ?? []).map(\.timestamp)
    #expect(timestamps == timestamps.sorted())
    #expect(model.messagesByRoute[Fixtures.telegramRoute]?.first?.id == older.id)
    #expect(model.messagesByRoute[Fixtures.telegramRoute]?.last?.id == newer.id)
}

@MainActor
@Test func snapshotMessagesAreSortedRegardlessOfSeedOrder() async throws {
    var scrambled = Fixtures.snapshot
    let route = Fixtures.telegramRoute
    scrambled.messagesByRoute[route] = [
        Message(id: "c", route: route, senderIdentityID: nil, body: "third", timestamp: Date(timeIntervalSince1970: 300), deliveryState: .acknowledged),
        Message(id: "a", route: route, senderIdentityID: nil, body: "first", timestamp: Date(timeIntervalSince1970: 100), deliveryState: .acknowledged),
        Message(id: "b", route: route, senderIdentityID: nil, body: "second", timestamp: Date(timeIntervalSince1970: 200), deliveryState: .acknowledged),
    ]
    let model = InboxPlusAppModel(
        gateway: InMemoryMessagingGateway(seed: scrambled),
        directory: Fixtures.directory
    )

    try await model.start()

    #expect(model.messagesByRoute[route]?.map(\.id) == ["a", "b", "c"])
}

@Test func outgoingMessagesAreTheOnesWithoutARemoteSender() {
    let route = ConversationRoute(accountID: "wa", conversationID: "chat")
    let mine = Message(id: "1", route: route, senderIdentityID: nil, body: "hi", timestamp: .now, deliveryState: .acknowledged)
    let theirs = Message(id: "2", route: route, senderIdentityID: "them", body: "hi", timestamp: .now, deliveryState: .acknowledged)

    #expect(mine.isOutgoing)
    #expect(!theirs.isOutgoing)
}

@MainActor
@Test func disconnectedAccountsReportTheirConnectionState() async throws {
    let gateway = OrderingTestGateway(snapshot: Fixtures.snapshot)
    let model = InboxPlusAppModel(gateway: gateway, directory: Fixtures.directory)
    try await model.start()
    #expect(model.isConnected("whatsapp-primary"))

    await gateway.publish(.connectionChanged(accountID: "whatsapp-primary", isConnected: false))

    let applied = await settle { !model.isConnected("whatsapp-primary") }
    #expect(applied)
    #expect(model.isConnected("instagram-primary"))
}

@MainActor
@Test func aConversationReadInOneLaunchStaysReadInTheNext() async throws {
    let gateway = InMemoryMessagingGateway(seed: Fixtures.snapshot)
    let model = InboxPlusAppModel(gateway: gateway, directory: Fixtures.directory)
    try await model.start()
    defer { model.stop() }

    model.openConversation(Fixtures.instagramRoute)

    let saved = try await eventually {
        try await gateway.loadSnapshot().conversations
            .first { $0.route == Fixtures.instagramRoute }?.unreadCount == 0
    }
    #expect(saved)
    let relaunched = InboxPlusAppModel(gateway: gateway, directory: Fixtures.directory)
    try await relaunched.start()
    defer { relaunched.stop() }
    #expect(relaunched.conversations.first { $0.route == Fixtures.instagramRoute }?.unreadCount == 0)
    #expect(relaunched.conversations.first { $0.route == Fixtures.whatsAppRoute }?.unreadCount == 1)
}

@MainActor
@Test func openingAConversationWhoseBadgeReadsZeroStillMarksItReadAtTheSource() async throws {
    // A message that arrived while the app was running never raised the badge, but the source
    // counts it and would bring the badge back on the next launch.
    let gateway = OrderingTestGateway(snapshot: Fixtures.snapshot)
    let model = InboxPlusAppModel(gateway: gateway, directory: Fixtures.directory)
    try await model.start()
    defer { model.stop() }
    #expect(model.conversations.first { $0.route == Fixtures.telegramRoute }?.unreadCount == 0)

    model.openConversation(Fixtures.telegramRoute)

    #expect(await eventually { await gateway.readRoutes == [Fixtures.telegramRoute] })
}

@MainActor
@Test func onlyIncomingMessagesInTheOpenConversationAreMarkedReadAsTheyArrive() async throws {
    let gateway = OrderingTestGateway(snapshot: Fixtures.snapshot)
    let model = InboxPlusAppModel(gateway: gateway, directory: Fixtures.directory)
    try await model.start()
    defer { model.stop() }
    model.openConversation(Fixtures.telegramRoute)
    #expect(await eventually { await gateway.readRoutes.count == 1 })

    func message(_ id: String, in route: ConversationRoute, from sender: String?) -> Message {
        Message(
            id: id, route: route, senderIdentityID: sender, body: "new",
            timestamp: Date(timeIntervalSince1970: 1_000), deliveryState: .acknowledged
        )
    }
    await gateway.publish(.messageUpserted(message("elsewhere", in: Fixtures.whatsAppRoute, from: "maya-whatsapp-identity")))
    await gateway.publish(.messageUpserted(message("mine", in: Fixtures.telegramRoute, from: nil)))
    await gateway.publish(.historicalMessageUpserted(message("backfill", in: Fixtures.telegramRoute, from: "family-telegram-identity")))
    await gateway.publish(.messageUpserted(message("theirs", in: Fixtures.telegramRoute, from: "family-telegram-identity")))

    #expect(await settle { model.messagesByRoute[Fixtures.telegramRoute]?.contains { $0.id == "theirs" } == true })
    #expect(await eventually { await gateway.readRoutes.count == 2 })
    for _ in 0..<20 { await Task.yield() }
    #expect(await gateway.readRoutes == [Fixtures.telegramRoute, Fixtures.telegramRoute])
}
