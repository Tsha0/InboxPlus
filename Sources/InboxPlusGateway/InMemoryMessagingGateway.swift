import Foundation
import InboxPlusCore

public actor InMemoryMessagingGateway: MessageInteractionGateway {
    private var snapshot: MessagingSnapshot
    private var continuations: [UUID: AsyncStream<GatewayEvent>.Continuation] = [:]

    public init(seed: MessagingSnapshot) { snapshot = seed }

    public func loadSnapshot() async throws -> MessagingSnapshot { snapshot }

    public func events() async -> AsyncStream<GatewayEvent> {
        let id = UUID()
        let pair = AsyncStream<GatewayEvent>.makeStream()
        continuations[id] = pair.continuation
        pair.continuation.onTermination = { [weak self] _ in
            Task { await self?.removeContinuation(id) }
        }
        return pair.stream
    }

    public func sendText(_ body: String, to route: ConversationRoute) async throws -> SendReceipt {
        deliver(text: body, to: route, replyTo: nil)
    }

    public func sendText(_ body: String, to route: ConversationRoute, replyingTo messageID: String) async throws -> SendReceipt {
        deliver(text: body, to: route, replyTo: quote(of: messageID, in: route))
    }

    public func send(_ attachment: OutgoingAttachment, to route: ConversationRoute) async throws -> SendReceipt {
        deliver(attachment, to: route, replyTo: nil)
    }

    public func send(
        _ attachment: OutgoingAttachment,
        to route: ConversationRoute,
        replyingTo messageID: String
    ) async throws -> SendReceipt {
        deliver(attachment, to: route, replyTo: quote(of: messageID, in: route))
    }

    public func toggleReaction(_ key: String, to messageID: String, in route: ConversationRoute) async throws {
        guard var message = snapshot.messagesByRoute[route]?.first(where: { $0.id == messageID }) else { return }
        if let index = message.reactions.firstIndex(where: { $0.key == key }) {
            let mine = message.reactions[index].includesMe
            message.reactions[index].count += mine ? -1 : 1
            message.reactions[index].includesMe = !mine
            if message.reactions[index].count == 0 { message.reactions.remove(at: index) }
        } else {
            message.reactions.append(MessageReaction(key: key, count: 1, includesMe: true))
        }
        snapshot.messagesByRoute[route] = snapshot.messagesByRoute[route]?.map { $0.id == messageID ? message : $0 }
        continuations.values.forEach { $0.yield(.historicalMessageUpserted(message)) }
    }

    public func markRead(_ route: ConversationRoute) async throws {
        guard let index = snapshot.conversations.firstIndex(where: { $0.route == route }) else { return }
        snapshot.conversations[index].unreadCount = 0
    }

    private func quote(of messageID: String, in route: ConversationRoute) -> MessageReply {
        let quoted = snapshot.messagesByRoute[route]?.first { $0.id == messageID }
        return MessageReply(messageID: messageID, senderDisplayName: quoted?.senderDisplayName, body: quoted?.body)
    }

    private func deliver(text body: String, to route: ConversationRoute, replyTo: MessageReply?) -> SendReceipt {
        let message = Message(
            id: UUID().uuidString,
            route: route,
            senderIdentityID: nil,
            body: body,
            timestamp: Date(),
            deliveryState: .acknowledged,
            replyTo: replyTo
        )
        snapshot.messagesByRoute[route, default: []].append(message)
        continuations.values.forEach { $0.yield(.messageUpserted(message)) }
        return SendReceipt(messageID: message.id, route: route, deliveryState: message.deliveryState)
    }

    private func deliver(_ attachment: OutgoingAttachment, to route: ConversationRoute, replyTo: MessageReply?) -> SendReceipt {
        let id = UUID().uuidString
        let message = Message(
            id: id,
            route: route,
            senderIdentityID: nil,
            body: attachment.caption ?? attachment.filename,
            timestamp: Date(),
            deliveryState: .acknowledged,
            kind: attachment.kind,
            attachments: [
                MessageAttachment(
                    id: "\(id)#0",
                    kind: attachment.kind,
                    filename: attachment.filename,
                    caption: attachment.caption,
                    mimeType: attachment.mimeType,
                    byteCount: attachment.byteCount,
                    pixelSize: attachment.pixelSize,
                    duration: attachment.duration,
                    // The fake serves the local file straight back, which is what makes an
                    // outgoing attachment visible in previews and tests without a homeserver.
                    source: MediaHandle(
                        source: attachment.fileURL.absoluteString,
                        mimeType: attachment.mimeType,
                        byteCount: attachment.byteCount
                    )
                ),
            ],
            replyTo: replyTo
        )
        snapshot.messagesByRoute[route, default: []].append(message)
        continuations.values.forEach { $0.yield(.messageUpserted(message)) }
        return SendReceipt(messageID: message.id, route: route, deliveryState: message.deliveryState)
    }

    private func removeContinuation(_ id: UUID) { continuations[id] = nil }
}
