import Foundation
import Testing
@testable import InboxPlusCore
@testable import InboxPlusGateway

private actor RecordingGateway: MessagingGateway {
    private let snapshot: MessagingSnapshot
    private var continuations: [UUID: AsyncStream<GatewayEvent>.Continuation] = [:]
    private(set) var sentRoutes: [ConversationRoute] = []
    private(set) var readRoutes: [ConversationRoute] = []

    init(accounts: [ConnectedAccount]) {
        snapshot = MessagingSnapshot(accounts: accounts, identities: [], conversations: [], messagesByRoute: [:])
    }

    func loadSnapshot() async throws -> MessagingSnapshot { snapshot }

    func events() async -> AsyncStream<GatewayEvent> {
        let pair = AsyncStream<GatewayEvent>.makeStream()
        continuations[UUID()] = pair.continuation
        return pair.stream
    }

    func subscriberCount() -> Int { continuations.count }

    func publish(_ event: GatewayEvent) {
        continuations.values.forEach { $0.yield(event) }
    }

    func sendText(_ body: String, to route: ConversationRoute) async throws -> SendReceipt {
        sentRoutes.append(route)
        return SendReceipt(messageID: UUID().uuidString, route: route, deliveryState: .pending)
    }

    func send(_ attachment: OutgoingAttachment, to route: ConversationRoute) async throws -> SendReceipt {
        try await sendText(attachment.filename, to: route)
    }

    func markRead(_ route: ConversationRoute) async throws {
        readRoutes.append(route)
    }
}

@Test(.timeLimit(.minutes(1)))
func aReplyInANetworkConnectedAfterTheSnapshotReachesTheGatewayThatReportedIt() async throws {
    let matrix = RecordingGateway(
        accounts: [ConnectedAccount(id: "matrix-local", platform: .matrix, displayName: "Local Matrix")]
    )
    let imessage = RecordingGateway(
        accounts: [ConnectedAccount(id: "imessage-local", platform: .iMessage, displayName: "iMessage")]
    )
    let composite = CompositeMessagingGateway([matrix, imessage])
    let stream = await composite.events()
    _ = try await composite.loadSnapshot()
    while await matrix.subscriberCount() == 0 { await Task.yield() }

    await matrix.publish(.accountUpserted(
        ConnectedAccount(id: "instagram", platform: .instagram, displayName: "Instagram")
    ))
    for await event in stream {
        if case .accountUpserted = event { break }
    }

    let route = ConversationRoute(accountID: "instagram", conversationID: "!portal")
    _ = try await composite.sendText("hello", to: route)

    #expect(await matrix.sentRoutes == [route])
    #expect(await imessage.sentRoutes.isEmpty)
}

@Test func markingAConversationReadReachesOnlyTheGatewayThatOwnsIt() async throws {
    let matrix = RecordingGateway(
        accounts: [ConnectedAccount(id: "matrix-local", platform: .matrix, displayName: "Local Matrix")]
    )
    let imessage = RecordingGateway(
        accounts: [ConnectedAccount(id: "imessage-local", platform: .iMessage, displayName: "iMessage")]
    )
    let composite = CompositeMessagingGateway([matrix, imessage])
    _ = try await composite.loadSnapshot()

    let route = ConversationRoute(accountID: "imessage-local", conversationID: "chat")
    try await composite.markRead(route)

    #expect(await imessage.readRoutes == [route])
    #expect(await matrix.readRoutes.isEmpty)
}
