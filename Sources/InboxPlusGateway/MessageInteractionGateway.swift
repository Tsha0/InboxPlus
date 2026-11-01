import Foundation
import InboxPlusCore

public enum MessageInteractionError: Error, LocalizedError, Equatable {
    case unsupported

    public var errorDescription: String? {
        switch self {
        case .unsupported: "This network does not accept replies or reactions from Inbox+."
        }
    }
}

/// A gateway that can answer a particular message rather than only the conversation.
///
/// Not every source can: Messages takes plain text through Apple events and nothing more. A
/// conversation's capabilities decide whether either action is offered at all.
public protocol MessageInteractionGateway: MessagingGateway {
    func sendText(_ body: String, to route: ConversationRoute, replyingTo messageID: String) async throws -> SendReceipt
    func send(
        _ attachment: OutgoingAttachment,
        to route: ConversationRoute,
        replyingTo messageID: String
    ) async throws -> SendReceipt
    /// Adds this account's reaction, or takes it back when it is already there.
    func toggleReaction(_ key: String, to messageID: String, in route: ConversationRoute) async throws
}
