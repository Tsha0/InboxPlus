import Foundation
import MatrixRustSDK
import PalloCore

/// What a normalized timeline event actually was, so Phase 5 can render media properly and Phase 3
/// can already tell ordinary text from a placeholder.
public enum NormalizedEventKind: String, Sendable, Equatable {
    case text
    case notice
    case emote
    case image
    case audio
    case video
    case file
    case gallery
    case location
    case sticker
    case poll
    case redacted
    case encrypted
    case membership
    case state
    case unsupported

    /// True when Pallo is showing a placeholder rather than the real content.
    public var isPlaceholder: Bool {
        switch self {
        case .text, .notice, .emote: false
        default: true
        }
    }
}

public struct NormalizedEvent: Sendable, Equatable {
    public let message: Message
    public let kind: NormalizedEventKind

    public init(message: Message, kind: NormalizedEventKind) {
        self.message = message
        self.kind = kind
    }
}

/// Maps Matrix timeline events onto Pallo's domain model.
///
/// The design forbids silently dropping anything: every event Pallo cannot render natively still
/// becomes a visible message with a placeholder body, and unknown or undecryptable events are
/// labelled rather than hidden.
public struct MatrixEventNormalizer: Sendable {
    public let accountID: String

    public init(accountID: String) {
        self.accountID = accountID
    }

    public func route(forRoom roomID: String) -> ConversationRoute {
        ConversationRoute(accountID: accountID, conversationID: roomID)
    }

    public func normalize(_ item: EventTimelineItem, roomID: String) -> NormalizedEvent {
        let (body, kind) = describe(item.content)
        let message = Message(
            id: identifier(for: item.eventOrTransactionId),
            route: route(forRoom: roomID),
            // An outgoing message carries no remote sender identity, matching `Message.isOutgoing`.
            senderIdentityID: item.isOwn ? nil : item.sender,
            body: body,
            timestamp: Self.date(from: item.timestamp),
            deliveryState: Self.deliveryState(for: item.localSendState)
        )
        return NormalizedEvent(message: message, kind: kind)
    }

    /// Local echoes are keyed by transaction ID until the server assigns an event ID.
    public func identifier(for id: EventOrTransactionId) -> String {
        switch id {
        case let .eventId(eventId): eventId
        case let .transactionId(transactionId): "txn:\(transactionId)"
        }
    }

    /// A send is only `acknowledged` once the server confirms it.
    ///
    /// A remote event has no local send state — it exists because the server already accepted it.
    public static func deliveryState(for state: EventSendState?) -> MessageDeliveryState {
        switch state {
        case .none, .some(.sent):
            .acknowledged
        case .some(.notSentYet):
            .pending
        case let .some(.sendingFailed(error, isRecoverable)):
            .failed(isRecoverable ? "\(error) (will retry)" : "\(error)")
        }
    }

    public static func date(from timestamp: Timestamp) -> Date {
        Date(timeIntervalSince1970: Double(timestamp) / 1000)
    }

    // MARK: - Content

    func describe(_ content: TimelineItemContent) -> (String, NormalizedEventKind) {
        switch content {
        case let .msgLike(msgLike):
            describe(msgLike.kind)
        case let .roomMembership(_, displayName, change, _):
            ("\(displayName ?? "Someone") \(Self.describe(change))", .membership)
        case .profileChange:
            ("Updated their profile", .membership)
        case let .state(_, state):
            ("Conversation setting changed (\(Self.describe(state)))", .state)
        case let .failedToParseMessageLike(eventType, _):
            ("Unsupported message (\(eventType))", .unsupported)
        case let .failedToParseState(eventType, _, _):
            ("Unsupported conversation change (\(eventType))", .unsupported)
        case .callInvite:
            ("Call invitation", .unsupported)
        case .rtcNotification:
            ("Call notification", .unsupported)
        }
    }

    private func describe(_ kind: MsgLikeKind) -> (String, NormalizedEventKind) {
        switch kind {
        case let .message(content):
            describe(content.msgType)
        case let .sticker(body, _, _):
            (body.isEmpty ? "Sticker" : body, .sticker)
        case let .poll(question, _, _, _, _, _, _):
            ("Poll: \(question)", .poll)
        case .redacted:
            ("Message deleted", .redacted)
        case .unableToDecrypt:
            ("Message could not be decrypted", .encrypted)
        case let .other(eventType):
            ("Unsupported message (\(eventType))", .unsupported)
        case .liveLocation:
            ("Live location", .location)
        }
    }

    private func describe(_ messageType: MessageType) -> (String, NormalizedEventKind) {
        switch messageType {
        case let .text(content): (content.body, .text)
        case let .notice(content): (content.body, .notice)
        case let .emote(content): (content.body, .emote)
        // Attachments carry a filename plus an optional caption rather than a body. Prefer the
        // caption the sender wrote, fall back to the filename, and only then to a generic label,
        // so an attachment is never rendered as an empty message.
        case let .image(content):
            (Self.attachment(content.caption, content.filename, fallback: "Photo"), .image)
        case let .audio(content):
            (Self.attachment(content.caption, content.filename, fallback: "Audio message"), .audio)
        case let .video(content):
            (Self.attachment(content.caption, content.filename, fallback: "Video"), .video)
        case let .file(content):
            (Self.attachment(content.caption, content.filename, fallback: "File"), .file)
        case let .gallery(content): (Self.caption(content.body, fallback: "Photos"), .gallery)
        case let .location(content): (Self.caption(content.body, fallback: "Location"), .location)
        case let .other(msgtype, body):
            (body.isEmpty ? "Unsupported message (\(msgtype))" : body, .unsupported)
        }
    }

    private static func caption(_ body: String, fallback: String) -> String {
        body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? fallback : body
    }

    private static func attachment(_ caption: String?, _ filename: String, fallback: String) -> String {
        for candidate in [caption ?? "", filename] where
            !candidate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return candidate
        }
        return fallback
    }

    private static func describe(_ change: MembershipChange?) -> String {
        switch change {
        case .some(.joined): "joined"
        case .some(.left): "left"
        case .some(.invited): "was invited"
        case .some(.banned): "was banned"
        case .some(.kicked): "was removed"
        default: "membership changed"
        }
    }

    private static func describe(_ state: OtherState) -> String {
        switch state {
        case .roomName: "name"
        case .roomTopic: "topic"
        case .roomAvatar: "avatar"
        default: "settings"
        }
    }
}

/// Orders a conversation deterministically.
///
/// Bridged events can arrive out of order, so ordering uses the remote timestamp with the event
/// identifier as a stable tie-break rather than arrival order.
public func palloMessageOrdering(_ lhs: Message, _ rhs: Message) -> Bool {
    if lhs.timestamp != rhs.timestamp { return lhs.timestamp < rhs.timestamp }
    return lhs.id < rhs.id
}
