import Testing
@testable import PalloCore
@testable import PalloGateway
@testable import PalloFeatures

@MainActor
@Test func linkedPersonOpensSummaryBeforeConversation() async throws {
    let gateway = InMemoryMessagingGateway(seed: Fixtures.snapshot)
    let model = PalloAppModel(gateway: gateway, directory: Fixtures.directory)
    try await model.start()

    let person = try #require(model.inboxItems.first { $0.id == .person("maya") })
    model.selectInboxItem(person)
    #expect(model.detailSelection == .personSummary("maya"))
}

@MainActor
@Test func sendingUsesOnlyTheExplicitlyOpenedRoute() async throws {
    let gateway = InMemoryMessagingGateway(seed: Fixtures.snapshot)
    let model = PalloAppModel(gateway: gateway, directory: Fixtures.directory)
    try await model.start()
    let instagram = ConversationRoute(accountID: "instagram-primary", conversationID: "maya-instagram")
    let whatsApp = ConversationRoute(accountID: "whatsapp-primary", conversationID: "maya-whatsapp")
    let whatsAppCountBefore = (try await gateway.loadSnapshot()).messagesByRoute[whatsApp]?.count

    model.openConversation(instagram)
    model.draft = "Sent through Instagram"
    try await model.sendDraft()

    #expect(model.openRoute == instagram)
    let snapshot = try await gateway.loadSnapshot()
    #expect(snapshot.messagesByRoute[instagram]?.last?.body == "Sent through Instagram")
    #expect(snapshot.messagesByRoute[whatsApp]?.count == whatsAppCountBefore)
}

@MainActor
@Test func userCanExplicitlyLinkAnOpenStandaloneConversation() async throws {
    let model = PalloAppModel(gateway: InMemoryMessagingGateway(seed: Fixtures.snapshot), directory: Fixtures.directory)
    try await model.start()
    model.openConversation(Fixtures.telegramRoute)

    let personID = try model.createPersonAndLinkOpenConversation(displayName: "Family")

    #expect(model.detailSelection == .personSummary(personID))
    #expect(model.inboxItems.first { $0.id == .person(personID) }?.conversationSummaries.map(\.route) == [Fixtures.telegramRoute])
}

@MainActor
@Test func startRejectsMultipleAccountsForTheSamePlatform() async throws {
    let duplicateAccountSnapshot = MessagingSnapshot(
        accounts: [
            ConnectedAccount(id: "whatsapp-one", platform: .whatsApp, displayName: "One"),
            ConnectedAccount(id: "whatsapp-two", platform: .whatsApp, displayName: "Two"),
        ],
        identities: [],
        conversations: [],
        messagesByRoute: [:]
    )
    let model = PalloAppModel(gateway: InMemoryMessagingGateway(seed: duplicateAccountSnapshot))

    await #expect(throws: AccountPolicyError.duplicatePlatform(.whatsApp)) {
        try await model.start()
    }
}

@MainActor
@Test func failedCreateAndLinkDoesNotLeaveAnUnlinkedPerson() async throws {
    let model = PalloAppModel(gateway: InMemoryMessagingGateway(seed: Fixtures.snapshot), directory: Fixtures.directory)
    try await model.start()
    model.openConversation(Fixtures.instagramRoute)
    let peopleBefore = model.people

    #expect(throws: ContactDirectoryError.identityAlreadyLinked) {
        try model.createPersonAndLinkOpenConversation(displayName: "Duplicate Maya")
    }

    #expect(model.people == peopleBefore)
    #expect(model.detailSelection == .conversation(Fixtures.instagramRoute))
}

@MainActor
@Test func createAndLinkWithoutAnOpenConversationIsAtomic() async throws {
    let model = PalloAppModel(gateway: InMemoryMessagingGateway(seed: Fixtures.snapshot), directory: Fixtures.directory)
    try await model.start()
    let peopleBefore = model.people

    #expect(throws: PalloAppModelError.missingOpenConversation) {
        try model.createPersonAndLinkOpenConversation(displayName: "Orphan")
    }

    #expect(model.people == peopleBefore)
    #expect(model.detailSelection == .empty)
}
