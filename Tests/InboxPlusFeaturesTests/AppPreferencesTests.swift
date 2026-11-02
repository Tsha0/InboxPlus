import Foundation
import Testing
import InboxPlusCore
import InboxPlusGateway
@testable import InboxPlusFeatures

private struct SendRefused: Error {}

private actor PreferenceGateway: TextOnlyTestGateway {
    let stream = AsyncStream<GatewayEvent>.makeStream()
    let snapshot: MessagingSnapshot
    private(set) var sent: [String] = []
    private var refusing = false
    private var held: CheckedContinuation<Void, Never>?
    private var holding = false

    init(snapshot: MessagingSnapshot) { self.snapshot = snapshot }

    func loadSnapshot() async throws -> MessagingSnapshot { snapshot }
    func events() async -> AsyncStream<GatewayEvent> { stream.stream }
    func publish(_ event: GatewayEvent) { stream.continuation.yield(event) }
    func refuseSends() { refusing = true }
    func holdSends() { holding = true }
    var isHoldingASend: Bool { held != nil }

    func release() {
        holding = false
        held?.resume()
        held = nil
    }

    func sendText(_ body: String, to route: ConversationRoute) async throws -> SendReceipt {
        if holding { await withCheckedContinuation { held = $0 } }
        if refusing { throw SendRefused() }
        sent.append(body)
        return .init(messageID: "sent-\(sent.count)", route: route, deliveryState: .acknowledged)
    }
}

private let account = ConnectedAccount(id: "instagram", platform: .instagram, displayName: "Instagram")
private let direct = ConversationRoute(accountID: "instagram", conversationID: "!sam")
private let group = ConversationRoute(accountID: "instagram", conversationID: "!trip")

private func seed() -> MessagingSnapshot {
    MessagingSnapshot(
        accounts: [account],
        identities: [
            RemoteIdentity(id: "sam", accountID: "instagram", displayName: "Sam"),
            RemoteIdentity(id: "maya", accountID: "instagram", displayName: "Maya"),
            RemoteIdentity(id: "trip", accountID: "instagram", displayName: "Weekend Trip"),
        ],
        conversations: [
            RemoteConversation(id: "!sam", accountID: "instagram", identityID: "sam", title: "Sam",
                               latestActivity: Date(timeIntervalSince1970: 100), unreadCount: 2),
            RemoteConversation(id: "!trip", accountID: "instagram", identityID: "trip", title: "Weekend Trip",
                               latestActivity: Date(timeIntervalSince1970: 200), unreadCount: 3,
                               capabilities: ConversationCapabilities(canSendText: false), isGroup: true),
        ],
        messagesByRoute: [:]
    )
}

private func incoming(_ id: String, in route: ConversationRoute, from sender: String) -> Message {
    Message(id: id, route: route, senderIdentityID: sender, body: id, timestamp: Date(), deliveryState: .acknowledged)
}

private func temporaryFile(_ name: String) -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathComponent(name)
}

/// Events are applied on the main actor after they are published, so a sentinel marks the end.
@MainActor
private func drain(_ gateway: PreferenceGateway, _ model: InboxPlusAppModel) async {
    let sentinel = Message(id: UUID().uuidString, route: direct, senderIdentityID: "sam", body: "",
                           timestamp: .distantPast, deliveryState: .acknowledged)
    await gateway.publish(.historicalMessageUpserted(sentinel))
    for _ in 0..<1000 {
        if model.messagesByRoute[direct]?.contains(where: { $0.id == sentinel.id }) == true { return }
        await Task.yield()
    }
    Issue.record("events were not applied")
}

@MainActor
@Test func preferencesAreRememberedBetweenLaunches() throws {
    let suite = "InboxPlusTests-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }

    let first = AppPreferences(defaults: defaults)
    #expect(first.notifications == NotificationPreferences(isEnabled: true, showsPreviews: true, playsSound: true))
    #expect(first.showsUnreadBadge)
    #expect(first.iMessageHistory == .year)
    #expect(first.messageRetention == .week)
    #expect(AppPreferences.messageRetention(in: defaults) == .week)

    first.notifications.showsPreviews = false
    first.notifications.playsSound = false
    first.showsUnreadBadge = false
    first.iMessageHistory = .all
    first.messageRetention = .quarter

    let relaunched = AppPreferences(defaults: defaults)
    #expect(relaunched.notifications == NotificationPreferences(isEnabled: true, showsPreviews: false, playsSound: false))
    #expect(!relaunched.showsUnreadBadge)
    #expect(relaunched.iMessageHistory == .all)
    #expect(AppPreferences.iMessageHistory(in: defaults) == .all)
    #expect(relaunched.messageRetention == .quarter)
    #expect(AppPreferences.messageRetention(in: defaults) == .quarter)
}

@Test func messagesAreKeptForAWeekUntilSomeoneChoosesOtherwise() {
    #expect(MessageRetention.standard == .week)
    #expect(MessageRetention.allCases.map(\.days) == [1, 7, 30, 90, 365])
}

