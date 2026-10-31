import Foundation
import Testing
@testable import InboxPlusCore
@testable import InboxPlusFeatures
@testable import InboxPlusGateway

@MainActor
private func startedModel(
    seed: MessagingSnapshot,
    favouriteStore: InboxFavouriteStore? = nil,
    lifecycle: (any AccountLifecycle)? = nil
) async throws -> InboxPlusAppModel {
    let model = InboxPlusAppModel(
        gateway: InMemoryMessagingGateway(seed: seed),
        favouriteStore: favouriteStore,
        accountLifecycle: lifecycle
    )
    try await model.start()
    return model
}

private func snapshot(
    accounts: [ConnectedAccount],
    identities: [RemoteIdentity] = [],
    conversations: [RemoteConversation] = [],
    messages: [ConversationRoute: [Message]] = [:]
) -> MessagingSnapshot {
    MessagingSnapshot(
        accounts: accounts,
        identities: identities,
        conversations: conversations,
        messagesByRoute: messages
    )
}

private let instagramAccount = ConnectedAccount(
    id: "instagram:1784",
    platform: .instagram,
    displayName: "throwaway"
)

@MainActor
@Test func aSecondAccountOnTheSamePlatformIsRefused() async throws {
    let model = try await startedModel(seed: snapshot(accounts: [instagramAccount]))

    #expect(throws: AccountPolicyError.duplicatePlatform(.instagram)) {
        try model.addAccount(
            ConnectedAccount(id: "instagram:other", platform: .instagram, displayName: "second")
        )
    }
    #expect(model.accounts.count == 1)
}

@MainActor
@Test func finishingALoginForAnAccountTheGatewayAlreadyReportedKeepsOneAccount() async throws {
    let model = try await startedModel(seed: snapshot(accounts: [instagramAccount]))

    try model.addAccount(instagramAccount)

    #expect(model.accounts == [instagramAccount])
}

@MainActor
@Test func adifferentPlatformIsAccepted() async throws {
    let model = try await startedModel(seed: snapshot(accounts: [instagramAccount]))

    try model.addAccount(
        ConnectedAccount(id: "whatsapp:1", platform: .whatsApp, displayName: "+15551234567")
    )
    #expect(model.platformsWithAccounts == [.instagram, .whatsApp])
}

@MainActor
@Test func disconnectingKeepsEveryMessageTheAccountDelivered() async throws {
    let route = ConversationRoute(accountID: instagramAccount.id, conversationID: "!room")
    let model = try await startedModel(seed: snapshot(
        accounts: [instagramAccount],
        identities: [RemoteIdentity(id: "maya", accountID: instagramAccount.id, displayName: "Maya")],
        conversations: [RemoteConversation(
            id: "!room",
            accountID: instagramAccount.id,
            identityID: "maya",
            title: "Maya",
            latestActivity: .now,
            unreadCount: 0
        )],
        messages: [route: [Message(
            id: "$1",
            route: route,
            senderIdentityID: "maya",
            body: "hello",
            timestamp: .now,
            deliveryState: .acknowledged
        )]]
    ))

    try await model.disconnect(accountID: instagramAccount.id)

    #expect(!model.isConnected(instagramAccount.id))
    #expect(model.accounts.count == 1, "disconnecting is not removing")
    #expect(model.messagesByRoute[route]?.count == 1, "history must survive a disconnection")
    #expect(model.healthBannerMessage != nil)
}

@MainActor
@Test func reconnectingClearsTheWarning() async throws {
    let model = try await startedModel(seed: snapshot(accounts: [instagramAccount]))

    try await model.disconnect(accountID: instagramAccount.id)
    try await model.reconnect(accountID: instagramAccount.id)

    #expect(model.isConnected(instagramAccount.id))
    #expect(model.health == .healthy)
}

