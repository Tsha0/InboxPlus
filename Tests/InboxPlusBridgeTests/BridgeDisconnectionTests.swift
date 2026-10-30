import Foundation
import Testing
import InboxPlusBridge
import InboxPlusCore
import InboxPlusRuntime
import InboxPlusTestSupport
@testable import InboxPlusBridgeService

// RuntimePaths rejects /var, including standardized temporary-directory URLs.
private func temporaryPaths() throws -> RuntimePaths {
    let root = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        .appendingPathComponent("Library/Caches", isDirectory: true)
        .appendingPathComponent("inboxplus-bridge-disconnect-\(UUID().uuidString)")
    return try RuntimePaths(root: root, profileName: "test")
}

private func record(_ descriptor: BridgeDescriptor, port: UInt16, paths: RuntimePaths) -> PreparedBridge {
    let directory = BridgeInstaller(paths: paths).directory(for: descriptor)
    return PreparedBridge(
        bridgeID: descriptor.id, platform: descriptor.platform, displayName: descriptor.displayName,
        version: "test", serverName: "inboxplus.localhost", ownerUserID: "@inboxplus:inboxplus.localhost",
        executable: directory.appendingPathComponent("bridge").path,
        configurationFile: directory.appendingPathComponent("config.yaml").path,
        registrationFile: directory.appendingPathComponent("registration.yaml").path,
        appservicePort: port, provisioningSecret: "test-secret-\(descriptor.id)",
        sha256: String(repeating: "a", count: 64)
    )
}

private final class EventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String] = []

    func append(_ entry: String) { lock.withLock { entries.append(entry) } }
    var all: [String] { lock.withLock { entries } }
    func clear() { lock.withLock { entries.removeAll() } }
}

private struct StartFailure: Error {}

private struct FakeSupervisor: BridgeProcessSupervising {
    let bridgeID: String
    let log: EventLog
    let failsToStart: Bool

    func start() async throws -> RuntimeSnapshot {
        log.append("start \(bridgeID)")
        if failsToStart { throw StartFailure() }
        return .stopped
    }

    func stop() async throws -> RuntimeSnapshot {
        log.append("stop \(bridgeID)")
        return .stopped
    }
}

private func fleet(
    runtime: BridgeRuntime,
    eligible: [PreparedBridge],
    log: EventLog,
    failingToStart: Set<String> = []
) -> BridgeFleet {
    BridgeFleet(
        eligible: eligible,
        wanted: { try runtime.bridgesToRun() },
        launch: { FakeSupervisor(bridgeID: $0.bridgeID, log: log, failsToStart: failingToStart.contains($0.bridgeID)) },
        onReady: { _, _ in },
        onStopped: { _ in },
        onFailed: { _, _ in }
    )
}

@Test func disconnectingStopsThatBridgeAloneAndReconnectingStartsItAgain() async throws {
    let paths = try temporaryPaths()
    defer { try? FileManager.default.removeItem(at: paths.root) }
    let telegram = record(BridgeCatalog.telegram, port: 29_301, paths: paths)
    let whatsApp = record(BridgeCatalog.whatsApp, port: 29_302, paths: paths)
    try PreparedBridgeStore(paths: paths).save([telegram, whatsApp])
    let log = EventLog()
    let runtime = BridgeRuntime(paths: paths)
    let session = fleet(runtime: runtime, eligible: [telegram, whatsApp], log: log)

    await session.reconcile()
    #expect(await session.runningBridgeIDs == ["telegram", "whatsapp"])

    log.clear()
    try DisconnectedAccountStore(paths: paths).insert("telegram")
    await session.reconcile()
    #expect(log.all == ["stop telegram"])
    #expect(await session.runningBridgeIDs == ["whatsapp"])

    log.clear()
    try DisconnectedAccountStore(paths: paths).remove("telegram")
    await session.reconcile()
    #expect(log.all == ["start telegram"])
    #expect(await session.runningBridgeIDs == ["telegram", "whatsapp"])
}

@Test func aBridgeDisconnectedInAnEarlierSessionIsNeverStarted() async throws {
    let paths = try temporaryPaths()
    defer { try? FileManager.default.removeItem(at: paths.root) }
    let telegram = record(BridgeCatalog.telegram, port: 29_301, paths: paths)
    let whatsApp = record(BridgeCatalog.whatsApp, port: 29_302, paths: paths)
    try PreparedBridgeStore(paths: paths).save([telegram, whatsApp])
    try DisconnectedAccountStore(paths: paths).insert("telegram")
    let log = EventLog()

    let session = fleet(runtime: BridgeRuntime(paths: paths), eligible: [telegram, whatsApp], log: log)
    await session.reconcile()

    #expect(log.all == ["start whatsapp"])
    #expect(try BridgeRuntime(paths: paths).bridgesToRun() == [whatsApp])
}

@Test func aRemovedBridgeStopsAndOnePreparedMidSessionWaitsForTheNextSession() async throws {
    let paths = try temporaryPaths()
    defer { try? FileManager.default.removeItem(at: paths.root) }
    let telegram = record(BridgeCatalog.telegram, port: 29_301, paths: paths)
    let whatsApp = record(BridgeCatalog.whatsApp, port: 29_302, paths: paths)
    let store = PreparedBridgeStore(paths: paths)
    try store.save([telegram])
    let log = EventLog()
    let session = fleet(runtime: BridgeRuntime(paths: paths), eligible: [telegram], log: log)
    await session.reconcile()

    log.clear()
    try store.remove(bridgeID: "telegram")
    // Synapse has not loaded this registration, so starting the bridge now could only fail.
    try store.upsert(whatsApp)
    await session.reconcile()

    #expect(log.all == ["stop telegram"])
    #expect(await session.runningBridgeIDs.isEmpty)
}

