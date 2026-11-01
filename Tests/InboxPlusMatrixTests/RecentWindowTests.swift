import Foundation
import MatrixRustSDK
import InboxPlusCore
import Testing
@testable import InboxPlusMatrix

private let august = Date(timeIntervalSince1970: 1_785_000_000)
private let today = Date(timeIntervalSince1970: 1_793_000_000)

private func timelineEvent(_ id: String, content: TimelineItemContent, at date: Date) -> EventTimelineItem {
    EventTimelineItem(
        isRemote: true, eventOrTransactionId: .eventId(eventId: id), sender: "@instagram_456:local",
        senderProfile: .unavailable, forwarder: nil, forwarderProfile: nil,
        isOwn: false, isEditable: false, content: content, eventTypeRaw: "m.room.message",
        timestamp: UInt64(date.timeIntervalSince1970 * 1000), localSendState: nil,
        localCreatedAt: nil, readReceipts: [:], origin: .pagination, canBeRepliedTo: true,
        lazyProvider: LazyTimelineItemProvider(noHandle: .init())
    )
}

private func message(_ id: String, at date: Date) -> EventTimelineItem {
    timelineEvent(id, content: .msgLike(content: MsgLikeContent(
        kind: .message(content: MessageContent(
            msgType: .text(content: TextMessageContent(body: "body of \(id)", formatted: nil)),
            body: "body of \(id)", isEdited: false, mentions: nil
        )), reactions: [], inReplyTo: nil, threadRoot: nil, threadSummary: nil
    )), at: date)
}

private func setupEvent(_ id: String, at date: Date) -> EventTimelineItem {
    id.hasSuffix("p")
        ? timelineEvent(id, content: .profileChange(
            displayName: "Alex", prevDisplayName: nil, avatarUrl: nil, prevAvatarUrl: nil
        ), at: date)
        : timelineEvent(id, content: .roomMembership(
            userId: "@instagram_456:local", userDisplayName: "Alex", change: .joined, reason: nil
        ), at: date)
}

private final class EventItem: TimelineItem, @unchecked Sendable {
    private let event: EventTimelineItem
    init(_ event: EventTimelineItem) {
        self.event = event
        super.init(noHandle: .init())
    }
    required init(unsafeFromHandle handle: UInt64) { fatalError("not a Rust object") }
    override func asEvent() -> EventTimelineItem? { event }
}

/// A room's history, oldest first, handed to the observer a page at a time from the newest end,
/// the way the SDK's back-pagination does.
private final class FakeRoom: @unchecked Sendable {
    let observer = RoomTimelineObserver(roomID: "room", normalizer: .init(accountID: "instagram"), accountID: "instagram") { _ in }
    private let lock = NSLock()
    private let events: [EventTimelineItem]
    private var cursor: Int
    private(set) var requested = 0

    init(_ events: [EventTimelineItem]) {
        self.events = events
        cursor = events.count
    }

    func paginate(_ count: UInt16) -> Bool {
        let page: [EventTimelineItem] = lock.withLock {
            requested += Int(count)
            let start = max(0, cursor - Int(count))
            defer { cursor = start }
            return Array(events[start..<cursor])
        }
        observer.onUpdate(diff: page.reversed().map { .pushFront(value: EventItem($0)) })
        return lock.withLock { cursor == 0 }
    }

    func backfill() async {
        await MatrixMessagingGateway.backfill(
            toWindow: RecentHistory.messageCount, step: 20, eventLimit: 200,
            loadedMessages: { self.observer.messageCount },
            paginate: { self.paginate($0) }
        )
    }
}

@Test func backfillCountsMessagesNotTheMemberEventsAroundThem() async {
    // 300 member events and 50 messages. The newest hundred events hold every message, one after
    // each member change, so a single 50-event page would have stopped at 25 messages.
    var events = (0..<250).map { setupEvent("setup-\($0)", at: august) }
    for index in 0..<50 {
        events.append(message("message-\(index)", at: august.addingTimeInterval(Double(index))))
        events.append(setupEvent("member-\(index)", at: today))
    }
    let room = FakeRoom(events)

    await room.backfill()

    #expect(room.observer.messageCount == 50)
    #expect(room.requested == 100)
}

