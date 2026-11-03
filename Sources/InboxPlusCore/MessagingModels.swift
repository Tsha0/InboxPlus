import Foundation

public struct ConnectedAccount: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let platform: Platform
    public var displayName: String
    /// What the network's bridge last reported about its own connection. Nil until it says.
    public var networkState: NetworkConnectionState?
    /// Who the user is signed in as on the network — a username, phone number or address. Nil
    /// when the source has not said.
    public var signedInAs: String?
    public var bridgeAvailable: Bool?

    public init(
        id: String,
        platform: Platform,
        displayName: String,
        networkState: NetworkConnectionState? = nil,
        signedInAs: String? = nil,
        bridgeAvailable: Bool? = nil
    ) {
        self.id = id
        self.platform = platform
        self.displayName = displayName
        self.networkState = networkState
        self.signedInAs = signedInAs
        self.bridgeAvailable = bridgeAvailable
    }
}

/// A bridge's connection to its network, as the bridge reports it. The raw values are the states
/// mautrix bridges publish.
public enum NetworkConnectionState: String, Codable, Hashable, Sendable {
    case connecting = "CONNECTING"
    case connected = "CONNECTED"
    case reconnecting = "TRANSIENT_DISCONNECT"
    case signedOut = "LOGGED_OUT"
    case badCredentials = "BAD_CREDENTIALS"
    case unknownError = "UNKNOWN_ERROR"
}

public enum AccountPolicyError: Error, Equatable {
    case duplicatePlatform(Platform)
}

public enum AccountPolicy {
    public static func validate(_ accounts: [ConnectedAccount]) throws {
        var seen: Set<Platform> = []
        for account in accounts where !seen.insert(account.platform).inserted {
            throw AccountPolicyError.duplicatePlatform(account.platform)
        }
    }
}

public struct RemoteIdentity: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let accountID: String
    public var displayName: String

    public init(id: String, accountID: String, displayName: String) {
        self.id = id
        self.accountID = accountID
        self.displayName = displayName
    }
}

public struct ConversationRoute: Codable, Hashable, Sendable {
    public let accountID: String
    public let conversationID: String

    public init(accountID: String, conversationID: String) {
        self.accountID = accountID
        self.conversationID = conversationID
    }
}

/// What a conversation will actually accept.
///
/// The design requires compose controls to be capability-driven: an action a network does not
/// support is absent or disabled rather than attempted optimistically and failed afterwards.
public struct ConversationCapabilities: Codable, Hashable, Sendable {
    public var canSendText: Bool
    /// The attachment kinds this conversation accepts. Empty means text only.
    public var attachmentKinds: Set<MessageKind>
    /// Nil when the network has not told us a limit, which is not the same as having none.
    public var maximumAttachmentBytes: Int?
    public var canReply: Bool
    public var canReact: Bool

    public init(
        canSendText: Bool = true,
        attachmentKinds: Set<MessageKind> = [],
        maximumAttachmentBytes: Int? = nil,
        canReply: Bool = false,
        canReact: Bool = false
    ) {
        self.canSendText = canSendText
        self.attachmentKinds = attachmentKinds
        self.maximumAttachmentBytes = maximumAttachmentBytes
        self.canReply = canReply
        self.canReact = canReact
    }

    public var acceptsAttachments: Bool { !attachmentKinds.isEmpty }

    public func accepts(_ kind: MessageKind) -> Bool { attachmentKinds.contains(kind) }

    /// Matrix itself accepts all four attachment kinds, replies and reactions, so a bridge that has
    /// not declared otherwise gets them.
    public static let mediaCapable = ConversationCapabilities(
        canSendText: true,
        attachmentKinds: [.image, .video, .audio, .file],
        canReply: true,
        canReact: true
    )

    public static let textOnly = ConversationCapabilities()
}

/// Why a chosen file cannot be sent here, phrased for the person who chose it.
public enum AttachmentRejection: Error, Equatable, Sendable {
    case kindNotSupported(MessageKind)
    case tooLarge(byteCount: Int, limit: Int)
    case unreadable(String)

    public var message: String {
        switch self {
        case let .kindNotSupported(kind):
            return "This conversation does not accept \(kind.rawValue) attachments."
        case let .tooLarge(byteCount, limit):
            let formatter = ByteCountFormatter()
            return "That file is \(formatter.string(fromByteCount: Int64(byteCount))); "
                + "this conversation accepts up to \(formatter.string(fromByteCount: Int64(limit)))."
        case let .unreadable(reason):
            return "That file could not be read: \(reason)"
        }
    }
}

