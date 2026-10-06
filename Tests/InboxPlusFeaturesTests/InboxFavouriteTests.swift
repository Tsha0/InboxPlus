import Foundation
import Testing
import InboxPlusCore
import InboxPlusGateway
import InboxPlusTestSupport
@testable import InboxPlusFeatures

@Test func favouritesSortFirstWithActivityOrderingWithinEachGroup() {
    let snapshot = Fixtures.snapshot
    let result = InboxProjector.project(
        accounts: snapshot.accounts, identities: snapshot.identities,
        conversations: snapshot.conversations, directory: .init(),
        favouriteRoutes: [Fixtures.telegramRoute, Fixtures.whatsAppRoute]
    )
    #expect(result.map(\.id) == [
        .conversation(Fixtures.whatsAppRoute), .conversation(Fixtures.telegramRoute),
        .conversation(Fixtures.instagramRoute),
    ])
    #expect(result.map(\.isFavourite) == [true, true, false])
    #expect(result.map(\.unreadCount) == [1, 0, 2])
}

@Test func favouriteTiesRemainDeterministic() {
    let snapshot = Fixtures.makeSnapshot(familyActivity: .distantPast, whatsAppActivity: .distantPast, instagramActivity: .distantPast)
    func project(_ conversations: [RemoteConversation]) -> [InboxItem] {
        InboxProjector.project(
            accounts: snapshot.accounts, identities: snapshot.identities,
            conversations: conversations, directory: .init(),
            favouriteRoutes: [Fixtures.telegramRoute, Fixtures.whatsAppRoute]
        )
    }
    #expect(project(snapshot.conversations) == project(snapshot.conversations.reversed()))
}

@MainActor
@Test func groupedFavouritesPersistAcrossRelaunchAndCanBeRemovedAsAGroup() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = InboxFavouriteStore(fileURL: root.appendingPathComponent("personal/favourites.json"))
    let otherStore = InboxFavouriteStore(fileURL: root.appendingPathComponent("work/favourites.json"))
    let model = InboxPlusAppModel(gateway: InMemoryMessagingGateway(seed: Fixtures.snapshot), directory: Fixtures.directory, favouriteStore: store)
    try await model.start()
    defer { model.stop() }
    let person = try #require(model.inboxItems.first { $0.id == .person("maya") })
    model.toggleFavourite(person)
    #expect(try store.load() == [Fixtures.whatsAppRoute, Fixtures.instagramRoute])
    #expect(try otherStore.load().isEmpty)

    // Real launches currently rebuild contact groups. Route favourites still survive.
    let relaunched = InboxPlusAppModel(gateway: InMemoryMessagingGateway(seed: Fixtures.snapshot), favouriteStore: store)
    try await relaunched.start()
    defer { relaunched.stop() }
    #expect(relaunched.inboxItems.filter(\.isFavourite).count == 2)
    model.toggleFavourite(person) // Resolve current state, even when the UI passes an older item.
    #expect(try store.load().isEmpty)
    #expect(model.inboxItems.allSatisfy { !$0.isFavourite })
}

@MainActor
@Test func favouritingStandaloneConversationSurvivesLinkingAndUnfavouritingRestoresOrder() async throws {
    let model = InboxPlusAppModel(gateway: InMemoryMessagingGateway(seed: Fixtures.snapshot), directory: Fixtures.directory)
    try await model.start()
    defer { model.stop() }
    let family = try #require(model.inboxItems.first { $0.id == .conversation(Fixtures.telegramRoute) })
    model.toggleFavourite(family)
    #expect(model.inboxItems.first?.id == family.id)
    model.markConversationRead(Fixtures.whatsAppRoute)
    #expect(model.inboxItems.first?.id == family.id)
    model.toggleFavourite(family)
    #expect(model.inboxItems.first?.id == .person("maya"))
    model.toggleFavourite(family)
    model.openConversation(Fixtures.telegramRoute)
    try model.linkOpenConversation(to: "maya")
    #expect(model.inboxItems.count == 1)
    #expect(model.inboxItems.first?.isFavourite == true)
    model.toggleFavourite(try #require(model.inboxItems.first))
    #expect(model.inboxItems.first?.isFavourite == false)
}

@MainActor
@Test func failedFavouriteWriteDoesNotPretendSelectionWasSaved() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try Data().write(to: root)
    defer { try? FileManager.default.removeItem(at: root) }
    let model = InboxPlusAppModel(
        gateway: InMemoryMessagingGateway(seed: Fixtures.snapshot),
        favouriteStore: InboxFavouriteStore(fileURL: root.appendingPathComponent("favourites.json"))
    )
    try await model.start()
    defer { model.stop() }
    model.toggleFavourite(try #require(model.inboxItems.first))
    #expect(model.favouriteError != nil)
    #expect(model.inboxItems.allSatisfy { !$0.isFavourite })
}

@Test func corruptFavouriteDataIsReported() throws {
    let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try Data("invalid".utf8).write(to: file)
    defer { try? FileManager.default.removeItem(at: file) }
    #expect(throws: (any Error).self) { try InboxFavouriteStore(fileURL: file).load() }
}
