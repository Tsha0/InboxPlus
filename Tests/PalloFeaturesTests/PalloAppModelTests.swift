import Foundation
import Testing
@testable import PalloCore
@testable import PalloGateway
@testable import PalloFeatures

private actor AppModelTestGateway: MessagingGateway {
    private let snapshot: MessagingSnapshot
    private var continuations: [UUID: AsyncStream<GatewayEvent>.Continuation] = [:]

    init(snapshot: MessagingSnapshot) {
        self.snapshot = snapshot
    }

    func loadSnapshot() async throws -> MessagingSnapshot {
        snapshot
    }

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

    func publish(_ event: GatewayEvent) {
        continuations.values.forEach { $0.yield(event) }
    }

    func activeSubscriptionCount() -> Int {
        continuations.count
    }

    private func removeContinuation(_ id: UUID) {
        continuations[id] = nil
    }
}

private enum AppModelTestError: LocalizedError {
    case gatewayUnavailable

    var errorDescription: String? { "Fixture gateway unavailable" }
}

@MainActor
private func eventually(_ condition: @MainActor () async -> Bool) async -> Bool {
    for _ in 0..<1_000 {
        if await condition() { return true }
        await Task.yield()
    }
    return false
}

@MainActor
@Test func linkedPersonOpensSummaryBeforeConversation() async throws {
    let gateway = InMemoryMessagingGateway(seed: Fixtures.snapshot)
    let model = PalloAppModel(gateway: gateway, directory: Fixtures.directory)
    try await model.start()

    let person = try #require(model.inboxItems.first { $0.id == .person("maya") })
    model.selectInboxItem(person)
    #expect(model.detailSelection == .personSummary("maya"))
}

@MainActor
@Test func sendingUsesOnlyTheExplicitlyOpenedRoute() async throws {
    let gateway = InMemoryMessagingGateway(seed: Fixtures.snapshot)
    let model = PalloAppModel(gateway: gateway, directory: Fixtures.directory)
    try await model.start()
    let instagram = ConversationRoute(accountID: "instagram-primary", conversationID: "maya-instagram")
    let whatsApp = ConversationRoute(accountID: "whatsapp-primary", conversationID: "maya-whatsapp")
    let whatsAppCountBefore = (try await gateway.loadSnapshot()).messagesByRoute[whatsApp]?.count

    model.openConversation(instagram)
    model.draft = "Sent through Instagram"
    try await model.sendDraft()

    #expect(model.openRoute == instagram)
    let snapshot = try await gateway.loadSnapshot()
    #expect(snapshot.messagesByRoute[instagram]?.last?.body == "Sent through Instagram")
    #expect(snapshot.messagesByRoute[whatsApp]?.count == whatsAppCountBefore)
}

@MainActor
@Test func userCanExplicitlyLinkAnOpenStandaloneConversation() async throws {
    let model = PalloAppModel(gateway: InMemoryMessagingGateway(seed: Fixtures.snapshot), directory: Fixtures.directory)
    try await model.start()
    model.openConversation(Fixtures.telegramRoute)

    let personID = try model.createPersonAndLinkOpenConversation(displayName: "Family")

    #expect(model.detailSelection == .personSummary(personID))
    #expect(model.inboxItems.first { $0.id == .person(personID) }?.conversationSummaries.map(\.route) == [Fixtures.telegramRoute])
}

@MainActor
@Test func startRejectsMultipleAccountsForTheSamePlatform() async throws {
    let duplicateAccountSnapshot = MessagingSnapshot(
        accounts: [
            ConnectedAccount(id: "whatsapp-one", platform: .whatsApp, displayName: "One"),
            ConnectedAccount(id: "whatsapp-two", platform: .whatsApp, displayName: "Two"),
        ],
        identities: [],
        conversations: [],
        messagesByRoute: [:]
    )
    let model = PalloAppModel(gateway: InMemoryMessagingGateway(seed: duplicateAccountSnapshot))

    await #expect(throws: AccountPolicyError.duplicatePlatform(.whatsApp)) {
        try await model.start()
    }
}

@MainActor
@Test func failedCreateAndLinkDoesNotLeaveAnUnlinkedPerson() async throws {
    let model = PalloAppModel(gateway: InMemoryMessagingGateway(seed: Fixtures.snapshot), directory: Fixtures.directory)
    try await model.start()
    model.openConversation(Fixtures.instagramRoute)
    let peopleBefore = model.people

    #expect(throws: ContactDirectoryError.identityAlreadyLinked) {
        try model.createPersonAndLinkOpenConversation(displayName: "Duplicate Maya")
    }

    #expect(model.people == peopleBefore)
    #expect(model.detailSelection == .conversation(Fixtures.instagramRoute))
}

@MainActor
@Test func createAndLinkWithoutAnOpenConversationIsAtomic() async throws {
    let model = PalloAppModel(gateway: InMemoryMessagingGateway(seed: Fixtures.snapshot), directory: Fixtures.directory)
    try await model.start()
    let peopleBefore = model.people

    #expect(throws: PalloAppModelError.missingOpenConversation) {
        try model.createPersonAndLinkOpenConversation(displayName: "Orphan")
    }

    #expect(model.people == peopleBefore)
    #expect(model.detailSelection == .empty)
}

