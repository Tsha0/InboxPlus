import Foundation
import Testing
import InboxPlusCore
import MatrixRustSDK
import InboxPlusGateway
@testable import InboxPlusMatrix

private final class NotificationTimelineItem: TimelineItem, @unchecked Sendable {
    let event: EventTimelineItem?
    init(id: String, origin: EventItemOrigin, pending: Bool = false, content: TimelineItemContent = .callInvite) {
        event = EventTimelineItem(
            isRemote: !pending, eventOrTransactionId: pending ? .transactionId(transactionId: id) : .eventId(eventId: id), sender: "@sender:server",
            senderProfile: .unavailable, forwarder: nil, forwarderProfile: nil,
            isOwn: pending, isEditable: false, content: content, eventTypeRaw: "m.call.invite",
            timestamp: 1000, localSendState: pending ? .notSentYet(progress: nil) : nil, localCreatedAt: nil, readReceipts: [:],
            origin: origin, canBeRepliedTo: false,
            lazyProvider: LazyTimelineItemProvider(noHandle: .init()))
        super.init(noHandle: .init())
    }
    required init(unsafeFromHandle handle: UInt64) { fatalError("Test fake") }
    override func asEvent() -> EventTimelineItem? { event }
}

private final class NotificationEvents: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [GatewayEvent] = []
    func append(_ event: GatewayEvent) { lock.withLock { stored.append(event) } }
    var liveIDs: [String] {
        lock.withLock {
            stored.compactMap { if case let .messageUpserted(message) = $0 { message.id } else { nil } }
        }
    }
    var removedIDs: Set<String> {
        lock.withLock {
            stored.reduce(into: Set<String>()) { ids, event in
                if case let .messagesRemoved(_, removed) = event { ids.formUnion(removed) }
            }
        }
    }
    var count: Int { lock.withLock { stored.count } }
}

@Test func timelineOnlyNotifiesNewSyncTailEvents() {
    let events = NotificationEvents()
    let observer = RoomTimelineObserver(roomID: "room", normalizer: .init(accountID: "account"), accountID: "account") {
        events.append($0)
    }
    observer.onUpdate(diff: [.append(values: [NotificationTimelineItem(id: "initial", origin: .sync)])])
    observer.onUpdate(diff: [.pushBack(value: NotificationTimelineItem(id: "page", origin: .pagination))])
    observer.onUpdate(diff: [.append(values: [NotificationTimelineItem(id: "cache", origin: .cache)])])
    observer.onUpdate(diff: [.pushFront(value: NotificationTimelineItem(id: "front", origin: .sync))])
    observer.onUpdate(diff: [.reset(values: [NotificationTimelineItem(id: "reset", origin: .sync)])])
    let live = NotificationTimelineItem(id: "live", origin: .sync)
    observer.onUpdate(diff: [.pushBack(value: live)])
    observer.onUpdate(diff: [.pushBack(value: live)])
    #expect(events.liveIDs == ["live"])
    #expect(events.count == 7)

    // Discovering that the sender belongs to this account updates every message, but
    // the corrected attribution is history, not a second live arrival.
    observer.updateOutgoingIdentifiers(["@sender:server"])
    #expect(events.liveIDs == ["live"])
    #expect(events.count == 9)
}

@Test func metadataIsExcludedFromLoadedHistoryAndLiveNotifications() async {
    let events = NotificationEvents()
    let observer = RoomTimelineObserver(roomID: "room", normalizer: .init(accountID: "account"), accountID: "account") {
        events.append($0)
    }
    let membership = NotificationTimelineItem(id: "membership", origin: .sync, content:
        .roomMembership(userId: "@sender:server", userDisplayName: "Sender", change: .joined, reason: nil))
    let profile = NotificationTimelineItem(id: "profile", origin: .sync, content:
        .profileChange(displayName: "Sender", prevDisplayName: nil, avatarUrl: nil, prevAvatarUrl: nil))
    observer.onUpdate(diff: [.reset(values: [membership, profile])])
    #expect(await observer.messages(waitingUpTo: .zero).isEmpty)
    observer.onUpdate(diff: [.pushBack(value: membership), .pushBack(value: profile)])
    #expect(events.count == 0)
    #expect(await observer.messages(waitingUpTo: .zero).isEmpty)
    observer.onUpdate(diff: [.pushBack(value: NotificationTimelineItem(id: "human", origin: .sync))])
    #expect(events.liveIDs == ["human"])
    #expect(await observer.messages(waitingUpTo: .zero).map(\.id) == ["human"])
}