@Test func theDefaultIMessageHistoryWindowIsTheYearInboxPlusAlwaysShowed() {
    #expect(IMessageHistoryWindow.year.interval == TimeInterval(365 * 86_400))
    #expect(IMessageHistoryWindow.all.interval == nil)
    #expect(IMessageHistoryWindow.month.interval! < IMessageHistoryWindow.quarter.interval!)
}

@MainActor
@Test func aMutedConversationNeitherNotifiesNorCountsTowardTheBadge() async throws {
    let store = ConversationPreferenceStore(fileURL: temporaryFile("inbox-conversation-preferences.json"))
    defer { try? FileManager.default.removeItem(at: store.fileURL.deletingLastPathComponent()) }
    let gateway = PreferenceGateway(snapshot: seed())
    let model = InboxPlusAppModel(gateway: gateway, preferenceStore: store)
    var notified: [String] = []
    model.onIncomingMessage = { notified.append($0.message.id) }
    try await model.start()
    #expect(model.unreadBadgeCount == 5)

    model.setMuted(true, for: group)
    #expect(model.isMuted(group))
    #expect(model.unreadBadgeCount == 2)
    #expect(model.mutedConversations.map(\.title) == ["Weekend Trip"])

    await gateway.publish(.messageUpserted(incoming("in-group", in: group, from: "maya")))
    await gateway.publish(.messageUpserted(incoming("direct", in: direct, from: "sam")))
    await drain(gateway, model)
    #expect(notified == ["direct"])

    // A mute is the user's decision about that conversation, so it outlives the session.
    #expect(try store.load().isMuted(group, at: Date()))
    #expect(InboxPlusAppModel(gateway: PreferenceGateway(snapshot: seed()), preferenceStore: store).isMuted(group))

    model.setMuted(false, for: group)
    #expect(model.unreadBadgeCount == 5)
    #expect(try !store.load().isMuted(group, at: Date()))
    model.stop()
}

@MainActor
@Test func removingAnAccountForgetsItsMutes() async throws {
    let store = ConversationPreferenceStore(fileURL: temporaryFile("inbox-conversation-preferences.json"))
    defer { try? FileManager.default.removeItem(at: store.fileURL.deletingLastPathComponent()) }
    let model = InboxPlusAppModel(gateway: PreferenceGateway(snapshot: seed()), preferenceStore: store)
    try await model.start()
    model.setMuted(true, for: group)

    try await model.eraseAccount(accountID: account.id)

    #expect(!model.isMuted(group))
    #expect(try !store.load().isMuted(group, at: Date()))
    model.stop()
}

@MainActor
@Test func aGroupNotificationNamesItsSenderAndOnlyAReplyableOneOffersReply() async throws {
    let gateway = PreferenceGateway(snapshot: seed())
    let model = InboxPlusAppModel(gateway: gateway)
    var alerts: [IncomingMessageAlert] = []
    model.onIncomingMessage = { alerts.append($0) }
    try await model.start()

    await gateway.publish(.messageUpserted(incoming("in-group", in: group, from: "maya")))
    await gateway.publish(.messageUpserted(incoming("direct", in: direct, from: "sam")))
    await drain(gateway, model)

    #expect(alerts.map(\.title) == ["Weekend Trip", "Sam"])
    #expect(alerts.map(\.senderName) == ["Maya", nil])
    #expect(alerts.map(\.canReply) == [false, true])
    model.stop()
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func aReplyFromANotificationIsSentWithoutTouchingTheDraft() async throws {
    let gateway = PreferenceGateway(snapshot: seed())
    let model = InboxPlusAppModel(gateway: gateway)
    try await model.start()

    await gateway.holdSends()
    let reply = Task { try await model.sendReply("  On my way  ", to: direct) }
    while !(await gateway.isHoldingASend) { await Task.yield() }
    // An update restart has to wait for it, like any other send.
    #expect(model.hasUnfinishedMessagingWork)
    await gateway.release()
    try await reply.value

    #expect(await gateway.sent == ["On my way"])
    #expect(!model.hasUnfinishedMessagingWork)
    #expect(model.conversations.first { $0.route == direct }?.unreadCount == 0)

    model.setDraft("half-written", for: group)
    try await model.sendReply("ok", to: group)
    #expect(model.draft(for: group) == "half-written")
    #expect(await gateway.sent == ["On my way", "ok"])
    model.stop()
}

@MainActor
@Test func aReplyThatFailsIsReportedOnItsConversation() async throws {
    let gateway = PreferenceGateway(snapshot: seed())
    let model = InboxPlusAppModel(gateway: gateway)
    try await model.start()
    await gateway.refuseSends()

    await #expect(throws: SendRefused.self) { try await model.sendReply("hello", to: direct) }
    #expect(model.sendFailure(for: direct) != nil)
    #expect(model.conversations.first { $0.route == direct }?.unreadCount == 2)
    model.stop()
}

@MainActor
@Test func noReplyIsSentOnceAnUpdateRestartIsUnderWay() async throws {
    let gateway = PreferenceGateway(snapshot: seed())
    let model = InboxPlusAppModel(gateway: gateway)
    try await model.start()
    model.isPreparingForUpdate = true

    await #expect(throws: ReplyError.restartingToUpdate) { try await model.sendReply("hello", to: direct) }
    #expect(await gateway.sent.isEmpty)
    model.stop()
}
