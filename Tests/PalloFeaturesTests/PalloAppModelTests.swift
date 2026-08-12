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

private actor ControlledSendGateway: MessagingGateway {
    struct Submission: Equatable, Sendable {
        let body: String
        let route: ConversationRoute
    }

    private let snapshot: MessagingSnapshot
    private var continuation: CheckedContinuation<SendReceipt, any Error>?
    private(set) var submission: Submission?

    init(snapshot: MessagingSnapshot) {
        self.snapshot = snapshot
    }

    func loadSnapshot() async throws -> MessagingSnapshot { snapshot }

    func events() async -> AsyncStream<GatewayEvent> {
        AsyncStream { $0.finish() }
    }

    func sendText(_ body: String, to route: ConversationRoute) async throws -> SendReceipt {
        submission = Submission(body: body, route: route)
        return try await withCheckedThrowingContinuation { continuation = $0 }
    }

    func completeSend() {
        continuation?.resume(
            returning: SendReceipt(
                messageID: "controlled-message",
                route: submission!.route,
                deliveryState: .acknowledged
            )
        )
        continuation = nil
    }
}

private actor RetrySendGateway: MessagingGateway {
    private let snapshot: MessagingSnapshot
    private var failsSends = true

    init(snapshot: MessagingSnapshot) {
        self.snapshot = snapshot
    }

    func loadSnapshot() async throws -> MessagingSnapshot { snapshot }

    func events() async -> AsyncStream<GatewayEvent> {
        AsyncStream { $0.finish() }
    }

    func sendText(_ body: String, to route: ConversationRoute) async throws -> SendReceipt {
        if failsSends { throw AppModelTestError.gatewayUnavailable }
        return SendReceipt(messageID: "retry-message", route: route, deliveryState: .acknowledged)
    }

    func allowSends() {
        failsSends = false
    }
}

private actor ControlledStartGateway: MessagingGateway {
    private let snapshot: MessagingSnapshot
    private var snapshotContinuations: [CheckedContinuation<MessagingSnapshot, any Error>] = []
    private var eventContinuations: [UUID: AsyncStream<GatewayEvent>.Continuation] = [:]
    private(set) var snapshotLoadCount = 0

    init(snapshot: MessagingSnapshot) {
        self.snapshot = snapshot
    }

    func loadSnapshot() async throws -> MessagingSnapshot {
        snapshotLoadCount += 1
        return try await withCheckedThrowingContinuation {
            snapshotContinuations.append($0)
        }
    }

    func events() async -> AsyncStream<GatewayEvent> {
        let id = UUID()
        let pair = AsyncStream<GatewayEvent>.makeStream()
        eventContinuations[id] = pair.continuation
        pair.continuation.onTermination = { [weak self] _ in
            Task { await self?.removeEventContinuation(id) }
        }
        return pair.stream
    }

    func sendText(_ body: String, to route: ConversationRoute) async throws -> SendReceipt {
        SendReceipt(messageID: UUID().uuidString, route: route, deliveryState: .acknowledged)
    }

    func publish(_ event: GatewayEvent) {
        eventContinuations.values.forEach { $0.yield(event) }
    }

    func completeSnapshotLoads() {
        snapshotContinuations.forEach { $0.resume(returning: snapshot) }
        snapshotContinuations.removeAll()
    }

    func failSnapshotLoads() {
        snapshotContinuations.forEach { $0.resume(throwing: AppModelTestError.gatewayUnavailable) }
        snapshotContinuations.removeAll()
    }

    func activeSubscriptionCount() -> Int {
        eventContinuations.count
    }

    private func removeEventContinuation(_ id: UUID) {
        eventContinuations[id] = nil
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
    try await model.sendDraft(model.captureDraft(to: instagram))

    #expect(model.openRoute == instagram)
    let snapshot = try await gateway.loadSnapshot()
    #expect(snapshot.messagesByRoute[instagram]?.last?.body == "Sent through Instagram")
    #expect(snapshot.messagesByRoute[whatsApp]?.count == whatsAppCountBefore)
}

@MainActor
@Test func inFlightSendKeepsCapturedRouteAndPreservesANewerDraft() async throws {
    let gateway = ControlledSendGateway(snapshot: Fixtures.snapshot)
    let model = PalloAppModel(gateway: gateway, directory: Fixtures.directory)
    try await model.start()
    let submittedRoute = Fixtures.instagramRoute
    let newerRoute = Fixtures.whatsAppRoute
    model.openConversation(submittedRoute)
    model.draft = "  route A draft  "
    let submission = model.captureDraft(to: submittedRoute)

    let sendTask = Task { @MainActor in
        try await model.sendDraft(submission)
    }
    let sendStarted = await eventually {
        await gateway.submission != nil
    }
    #expect(sendStarted)

    model.openConversation(newerRoute)
    model.draft = "route B newer draft"
    await gateway.completeSend()
    try await sendTask.value

    #expect(
        await gateway.submission
            == ControlledSendGateway.Submission(body: "route A draft", route: submittedRoute)
    )
    #expect(model.openRoute == newerRoute)
    #expect(model.draft == "route B newer draft")
}

