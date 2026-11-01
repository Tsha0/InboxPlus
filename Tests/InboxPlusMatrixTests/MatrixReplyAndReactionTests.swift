import Foundation
import MatrixRustSDK
import InboxPlusCore
import Testing
@testable import InboxPlusMatrix

private let ownUser = "@owner:local"
private let ownGhost = "@instagram_123:local"

/// The FFI supplies a NoHandle initializer for SDK fakes; nothing here is lowered to Rust.
private final class QuotedEvent: InReplyToDetails, @unchecked Sendable {
    private let id: String
    private let details: EmbeddedEventDetails
    init(_ id: String, _ details: EmbeddedEventDetails) {
        self.id = id
        self.details = details
        super.init(noHandle: .init())
    }
    required init(unsafeFromHandle handle: UInt64) { fatalError("not a Rust object") }
    override func eventId() -> String { id }
    override func event() -> EmbeddedEventDetails { details }
}

private func text(_ body: String) -> TimelineItemContent {
    .msgLike(content: MsgLikeContent(
        kind: .message(content: MessageContent(
            msgType: .text(content: TextMessageContent(body: body, formatted: nil)),
            body: body, isEdited: false, mentions: nil
        )), reactions: [], inReplyTo: nil, threadRoot: nil, threadSummary: nil
    ))
}

private func event(reactions: [Reaction] = [], inReplyTo: InReplyToDetails? = nil) -> EventTimelineItem {
    EventTimelineItem(
        isRemote: true, eventOrTransactionId: .eventId(eventId: "$reply"), sender: "@instagram_456:local",
        senderProfile: .unavailable, forwarder: nil, forwarderProfile: nil,
        isOwn: false, isEditable: false,
        content: .msgLike(content: MsgLikeContent(
            kind: .message(content: MessageContent(
                msgType: .text(content: TextMessageContent(body: "Sounds good", formatted: nil)),
                body: "Sounds good", isEdited: false, mentions: nil
            )), reactions: reactions, inReplyTo: inReplyTo, threadRoot: nil, threadSummary: nil
        )),
        eventTypeRaw: "m.room.message", timestamp: 123_000, localSendState: nil,
        localCreatedAt: nil, readReceipts: [:], origin: nil, canBeRepliedTo: true,
        lazyProvider: LazyTimelineItemProvider(noHandle: .init())
    )
}

private func senders(_ ids: String...) -> [ReactionSenderData] {
    ids.map { ReactionSenderData(senderId: $0, timestamp: 1) }
}

@Test func reactionsCarryTheirCountAndWhetherThisAccountChoseThem() throws {
    let normalizer = MatrixEventNormalizer(accountID: "instagram")
    let message = try #require(normalizer.normalize(
        event(reactions: [
            Reaction(key: "❤️", senders: senders("@instagram_456:local", "@instagram_789:local")),
            // Sent from Inbox+ itself.
            Reaction(key: "👍", senders: senders(ownUser)),
            // Sent from the Instagram app, which the bridge relays as this account's ghost.
            Reaction(key: "😂", senders: senders(ownGhost, "@instagram_456:local")),
        ]),
        roomID: "room", outgoingIdentifiers: [ownGhost], ownUserID: ownUser
    ))
    #expect(message.reactions == [
        MessageReaction(key: "❤️", count: 2, includesMe: false),
        MessageReaction(key: "👍", count: 1, includesMe: true),
        MessageReaction(key: "😂", count: 2, includesMe: true),
    ])
}

@Test func aReplyQuotesItsMessageOnceTheTimelineHasLoadedIt() throws {
    let normalizer = MatrixEventNormalizer(accountID: "instagram")
    let loaded = try #require(normalizer.normalize(
        event(inReplyTo: QuotedEvent("$original", .ready(
            content: text("Dinner at 8?"), sender: "@instagram_456:local",
            senderProfile: .ready(displayName: "Maya", displayNameAmbiguous: false, avatarUrl: nil, status: nil, call: nil),
            timestamp: 100, eventOrTransactionId: .eventId(eventId: "$original")
        ))),
        roomID: "room"
    ))
    #expect(loaded.replyTo == MessageReply(messageID: "$original", senderDisplayName: "Maya", body: "Dinner at 8?"))

    let unnamed = normalizer.normalize(
        event(inReplyTo: QuotedEvent("$original", .ready(
            content: text("Dinner at 8?"), sender: "@instagram_456:local", senderProfile: .unavailable,
            timestamp: 100, eventOrTransactionId: .eventId(eventId: "$original")
        ))),
        roomID: "room"
    )
    #expect(unnamed?.replyTo?.senderDisplayName == "instagram_456")

    let pending = try #require(normalizer.normalize(event(inReplyTo: QuotedEvent("$old", .unavailable)), roomID: "room"))
    #expect(pending.replyTo == MessageReply(messageID: "$old"))
    #expect(MatrixMessagingGateway.needsQuotedMessage(pending))
    #expect(!MatrixMessagingGateway.needsQuotedMessage(loaded))
    #expect(normalizer.normalize(event(), roomID: "room")?.replyTo == nil)
}

@Test func aLocalEchoIsNeverAskedForItsQuotedMessage() {
    let reply = Message(
        id: "txn:abc", route: .init(accountID: "instagram", conversationID: "room"), senderIdentityID: nil,
        body: "Yes", timestamp: .now, deliveryState: .pending, replyTo: MessageReply(messageID: "$original")
    )
    #expect(!MatrixMessagingGateway.needsQuotedMessage(reply))
}

@Test func messageIdentifiersMapBackToTheTimelineItemTheyCameFrom() {
    let normalizer = MatrixEventNormalizer(accountID: "instagram")
    for id in [EventOrTransactionId.eventId(eventId: "$event"), .transactionId(transactionId: "abc")] {
        #expect(normalizer.eventOrTransactionID(for: normalizer.identifier(for: id)) == id)
    }
}
