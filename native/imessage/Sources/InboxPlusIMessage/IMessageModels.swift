import Foundation

public struct ConnectedAccount: Sendable {
    public let id: String
    public var displayName: String
    public var signedInAs: String?
}

public struct RemoteIdentity: Sendable {
    public let id: String
    public let accountID: String
    public var displayName: String
}

public struct ConversationRoute: Hashable, Sendable {
    public let accountID: String
    public let conversationID: String

    public init(accountID: String, conversationID: String) {
        self.accountID = accountID
        self.conversationID = conversationID
    }
}

public struct RemoteConversation: Sendable {
    public let id: String
    public let accountID: String
    public let identityID: String
    public var title: String
    public var latestPreview: String
    public var latestActivity: Date
    public var unreadCount: Int
    public var isGroup: Bool
    public var isFromUnknownSender: Bool

    public var route: ConversationRoute { .init(accountID: accountID, conversationID: id) }

    init(
        id: String,
        accountID: String,
        identityID: String,
        title: String,
        latestPreview: String = "",
        latestActivity: Date,
        unreadCount: Int,
        isGroup: Bool = false,
        isFromUnknownSender: Bool = false
    ) {
        self.id = id
        self.accountID = accountID
        self.identityID = identityID
        self.title = title
        self.latestPreview = latestPreview
        self.latestActivity = latestActivity
        self.unreadCount = unreadCount
        self.isGroup = isGroup
        self.isFromUnknownSender = isFromUnknownSender
    }
}

public enum MessageDeliveryState: Equatable, Sendable { case pending, acknowledged }

public enum MessageKind: String, Sendable {
    case text, image, audio, video, file
}

public struct MediaHandle: Equatable, Sendable {
    public let source: String
    public var mimeType: String?
}

public struct MessageAttachment: Equatable, Sendable {
    public let id: String
    public let kind: MessageKind
    public var filename: String?
    public var mimeType: String?
    public var byteCount: Int?
    public var source: MediaHandle?
    public var reportedDescription: String?

    public var displayName: String {
        switch kind {
        case .image: "Photo"
        case .audio: "Audio message"
        case .video: "Video"
        case .file: filename.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 } ?? "File"
        default: "Attachment"
        }
    }
}

public struct MessageReaction: Equatable, Sendable {
    public let key: String
    public var count: Int
    public var includesMe: Bool

    static func tally(_ entries: [(key: String, isMine: Bool)]) -> [MessageReaction] {
        var reactions: [MessageReaction] = []
        for entry in entries {
            if let index = reactions.firstIndex(where: { $0.key == entry.key }) {
                reactions[index].count += 1
                reactions[index].includesMe = reactions[index].includesMe || entry.isMine
            } else {
                reactions.append(MessageReaction(key: entry.key, count: 1, includesMe: entry.isMine))
            }
        }
        return reactions
    }
}

public struct Message: Equatable, Sendable {
    public let id: String
    public let route: ConversationRoute
    public let senderIdentityID: String?
    public var senderDisplayName: String?
    public var body: String
    public let timestamp: Date
    public var deliveryState: MessageDeliveryState
    public var kind: MessageKind
    public var attachments: [MessageAttachment]
    public var reactions: [MessageReaction]

    public var isOutgoing: Bool { senderIdentityID == nil }

    init(
        id: String,
        route: ConversationRoute,
        senderIdentityID: String?,
        senderDisplayName: String? = nil,
        body: String,
        timestamp: Date,
        deliveryState: MessageDeliveryState,
        kind: MessageKind = .text,
        attachments: [MessageAttachment] = [],
        reactions: [MessageReaction] = []
    ) {
        self.id = id
        self.route = route
        self.senderIdentityID = senderIdentityID
        self.senderDisplayName = senderDisplayName
        self.body = body
        self.timestamp = timestamp
        self.deliveryState = deliveryState
        self.kind = kind
        self.attachments = attachments
        self.reactions = reactions
    }
}

public struct MessagingSnapshot: Sendable {
    public var accounts: [ConnectedAccount]
    public var identities: [RemoteIdentity]
    public var conversations: [RemoteConversation]
    public var messagesByRoute: [ConversationRoute: [Message]]
}

public enum GatewayEvent: Sendable {
    case messageUpserted(Message)
    case historicalMessageUpserted(Message)
    case conversationUpserted(RemoteConversation)
    case identityUpserted(RemoteIdentity)
}

public struct SendReceipt: Sendable {
    public let messageID: String
    public let route: ConversationRoute
    public let deliveryState: MessageDeliveryState
}

public struct StartedConversation: Sendable {
    public let identity: RemoteIdentity
    public let conversation: RemoteConversation
}

public enum ConversationStartError: Error {
    case invalidRecipient
    case unavailable
}
