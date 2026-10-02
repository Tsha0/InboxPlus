import Foundation
import Testing
import InboxPlusCore
import InboxPlusGateway
@testable import InboxPlusFeatures

private struct StubFetcher: RemoteMediaFetching {
    var failure: (any Error)?
    func fetch(_ handle: MediaHandle) async throws -> Data {
        if let failure { throw failure }
        return Data(repeating: 4, count: 16)
    }
}

private struct FixedFreeSpace: FreeSpaceReporting {
    let bytes: Int?
    func freeBytes() -> Int? { bytes }
}

private struct Failure: Error, LocalizedError {
    var errorDescription: String? { "the homeserver refused" }
}

@MainActor
private func makeController(
    failure: (any Error)? = nil,
    freeBytes: Int = 100 * 1024 * 1024 * 1024
) throws -> (MediaController, URL) {
    let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(".build/MediaControllerTests-\(UUID().uuidString)")
    let loader = MediaLoader(
        cache: try MediaCache(directory: directory),
        fetcher: StubFetcher(failure: failure),
        freeSpace: FixedFreeSpace(bytes: freeBytes)
    )
    return (MediaController(loader: loader), directory)
}

private let image = MessageAttachment(
    id: "a1",
    kind: .image,
    source: MediaHandle(source: "mxc://s/1", mimeType: "image/png")
)

