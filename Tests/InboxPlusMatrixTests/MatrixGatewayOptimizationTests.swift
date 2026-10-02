import Foundation
import MatrixRustSDK
import InboxPlusCore
import Testing
@testable import InboxPlusMatrix
import InboxPlusRuntime

private actor OperationCounter {
    private var active = 0
    private(set) var peak = 0
    func enter() { active += 1; peak = max(peak, active) }
    func leave() { active -= 1 }
}

@Test func roomStartupWorkHasBoundedConcurrencyAndPreservesOrdering() async throws {
    let counter = OperationCounter()
    let inputs = Array(0..<12)
    let result = try await boundedConcurrentMap(inputs, limit: 3) { value in
        await counter.enter()
        try await Task.sleep(for: .milliseconds(20 - value))
        await counter.leave()
        return value * 2
    }
    #expect(result == inputs.map { $0 * 2 })
    #expect(await counter.peak == 3)
}

@Test func roomStartupCancellationDoesNotKeepLaunchingOperations() async throws {
    let counter = OperationCounter()
    let task = Task {
        try await boundedConcurrentMap(Array(0..<100), limit: 2) { value in
            await counter.enter()
            try await Task.sleep(for: .seconds(30))
            return value
        }
    }
    for _ in 0..<100 {
        if await counter.peak == 2 { break }
        try await Task.sleep(for: .milliseconds(1))
    }
    task.cancel()
    await #expect(throws: CancellationError.self) { try await task.value }
    #expect(await counter.peak <= 2)
}

private func observerMessage(_ id: Int, body: String = "body") -> Message {
    Message(id: "event-\(id)", route: ConversationRoute(accountID: "bridge", conversationID: "room"),
            senderIdentityID: "alice", body: body, timestamp: Date(timeIntervalSince1970: Double(id)),
            deliveryState: .acknowledged)
}

@Test func observerBoundsItsDuplicateCacheWithoutDroppingDeliveredMessages() async {
    let observer = RoomTimelineObserver(roomID: "room", normalizer: MatrixEventNormalizer(accountID: "bridge"),
                                        accountID: "bridge", snapshotMessageLimit: 3)
    let messages = (0..<100).map { observerMessage($0) }
    observer.receive(messages)
    var batches = observer.batches.makeAsyncIterator()
    #expect(await batches.next() == messages)
    let snapshot = await observer.messages(waitingUpTo: .zero).sorted(by: inboxplusMessageOrdering)
    #expect(snapshot.map(\.id) == ["event-97", "event-98", "event-99"])
    observer.finish()
    #expect(await batches.next() == nil)
}

@Test func observerSuppressesDuplicatesButDeliversChangedAndEvictedEvents() async {
    let observer = RoomTimelineObserver(roomID: "room", normalizer: MatrixEventNormalizer(accountID: "bridge"),
                                        accountID: "bridge", snapshotMessageLimit: 2)
    var batches = observer.batches.makeAsyncIterator()
    let original = observerMessage(1)
    observer.receive([original])
    #expect(await batches.next() == [original])
    observer.receive([original])
    let changed = observerMessage(1, body: "edited")
    observer.receive([changed])
    #expect(await batches.next() == [changed])
    observer.receive([observerMessage(2), observerMessage(3)])
    _ = await batches.next()
    observer.receive([original])
    #expect(await batches.next() == [original])
    observer.finish()
    observer.receive([observerMessage(4)])
    #expect(await batches.next() == nil)
}

@Test func olderBackfillDoesNotEvictTheLatestObserverSnapshot() async {
    let observer = RoomTimelineObserver(roomID: "room", normalizer: MatrixEventNormalizer(accountID: "bridge"),
                                        accountID: "bridge", snapshotMessageLimit: 2)
    observer.receive([observerMessage(100), observerMessage(101)])
    observer.receive([observerMessage(1), observerMessage(2)])
    let snapshot = await observer.messages(waitingUpTo: .zero).sorted(by: inboxplusMessageOrdering)
    #expect(snapshot.map(\.id) == ["event-100", "event-101"])
    observer.finish()
}

private final class StubSyncService: SyncService, @unchecked Sendable {
    private let lock = NSLock()
    private var recordedStarts = 0
    private var recordedStops = 0
    var starts: Int { lock.withLock { recordedStarts } }
    var stops: Int { lock.withLock { recordedStops } }
    init() { super.init(noHandle: .init()) }
    required init(unsafeFromHandle handle: UInt64) { super.init(unsafeFromHandle: handle) }
    override func start() async { lock.withLock { recordedStarts += 1 } }
    override func stop() async { lock.withLock { recordedStops += 1 } }
}

private final class StubSyncBuilder: SyncServiceBuilder, @unchecked Sendable {
    let service: StubSyncService
    init(service: StubSyncService) { self.service = service; super.init(noHandle: .init()) }
    required init(unsafeFromHandle handle: UInt64) {
        service = StubSyncService()
        super.init(unsafeFromHandle: handle)
    }
    override func finish() async throws -> SyncService { service }
}

private final class StubMediaSDKClient: Client, @unchecked Sendable {
    private let content = Data("authenticated media".utf8)
    let service = StubSyncService()
    init() { super.init(noHandle: .init()) }
    required init(unsafeFromHandle handle: UInt64) { super.init(unsafeFromHandle: handle) }
    override func restoreSession(session: Session) async throws {}
    override func rooms() -> [Room] { [] }
    override func syncService() -> SyncServiceBuilder { StubSyncBuilder(service: service) }
    override func getMediaContent(mediaSource: MediaSource) async throws -> Data {
        #expect(mediaSource.url() == "mxc://inboxplus.localhost/photo")
        return content
    }
}

