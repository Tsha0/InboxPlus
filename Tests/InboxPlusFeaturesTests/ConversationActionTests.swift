import Foundation
import Testing
import InboxPlusCore
import InboxPlusGateway
import InboxPlusTestSupport
@testable import InboxPlusFeatures

private actor PublishingGateway: TextOnlyTestGateway {
    private let snapshot: MessagingSnapshot
    private let stream = AsyncStream<GatewayEvent>.makeStream()
    init(snapshot: MessagingSnapshot) { self.snapshot = snapshot }
    func loadSnapshot() async throws -> MessagingSnapshot { snapshot }
    func events() async -> AsyncStream<GatewayEvent> { stream.stream }
    func publish(_ event: GatewayEvent) { stream.continuation.yield(event) }
    func sendText(_ body: String, to route: ConversationRoute) async throws -> SendReceipt {
        SendReceipt(messageID: "sent", route: route, deliveryState: .acknowledged)
    }
}

private func makeStore() -> (store: ConversationPreferenceStore, root: URL) {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    return (ConversationPreferenceStore(fileURL: root.appendingPathComponent("profile/conversations.json")), root)
}

private func incoming(_ id: String, in route: ConversationRoute) -> Message {
    Message(id: id, route: route, senderIdentityID: "someone", body: id, timestamp: Date(), deliveryState: .acknowledged)
}

