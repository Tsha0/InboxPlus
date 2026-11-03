import Foundation
import Testing
import InboxPlusCore
import InboxPlusGateway
import InboxPlusTestSupport
@testable import InboxPlusFeatures

private var linkableSnapshot: MessagingSnapshot {
    let snapshot = Fixtures.snapshot
    let conversations = snapshot.conversations.map { conversation in
        var updated = conversation
        updated.title = "Maya"
        updated.isGroup = conversation.route == Fixtures.telegramRoute
        return updated
    }
    return MessagingSnapshot(
        accounts: snapshot.accounts, identities: snapshot.identities,
        conversations: conversations, messagesByRoute: snapshot.messagesByRoute
    )
}

@MainActor
@Test func manualContactLinksSurviveRelaunchAndRuntimeRefreshWithinTheirProfile() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = ContactDirectoryStore(fileURL: root.appendingPathComponent("personal/contacts/directory.json"))
    let model = InboxPlusAppModel(gateway: InMemoryMessagingGateway(seed: linkableSnapshot), contactStore: store)
    try await model.start()
    defer { model.stop() }
    model.openConversation(Fixtures.whatsAppRoute)
    let personID = try model.createPersonAndLinkOpenConversation(displayName: "Maya")
    model.openConversation(Fixtures.instagramRoute)
    try model.linkOpenConversation(to: personID)
    try await model.refreshRuntime {}
    #expect(model.personID(for: Fixtures.instagramRoute) == personID)
    model.stop()

    let relaunched = InboxPlusAppModel(gateway: InMemoryMessagingGateway(seed: linkableSnapshot), contactStore: store)
    try await relaunched.start()
    defer { relaunched.stop() }
    #expect(relaunched.people == [InboxPlusPerson(id: personID, displayName: "Maya")])
    #expect(relaunched.personID(for: Fixtures.whatsAppRoute) == personID)
    #expect(relaunched.personID(for: Fixtures.instagramRoute) == personID)
    #expect(relaunched.summaries(for: personID).count == 2)
    let otherStore = ContactDirectoryStore(fileURL: root.appendingPathComponent("work/contacts/directory.json"))
    #expect(try otherStore.load().people.isEmpty)
    let file = try FileManager.default.attributesOfItem(atPath: store.fileURL.path)
    let folder = try FileManager.default.attributesOfItem(atPath: store.fileURL.deletingLastPathComponent().path)
    #expect((file[.posixPermissions] as? NSNumber)?.intValue == 0o600)
    #expect((folder[.posixPermissions] as? NSNumber)?.intValue == 0o700)

    let removal = try await relaunched.eraseAccount(accountID: Fixtures.instagramRoute.accountID)
    #expect(removal.unfinished.isEmpty)
    let saved = try store.load()
    #expect(saved.people[personID]?.displayName == "Maya")
    #expect(saved.personID(linkedTo: "maya-instagram-identity") == nil)
    #expect(saved.personID(linkedTo: "maya-whatsapp-identity") == personID)
}

@MainActor
@Test func temporarilyMissingConversationsDoNotPruneSavedContacts() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = ContactDirectoryStore(fileURL: root.appendingPathComponent("contacts/directory.json"))
    try store.save(Fixtures.directory)
    let model = InboxPlusAppModel(gateway: InMemoryMessagingGateway(seed: .empty), contactStore: store)
    try await model.start()
    defer { model.stop() }
    try await model.refreshConversations()
    #expect(model.people == Array(Fixtures.directory.people.values))
    #expect(try store.load().links == Fixtures.directory.links)
}