@Test func serverConfirmationReplacesPendingTimelineMessage() async throws {
    let events = NotificationEvents()
    let observer = RoomTimelineObserver(roomID: "room", normalizer: .init(accountID: "account"), accountID: "account") {
        events.append($0)
    }
    let metadata = NotificationTimelineItem(id: "membership", origin: .sync, content:
        .roomMembership(userId: "@sender:server", userDisplayName: "Sender", change: .joined, reason: nil))
    observer.onUpdate(diff: [.reset(values: [metadata])])
    observer.onUpdate(diff: [.pushBack(value: NotificationTimelineItem(id: "local", origin: .sync, pending: true))])
    #expect(observer.message(id: "txn:local")?.deliveryState == .pending)
    observer.onUpdate(diff: [.set(index: 1, value: NotificationTimelineItem(id: "$confirmed", origin: .sync))])
    let messages = await observer.messages(waitingUpTo: .zero)
    #expect(messages.map(\.id) == ["$confirmed"])
    #expect(messages.first?.deliveryState == .acknowledged)
    #expect(observer.message(id: "txn:local") == nil)
    #expect(events.removedIDs == ["txn:local"])
    observer.updateOutgoingIdentifiers(["@sender:server"])
    #expect(observer.message(id: "txn:local") == nil)
}

@Test func timelineAppliesIndexedChangesAndRemovalsWithoutMergingIdenticalMessages() async {
    let events = NotificationEvents()
    let observer = RoomTimelineObserver(roomID: "room", normalizer: .init(accountID: "account"), accountID: "account") {
        events.append($0)
    }
    func item(_ id: String) -> TimelineItem { NotificationTimelineItem(id: id, origin: .sync) }
    observer.onUpdate(diff: [.reset(values: [item("a"), item("b"), item("c")])])
    #expect(observer.messageCount == 3)
    observer.onUpdate(diff: [.pushFront(value: item("front")), .insert(index: 2, value: item("middle")),
                             .pushBack(value: item("back")), .popFront, .popBack, .remove(index: 1)])
    #expect(Set(await observer.messages(waitingUpTo: .zero).map(\.id)) == ["a", "b", "c"])
    observer.onUpdate(diff: [.truncate(length: 1)])
    #expect(await observer.messages(waitingUpTo: .zero).map(\.id) == ["a"])
    observer.onUpdate(diff: [.reset(values: [item("reset")])])
    #expect(await observer.messages(waitingUpTo: .zero).map(\.id) == ["reset"])
    observer.onUpdate(diff: [.clear])
    #expect(observer.messageCount == 0)
    #expect(events.removedIDs == ["a", "b", "c", "reset"])
}

@Test func replacingAMessageWithMetadataRemovesItsBubble() {
    let events = NotificationEvents()
    let observer = RoomTimelineObserver(roomID: "room", normalizer: .init(accountID: "account"), accountID: "account") {
        events.append($0)
    }
    observer.onUpdate(diff: [.reset(values: [NotificationTimelineItem(id: "event", origin: .sync)])])
    observer.onUpdate(diff: [.set(index: 0, value: NotificationTimelineItem(id: "event", origin: .sync, content:
        .roomMembership(userId: "@sender:server", userDisplayName: "Sender", change: .joined, reason: nil)))])
    #expect(observer.messageCount == 0)
    #expect(events.removedIDs == ["event"])
}