/// Gateway events reach the model through an unstructured task.
@MainActor
private func settle(until condition: @MainActor () -> Bool) async -> Bool {
    for _ in 0..<500 {
        if condition() { return true }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return condition()
}

@MainActor
private func item(_ route: ConversationRoute, in model: InboxPlusAppModel) throws -> InboxItem {
    try #require(model.inboxItems.first { $0.conversationSummaries.contains { $0.route == route } })
}

// MARK: - Preferences

@Test func aTimedMuteEndsOnItsOwnAndAnOpenEndedOneDoesNot() {
    let start = Date(timeIntervalSince1970: 1_000)
    var preferences = ConversationPreferences()
    preferences.mute([Fixtures.whatsAppRoute], for: .oneHour, from: start)
    preferences.mute([Fixtures.telegramRoute], for: .forever, from: start)
    #expect(preferences.isMuted(Fixtures.whatsAppRoute, at: start.addingTimeInterval(3_599)))
    #expect(!preferences.isMuted(Fixtures.whatsAppRoute, at: start.addingTimeInterval(3_600)))
    #expect(preferences.isMuted(Fixtures.telegramRoute, at: .distantFuture))
    #expect(preferences.nextMuteEnd(after: start) == start.addingTimeInterval(3_600))
    #expect(preferences.nextMuteEnd(after: start.addingTimeInterval(3_600)) == nil)

    preferences.mute([Fixtures.whatsAppRoute], for: .eightHours, from: start)
    #expect(preferences.nextMuteEnd(after: start) == start.addingTimeInterval(8 * 3_600))
    preferences.unmute([Fixtures.telegramRoute])
    #expect(!preferences.isMuted(Fixtures.telegramRoute, at: start))
}

@Test func aHiddenConversationComesBackWhenSomethingNewArrivesUnlessItIsMuted() {
    let now = Date(timeIntervalSince1970: 1_000)
    var conversations = Fixtures.snapshot.conversations
    var preferences = ConversationPreferences()
    preferences.hide(conversations.map { ($0.route, $0.latestActivity) })
    preferences.mute([Fixtures.telegramRoute], for: .forever, from: now)

    preferences.reviveHidden(in: conversations, at: now)
    #expect(preferences.hidden == [Fixtures.whatsAppRoute, Fixtures.instagramRoute, Fixtures.telegramRoute])

    for index in conversations.indices where conversations[index].route != Fixtures.instagramRoute {
        conversations[index].latestActivity = Date(timeIntervalSince1970: 900)
    }
    preferences.reviveHidden(in: conversations, at: now)
    #expect(preferences.hidden == [Fixtures.instagramRoute, Fixtures.telegramRoute])

    preferences.forget(accountID: Fixtures.telegramRoute.accountID)
    #expect(preferences.hidden == [Fixtures.instagramRoute])
    #expect(!preferences.isMuted(Fixtures.telegramRoute, at: now))
}

@Test func openInAppOffersEachNetworkOfARowOnce() {
    func summary(_ id: String, _ platform: Platform) -> ConversationSummary {
        ConversationSummary(
            route: ConversationRoute(accountID: platform.rawValue, conversationID: id), platform: platform,
            title: id, latestPreview: "", latestActivity: .now, unreadCount: 0
        )
    }
    let person = InboxItem(
        id: .person("maya"), title: "Maya", latestActivity: .now, unreadCount: 0,
        conversationSummaries: [
            summary("dm", .instagram), summary("chat", .whatsApp), summary("group", .instagram), summary("text", .iMessage),
        ]
    )
    #expect(person.appLinks.map(\.platform) == [.instagram, .whatsApp])
}

// MARK: - Inbox rows

@MainActor
@Test(.timeLimit(.minutes(1))) func aMutedConversationStaysQuietAndStaysMutedAfterARelaunch() async throws {
    let (store, root) = makeStore()
    defer { try? FileManager.default.removeItem(at: root) }
    let gateway = PublishingGateway(snapshot: Fixtures.snapshot)
    let model = InboxPlusAppModel(gateway: gateway, preferenceStore: store)
    var notified: [String] = []
    model.onIncomingMessage = { notified.append($0.message.id) }
    try await model.start()
    defer { model.stop() }

    let family = try item(Fixtures.telegramRoute, in: model)
    model.perform(.mute(.oneHour), on: family)
    #expect(try item(Fixtures.telegramRoute, in: model).isMuted)

    await gateway.publish(.messageUpserted(incoming("muted", in: Fixtures.telegramRoute)))
    await gateway.publish(.messageUpserted(incoming("heard", in: Fixtures.whatsAppRoute)))
    #expect(await settle { model.messagesByRoute[Fixtures.whatsAppRoute]?.contains { $0.id == "heard" } == true })
    #expect(model.messagesByRoute[Fixtures.telegramRoute]?.contains { $0.id == "muted" } == true)
    #expect(notified == ["heard"])

    let relaunched = InboxPlusAppModel(gateway: InMemoryMessagingGateway(seed: Fixtures.snapshot), preferenceStore: store)
    try await relaunched.start()
    defer { relaunched.stop() }
    #expect(relaunched.isMuted(Fixtures.telegramRoute))
    relaunched.perform(.unmute, on: family)
    #expect(!relaunched.isMuted(Fixtures.telegramRoute))
    #expect(try !store.load().isMuted(Fixtures.telegramRoute, at: Date()))
}

@MainActor
@Test(.timeLimit(.minutes(1))) func hidingKeepsAConversationOutOfTheInboxUntilSomeoneWritesInIt() async throws {
    let (store, root) = makeStore()
    defer { try? FileManager.default.removeItem(at: root) }
    let gateway = PublishingGateway(snapshot: Fixtures.snapshot)
    let model = InboxPlusAppModel(gateway: gateway, preferenceStore: store)
    try await model.start()
    defer { model.stop() }

    let family = try item(Fixtures.telegramRoute, in: model)
    let maya = try item(Fixtures.whatsAppRoute, in: model)
    model.perform(.hide, on: family)
    model.perform(.hide, on: maya)
    model.perform(.mute(.forever), on: maya)
    #expect(Set(model.hiddenInboxItems.map(\.id)) == [family.id, maya.id])
    #expect(model.listedInboxItems.map(\.id) == [.conversation(Fixtures.instagramRoute)])
    model.navigateConversation(forward: true, query: "", filter: InboxFilter())
    #expect(model.openRoute == Fixtures.instagramRoute)

    let relaunched = InboxPlusAppModel(gateway: InMemoryMessagingGateway(seed: Fixtures.snapshot), preferenceStore: store)
    try await relaunched.start()
    #expect(relaunched.hiddenInboxItems.count == 2)
    relaunched.stop()

    await gateway.publish(.messageUpserted(incoming("news", in: Fixtures.telegramRoute)))
    await gateway.publish(.messageUpserted(incoming("noise", in: Fixtures.whatsAppRoute)))
    #expect(await settle { model.listedInboxItems.contains { $0.id == family.id } })
    // Muting is what keeps a noisy conversation hidden while people keep writing in it.
    #expect(await settle { model.messagesByRoute[Fixtures.whatsAppRoute]?.contains { $0.id == "noise" } == true })
    #expect(model.hiddenInboxItems.map(\.id) == [maya.id])
    #expect(try store.load().hidden == [Fixtures.whatsAppRoute])

    model.perform(.unhide, on: maya)
    #expect(model.hiddenInboxItems.isEmpty)
}

@MainActor
@Test(.timeLimit(.minutes(1))) func aConversationMarkedUnreadStaysUnreadUntilItIsOpened() async throws {
    let (store, root) = makeStore()
    defer { try? FileManager.default.removeItem(at: root) }
    let gateway = PublishingGateway(snapshot: Fixtures.snapshot)
    let model = InboxPlusAppModel(gateway: gateway, directory: Fixtures.directory, preferenceStore: store)
    try await model.start()
    defer { model.stop() }

    model.perform(.markUnread, on: try item(Fixtures.telegramRoute, in: model))
    #expect(try item(Fixtures.telegramRoute, in: model).unreadCount == 1)

    // The network still counts nothing unread there; that must not clear the user's mark.
    let reported = try #require(Fixtures.snapshot.conversations.first { $0.route == Fixtures.telegramRoute })
    await gateway.publish(.conversationUpserted(reported))
    await gateway.publish(.historicalMessageUpserted(incoming("sentinel", in: Fixtures.telegramRoute)))
    #expect(await settle { model.messagesByRoute[Fixtures.telegramRoute]?.contains { $0.id == "sentinel" } == true })
    #expect(model.conversations.first { $0.route == Fixtures.telegramRoute }?.unreadCount == 1)

    let relaunched = InboxPlusAppModel(gateway: InMemoryMessagingGateway(seed: Fixtures.snapshot), preferenceStore: store)
    try await relaunched.start()
    #expect(relaunched.conversations.first { $0.route == Fixtures.telegramRoute }?.unreadCount == 1)
    relaunched.openConversation(Fixtures.telegramRoute)
    #expect(relaunched.conversations.first { $0.route == Fixtures.telegramRoute }?.unreadCount == 0)
    #expect(try store.load().markedUnread.isEmpty)
    relaunched.stop()

    // A row that groups a person's networks is read as a whole, and marked unread by its latest.
    let maya = try #require(model.inboxItems.first { $0.id == .person("maya") })
    #expect(maya.unreadCount == 3)
    model.perform(.markRead, on: maya)
    #expect(try #require(model.inboxItems.first { $0.id == maya.id }).unreadCount == 0)
    model.perform(.markUnread, on: maya)
    #expect(model.conversations.first { $0.route == Fixtures.instagramRoute }?.unreadCount == 1)
    #expect(model.conversations.first { $0.route == Fixtures.whatsAppRoute }?.unreadCount == 0)
}

// MARK: - Messages

@MainActor
@Test(.timeLimit(.minutes(1))) func aReplyIsSentAsOneAndTheComposerStopsReplyingAfterwards() async throws {
    let model = InboxPlusAppModel(gateway: InMemoryMessagingGateway(seed: Fixtures.snapshot))
    try await model.start()
    defer { model.stop() }
    let route = Fixtures.instagramRoute
    let original = try #require(model.messagesByRoute[route]?.first)

    model.beginReply(to: original)
    #expect(model.replyTarget(in: route)?.id == original.id)
    #expect(model.replyTarget(in: Fixtures.whatsAppRoute) == nil)
    model.setDraft("On my way", for: route)
    try await model.sendDraft(model.captureDraft(to: route))

    #expect(model.replyTarget(in: route) == nil)
    #expect(await settle { model.messagesByRoute[route]?.contains { $0.body == "On my way" } == true })
    let sent = model.messagesByRoute[route]?.first { $0.body == "On my way" }
    #expect(sent?.replyTo?.messageID == original.id)
    #expect(sent?.replyTo?.body == original.body)
}

@MainActor
@Test(.timeLimit(.minutes(1))) func withoutTextTheFirstFileCarriesTheReply() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let model = InboxPlusAppModel(gateway: InMemoryMessagingGateway(seed: Fixtures.snapshot))
    try await model.start()
    defer { model.stop() }
    let route = Fixtures.instagramRoute
    let original = try #require(model.messagesByRoute[route]?.first)
    for name in ["first.png", "second.png"] {
        let url = directory.appendingPathComponent(name)
        try Data(repeating: 1, count: 16).write(to: url)
        #expect(model.stageAttachment(at: url, for: route) == nil)
    }

    model.beginReply(to: original)
    let submission = model.captureDraft(to: route)
    try await model.sendStagedAttachments(for: submission)
    try await model.sendDraft(submission)

    func sent(_ name: String) -> Message? {
        model.messagesByRoute[route]?.first { $0.attachments.first?.filename == name }
    }
    #expect(await settle { sent("first.png") != nil && sent("second.png") != nil })
    #expect(sent("first.png")?.replyTo?.messageID == original.id)
    #expect(sent("second.png")?.replyTo == nil)
    #expect(model.replyTarget(in: route) == nil)
}

