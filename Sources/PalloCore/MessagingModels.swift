import Foundation

public struct ConnectedAccount: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let platform: Platform
    public var displayName: String

    public init(id: String, platform: Platform, displayName: String) {
        self.id = id
        self.platform = platform
        self.displayName = displayName
    }
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

public struct RemoteConversation: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let accountID: String
    public let identityID: String
    public var title: String
    public var latestPreview: String
    public var latestActivity: Date
    public var unreadCount: Int

    public var route: ConversationRoute { .init(accountID: accountID, conversationID: id) }

    public init(id: String, accountID: String, identityID: String, title: String, latestPreview: String = "", latestActivity: Date, unreadCount: Int) {
        self.id = id
        self.accountID = accountID
        self.identityID = identityID
        self.title = title
        self.latestPreview = latestPreview
        self.latestActivity = latestActivity
        self.unreadCount = unreadCount
    }
}

public enum MessageDeliveryState: Codable, Hashable, Sendable { case pending, acknowledged, failed(String) }

public struct Message: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let route: ConversationRoute
    public let senderIdentityID: String?
    public var body: String
    public let timestamp: Date
    public var deliveryState: MessageDeliveryState

    public init(id: String, route: ConversationRoute, senderIdentityID: String?, body: String, timestamp: Date, deliveryState: MessageDeliveryState) {
        self.id = id
        self.route = route
        self.senderIdentityID = senderIdentityID
        self.body = body
        self.timestamp = timestamp
        self.deliveryState = deliveryState
    }
}
