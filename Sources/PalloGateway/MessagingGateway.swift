import PalloCore

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
    case conversationUpserted(RemoteConversation)
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
    func sendText(_ body: String, to route: ConversationRoute) async throws -> SendReceipt
}
