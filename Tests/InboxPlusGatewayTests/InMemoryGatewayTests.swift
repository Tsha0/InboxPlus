import Foundation
import Testing
@testable import InboxPlusCore
@testable import InboxPlusGateway

@Test func sendAcknowledgesTheExactRouteAndPublishesEvent() async throws {
    let expected = ConversationRoute(accountID: "instagram-primary", conversationID: "maya-ig")
    let gateway = InMemoryMessagingGateway(seed: .empty)
    let stream = await gateway.events()

    let receipt = try await gateway.sendText("Hello", to: expected)
    #expect(receipt.route == expected)
    #expect(receipt.deliveryState == .acknowledged)

    for await event in stream {
        guard case let .messageUpserted(message) = event else { continue }
        #expect(message.route == expected)
        #expect(message.body == "Hello")
        break
    }
}