@MainActor
@Test func inFlightSendDoesNotClearAReenteredSameTextDraft() async throws {
    let gateway = ControlledSendGateway(snapshot: Fixtures.snapshot)
    let model = PalloAppModel(gateway: gateway, directory: Fixtures.directory)
    try await model.start()
    model.draft = "same text"
    let submission = model.captureDraft(to: Fixtures.instagramRoute)

    let sendTask = Task { @MainActor in
        try await model.sendDraft(submission)
    }
    let sendStarted = await eventually {
        await gateway.submission != nil
    }
    #expect(sendStarted)

    model.draft = "intermediate edit"
    model.draft = "same text"
    await gateway.completeSend()
    try await sendTask.value

    #expect(model.draft == "same text")
}

@MainActor
@Test func sendFailureIsScopedToItsRouteAndSuccessfulRetryClearsIt() async throws {
    let gateway = RetrySendGateway(snapshot: Fixtures.snapshot)
    let model = PalloAppModel(gateway: gateway, directory: Fixtures.directory)
    try await model.start()
    let route = Fixtures.instagramRoute
    model.openConversation(route)
    model.draft = "retry this message"

    do {
        try await model.sendDraft(model.captureDraft(to: route))
        Issue.record("Expected the fixture send to fail")
    } catch {
        model.reportSendFailure(error, for: route)
    }

    #expect(model.sendFailure(for: route) == "Fixture gateway unavailable")
    #expect(model.sendFailure(for: Fixtures.whatsAppRoute) == nil)
    #expect(model.draft == "retry this message")

    await gateway.allowSends()
    try await model.sendDraft(model.captureDraft(to: route))

    #expect(model.sendFailure(for: route) == nil)
    #expect(model.draft.isEmpty)
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
@Test func newerOutgoingMessageRefreshesOnlyItsConversationAndReordersInbox() async throws {
    let gateway = AppModelTestGateway(snapshot: Fixtures.snapshot)
    let model = PalloAppModel(gateway: gateway, directory: Fixtures.directory)
    try await model.start()
    let originalInstagram = try #require(
        model.conversations.first { $0.route == Fixtures.instagramRoute }
    )
    let originalTelegramUnread = try #require(
        model.conversations.first { $0.route == Fixtures.telegramRoute }?.unreadCount
    )
    let sentAt = Date(timeIntervalSince1970: 400)
    let outgoing = Message(
        id: "telegram-outgoing",
        route: Fixtures.telegramRoute,
        senderIdentityID: nil,
        body: "Newest exact-route reply",
        timestamp: sentAt,
        deliveryState: .acknowledged
    )

    await gateway.publish(.messageUpserted(outgoing))
    let eventApplied = await eventually {
        model.messagesByRoute[Fixtures.telegramRoute]?.contains { $0.id == outgoing.id } == true
    }
    let telegram = try #require(
        model.conversations.first { $0.route == Fixtures.telegramRoute }
    )
    let telegramSummary = try #require(
        model.inboxItems
            .flatMap(\.conversationSummaries)
            .first { $0.route == Fixtures.telegramRoute }
    )

    #expect(eventApplied)
    #expect(telegram.latestPreview == "Newest exact-route reply")
    #expect(telegram.latestActivity == sentAt)
    #expect(telegram.unreadCount == originalTelegramUnread)
    #expect(model.conversations.first { $0.route == Fixtures.instagramRoute } == originalInstagram)
    #expect(telegramSummary.latestPreview == "Newest exact-route reply")
    #expect(telegramSummary.latestActivity == sentAt)
    #expect(model.inboxItems.first?.id == .conversation(Fixtures.telegramRoute))
}

