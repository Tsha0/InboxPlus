import Foundation
import Testing
import InboxPlusCore
import InboxPlusGateway
import InboxPlusTestSupport
@testable import InboxPlusFeatures

@MainActor
@Test func groupedFavouritesPersistAcrossRelaunchAndCanBeRemovedAsAGroup() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = InboxFavouriteStore(fileURL: root.appendingPathComponent("personal/favourites.json"))
    let otherStore = InboxFavouriteStore(fileURL: root.appendingPathComponent("work/favourites.json"))
    let snapshot = Fixtures.makeSnapshot(
        familyActivity: Date(timeIntervalSince1970: 400),
        whatsAppActivity: Date(timeIntervalSince1970: 200),
        instagramActivity: Date(timeIntervalSince1970: 300)
    )
    let model = InboxPlusAppModel(gateway: InMemoryMessagingGateway(seed: snapshot), directory: Fixtures.directory, favouriteStore: store)
    try await model.start()
    defer { model.stop() }
    let person = try #require(model.inboxItems.first { $0.id == .person("maya") })
    #expect(model.inboxItems.first?.id == .conversation(Fixtures.telegramRoute))
    model.toggleFavourite(person)
    #expect(model.inboxItems.first?.id == person.id)
    #expect(try store.load() == [Fixtures.whatsAppRoute, Fixtures.instagramRoute])
    #expect(try otherStore.load().isEmpty)

    // Real launches currently rebuild contact groups. Route favourites still survive.
    let relaunched = InboxPlusAppModel(gateway: InMemoryMessagingGateway(seed: snapshot), favouriteStore: store)
    try await relaunched.start()
    defer { relaunched.stop() }
    #expect(relaunched.inboxItems.map(\.id) == [
        .conversation(Fixtures.instagramRoute), .conversation(Fixtures.whatsAppRoute),
        .conversation(Fixtures.telegramRoute),
    ])
    #expect(relaunched.inboxItems.filter(\.isFavourite).count == 2)
    model.toggleFavourite(person) // Resolve current state, even when the UI passes an older item.
    #expect(try store.load().isEmpty)
    #expect(model.inboxItems.allSatisfy { !$0.isFavourite })
    #expect(model.inboxItems.first?.id == .conversation(Fixtures.telegramRoute))
}
