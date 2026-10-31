import InboxPlusCore

public struct MessagingSnapshot: Sendable {
    public var accounts: [ConnectedAccount]
    public var identities: [RemoteIdentity]
    public var conversations: [RemoteConversation]
    public var messagesByRoute: [ConversationRoute: [Message]]

    public init(accounts: [ConnectedAccount], identities: [RemoteIdentity], conversations: [RemoteConversation], messagesByRoute: [ConversationRoute: [Message]]) {
        self.accounts = accounts
        self.identities = identities
        self.conversations = conversations
        self.messagesByRoute = messagesByRoute
    }

    public static let empty = Self(accounts: [], identities: [], conversations: [], messagesByRoute: [:])
}

public enum GatewayEvent: Sendable {
    case messageUpserted(Message)
    /// Initial timeline contents, pagination, and replacement events; never alert the user.
    case historicalMessageUpserted(Message)
    case conversationUpserted(RemoteConversation)
    /// Must be delivered before any conversation that names this identity.
    ///
    /// The inbox can only project a conversation whose identity it knows, so a conversation that
    /// arrives without one is dropped and the user simply never sees it.
    case identityUpserted(RemoteIdentity)
    /// Must be delivered before any conversation filed under an account the snapshot did not list.
    ///
    /// The inbox drops a conversation whose account it does not know, so a network connected after
    /// launch would otherwise stay invisible until the next snapshot.
    case accountUpserted(ConnectedAccount)
    case connectionChanged(accountID: String, isConnected: Bool)
}

public struct SendReceipt: Sendable {
    public let messageID: String
    public let route: ConversationRoute
    public let deliveryState: MessageDeliveryState

    public init(messageID: String, route: ConversationRoute, deliveryState: MessageDeliveryState) {
        self.messageID = messageID
        self.route = route
        self.deliveryState = deliveryState
    }
}

public protocol MessagingGateway: Sendable {
    func loadSnapshot() async throws -> MessagingSnapshot
    func events() async -> AsyncStream<GatewayEvent>
    /// Delivers a conversation's recent messages as `historicalMessageUpserted` if the snapshot
    /// left them out. Called every time a conversation is opened, so a repeat must be cheap.
    func loadRecentMessages(in route: ConversationRoute) async throws
    func sendText(_ body: String, to route: ConversationRoute) async throws -> SendReceipt
    /// Uploads and sends a local file. Like `sendText`, the receipt is only `acknowledged` once
    /// the server has confirmed it.
    func send(_ attachment: OutgoingAttachment, to route: ConversationRoute) async throws -> SendReceipt
    /// Records that the user has read a conversation up to its latest message, wherever the next
    /// snapshot reads unread counts from, so a badge cleared now stays cleared after a relaunch.
    ///
    /// Must never tell the other person their message was seen.
    func markRead(_ route: ConversationRoute) async throws
}

public extension MessagingGateway {
    /// A gateway that delivers each conversation's history on its own has nothing to load.
    func loadRecentMessages(in route: ConversationRoute) async throws {}
}