@MainActor
@Test(.timeLimit(.minutes(1))) func reactionsAndRepliesAreOnlyOfferedWhereTheNetworkTakesThem() async throws {
    var snapshot = Fixtures.snapshot
    let textOnly = try #require(snapshot.conversations.firstIndex { $0.route == Fixtures.telegramRoute })
    snapshot.conversations[textOnly].capabilities = .textOnly
    let model = InboxPlusAppModel(gateway: InMemoryMessagingGateway(seed: snapshot))
    try await model.start()
    defer { model.stop() }

    let original = try #require(model.messagesByRoute[Fixtures.instagramRoute]?.first)
    #expect(model.canReact(to: original))
    try await model.toggleReaction("👍", on: original)
    #expect(await settle {
        model.messagesByRoute[Fixtures.instagramRoute]?.first?.reactions
            == [MessageReaction(key: "👍", count: 1, includesMe: true)]
    })

    let family = try #require(model.messagesByRoute[Fixtures.telegramRoute]?.first)
    #expect(!model.canReact(to: family))
    #expect(!model.canReply(to: family))
    await #expect(throws: MessageInteractionError.unsupported) {
        try await model.toggleReaction("👍", on: family)
    }
    model.beginReply(to: family)
    #expect(model.replyTarget(in: Fixtures.telegramRoute) == nil)

    var pending = original
    pending.deliveryState = .pending
    #expect(!model.canReply(to: pending))
}
