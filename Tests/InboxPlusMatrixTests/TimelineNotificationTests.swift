import Foundation
import Testing
import MatrixRustSDK
import InboxPlusGateway
@testable import InboxPlusMatrix

private final class NotificationTimelineItem: TimelineItem, @unchecked Sendable {
    let event: EventTimelineItem?
    init(id: String, origin: EventItemOrigin) {
        event = EventTimelineItem(
            isRemote: true, eventOrTransactionId: .eventId(eventId: id), sender: "@sender:server",
            senderProfile: .unavailable, forwarder: nil, forwarderProfile: nil,
            isOwn: false, isEditable: false, content: .callInvite, eventTypeRaw: "m.call.invite",
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
}
