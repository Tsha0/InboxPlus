import Foundation
import MatrixRustSDK
import InboxPlusCore
import InboxPlusGateway
import Testing
@testable import InboxPlusMatrix

private let ownerGhost = "@instagram_123:local"
private let otherGhost = "@instagram_456:local"

private func bridgedEvent(
    _ id: String,
    sender: String = ownerGhost,
    isOwn: Bool = false,
    body: String = "Sent from the native app"
) -> EventTimelineItem {
    EventTimelineItem(
        isRemote: true, eventOrTransactionId: .eventId(eventId: id), sender: sender,
        senderProfile: .unavailable, forwarder: nil, forwarderProfile: nil,
        isOwn: isOwn, isEditable: false,
        content: .msgLike(content: MsgLikeContent(
            kind: .message(content: MessageContent(
                msgType: .text(content: TextMessageContent(body: body, formatted: nil)),
                body: body, isEdited: false, mentions: nil
            )), reactions: [], inReplyTo: nil, threadRoot: nil, threadSummary: nil
        )),
        eventTypeRaw: "m.room.message", timestamp: 123_000, localSendState: nil,
        localCreatedAt: nil, readReceipts: [:], origin: nil, canBeRepliedTo: true,
        lazyProvider: LazyTimelineItemProvider(noHandle: .init())
    )
}

/// The FFI supplies a NoHandle initializer specifically for SDK fakes; none is lowered to Rust.
private final class EventItem: TimelineItem, @unchecked Sendable {
    private let event: EventTimelineItem
    init(_ event: EventTimelineItem) {
        self.event = event
        super.init(noHandle: .init())
    }
    required init(unsafeFromHandle handle: UInt64) { fatalError("not a Rust object") }
    override func asEvent() -> EventTimelineItem? { event }
}

private final class MessagesReceived: @unchecked Sendable {
    private let lock = NSLock()
    private var messages: [Message] = []
    func receive(_ event: GatewayEvent) {
        if case let .messageUpserted(message) = event {
            lock.withLock { messages.append(message) }
        }
    }
    var all: [Message] { lock.withLock { messages } }
}

@Test func nativeAppGhostMessagesAreOutgoingWithoutChangingSDKOwnMessagesOrOtherSenders() throws {
    let normalizer = MatrixEventNormalizer(accountID: "matrix-local")
    let own = try #require(normalizer.normalize(
        bridgedEvent("own"), roomID: "group", accountID: "instagram", outgoingIdentifiers: [ownerGhost]
    ))
    #expect(own.isOutgoing)
    #expect(own.deliveryState == .acknowledged)
    #expect(own.route.accountID == "instagram")

    let incoming = try #require(normalizer.normalize(
        bridgedEvent("incoming", sender: otherGhost), roomID: "group", outgoingIdentifiers: [ownerGhost]
    ))
    #expect(incoming.senderIdentityID == otherGhost)
    #expect(!incoming.isOutgoing)
    #expect(normalizer.normalize(
        bridgedEvent("matrix-own", sender: "@owner:local", isOwn: true), roomID: "group"
    )?.isOutgoing == true)
    // A sender shared with a different bridge/account cannot be trusted in this room.
    #expect(normalizer.normalize(bridgedEvent("unmapped"), roomID: "matrix-room")?.isOutgoing == false)
    #expect(normalizer.normalize(
        bridgedEvent("bot", sender: "@instagrambot:local"), roomID: "group", outgoingIdentifiers: [ownerGhost]
    )?.isOutgoing == false)
}

@Test func historyAndLiveUpdatesShareOwnerAttributionInGroups() async throws {
    let received = MessagesReceived()
    let observer = RoomTimelineObserver(
        roomID: "group", normalizer: MatrixEventNormalizer(accountID: "matrix-local"),
        accountID: "instagram", outgoingIdentifiers: [ownerGhost], onEvent: received.receive
    )
    observer.onUpdate(diff: [.reset(values: [
        EventItem(bridgedEvent("history-own")),
        EventItem(bridgedEvent("history-other", sender: otherGhost))
    ])])
    observer.onUpdate(diff: [.pushBack(value: EventItem(bridgedEvent("live-own"))),
                             .append(values: [EventItem(bridgedEvent("live-other", sender: otherGhost))])])
    let messages = await observer.messages(waitingUpTo: .zero)
    #expect(messages.count == 4)
    #expect(messages.filter(\.isOutgoing).map(\.id).sorted() == ["history-own", "live-own"])
    #expect(messages.filter { !$0.isOutgoing }.allSatisfy { $0.senderIdentityID == otherGhost })
    #expect(messages.allSatisfy { $0.route.accountID == "instagram" })
    #expect(received.all.count == 4)
    // Edits continue to carry the native app sender's outgoing attribution.
    observer.onUpdate(diff: [.set(index: 0, value: EventItem(bridgedEvent("history-own", body: "Edited")))])
    #expect(received.all.last?.body == "Edited")
    #expect(received.all.last?.isOutgoing == true)
}

@Test func identityRecoveryReclassifiesHistoryAndPublishesOnlyChangedMessages() async throws {
    let received = MessagesReceived()
    let observer = RoomTimelineObserver(
        roomID: "group", normalizer: MatrixEventNormalizer(accountID: "matrix-local"),
        accountID: "instagram", onEvent: received.receive
    )
    observer.onUpdate(diff: [.reset(values: [
        EventItem(bridgedEvent("own")), EventItem(bridgedEvent("other", sender: otherGhost))
    ])])
    #expect(received.all.allSatisfy { !$0.isOutgoing })
    observer.updateOutgoingIdentifiers([ownerGhost])
    #expect(received.all.count == 3)
    #expect(received.all.last?.id == "own")
    #expect(received.all.last?.isOutgoing == true)
    observer.updateOutgoingIdentifiers([ownerGhost])
    observer.onUpdate(diff: [.pushBack(value: EventItem(bridgedEvent("own")))])
    #expect(received.all.count == 3)
    let snapshot = await observer.messages(waitingUpTo: .zero)
    #expect(snapshot.first { $0.id == "own" }?.isOutgoing == true)
    #expect(snapshot.first { $0.id == "other" }?.senderIdentityID == otherGhost)
}

@Test func confirmedBotSendsAreOutgoingWhileBotNoticesAndOtherPeopleStayIncoming() throws {
    let normalizer = MatrixEventNormalizer(accountID: "gvoice")
    let bot = "@gvoicebot:local"
    let outgoing = try #require(normalizer.normalize(
        bridgedEvent("$voice-send", sender: bot), roomID: "voice",
        outgoingIdentifiers: ["$voice-send"]
    ))
    #expect(outgoing.isOutgoing)
    #expect(normalizer.normalize(
        bridgedEvent("$bot-notice", sender: bot), roomID: "voice",
        outgoingIdentifiers: ["$voice-send"]
    )?.senderIdentityID == bot)
    #expect(normalizer.normalize(
        bridgedEvent("$voice-incoming", sender: "@gvoice_peer:local"), roomID: "voice",
        outgoingIdentifiers: ["$voice-send"]
    )?.isOutgoing == false)
}
