import Foundation
import Testing
import InboxPlusCore
import InboxPlusGateway
@testable import InboxPlusFeatures

private let maya = ConversationRoute(accountID: "instagram", conversationID: "maya")
private let sam = ConversationRoute(accountID: "instagram", conversationID: "sam")

private func composerDirectory() -> URL {
    URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(".build/ComposerTests-\(UUID().uuidString)", isDirectory: true)
}

private func permissions(of url: URL) throws -> Int {
    try #require(FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int)
}

private let pngBytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] + Array(repeating: 1, count: 24))

@MainActor
private func makeModel(
    composerFiles: ComposerFileStore,
    capabilities: ConversationCapabilities = .mediaCapable
) async throws -> (InboxPlusAppModel, InMemoryMessagingGateway) {
    let snapshot = MessagingSnapshot(
        accounts: [ConnectedAccount(id: "instagram", platform: .instagram, displayName: "Instagram")],
        identities: [
            RemoteIdentity(id: "maya-id", accountID: "instagram", displayName: "Maya"),
            RemoteIdentity(id: "sam-id", accountID: "instagram", displayName: "Sam"),
        ],
        conversations: [
            RemoteConversation(id: "maya", accountID: "instagram", identityID: "maya-id", title: "Maya",
                               latestActivity: Date(timeIntervalSince1970: 200), unreadCount: 0,
                               capabilities: capabilities),
            RemoteConversation(id: "sam", accountID: "instagram", identityID: "sam-id", title: "Sam",
                               latestActivity: Date(timeIntervalSince1970: 100), unreadCount: 0,
                               capabilities: capabilities),
        ],
        messagesByRoute: [:]
    )
    let gateway = InMemoryMessagingGateway(seed: snapshot)
    let model = InboxPlusAppModel(gateway: gateway, composerFiles: composerFiles)
    try await model.start()
    return (model, gateway)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func eachConversationKeepsItsOwnDraft() async throws {
    let directory = composerDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let (model, _) = try await makeModel(composerFiles: ComposerFileStore(directory: directory))
    defer { model.stop() }

    model.openConversation(maya)
    model.setDraft("See you at", for: maya)
    model.openConversation(sam)
    #expect(model.draft(for: sam).isEmpty)
    model.setDraft("Running late", for: sam)
    model.openConversation(maya)

    #expect(model.draft(for: maya) == "See you at")
    #expect(model.draft(for: sam) == "Running late")
    #expect(model.routesWithDrafts == [maya, sam])
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func sendingOneDraftLeavesAnotherConversationsDraftAlone() async throws {
    let directory = composerDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let (model, _) = try await makeModel(composerFiles: ComposerFileStore(directory: directory))
    defer { model.stop() }
    model.setDraft("For Maya", for: maya)
    model.setDraft("For Sam", for: sam)

    try await model.sendDraft(model.captureDraft(to: maya))

    #expect(model.draft(for: maya).isEmpty)
    #expect(model.draft(for: sam) == "For Sam")
    #expect(model.routesWithDrafts == [sam])
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func onlyADraftWithSomethingInItMarksItsConversation() async throws {
    let directory = composerDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let (model, _) = try await makeModel(composerFiles: ComposerFileStore(directory: directory))
    defer { model.stop() }

    model.setDraft(" \n ", for: maya)
    #expect(model.routesWithDrafts.isEmpty)
    // The blank lines are still the user's to keep typing after, so the text itself is kept.
    #expect(model.draft(for: maya) == " \n ")
    model.setDraft(" \nhi", for: maya)
    #expect(model.routesWithDrafts == [maya])
    model.setDraft("", for: maya)
    #expect(model.routesWithDrafts.isEmpty)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func aMultiLineMessageIsSentWithItsLineBreaks() async throws {
    let directory = composerDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let (model, gateway) = try await makeModel(composerFiles: ComposerFileStore(directory: directory))
    defer { model.stop() }
    model.setDraft("First line\n\nThird line\n", for: maya)

    try await model.sendDraft(model.captureDraft(to: maya))

    let sent = try #require(try await gateway.loadSnapshot().messagesByRoute[maya]?.last)
    #expect(sent.body == "First line\n\nThird line")
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func aPastedPictureIsStagedWhereOnlyThisUserCanReadItAndDeletedOnceSent() async throws {
    let directory = composerDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let (model, _) = try await makeModel(composerFiles: ComposerFileStore(directory: directory))
    defer { model.stop() }

    #expect(model.stageAttachment(pngBytes, named: "Image.png", for: maya) == nil)

    let staged = try #require(model.stagedAttachments(for: maya).first)
    #expect(staged.filename == "Image.png")
    #expect(staged.kind == .image)
    #expect(staged.byteCount == pngBytes.count)
    #expect(try Data(contentsOf: staged.fileURL) == pngBytes)
    #expect(try permissions(of: staged.fileURL) == 0o600)
    #expect(try permissions(of: staged.fileURL.deletingLastPathComponent()) == 0o700)
    #expect(try permissions(of: directory) == 0o700)
    #expect(model.routesWithDrafts.isEmpty)
    #expect(model.hasUnfinishedMessagingWork)

    try await model.sendStagedAttachments(for: model.captureDraft(to: maya))

    #expect(model.stagedAttachments(for: maya).isEmpty)
    #expect(!FileManager.default.fileExists(atPath: staged.fileURL.deletingLastPathComponent().path))
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func aPastedPictureTakenBackIsDeleted() async throws {
    let directory = composerDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let (model, _) = try await makeModel(composerFiles: ComposerFileStore(directory: directory))
    defer { model.stop() }
    model.stageAttachment(pngBytes, named: "Image.png", for: maya)
    let staged = try #require(model.stagedAttachments(for: maya).first)

    model.removeStagedAttachment(staged, for: maya)

    #expect(!FileManager.default.fileExists(atPath: staged.fileURL.path))
    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func aPastedPictureTheConversationRefusesLeavesNothingBehind() async throws {
    let directory = composerDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let (model, _) = try await makeModel(
        composerFiles: ComposerFileStore(directory: directory),
        capabilities: ConversationCapabilities(attachmentKinds: [.file])
    )
    defer { model.stop() }

    let rejection = model.stageAttachment(pngBytes, named: "Image.png", for: maya)

    #expect(rejection == .kindNotSupported(.image))
    #expect(model.sendFailure(for: maya) == rejection?.message)
    #expect(model.stagedAttachments(for: maya).isEmpty)
    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func takingBackAFileTheUserChoseNeverDeletesIt() async throws {
    let directory = composerDirectory()
    let ownFolder = composerDirectory()
    defer {
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.removeItem(at: ownFolder)
    }
    let (model, _) = try await makeModel(composerFiles: ComposerFileStore(directory: directory))
    defer { model.stop() }
    try FileManager.default.createDirectory(at: ownFolder, withIntermediateDirectories: true)
    let own = ownFolder.appendingPathComponent("holiday.png")
    try pngBytes.write(to: own)
    model.stageAttachment(at: own, for: maya)
    let staged = try #require(model.stagedAttachments(for: maya).first)

    model.removeStagedAttachment(staged, for: maya)

    #expect(FileManager.default.fileExists(atPath: own.path))
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func removingAnAccountDropsItsDraftsAndPastedPictures() async throws {
    let directory = composerDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let (model, _) = try await makeModel(composerFiles: ComposerFileStore(directory: directory))
    defer { model.stop() }
    model.setDraft("Never sent", for: maya)
    model.stageAttachment(pngBytes, named: "Image.png", for: sam)

    try await model.eraseAccount(accountID: "instagram")

    #expect(model.draft(for: maya).isEmpty)
    #expect(model.routesWithDrafts.isEmpty)
    #expect(model.stagedAttachments(for: sam).isEmpty)
    #expect(!model.hasUnfinishedMessagingWork)
    #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).isEmpty)
}

@Test func leftoversFromAnEarlierLaunchAreCleared() throws {
    let directory = composerDirectory()
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = ComposerFileStore(directory: directory)
    let leftover = try store.write(pngBytes, named: "Image.png")
    #expect(FileManager.default.fileExists(atPath: leftover.path))

    store.removeAll()

    #expect(!FileManager.default.fileExists(atPath: directory.path))
}