@MainActor
@Test func anAttachmentIsIdleUntilSomethingAsksForIt() throws {
    let (controller, directory) = try makeController()
    defer { try? FileManager.default.removeItem(at: directory) }

    // Lazily means lazily: constructing the controller downloads nothing.
    #expect(controller.state(for: image, accountID: "instagram") == .idle)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func loadingAnAttachmentEndsWithAFileOnDisk() async throws {
    let (controller, directory) = try makeController()
    defer { try? FileManager.default.removeItem(at: directory) }

    controller.load(image, accountID: "instagram", messageID: "$1")
    #expect(controller.state(for: image, accountID: "instagram") == .loading)

    let url = try await waitForFile(controller, image)
    #expect(FileManager.default.fileExists(atPath: url.path))
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func aFailedDownloadSaysWhyAndCanBeRetried() async throws {
    let (controller, directory) = try makeController(failure: Failure())
    defer { try? FileManager.default.removeItem(at: directory) }

    controller.load(image, accountID: "instagram", messageID: "$1")
    let reason = try await waitForFailure(controller, image)
    #expect(reason.contains("refused"))

    // A failure must not be sticky, or a transient network blip loses the photo forever.
    controller.retry(image, accountID: "instagram", messageID: "$1")
    #expect(controller.state(for: image, accountID: "instagram") != .idle)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func diskPressurePausesAndExplainsRatherThanLookingBroken() async throws {
    let (controller, directory) = try makeController(freeBytes: 100 * 1024 * 1024)
    defer { try? FileManager.default.removeItem(at: directory) }

    controller.load(image, accountID: "instagram", messageID: "$1")
    let deadline = ContinuousClock().now.advanced(by: .seconds(5))
    while ContinuousClock().now < deadline {
        if case .paused = controller.state(for: image, accountID: "instagram") { break }
        try await Task.sleep(for: .milliseconds(10))
    }
    guard case let .paused(reason) = controller.state(for: image, accountID: "instagram") else {
        Issue.record("expected the download to be paused, got \(controller.state(for: image, accountID: "instagram"))")
        return
    }
    #expect(reason.contains("nothing has been deleted"))
    #expect(controller.storageWarning != nil)
}

@MainActor
@Test func anAttachmentWithNothingToFetchIsNeverLoaded() throws {
    let (controller, directory) = try makeController()
    defer { try? FileManager.default.removeItem(at: directory) }

    let card = MessageAttachment(id: "card", kind: .appNative)
    controller.load(card, accountID: "instagram", messageID: "$1")
    #expect(controller.state(for: card, accountID: "instagram") == .idle)
}

@MainActor
@Test func aControllerWithoutALoaderNeverDownloads() {
    // Previews and fixture runs must not reach for a network that is not there.
    let controller = MediaController()
    controller.load(image, accountID: "instagram", messageID: "$1")
    #expect(controller.state(for: image, accountID: "instagram") == .idle)
}

// MARK: - Helpers

@MainActor
private func waitForFile(_ controller: MediaController, _ attachment: MessageAttachment,
                         accountID: String = "instagram") async throws -> URL {
    let deadline = ContinuousClock().now.advanced(by: .seconds(10))
    while ContinuousClock().now < deadline {
        if case let .ready(url) = controller.state(for: attachment, accountID: accountID) { return url }
        try await Task.sleep(for: .milliseconds(10))
    }
    throw Failure()
}

@MainActor
private func waitForFailure(_ controller: MediaController, _ attachment: MessageAttachment) async throws -> String {
    let deadline = ContinuousClock().now.advanced(by: .seconds(10))
    while ContinuousClock().now < deadline {
        if case let .failed(reason) = controller.state(for: attachment, accountID: "instagram") { return reason }
        try await Task.sleep(for: .milliseconds(10))
    }
    throw Failure()
}

private actor RecordingFetcher: RemoteMediaFetching {
    private(set) var requested: [String] = []
    private let failingSource: String?
    init(failingSource: String? = nil) { self.failingSource = failingSource }
    func fetch(_ handle: MediaHandle) async throws -> Data {
        requested.append(handle.source)
        if handle.source == failingSource { throw Failure() }
        return Data(repeating: 4, count: 16)
    }
}

@MainActor
@Test func imageLoadingUsesTheThumbnailAndErasurePurgesTheCachedFile() async throws {
    let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(".build/MediaControllerThumbnailTests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let cache = try MediaCache(directory: directory)
    let fetcher = RecordingFetcher()
    let loader = MediaLoader(cache: cache, fetcher: fetcher,
                             freeSpace: FixedFreeSpace(bytes: 100 * 1024 * 1024 * 1024))
    let controller = MediaController(loader: loader)
    let thumbnail = MediaHandle(source: "mxc://s/thumbnail", mimeType: "image/png")
    let attachment = MessageAttachment(id: "thumb", kind: .image,
                                      source: MediaHandle(source: "mxc://s/full"), thumbnail: thumbnail)
    controller.load(attachment, accountID: "instagram", messageID: "$thumb")
    let url = try await waitForFile(controller, attachment)
    #expect(await fetcher.requested == [thumbnail.source])
    await controller.purge(accountID: "instagram").value
    #expect(controller.state(for: attachment, accountID: "instagram") == .idle)
    #expect(!FileManager.default.fileExists(atPath: url.path))
    controller.load(attachment, accountID: "instagram", messageID: "$thumb")
    #expect(controller.state(for: attachment, accountID: "instagram") == .idle)
}

@MainActor
@Test func aMissingThumbnailFallsBackToTheOriginalPhoto() async throws {
    let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(".build/MediaControllerFallbackTests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let thumbnail = MediaHandle(source: "mxc://s/missing-thumbnail", mimeType: "image/png")
    let original = MediaHandle(source: "mxc://s/original", mimeType: "image/png")
    let fetcher = RecordingFetcher(failingSource: thumbnail.source)
    let controller = MediaController(loader: MediaLoader(cache: try MediaCache(directory: directory),
        fetcher: fetcher, freeSpace: FixedFreeSpace(bytes: 100 * 1024 * 1024 * 1024)))
    let attachment = MessageAttachment(id: "fallback", kind: .image, source: original, thumbnail: thumbnail)
    controller.load(attachment, accountID: "instagram", messageID: "$fallback")
    _ = try await waitForFile(controller, attachment)
    #expect(await fetcher.requested == [thumbnail.source, original.source])
}

@MainActor
@Test func anUndecodableThumbnailCanBeReplacedByTheOriginalOnlyOnce() async throws {
    let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(".build/MediaControllerDecodeFallbackTests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let thumbnail = MediaHandle(source: "mxc://s/undecodable-thumbnail", mimeType: "image/png")
    let original = MediaHandle(source: "mxc://s/decode-original", mimeType: "image/png")
    let fetcher = RecordingFetcher()
    let controller = MediaController(loader: MediaLoader(cache: try MediaCache(directory: directory),
        fetcher: fetcher, freeSpace: FixedFreeSpace(bytes: 100 * 1024 * 1024 * 1024)))
    let attachment = MessageAttachment(id: "decode-fallback", kind: .image, source: original, thumbnail: thumbnail)
    controller.load(attachment, accountID: "instagram", messageID: "$decode-fallback")
    _ = try await waitForFile(controller, attachment)
    #expect(controller.retryOriginal(attachment, accountID: "instagram", messageID: "$decode-fallback"))
    _ = try await waitForFile(controller, attachment)
    #expect(!controller.retryOriginal(attachment, accountID: "instagram", messageID: "$decode-fallback"))
    #expect(await fetcher.requested == [thumbnail.source, original.source])
}

private actor DeferredMediaFetcher: RemoteMediaFetching {
    private var continuation: CheckedContinuation<Data, Never>?
    var isWaiting: Bool { continuation != nil }
    func fetch(_ handle: MediaHandle) async throws -> Data {
        await withCheckedContinuation { continuation = $0 }
    }
    func finish() {
        continuation?.resume(returning: Data(repeating: 7, count: 16))
        continuation = nil
    }
}

@MainActor
@Test func replacingALoaderResetsPendingLoadsAndIgnoresObsoleteCompletions() async throws {
    let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(".build/MediaControllerReplacementTests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let oldFetcher = DeferredMediaFetcher()
    let nextFetcher = DeferredMediaFetcher()
    let oldCache = try MediaCache(directory: directory.appendingPathComponent("old"))
    let oldLoader = MediaLoader(cache: oldCache, fetcher: oldFetcher,
                               freeSpace: FixedFreeSpace(bytes: 100 * 1024 * 1024 * 1024))
    let controller = MediaController(loader: oldLoader)
    controller.load(image, accountID: "instagram", messageID: "$1")
    for _ in 0..<200 {
        if await oldFetcher.isWaiting { break }
        await Task.yield()
    }
    #expect(await oldFetcher.isWaiting)

    controller.attach(loader: MediaLoader(cache: try MediaCache(directory: directory.appendingPathComponent("next")),
        fetcher: nextFetcher, freeSpace: FixedFreeSpace(bytes: 100 * 1024 * 1024 * 1024)))
    #expect(controller.state(for: image, accountID: "instagram") == .idle)
    controller.load(image, accountID: "instagram", messageID: "$1")
    for _ in 0..<200 {
        if await nextFetcher.isWaiting { break }
        await Task.yield()
    }
    #expect(await nextFetcher.isWaiting)
    await oldFetcher.finish()
    _ = try await oldLoader.file(for: image, context: MediaCacheContext(accountID: "instagram", messageID: "$1"))
    await Task.yield()
    #expect(controller.state(for: image, accountID: "instagram") == .loading)

    // A stale completion must not remove the replacement task, or another attach cannot reset it.
    controller.attach(loader: MediaLoader(cache: try MediaCache(directory: directory.appendingPathComponent("final")),
        fetcher: StubFetcher(), freeSpace: FixedFreeSpace(bytes: 100 * 1024 * 1024 * 1024)))
    #expect(controller.state(for: image, accountID: "instagram") == .idle)
    controller.load(image, accountID: "instagram", messageID: "$1")
    let finalURL = try await waitForFile(controller, image)
    await nextFetcher.finish()
    await Task.yield()
    #expect(controller.state(for: image, accountID: "instagram") == .ready(finalURL))
    #expect(finalURL.path.contains("/final/"))
}

@MainActor
@Test func identicalAttachmentIDsKeepIndependentAccountStateAndPurgeOnlyTheirOwner() async throws {
    let (controller, directory) = try makeController()
    defer { try? FileManager.default.removeItem(at: directory) }
    controller.load(image, accountID: "instagram", messageID: "$shared")
    let instagramURL = try await waitForFile(controller, image)
    #expect(controller.state(for: image, accountID: "telegram") == .idle)
    controller.load(image, accountID: "telegram", messageID: "$shared")
    let telegramURL = try await waitForFile(controller, image, accountID: "telegram")
    #expect(instagramURL != telegramURL)

    await controller.purge(accountID: "instagram").value
    #expect(controller.state(for: image, accountID: "instagram") == .idle)
    #expect(controller.state(for: image, accountID: "telegram") == .ready(telegramURL))
    #expect(!FileManager.default.fileExists(atPath: instagramURL.path))
    #expect(FileManager.default.fileExists(atPath: telegramURL.path))
}