@Test func aBridgeThatFailedToStartIsRetriedOnlyWhenReconnected() async throws {
    let paths = try temporaryPaths()
    defer { try? FileManager.default.removeItem(at: paths.root) }
    let telegram = record(BridgeCatalog.telegram, port: 29_301, paths: paths)
    try PreparedBridgeStore(paths: paths).save([telegram])
    let log = EventLog()
    let session = fleet(
        runtime: BridgeRuntime(paths: paths), eligible: [telegram], log: log, failingToStart: ["telegram"]
    )

    await session.reconcile()
    await session.reconcile()
    #expect(log.all == ["start telegram"])

    try DisconnectedAccountStore(paths: paths).insert("telegram")
    await session.reconcile()
    try DisconnectedAccountStore(paths: paths).remove("telegram")
    await session.reconcile()
    #expect(log.all == ["start telegram", "start telegram"])
}

@Test func anUnreadableDisconnectionListLeavesRunningBridgesAlone() async throws {
    let paths = try temporaryPaths()
    defer { try? FileManager.default.removeItem(at: paths.root) }
    let telegram = record(BridgeCatalog.telegram, port: 29_301, paths: paths)
    try PreparedBridgeStore(paths: paths).save([telegram])
    let log = EventLog()
    let session = fleet(runtime: BridgeRuntime(paths: paths), eligible: [telegram], log: log)
    await session.reconcile()

    try Data("not json".utf8).write(to: DisconnectedAccountStore(paths: paths).file)
    await session.reconcile()

    #expect(log.all == ["start telegram"])
    #expect(await session.runningBridgeIDs == ["telegram"])
}

@Test func disconnectionsArePersistedPrivatelyAndSurviveANewStore() throws {
    let paths = try temporaryPaths()
    defer { try? FileManager.default.removeItem(at: paths.root) }
    #expect(try DisconnectedAccountStore(paths: paths).load().isEmpty)

    try DisconnectedAccountStore(paths: paths).insert("telegram")
    try DisconnectedAccountStore(paths: paths).insert("imessage-local")
    try DisconnectedAccountStore(paths: paths).remove("imessage-local")

    let store = DisconnectedAccountStore(paths: paths)
    #expect(try store.load() == ["telegram"])
    let attributes = try FileManager.default.attributesOfItem(atPath: store.file.path)
    #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o600)
}

@Test func removingABridgeDeletesEverythingItKeptAndNothingOfAnotherBridge() throws {
    let paths = try temporaryPaths()
    defer { try? FileManager.default.removeItem(at: paths.root) }
    let runtime = BridgeRuntime(paths: paths)
    let installer = BridgeInstaller(paths: paths)
    let fileManager = FileManager.default
    func write(_ url: URL) throws {
        try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: url)
    }

    let removedDirectory = installer.directory(for: BridgeCatalog.telegram)
    let keptDirectory = installer.directory(for: BridgeCatalog.whatsApp)
    for name in ["config.yaml", "registration.yaml", "bridge.db", "bridge.db-wal", "logs/bridge.log"] {
        try write(removedDirectory.appendingPathComponent(name))
        try write(keptDirectory.appendingPathComponent(name))
    }
    let removedRegistration = runtime.appServiceDirectory.appendingPathComponent("telegram.yaml")
    let keptRegistration = runtime.appServiceDirectory.appendingPathComponent("whatsapp.yaml")
    try write(removedRegistration)
    try write(keptRegistration)
    let removedLogs = ["telegram.out.log", "telegram.err.log", "telegram.out.log.1"]
        .map { paths.logs.appendingPathComponent($0) }
    let keptLogs = ["whatsapp.out.log", "synapse.out.log"].map { paths.logs.appendingPathComponent($0) }
    for log in removedLogs + keptLogs { try write(log) }
    let telegram = record(BridgeCatalog.telegram, port: 29_301, paths: paths)
    let whatsApp = record(BridgeCatalog.whatsApp, port: 29_302, paths: paths)
    try PreparedBridgeStore(paths: paths).save([telegram, whatsApp])

    try runtime.remove(BridgeCatalog.telegram)

    for gone in [removedDirectory, removedRegistration] + removedLogs {
        #expect(!fileManager.fileExists(atPath: gone.path), "\(gone.lastPathComponent) survived")
    }
    for kept in [keptDirectory.appendingPathComponent("bridge.db"), keptRegistration] + keptLogs {
        #expect(fileManager.fileExists(atPath: kept.path), "\(kept.lastPathComponent) was deleted")
    }
    #expect(try runtime.prepared() == [whatsApp])
}

@Test func signingOutAsksTheBridgeToEndEveryLoginForTheActingUser() async throws {
    let bridge = DummyBridge(script: .telegram)
    let client = try BridgeProvisioningClient(
        baseURL: URL(string: "http://127.0.0.1:29337")!,
        provisioningToken: "provisioning-secret",
        userID: "@inboxplus:inboxplus.localhost",
        transport: bridge
    )

    try await client.logOutEverywhere()

    #expect(await bridge.paths() == ["/_matrix/provision/v3/logout/all"])
}
