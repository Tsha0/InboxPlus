import Foundation
import Testing
import MatrixRustSDK
import InboxPlusGateway
@testable import InboxPlusMatrix

private final class NotificationTimelineItem: TimelineItem, @unchecked Sendable {
    let event: EventTimelineItem?
    init(id: String, origin: EventItemOrigin, content: TimelineItemContent = .callInvite) {
        event = EventTimelineItem(
            isRemote: true, eventOrTransactionId: .eventId(eventId: id), sender: "@sender:server",
            senderProfile: .unavailable, forwarder: nil, forwarderProfile: nil,
            isOwn: false, isEditable: false, content: content, eventTypeRaw: "m.call.invite",
            timestamp: 1000, localSendState: nil, localCreatedAt: nil, readReceipts: [:],
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
    #expect(events.count == 6)

    // Discovering that the sender belongs to this account updates every message, but
    // the corrected attribution is history, not a second live arrival.
    observer.updateOutgoingIdentifiers(["@sender:server"])
    #expect(events.liveIDs == ["live"])
    #expect(events.count == 12)
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