@Test func backfillStopsAtTheEventLimitInARoomOfMostlyMemberChanges() async {
    // One message in every seven events, as in a large group: the window is never reached, and
    // the walk stops at the limit rather than reading the room's whole history.
    let events = (0..<350).map { index in
        index % 7 == 6
            ? message("message-\(index)", at: august.addingTimeInterval(Double(index)))
            : setupEvent("member-\(index)", at: today)
    }
    let room = FakeRoom(events)

    await room.backfill()

    #expect(room.requested == 200)
    #expect(room.observer.messageCount == 29)
}

@Test func backfillStopsAtTheStartOfASmallRoom() async {
    let events = (0..<5).map { setupEvent("member-\($0)", at: today) }
        + (0..<10).map { message("message-\($0)", at: august.addingTimeInterval(Double($0))) }
    let room = FakeRoom(events)

    await room.backfill()

    #expect(room.requested == 20)
    #expect(room.observer.messageCount == 10)
}

@Test func aChatEndsOnItsNewestMessageNotTheSetupEventsSentAfterIt() async throws {
    // A bridge backfills messages with their original timestamps, then sends member and profile
    // events stamped today. Those must not become the last line of the chat or its preview.
    let messages = (0..<60).map { message("message-\($0)", at: august.addingTimeInterval(Double($0) * 86_400)) }
    let setup = (0..<20).map { setupEvent($0.isMultiple(of: 2) ? "setup-\($0)p" : "setup-\($0)", at: today) }
    let observer = RoomTimelineObserver(roomID: "room", normalizer: .init(accountID: "instagram"), accountID: "instagram") { _ in }
    observer.onUpdate(diff: [.reset(values: (messages + setup).map(EventItem.init))])

    let ordered = await observer.messages(waitingUpTo: .zero).sorted(by: inboxplusMessageOrdering)
    #expect(ordered.count == 60)
    #expect(ordered.last?.id == "message-59")

    let conversation = MatrixMessagingGateway.conversation(
        roomID: "room", accountID: "instagram", identityID: "@instagram_456:local", title: "Alex",
        messages: ordered, unreadCount: 0, isGroup: false, deepLink: nil
    )
    #expect(conversation.latestPreview == "body of message-59")
    #expect(conversation.latestActivity == august.addingTimeInterval(59 * 86_400))
}

private func roomState(_ events: [[String: Any]]) throws -> Data {
    try JSONSerialization.data(withJSONObject: events)
}

private func member() -> [String: Any] {
    ["type": "m.room.member", "state_key": "@instagram_456:local", "content": ["membership": "join"]]
}

@Test func anInstagramPortalLinksToItsThreadOnInstagram() throws {
    let state = try roomState([member(), [
        "type": "m.bridge", "state_key": "instagram",
        "content": ["protocol": ["id": "instagram"], "channel": ["id": "17843697123456789"]],
    ]])

    let link = try #require(BridgeChannelLink.link(inRoomState: state, platform: .instagram))
    #expect(link.url.absoluteString == "https://www.instagram.com/direct/t/17843697123456789/")
    #expect(link.platform == .instagram)
}

@Test func theOlderBridgeStateEventTypeIsReadToo() throws {
    let state = try roomState([[
        "type": "uk.half-shot.bridge", "state_key": "instagram", "content": ["channel": ["id": "42"]],
    ]])
    #expect(BridgeChannelLink.link(inRoomState: state, platform: .instagram)?.url.absoluteString
        == "https://www.instagram.com/direct/t/42/")
}

@Test func aChannelIDThatIsNotAThreadNumberGetsNoLink() throws {
    for id in ["", "../../accounts/login", "123/../456", "１２３", "123?next=evil", "12 3"] {
        let state = try roomState([["type": "m.bridge", "content": ["channel": ["id": id]]]])
        #expect(BridgeChannelLink.link(inRoomState: state, platform: .instagram) == nil, "\(id)")
    }
}

@Test func onlyNetworksWithAKnownThreadLinkGetOne() throws {
    let state = try roomState([["type": "m.bridge", "content": ["channel": ["id": "42"]]]])
    #expect(BridgeChannelLink.supports(.instagram))
    for platform in Platform.allCases where platform != .instagram {
        #expect(!BridgeChannelLink.supports(platform))
        #expect(BridgeChannelLink.link(inRoomState: state, platform: platform) == nil)
    }
}

@Test func aRoomWithoutBridgeStateGetsNoLink() throws {
    #expect(BridgeChannelLink.link(inRoomState: try roomState([member()]), platform: .instagram) == nil)
    #expect(BridgeChannelLink.link(inRoomState: Data("not json".utf8), platform: .instagram) == nil)
}