@MainActor
@Test func erasingAnAccountRemovesEverythingItBrought() async throws {
    let route = ConversationRoute(accountID: instagramAccount.id, conversationID: "!room")
    let keptAccount = ConnectedAccount(id: "whatsapp:1", platform: .whatsApp, displayName: "kept")
    let keptRoute = ConversationRoute(accountID: keptAccount.id, conversationID: "!kept")
    let model = try await startedModel(seed: snapshot(
        accounts: [instagramAccount, keptAccount],
        identities: [
            RemoteIdentity(id: "maya", accountID: instagramAccount.id, displayName: "Maya"),
            RemoteIdentity(id: "sam", accountID: keptAccount.id, displayName: "Sam"),
        ],
        conversations: [
            RemoteConversation(
                id: "!room",
                accountID: instagramAccount.id,
                identityID: "maya",
                title: "Maya",
                latestActivity: .now,
                unreadCount: 0
            ),
            RemoteConversation(
                id: "!kept",
                accountID: keptAccount.id,
                identityID: "sam",
                title: "Sam",
                latestActivity: .now,
                unreadCount: 0
            ),
        ],
        messages: [
            route: [Message(
                id: "$1",
                route: route,
                senderIdentityID: "maya",
                body: "hello",
                timestamp: .now,
                deliveryState: .acknowledged
            )],
            keptRoute: [Message(
                id: "$2",
                route: keptRoute,
                senderIdentityID: "sam",
                body: "kept",
                timestamp: .now,
                deliveryState: .acknowledged
            )],
        ]
    ))

    model.openConversation(route)
    try await model.eraseAccount(accountID: instagramAccount.id)

    #expect(model.accounts.map(\.id) == [keptAccount.id])
    #expect(model.conversations.map(\.id) == ["!kept"])
    #expect(model.messagesByRoute[route] == nil)
    #expect(model.identities.map(\.id) == ["sam"])
    // The open conversation belonged to the erased account, so the detail pane cannot keep showing it.
    #expect(model.detailSelection == .empty)
    // Everything belonging to the other account is untouched.
    #expect(model.messagesByRoute[keptRoute]?.count == 1)
}

@MainActor
@Test func erasingOneAccountLeavesAnotherAccountsDisconnectionWarningIntact() async throws {
    let doomed = ConnectedAccount(id: "instagram:1", platform: .instagram, displayName: "a")
    let troubled = ConnectedAccount(id: "whatsapp:1", platform: .whatsApp, displayName: "b")
    let model = try await startedModel(seed: snapshot(accounts: [doomed, troubled]))

    try await model.disconnect(accountID: troubled.id)
    try await model.eraseAccount(accountID: doomed.id)

    #expect(!model.isConnected(troubled.id))
    #expect(model.healthBannerMessage != nil, "an unrelated account is still disconnected")
}

@MainActor
@Test func lastActivityTracksTheNewestMessagePerAccount() async throws {
    let old = Date(timeIntervalSince1970: 1_000)
    let model = try await startedModel(seed: snapshot(
        accounts: [instagramAccount],
        identities: [RemoteIdentity(id: "maya", accountID: instagramAccount.id, displayName: "Maya")],
        conversations: [RemoteConversation(
            id: "!room",
            accountID: instagramAccount.id,
            identityID: "maya",
            title: "Maya",
            latestActivity: old,
            unreadCount: 0
        )]
    ))

    #expect(model.lastActivity(for: instagramAccount.id) == old)
    #expect(model.lastActivity(for: "nobody") == nil)
}

// MARK: - The runtime behind account changes

private struct LifecycleFailure: Error {}

private actor FakeAccountLifecycle: AccountLifecycle {
    private(set) var persisted: Set<String>
    private(set) var calls: [String] = []
    private var failing = false
    private let removal: AccountRemoval

    init(persisted: Set<String> = [], removal: AccountRemoval = AccountRemoval()) {
        self.persisted = persisted
        self.removal = removal
    }

    func failNextChanges() { failing = true }

    func disconnectedAccountIDs() -> Set<String> { persisted }

    func disconnect(_ account: ConnectedAccount) throws {
        calls.append("disconnect \(account.id)")
        if failing { throw LifecycleFailure() }
        persisted.insert(account.id)
    }

    func reconnect(_ account: ConnectedAccount) throws -> AccountReconnection {
        calls.append("reconnect \(account.id)")
        if failing { throw LifecycleFailure() }
        persisted.remove(account.id)
        return .reconnected
    }

    func remove(_ account: ConnectedAccount) throws -> AccountRemoval {
        calls.append("remove \(account.id)")
        if failing { throw LifecycleFailure() }
        return removal
    }
}

private let localMatrix = ConnectedAccount(id: "matrix-local", platform: .matrix, displayName: "Local Matrix")
private let iMessageAccount = ConnectedAccount(id: "imessage-local", platform: .iMessage, displayName: "iMessage")

@MainActor
@Test func anAccountDisconnectedInAnEarlierSessionStillReadsAsDisconnected() async throws {
    let lifecycle = FakeAccountLifecycle(persisted: [instagramAccount.id, "removed-long-ago"])
    let model = try await startedModel(seed: snapshot(accounts: [instagramAccount]), lifecycle: lifecycle)

    #expect(!model.isConnected(instagramAccount.id))
    #expect(model.healthBannerMessage == "1 account(s) disconnected")
}