@MainActor
@Test func suggestedContactLinksSurviveRelaunch() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = ContactDirectoryStore(fileURL: root.appendingPathComponent("contacts/directory.json"))
    let model = InboxPlusAppModel(gateway: InMemoryMessagingGateway(seed: linkableSnapshot), contactStore: store)
    try await model.start()
    defer { model.stop() }
    let suggestion = try #require(model.suggestedContactLinks.first)
    try model.acceptSuggestedContactLink(suggestion)
    let relaunched = InboxPlusAppModel(gateway: InMemoryMessagingGateway(seed: linkableSnapshot), contactStore: store)
    try await relaunched.start()
    defer { relaunched.stop() }
    #expect(relaunched.people == model.people)
    #expect(relaunched.suggestedContactLinks.isEmpty)
    #expect(relaunched.summaries(for: try #require(relaunched.people.first).id).count == 2)
}

@MainActor
@Test func failedContactSavesDoNotPublishPeopleOrLinksAndCanBeRetried() async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = ContactDirectoryStore(fileURL: root.appendingPathComponent("contacts/directory.json"))
    let model = InboxPlusAppModel(gateway: InMemoryMessagingGateway(seed: linkableSnapshot), contactStore: store)
    try await model.start()
    defer { model.stop() }
    try FileManager.default.createDirectory(at: store.fileURL, withIntermediateDirectories: true)
    model.openConversation(Fixtures.whatsAppRoute)
    #expect(throws: ContactStorageError.self) {
        try model.createPersonAndLinkOpenConversation(displayName: "Private name")
    }
    #expect(model.people.isEmpty)
    #expect(model.personID(for: Fixtures.whatsAppRoute) == nil)
    #expect(model.detailSelection == .conversation(Fixtures.whatsAppRoute))
    #expect(model.contactError == ContactStorageError.saveFailed.localizedDescription)
    let suggestion = try #require(model.suggestedContactLinks.first)
    #expect(throws: ContactStorageError.self) { try model.acceptSuggestedContactLink(suggestion) }
    #expect(model.people.isEmpty)
    try FileManager.default.removeItem(at: store.fileURL)
    let personID = try model.createPersonAndLinkOpenConversation(displayName: "Maya")
    #expect(model.contactError == nil)

    let saved = try Data(contentsOf: store.fileURL)
    try FileManager.default.removeItem(at: store.fileURL)
    try FileManager.default.createDirectory(at: store.fileURL, withIntermediateDirectories: false)
    model.openConversation(Fixtures.instagramRoute)
    #expect(throws: ContactStorageError.self) { try model.linkOpenConversation(to: personID) }
    #expect(model.personID(for: Fixtures.instagramRoute) == nil)
    #expect(model.personID(for: Fixtures.whatsAppRoute) == personID)
    try FileManager.default.removeItem(at: store.fileURL)
    try saved.write(to: store.fileURL)
    #expect(try store.load().links[personID]?.remoteIdentityIDs.count == 1)
}

@MainActor
@Test(arguments: [
    "not json: private contact details",
    #"{"schemaVersion":99,"people":{},"links":{}}"#,
    #"{"schemaVersion":1,"people":{},"links":{"missing":{"personID":"missing","remoteIdentityIDs":["private-id"]}}}"#,
])
func unreadableContactsAreReportedAndNeverOverwritten(contents: String) async throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let store = ContactDirectoryStore(fileURL: root.appendingPathComponent("directory.json"))
    let original = Data(contents.utf8)
    try original.write(to: store.fileURL)
    let model = InboxPlusAppModel(gateway: InMemoryMessagingGateway(seed: linkableSnapshot), contactStore: store)
    try await model.start()
    defer { model.stop() }
    #expect(model.contactError == ContactStorageError.loadFailed.localizedDescription)
    model.openConversation(Fixtures.whatsAppRoute)
    #expect(throws: ContactStorageError.self) { try model.createPersonAndLinkOpenConversation(displayName: "Maya") }
    let suggestion = try #require(model.suggestedContactLinks.first)
    #expect(throws: ContactStorageError.self) { try model.acceptSuggestedContactLink(suggestion) }
    #expect(model.people.isEmpty)
    #expect(try Data(contentsOf: store.fileURL) == original)
}