@MainActor
@Test func messageUpsertReplacesMatchingRouteAndIDWithoutDuplication() async throws {
    let gateway = AppModelTestGateway(snapshot: Fixtures.snapshot)
    let model = PalloAppModel(gateway: gateway, directory: Fixtures.directory)
    try await model.start()
    let original = try #require(model.messagesByRoute[Fixtures.instagramRoute]?.first)
    let deliveryUpdate = Message(
        id: original.id,
        route: original.route,
        senderIdentityID: original.senderIdentityID,
        body: original.body,
        timestamp: original.timestamp,
        deliveryState: .failed("offline")
    )

    await gateway.publish(.messageUpserted(deliveryUpdate))

    let updateApplied = await eventually {
        model.messagesByRoute[Fixtures.instagramRoute]?.first?.deliveryState == .failed("offline")
    }
    #expect(updateApplied)
    #expect(model.messagesByRoute[Fixtures.instagramRoute]?.count == 1)
}

@MainActor
@Test func healthRemainsUnhealthyUntilEveryDisconnectedAccountReconnects() async throws {
    let gateway = AppModelTestGateway(snapshot: Fixtures.snapshot)
    let model = PalloAppModel(gateway: gateway, directory: Fixtures.directory)
    try await model.start()

    await gateway.publish(.connectionChanged(accountID: "whatsapp-primary", isConnected: false))
    await gateway.publish(.connectionChanged(accountID: "instagram-primary", isConnected: false))
    await gateway.publish(.connectionChanged(accountID: "whatsapp-primary", isConnected: true))
    let reconnectBarrier = RemoteConversation(
        id: "reconnect-barrier",
        accountID: "telegram-primary",
        identityID: "family-telegram-identity",
        title: "Reconnect Barrier",
        latestActivity: .distantFuture,
        unreadCount: 0
    )
    await gateway.publish(.conversationUpserted(reconnectBarrier))

    let reconnectBarrierApplied = await eventually {
        model.conversations.contains { $0.route == reconnectBarrier.route }
    }
    #expect(reconnectBarrierApplied)
    #expect(model.health != .healthy)

    await gateway.publish(.connectionChanged(accountID: "instagram-primary", isConnected: true))

    let allAccountsReconnected = await eventually { model.health == .healthy }
    #expect(allAccountsReconnected)
}

@MainActor
@Test func connectionEventsForUnknownAccountsDoNotChangeHealth() async throws {
    let gateway = AppModelTestGateway(snapshot: Fixtures.snapshot)
    let model = PalloAppModel(gateway: gateway, directory: Fixtures.directory)
    try await model.start()
    let barrierConversation = RemoteConversation(
        id: "barrier",
        accountID: "telegram-primary",
        identityID: "family-telegram-identity",
        title: "Barrier",
        latestActivity: .distantFuture,
        unreadCount: 0
    )

    await gateway.publish(.connectionChanged(accountID: "unknown-account", isConnected: false))
    await gateway.publish(.conversationUpserted(barrierConversation))

    let barrierApplied = await eventually {
        model.conversations.contains { $0.route == barrierConversation.route }
    }
    #expect(barrierApplied)
    #expect(model.health == .healthy)
}

@MainActor
@Test func repeatedStartLeavesExactlyOneActiveEventSubscription() async throws {
    let gateway = AppModelTestGateway(snapshot: Fixtures.snapshot)
    let model = PalloAppModel(gateway: gateway, directory: Fixtures.directory)
    try await model.start()
    let firstSubscriptionStarted = await eventually {
        await gateway.activeSubscriptionCount() == 1
    }
    #expect(firstSubscriptionStarted)

    try await model.start()

    let oldSubscriptionCancelled = await eventually {
        await gateway.activeSubscriptionCount() == 1
    }
    #expect(oldSubscriptionCancelled)
}

@MainActor
@Test func stopCancelsTheActiveEventSubscription() async throws {
    let gateway = AppModelTestGateway(snapshot: Fixtures.snapshot)
    let model = PalloAppModel(gateway: gateway, directory: Fixtures.directory)
    try await model.start()
    let subscriptionStarted = await eventually {
        await gateway.activeSubscriptionCount() == 1
    }
    #expect(subscriptionStarted)

    model.stop()

    let subscriptionCancelled = await eventually {
        await gateway.activeSubscriptionCount() == 0
    }
    #expect(subscriptionCancelled)
}

@MainActor
@Test func healthTitleIsQuietWhenHealthyAndActionableWhenDisconnected() async throws {
    let model = PalloAppModel(gateway: InMemoryMessagingGateway(seed: Fixtures.snapshot), directory: Fixtures.directory)
    try await model.start()
    #expect(model.health.menuBarTitle == "Pallo is running")
    #expect(ServiceHealth.needsAttention("Reconnect Instagram").menuBarTitle == "Pallo needs attention")
}

@Test func healthSymbolReflectsLifecycleState() {
    #expect(ServiceHealth.starting.symbolName == "ellipsis.circle")
    #expect(ServiceHealth.healthy.symbolName == "checkmark.circle.fill")
    #expect(ServiceHealth.needsAttention("Reconnect Instagram").symbolName == "exclamationmark.triangle.fill")
}

@MainActor
@Test func reportingStartupFailureMakesHealthActionable() {
    let model = PalloAppModel(gateway: InMemoryMessagingGateway(seed: Fixtures.snapshot))

    model.reportStartupFailure(AppModelTestError.gatewayUnavailable)

    #expect(model.health == .needsAttention("Pallo could not start: Fixture gateway unavailable"))
}