@MainActor
@Test func disconnectingWaitsForTheRuntimeAndAFailureLeavesTheAccountAsItWas() async throws {
    let lifecycle = FakeAccountLifecycle()
    let model = try await startedModel(seed: snapshot(accounts: [instagramAccount]), lifecycle: lifecycle)

    try await model.disconnect(accountID: instagramAccount.id)
    #expect(await lifecycle.calls == ["disconnect \(instagramAccount.id)"])
    #expect(!model.isConnected(instagramAccount.id))

    await lifecycle.failNextChanges()
    await #expect(throws: LifecycleFailure.self) {
        try await model.reconnect(accountID: instagramAccount.id)
    }
    #expect(!model.isConnected(instagramAccount.id), "the bridge did not start, so it is still disconnected")
    #expect(model.accountIDsChanging.isEmpty)
}

@MainActor
@Test func aRemovalTheRuntimeCouldNotFinishLeavesEverythingOnScreen() async throws {
    let route = ConversationRoute(accountID: instagramAccount.id, conversationID: "!room")
    let lifecycle = FakeAccountLifecycle()
    let model = try await startedModel(
        seed: snapshot(
            accounts: [instagramAccount],
            identities: [RemoteIdentity(id: "maya", accountID: instagramAccount.id, displayName: "Maya")],
            conversations: [RemoteConversation(
                id: "!room", accountID: instagramAccount.id, identityID: "maya", title: "Maya",
                latestActivity: .now, unreadCount: 0
            )],
            messages: [route: [Message(
                id: "$1", route: route, senderIdentityID: "maya", body: "hello",
                timestamp: .now, deliveryState: .acknowledged
            )]]
        ),
        lifecycle: lifecycle
    )
    await lifecycle.failNextChanges()

    await #expect(throws: LifecycleFailure.self) {
        try await model.eraseAccount(accountID: instagramAccount.id)
    }

    #expect(model.accounts == [instagramAccount], "nothing may look deleted that was not")
    #expect(model.conversations.map(\.id) == ["!room"])
    #expect(model.messagesByRoute[route]?.count == 1)
    #expect(model.accountIDsChanging.isEmpty)
}

@MainActor
@Test func aRemovalReportsWhatItCouldNotFinish() async throws {
    let unfinished = "Inbox+ could not sign out of Instagram."
    let lifecycle = FakeAccountLifecycle(removal: AccountRemoval(unfinished: [unfinished]))
    let model = try await startedModel(seed: snapshot(accounts: [instagramAccount]), lifecycle: lifecycle)

    let removal = try await model.eraseAccount(accountID: instagramAccount.id)

    #expect(await lifecycle.calls == ["remove \(instagramAccount.id)"])
    #expect(removal.unfinished == [unfinished])
    #expect(model.accounts.isEmpty)
}

@MainActor
@Test func theLocalHomeserverIsNeitherDisconnectedNorRemovedAndIMessageIsOnlyDisconnected() async throws {
    let lifecycle = FakeAccountLifecycle()
    let model = try await startedModel(
        seed: snapshot(accounts: [localMatrix, iMessageAccount]), lifecycle: lifecycle
    )

    try await model.disconnect(accountID: localMatrix.id)
    try await model.eraseAccount(accountID: localMatrix.id)
    try await model.eraseAccount(accountID: iMessageAccount.id)
    try await model.disconnect(accountID: iMessageAccount.id)

    #expect(await lifecycle.calls == ["disconnect imessage-local"])
    #expect(model.accounts.map(\.id) == [localMatrix.id, iMessageAccount.id])
    #expect(model.isConnected(localMatrix.id))
    #expect(!model.isConnected(iMessageAccount.id))
    #expect(!localMatrix.canDisconnect && !localMatrix.canRemove)
    #expect(iMessageAccount.canDisconnect && !iMessageAccount.canRemove)
    #expect(instagramAccount.canDisconnect && instagramAccount.canRemove)
}

@MainActor
@Test func erasingAnAccountForgetsItsFavourites() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("InboxPlusEraseFavourites-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = InboxFavouriteStore(fileURL: root.appendingPathComponent("favourites.json"))
    let keptAccount = ConnectedAccount(id: "whatsapp:1", platform: .whatsApp, displayName: "kept")
    let erasedRoute = ConversationRoute(accountID: instagramAccount.id, conversationID: "!room")
    let keptRoute = ConversationRoute(accountID: keptAccount.id, conversationID: "!kept")
    try store.save([erasedRoute, keptRoute])
    let model = try await startedModel(
        seed: snapshot(accounts: [instagramAccount, keptAccount]), favouriteStore: store
    )

    try await model.eraseAccount(accountID: instagramAccount.id)

    #expect(try store.load() == [keptRoute])
}