@MainActor
@Test func olderMessageAndDeliveryUpdateDoNotRegressConversationProjection() async throws {
    let gateway = AppModelTestGateway(snapshot: Fixtures.snapshot)
    let model = PalloAppModel(gateway: gateway, directory: Fixtures.directory)
    try await model.start()
    let newest = Message(
        id: "telegram-newest",
        route: Fixtures.telegramRoute,
        senderIdentityID: nil,
        body: "Keep this preview",
        timestamp: Date(timeIntervalSince1970: 400),
        deliveryState: .pending
    )
    let deliveryUpdate = Message(
        id: newest.id,
        route: newest.route,
        senderIdentityID: newest.senderIdentityID,
        body: newest.body,
        timestamp: newest.timestamp,
        deliveryState: .acknowledged
    )
    let older = Message(
        id: "telegram-older",
        route: Fixtures.telegramRoute,
        senderIdentityID: nil,
        body: "Do not regress to this preview",
        timestamp: Date(timeIntervalSince1970: 50),
        deliveryState: .acknowledged
    )

    await gateway.publish(.messageUpserted(newest))
    await gateway.publish(.messageUpserted(deliveryUpdate))
    await gateway.publish(.messageUpserted(older))
    let eventsApplied = await eventually {
        let messages = model.messagesByRoute[Fixtures.telegramRoute] ?? []
        return messages.contains { $0.id == older.id }
            && messages.first { $0.id == newest.id }?.deliveryState == .acknowledged
    }
    let telegram = try #require(
        model.conversations.first { $0.route == Fixtures.telegramRoute }
    )

    #expect(eventsApplied)
    #expect(telegram.latestPreview == "Keep this preview")
    #expect(telegram.latestActivity == Date(timeIntervalSince1970: 400))
    #expect(telegram.unreadCount == 0)
    #expect(model.inboxItems.first?.id == .conversation(Fixtures.telegramRoute))
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
@Test func concurrentStartCallsShareOneGaplessSubscription() async throws {
    let gateway = ControlledStartGateway(snapshot: Fixtures.snapshot)
    let model = PalloAppModel(gateway: gateway, directory: Fixtures.directory)

    let firstStart = Task { @MainActor in try await model.start() }
    let secondStart = Task { @MainActor in try await model.start() }
    let subscribedBeforeSnapshotCompletes = await eventually {
        let subscriptions = await gateway.activeSubscriptionCount()
        let loads = await gateway.snapshotLoadCount
        return subscriptions == 1 && loads == 1
    }
    let snapshotLoadCount = await gateway.snapshotLoadCount
    await gateway.completeSnapshotLoads()
    try await firstStart.value
    try await secondStart.value

    #expect(subscribedBeforeSnapshotCompletes)
    #expect(snapshotLoadCount == 1)
    #expect(await gateway.activeSubscriptionCount() == 1)
}

@MainActor
@Test func eventPublishedDuringSnapshotLoadIsAppliedAfterTheSnapshot() async throws {
    let gateway = ControlledStartGateway(snapshot: Fixtures.snapshot)
    let model = PalloAppModel(gateway: gateway, directory: Fixtures.directory)
    let eventConversation = RemoteConversation(
        id: "during-start",
        accountID: "telegram-primary",
        identityID: "family-telegram-identity",
        title: "During Start",
        latestPreview: "arrived while loading",
        latestActivity: .distantFuture,
        unreadCount: 0
    )

    let startTask = Task { @MainActor in try await model.start() }
    let subscribedBeforeSnapshotCompletes = await eventually {
        let subscriptions = await gateway.activeSubscriptionCount()
        let loads = await gateway.snapshotLoadCount
        return subscriptions == 1 && loads == 1
    }
    await gateway.publish(.conversationUpserted(eventConversation))
    await gateway.completeSnapshotLoads()
    try await startTask.value

    #expect(subscribedBeforeSnapshotCompletes)
    #expect(model.conversations.contains { $0.route == eventConversation.route })
    #expect(model.inboxItems.first?.latestActivity == .distantFuture)
}

@MainActor
@Test func startupFailureCancelsItsOwnedEventSubscription() async {
    let gateway = ControlledStartGateway(snapshot: Fixtures.snapshot)
    let model = PalloAppModel(gateway: gateway, directory: Fixtures.directory)

    let startTask = Task { @MainActor in try await model.start() }
    let subscribedBeforeFailure = await eventually {
        let subscriptions = await gateway.activeSubscriptionCount()
        let loads = await gateway.snapshotLoadCount
        return subscriptions == 1 && loads == 1
    }
    await gateway.failSnapshotLoads()

    await #expect(throws: AppModelTestError.gatewayUnavailable) {
        try await startTask.value
    }
    let subscriptionCancelled = await eventually {
        await gateway.activeSubscriptionCount() == 0
    }
    #expect(subscribedBeforeFailure)
    #expect(subscriptionCancelled)
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
@Test func startAfterStopCreatesAFreshWorkingSubscription() async throws {
    let gateway = AppModelTestGateway(snapshot: Fixtures.snapshot)
    let model = PalloAppModel(gateway: gateway, directory: Fixtures.directory)
    try await model.start()
    model.stop()
    let firstSubscriptionCancelled = await eventually {
        await gateway.activeSubscriptionCount() == 0
    }
    #expect(firstSubscriptionCancelled)

    try await model.start()
    let restartedSubscription = await eventually {
        await gateway.activeSubscriptionCount() == 1
    }
    let eventConversation = RemoteConversation(
        id: "after-restart",
        accountID: "telegram-primary",
        identityID: "family-telegram-identity",
        title: "After Restart",
        latestActivity: .distantFuture,
        unreadCount: 0
    )
    await gateway.publish(.conversationUpserted(eventConversation))
    let eventApplied = await eventually {
        model.conversations.contains { $0.route == eventConversation.route }
    }

    #expect(restartedSubscription)
    #expect(eventApplied)
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
