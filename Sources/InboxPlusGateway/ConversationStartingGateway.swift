import Foundation
import InboxPlusCore

public struct StartedConversation: Sendable {
    public let identity: RemoteIdentity
    public let conversation: RemoteConversation

    public init(identity: RemoteIdentity, conversation: RemoteConversation) {
        self.identity = identity
        self.conversation = conversation
    }
}

public enum ConversationStartError: Error, LocalizedError {
    case unsupported
    case invalidRecipient
    case unavailable

    public var errorDescription: String? {
        switch self {
        case .unsupported: "Starting new conversations is not supported on this network yet. Start one in the network’s app, then return to Inbox+."
        case .invalidRecipient: "Enter an email address or an international phone number beginning with +."
        case .unavailable: "This account is not connected."
        }
    }
}

public protocol ConversationStartingGateway: MessagingGateway {
    func canStartConversation(accountID: String) async -> Bool
    func startConversation(accountID: String, recipient: String) async throws -> StartedConversation
}