@Test func matrixShutdownStopsTheSharedClientAndCanReconnect() async throws {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(".build/MatrixShutdownTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let paths = try RuntimePaths(root: root, profileName: "shutdown")
    let store = MatrixClientStore(profile: paths)
    let saved = PersistedSession(accessToken: "test-only", refreshToken: nil, userID: "@inboxplus:inboxplus.localhost",
                                 deviceID: "TEST", homeserverURL: "http://127.0.0.1:18008", oauthData: nil,
                                 usesNativeSlidingSync: true)
    try store.saveSession(saved)
    let sdk = StubMediaSDKClient()
    let client = InboxPlusMatrixClient(
        homeserverURL: URL(string: saved.homeserverURL)!, store: store,
        provisioner: try MatrixAccountProvisioner(baseURL: URL(string: saved.homeserverURL)!,
                                                 serverName: "inboxplus.localhost", registrationSecret: "test-only"),
        buildClient: { sdk }
    )
    let gateway = MatrixMessagingGateway(client: client, initialSyncWait: .zero, roomDiscoveryInterval: .seconds(3_600))
    async let firstStart: Void = gateway.start()
    async let secondStart: Void = gateway.start()
    _ = try await (firstStart, secondStart)
    #expect(sdk.service.starts == 1)
    var firstStream = await gateway.events().makeAsyncIterator()
    await gateway.stop()
    #expect(await firstStream.next() == nil)
    #expect(sdk.service.stops == 1)
    await #expect(throws: InboxPlusMatrixClientError.notConnected) { try await client.requireClient() }
    try await gateway.start()
    #expect(sdk.service.starts == 2)
    await gateway.stop()
    #expect(sdk.service.stops == 2)
}

private actor ClientBuildGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var open = false
    private(set) var waiting = false
    func wait() async {
        waiting = true
        if open { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func release() { open = true; continuation?.resume(); continuation = nil }
}

@Test func cancellingASharedMatrixStartWaiterDoesNotReportSuccessfulStartup() async throws {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(".build/MatrixStartCancellationTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let store = MatrixClientStore(profile: try RuntimePaths(root: root, profileName: "cancel"))
    let saved = PersistedSession(accessToken: "test-only", refreshToken: nil, userID: "@inboxplus:inboxplus.localhost",
                                 deviceID: "TEST", homeserverURL: "http://127.0.0.1:18008", oauthData: nil,
                                 usesNativeSlidingSync: true)
    try store.saveSession(saved)
    let sdk = StubMediaSDKClient(), gate = ClientBuildGate()
    let client = InboxPlusMatrixClient(
        homeserverURL: URL(string: saved.homeserverURL)!, store: store,
        provisioner: try MatrixAccountProvisioner(baseURL: URL(string: saved.homeserverURL)!,
                                                 serverName: "inboxplus.localhost", registrationSecret: "test-only"),
        buildClient: { await gate.wait(); return sdk }
    )
    let gateway = MatrixMessagingGateway(client: client, initialSyncWait: .zero, roomDiscoveryInterval: .seconds(3_600))
    let first = Task { try await gateway.start() }
    for _ in 0..<100 {
        if await gate.waiting { break }
        try await Task.sleep(for: .milliseconds(1))
    }
    let second = Task { try await gateway.start() }
    try await Task.sleep(for: .milliseconds(10))
    second.cancel()
    await gate.release()
    try await first.value
    await #expect(throws: CancellationError.self) { try await second.value }
    #expect(sdk.service.starts == 1)
    await gateway.stop()
}

@Test func mediaFetchUsesTheClientConnectedByTheMessagingSession() async throws {
    let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        .appendingPathComponent(".build/MediaClientTests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: root) }
    let paths = try RuntimePaths(root: root, profileName: "media")
    let store = MatrixClientStore(profile: paths)
    let saved = PersistedSession(accessToken: "test-only", refreshToken: nil, userID: "@inboxplus:inboxplus.localhost",
                                 deviceID: "TEST", homeserverURL: "http://127.0.0.1:18008", oauthData: nil,
                                 usesNativeSlidingSync: true)
    try store.saveSession(saved)
    let sdk = StubMediaSDKClient()
    let client = InboxPlusMatrixClient(
        homeserverURL: URL(string: saved.homeserverURL)!, store: store,
        provisioner: try MatrixAccountProvisioner(baseURL: URL(string: saved.homeserverURL)!,
                                                 serverName: "inboxplus.localhost", registrationSecret: "test-only"),
        buildClient: { sdk }
    )
    let fetcher = MatrixMediaFetcher(client: client)
    #expect(try await client.connect() == saved)
    #expect(try await client.requireClient() === sdk)
    let data = try await fetcher.fetch(MediaHandle(source: "mxc://inboxplus.localhost/photo"))
    #expect(data == Data("authenticated media".utf8))
    await client.disconnect()
    await #expect(throws: InboxPlusMatrixClientError.notConnected) {
        try await fetcher.fetch(MediaHandle(source: "mxc://inboxplus.localhost/photo"))
    }
}
