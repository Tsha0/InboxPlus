import Foundation
import Testing
import InboxPlusCore
@testable import InboxPlusGateway

private let gibibyte = 1024 * 1024 * 1024

@Test func aHealthyDiskDownloadsWithoutComment() {
    let decision = MediaStoragePolicy().decide(freeBytes: 100 * gibibyte)
    #expect(decision.allowsDownloads)
    #expect(decision.warning == nil)
}

@Test func aFillingDiskWarnsBeforeItStopsAnything() {
    let decision = MediaStoragePolicy().decide(freeBytes: 3 * gibibyte)
    #expect(decision.allowsDownloads)
    #expect(decision.warning != nil)
}

@Test func aFullDiskStopsDownloadsAndSaysNothingWasDeleted() {
    // The design allows stopping optional downloads; it forbids deleting messages. The warning has
    // to say so, or a user under disk pressure will assume InboxPlus threw their history away.
    let decision = MediaStoragePolicy().decide(freeBytes: 512 * 1024 * 1024)
    #expect(!decision.allowsDownloads)
    #expect(decision.warning?.contains("nothing has been deleted") == true)
}

@Test func anUnreadableVolumeIsNotTreatedAsPressure() {
    let decision = MediaStoragePolicy().decide(freeBytes: nil)
    #expect(decision.allowsDownloads)
    #expect(decision.warning == nil)
}

// MARK: - Loader

private actor CountingFetcher: RemoteMediaFetching {
    private(set) var fetches: [String] = []
    private let payload: Data
    private let delay: Duration

    init(payload: Data = Data(repeating: 5, count: 32), delay: Duration = .zero) {
        self.payload = payload
        self.delay = delay
    }

    func fetch(_ handle: MediaHandle) async throws -> Data {
        fetches.append(handle.source)
        if delay != .zero { try? await Task.sleep(for: delay) }
        return payload
    }

    func count() -> Int { fetches.count }
}

private struct FixedFreeSpace: FreeSpaceReporting {
    let bytes: Int?
    func freeBytes() -> Int? { bytes }
}

private func makeLoader(
    freeBytes: Int? = 100 * gibibyte,
    fetcher: CountingFetcher = CountingFetcher()
) throws -> (MediaLoader, CountingFetcher, URL) {
    let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(".build/MediaLoaderTests-\(UUID().uuidString)")
    let cache = try MediaCache(directory: directory)
    let loader = MediaLoader(cache: cache, fetcher: fetcher, freeSpace: FixedFreeSpace(bytes: freeBytes))
    return (loader, fetcher, directory)
}

private let context = MediaCacheContext(accountID: "instagram", messageID: "$1")

@Test func mediaIsFetchedOnceAndServedFromDiskAfterwards() async throws {
    let (loader, fetcher, directory) = try makeLoader()
    defer { try? FileManager.default.removeItem(at: directory) }
    let handle = MediaHandle(source: "mxc://s/1", mimeType: "image/png")

    let first = try await loader.file(for: handle, context: context)
    let second = try await loader.file(for: handle, context: context)

    #expect(first == second)
    #expect(await fetcher.count() == 1)
}

@Test func twoViewsAskingAtOnceShareOneDownload() async throws {
    // A transcript can put the same image on screen twice; fetching it twice wastes bandwidth and
    // races two writers onto one path.
    let (loader, fetcher, directory) = try makeLoader(fetcher: CountingFetcher(delay: .milliseconds(80)))
    defer { try? FileManager.default.removeItem(at: directory) }
    let handle = MediaHandle(source: "mxc://s/1")

    async let a = loader.file(for: handle, context: context)
    async let b = loader.file(for: handle, context: context)
    _ = try await (a, b)

    #expect(await fetcher.count() == 1)
}

@Test func nothingIsFetchedForAnAttachmentThatHasNoBytes() async throws {
    let (loader, fetcher, directory) = try makeLoader()
    defer { try? FileManager.default.removeItem(at: directory) }

    await #expect(throws: MediaLoadError.nothingToDownload) {
        try await loader.file(for: MessageAttachment(id: "1", kind: .appNative), context: context)
    }
    #expect(await fetcher.count() == 0)
}

@Test func aFullDiskStopsNewDownloadsButNotCachedOnes() async throws {
    let (loader, _, directory) = try makeLoader(freeBytes: 100 * gibibyte)
    defer { try? FileManager.default.removeItem(at: directory) }
    let cached = MediaHandle(source: "mxc://s/cached")
    let downloaded = try await loader.file(for: cached, context: context)

    // Same cache, now on a full volume.
    let squeezed = MediaLoader(
        cache: try MediaCache(directory: directory),
        fetcher: CountingFetcher(),
        freeSpace: FixedFreeSpace(bytes: 100 * 1024 * 1024)
    )
    #expect(try await squeezed.file(for: cached, context: context) == downloaded)
    await #expect(throws: MediaLoadError.pausedForDiskSpace) {
        try await squeezed.file(for: MediaHandle(source: "mxc://s/new"), context: context)
    }
}

private actor SuspendedMediaFetcher: RemoteMediaFetching {
    private var result: CheckedContinuation<Data, any Error>?
    private var started: [CheckedContinuation<Void, Never>] = []

    func fetch(_ handle: MediaHandle) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            result = continuation
            for waiter in started { waiter.resume() }
            started.removeAll()
        }
    }

    func waitUntilStarted() async {
        if result != nil { return }
        await withCheckedContinuation { started.append($0) }
    }

    func finish() { result?.resume(returning: Data([1, 2, 3])); result = nil }
}

@Test func erasingAnAccountPreventsAnUncooperativeDownloadFromRecreatingMedia() async throws {
    let directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(".build/MediaLoaderTests-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    let cache = try MediaCache(directory: directory)
    let fetcher = SuspendedMediaFetcher()
    let loader = MediaLoader(cache: cache, fetcher: fetcher, freeSpace: FixedFreeSpace(bytes: 100 * gibibyte))
    let other = MediaHandle(source: "mxc://s/other")
    try await cache.store(Data([4]), for: other, context: .init(accountID: "other", messageID: "2"))
    let erased = MediaHandle(source: "mxc://s/erased")
    let pending = Task { try await loader.file(for: erased, context: context) }
    await fetcher.waitUntilStarted()
    try await loader.purge(accountID: context.accountID)
    await fetcher.finish()
    await #expect(throws: CancellationError.self) { try await pending.value }
    #expect(await cache.cachedFile(for: erased, accountID: context.accountID) == nil)
    #expect(await cache.cachedFile(for: other, accountID: "other") != nil)
}

@Test func sharedRemoteMediaIsFetchedAndPurgedSeparatelyForEachAccount() async throws {
    let (loader, fetcher, directory) = try makeLoader()
    defer { try? FileManager.default.removeItem(at: directory) }
    let handle = MediaHandle(source: "mxc://s/shared")
    let first = try await loader.file(for: handle, context: context)
    let otherContext = MediaCacheContext(accountID: "whatsapp", messageID: "$2")
    let second = try await loader.file(for: handle, context: otherContext)
    #expect(first != second)
    #expect(await fetcher.count() == 2)
    try await loader.purge(accountID: otherContext.accountID)
    #expect(!FileManager.default.fileExists(atPath: second.path))
    #expect(try await loader.file(for: handle, context: context) == first)
    #expect(await fetcher.count() == 2)
}
