import Foundation
import Testing
import InboxPlusCore
import InboxPlusGateway
@testable import InboxPlusFeatures

private actor ConversationStartTestGateway: ConversationStartingGateway, TextOnlyTestGateway {
    private(set) var sends = 0
    private let platform: Platform
    private let supportsStarting: Bool

    init(platform: Platform = .iMessage, supportsStarting: Bool = true) {
        self.platform = platform
        self.supportsStarting = supportsStarting
    }

    func loadSnapshot() async throws -> MessagingSnapshot {
        MessagingSnapshot(
            accounts: [ConnectedAccount(id: "account", platform: platform, displayName: platform.accessibilityLabel)],
            identities: [], conversations: [], messagesByRoute: [:]
        )
    }

    func events() async -> AsyncStream<GatewayEvent> { AsyncStream { $0.finish() } }
    func canStartConversation(accountID: String) async -> Bool { accountID == "account" && supportsStarting }
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

private actor RecipientContactsFixture {
    var snapshot: LocalRecipientSnapshot = .available([
        LocalRecipient(name: "Ada Example", address: "+15555550123"),
        LocalRecipient(name: "Ada Example", address: "ada@example.com"),
    ])
    private(set) var reads = 0

    func load() -> LocalRecipientSnapshot {
        reads += 1
        return snapshot
    }

    func set(_ snapshot: LocalRecipientSnapshot) { self.snapshot = snapshot }
}

@Test @MainActor func recipientContactsRefreshAndRevokedAccessKeepManualConversationCreationUsable() async throws {
    let contacts = RecipientContactsFixture()
    let gateway = ConversationStartTestGateway()
    let model = InboxPlusAppModel(gateway: gateway, localRecipientSource: { await contacts.load() })
    try await model.start()
    let first = await model.recipientContacts(accountID: "account")
    #expect(first == .available([
        LocalRecipient(name: "Ada Example", address: "+15555550123"),
        LocalRecipient(name: "Ada Example", address: "ada@example.com"),
    ]))
    #expect(model.conversations.isEmpty)
    #expect(model.openRoute == nil)
    #expect(await gateway.sends == 0)

    await contacts.set(.available([LocalRecipient(name: "Grace Example", address: "grace@example.com")]))
    #expect(await model.recipientContacts(accountID: "account") == .available([
        LocalRecipient(name: "Grace Example", address: "grace@example.com"),
    ]))
    await contacts.set(.accessUnavailable)
    #expect(await model.recipientContacts(accountID: "account") == .accessUnavailable)
    try await model.startConversation(accountID: "account", recipient: "manual@example.com")
    #expect(model.openRoute == model.conversations.first?.route)
    #expect(await gateway.sends == 0)
    await contacts.set(.failed)
    #expect(await model.recipientContacts(accountID: "account") == .failed)
    try await model.disconnect(accountID: "account")
    #expect(await model.recipientContacts(accountID: "account") == .available([]))
    #expect(await model.recipientContacts(accountID: "missing") == .available([]))
    #expect(await contacts.reads == 4)
}

@Test @MainActor func recipientContactsDoNotReadContactsForUnsupportedNetworksOrCapabilities() async throws {
    let contacts = RecipientContactsFixture()
    for gateway in [ConversationStartTestGateway(platform: .instagram),
                    ConversationStartTestGateway(supportsStarting: false)] {
        let model = InboxPlusAppModel(gateway: gateway, localRecipientSource: { await contacts.load() })
        try await model.start()
        #expect(await model.recipientContacts(accountID: "account") == .available([]))
        model.stop()
    }
    #expect(await contacts.reads == 0)
}
