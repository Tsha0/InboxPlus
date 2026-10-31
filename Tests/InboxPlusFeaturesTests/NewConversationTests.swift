import Foundation
import Testing
import InboxPlusCore
import InboxPlusGateway
@testable import InboxPlusFeatures

private actor ConversationStartTestGateway: ConversationStartingGateway, TextOnlyTestGateway {
    private(set) var sends = 0

    func loadSnapshot() async throws -> MessagingSnapshot {
        MessagingSnapshot(
            accounts: [ConnectedAccount(id: "account", platform: .iMessage, displayName: "iMessage")],
            identities: [], conversations: [], messagesByRoute: [:]
        )
    }

    func events() async -> AsyncStream<GatewayEvent> { AsyncStream { $0.finish() } }
    func canStartConversation(accountID: String) async -> Bool { accountID == "account" }
    func startConversation(accountID: String, recipient: String) async throws -> StartedConversation {
        StartedConversation(
            identity: RemoteIdentity(id: recipient, accountID: accountID, displayName: recipient),
            conversation: RemoteConversation(id: recipient, accountID: accountID, identityID: recipient, title: recipient, latestActivity: .now, unreadCount: 0)
        )
    }
    func sendText(_ body: String, to route: ConversationRoute) async throws -> SendReceipt {
        sends += 1
        return SendReceipt(messageID: "sent", route: route, deliveryState: .pending)
    }
}

@Test @MainActor func startingAndReopeningAConversationDoesNotSendOrDuplicateIt() async throws {
    let gateway = ConversationStartTestGateway()
    let model = InboxPlusAppModel(gateway: gateway)
    try await model.start()
    #expect(await model.canStartConversation(accountID: "account"))
    try await model.startConversation(accountID: "account", recipient: "person@example.com")
    try await model.startConversation(accountID: "account", recipient: "person@example.com")
    #expect(model.conversations.count == 1)
    #expect(model.identities.count == 1)
    #expect(model.openRoute == model.conversations.first?.route)
    #expect(await gateway.sends == 0)
    try await model.disconnect(accountID: "account")
    #expect(await !model.canStartConversation(accountID: "account"))
    await #expect(throws: ConversationStartError.self) {
        try await model.startConversation(accountID: "account", recipient: "other@example.com")
    }
    #expect(model.conversations.count == 1)
}