public struct RemoteConversation: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let accountID: String
    public let identityID: String
    public var title: String
    public var latestPreview: String
    public var latestActivity: Date
    public var unreadCount: Int
    public var capabilities: ConversationCapabilities
    public var isGroup: Bool
    /// Someone the user has no record of: not in their contacts and never written to. Only a
    /// source that can tell sets it, which is why it defaults to false.
    public var isFromUnknownSender: Bool
    /// The conversation in its network's own app, which still has the history Inbox+ does not keep.
    public var deepLink: VerifiedDeepLink?

    public var route: ConversationRoute { .init(accountID: accountID, conversationID: id) }

    public init(
        id: String,
        accountID: String,
        identityID: String,
        title: String,
        latestPreview: String = "",
        latestActivity: Date,
        unreadCount: Int,
        capabilities: ConversationCapabilities = .mediaCapable,
        isGroup: Bool = false,
        isFromUnknownSender: Bool = false,
        deepLink: VerifiedDeepLink? = nil
    ) {
        self.id = id
        self.accountID = accountID
        self.identityID = identityID
        self.title = title
        self.latestPreview = latestPreview
        self.latestActivity = latestActivity
        self.unreadCount = unreadCount
        self.capabilities = capabilities
        self.isGroup = isGroup
        self.isFromUnknownSender = isFromUnknownSender
        self.deepLink = deepLink
    }
}

public enum MessageDeliveryState: Codable, Hashable, Sendable { case pending, acknowledged, failed(String) }

/// One emoji on a message, with how many people chose it.
public struct MessageReaction: Codable, Hashable, Sendable {
    public let key: String
    public var count: Int
    /// Whether this account is one of them, which is what choosing the same emoji again takes back.
    public var includesMe: Bool

    public init(key: String, count: Int, includesMe: Bool) {
        self.key = key
        self.count = count
        self.includesMe = includesMe
    }

    /// Folds one entry per person into one reaction per emoji, in the order each emoji first appeared.
    public static func tally(_ entries: [(key: String, isMine: Bool)]) -> [MessageReaction] {
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

/// The message a reply answers, as far as the network has delivered it.
public struct MessageReply: Codable, Hashable, Sendable {
    public let messageID: String
    public var senderDisplayName: String?
    /// Nil until the quoted message itself has been loaded.
    public var body: String?

    public init(messageID: String, senderDisplayName: String? = nil, body: String? = nil) {
        self.messageID = messageID
        self.senderDisplayName = senderDisplayName
        self.body = body
    }
}

public struct Message: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let route: ConversationRoute
    public let senderIdentityID: String?
    public var senderDisplayName: String?
    /// Always plain text, so previews, notifications and VoiceOver never show formatting syntax.
    public var body: String
    /// The sender's formatting as inline Markdown. Nil unless the network sent formatted text.
    public var markdownBody: String?
    public let timestamp: Date
    public var deliveryState: MessageDeliveryState
    public var kind: MessageKind
    public var attachments: [MessageAttachment]
    public var reactions: [MessageReaction]
    public var replyTo: MessageReply?

    /// Messages this account sent carry no remote sender identity.
    public var isOutgoing: Bool { senderIdentityID == nil }

    /// A reply or reaction has to point at something the server already has, and at something
    /// someone said rather than a deletion or a change to the room.
    public var acceptsResponses: Bool {
        deliveryState == .acknowledged && ![.redacted, .encrypted, .membership, .state].contains(kind)
    }

    public init(
        id: String,
        route: ConversationRoute,
        senderIdentityID: String?,
        body: String,
        timestamp: Date,
        deliveryState: MessageDeliveryState,
        kind: MessageKind = .text,
        attachments: [MessageAttachment] = [],
        reactions: [MessageReaction] = [],
        replyTo: MessageReply? = nil,
        markdownBody: String? = nil,
        senderDisplayName: String? = nil
    ) {
        self.id = id
        self.route = route
        self.senderIdentityID = senderIdentityID
        self.senderDisplayName = senderDisplayName
        self.body = body
        self.markdownBody = markdownBody
        self.timestamp = timestamp
        self.deliveryState = deliveryState
        self.kind = kind
        self.attachments = attachments
        self.reactions = reactions
        self.replyTo = replyTo
    }
}
