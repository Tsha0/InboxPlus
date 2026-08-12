import Foundation
import PalloCore

public actor InMemoryMessagingGateway: MessagingGateway {
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
        let message = Message(
            id: UUID().uuidString,
            route: route,
            senderIdentityID: nil,
            body: body,
            timestamp: Date(),
            deliveryState: .acknowledged
        )
        snapshot.messagesByRoute[route, default: []].append(message)
        continuations.values.forEach { $0.yield(.messageUpserted(message)) }
        return SendReceipt(messageID: message.id, route: route, deliveryState: message.deliveryState)
    }

    private func removeContinuation(_ id: UUID) { continuations[id] = nil }
}
