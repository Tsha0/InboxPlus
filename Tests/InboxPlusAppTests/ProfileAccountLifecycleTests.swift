import Foundation
import InboxPlusBridge
import InboxPlusBridgeService
import InboxPlusCore
import InboxPlusFeatures
import InboxPlusGateway
import InboxPlusRuntime
import Testing
@testable import InboxPlusApp

private final class EventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String] = []

    func append(_ entry: String) { lock.withLock { entries.append(entry) } }
    var all: [String] { lock.withLock { entries } }
}

/// Stands in for the runtime session and the bridge it runs: the bridge answers exactly when the
/// profile says it should be running, which is what the session's reconciling guarantees.
private struct SimulatedBridge: SynapseHTTPTransport {
    let paths: RuntimePaths
    let log: EventLog
    var neverStops = false
    var signOutFails = false

    func send(_ request: SynapseHTTPRequest) async throws -> SynapseHTTPResponse {
        let wanted = try !DisconnectedAccountStore(paths: paths).load().contains("telegram")
        guard wanted || neverStops else {
            throw HealthTransportError.requestFailed(code: URLError.Code.cannotConnectToHost.rawValue)
        }
        guard request.url.path.hasSuffix("/logout/all") else {
            return SynapseHTTPResponse(statusCode: 200, body: Data(#"{"flows":[]}"#.utf8))
        }
        log.append("sign out")
        guard !signOutFails else {
            return SynapseHTTPResponse(statusCode: 502, body: Data(#"{"errcode":"M_UNKNOWN"}"#.utf8))
        }
        return SynapseHTTPResponse(statusCode: 200, body: Data("{}".utf8))
    }
}

private struct RecordingRooms: AccountRoomForgetting {
    let paths: RuntimePaths
    let log: EventLog

    func forgetRooms(ofAccount accountID: String) async throws {
        let stopped = try DisconnectedAccountStore(paths: paths).load().contains(accountID)
        log.append(stopped ? "forget \(accountID)" : "forget \(accountID) while its bridge runs")
    }
}

private struct RecordingPolling: PollingMessageSource {
    let log: EventLog

    func pausePolling() { log.append("pause") }
    func resumePolling() { log.append("resume") }
}

private let telegram = ConnectedAccount(id: "telegram", platform: .telegram, displayName: "Telegram")
private let iMessage = ConnectedAccount(id: "imessage-local", platform: .iMessage, displayName: "iMessage")

/// A profile with a prepared Telegram bridge and the files it leaves behind.
private struct Profile {
    let paths: RuntimePaths
    let bridgeDirectory: URL
    let registration: URL

    init() throws {
        // RuntimePaths rejects /var, including standardized temporary-directory URLs.
        let root = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Library/Caches", isDirectory: true)
            .appendingPathComponent("inboxplus-account-lifecycle-\(UUID().uuidString)")
        paths = try RuntimePaths(root: root, profileName: "test")
        bridgeDirectory = BridgeInstaller(paths: paths).directory(for: BridgeCatalog.telegram)
        registration = BridgeRuntime(paths: paths).appServiceDirectory.appendingPathComponent("telegram.yaml")

        for file in [bridgeDirectory.appendingPathComponent("bridge.db"), registration] {
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(), withIntermediateDirectories: true
            )
            try Data("x".utf8).write(to: file)
        }
        let record = PreparedBridge(
            bridgeID: "telegram", platform: .telegram, displayName: "Telegram", version: "test",
            serverName: "inboxplus.localhost", ownerUserID: "@inboxplus:inboxplus.localhost",
            executable: bridgeDirectory.appendingPathComponent("bridge").path,
            configurationFile: bridgeDirectory.appendingPathComponent("config.yaml").path,
            registrationFile: bridgeDirectory.appendingPathComponent("registration.yaml").path,
            appservicePort: 29_317, provisioningSecret: "provisioning-secret",
            sha256: String(repeating: "a", count: 64)
        )
        try FileManager.default.createDirectory(at: paths.state, withIntermediateDirectories: true)
        try JSONEncoder().encode([record])
            .write(to: paths.state.appendingPathComponent("bridges.json"))
    }

    var disconnected: Set<String> { (try? DisconnectedAccountStore(paths: paths).load()) ?? [] }
    var bridgeFilesExist: Bool {
        FileManager.default.fileExists(atPath: bridgeDirectory.path)
            || FileManager.default.fileExists(atPath: registration.path)
    }

    func lifecycle(
        log: EventLog,
        neverStops: Bool = false,
        signOutFails: Bool = false,
        iMessageIsLive: Bool = true
    ) -> ProfileAccountLifecycle {
        let sources = LiveSources()
        sources.matrix = RecordingRooms(paths: paths, log: log)
        if iMessageIsLive { sources.iMessage = RecordingPolling(log: log) }
        return ProfileAccountLifecycle(
            paths: paths,
            sources: sources,
            transport: SimulatedBridge(paths: paths, log: log, neverStops: neverStops, signOutFails: signOutFails),
            stopTimeout: .seconds(neverStops ? 1 : 10),
            startTimeout: .seconds(10),
            pollInterval: .milliseconds(20)
        )
    }

    func delete() { try? FileManager.default.removeItem(at: paths.root) }
}

@Test func disconnectingIsRecordedForTheSessionAndReconnectingUndoesIt() async throws {
    let profile = try Profile()
    defer { profile.delete() }
    let lifecycle = profile.lifecycle(log: EventLog())

    try await lifecycle.disconnect(telegram)
    #expect(profile.disconnected == ["telegram"])
    #expect(try await lifecycle.disconnectedAccountIDs() == ["telegram"])

    #expect(try await lifecycle.reconnect(telegram) == .reconnected)
    #expect(profile.disconnected.isEmpty)
}

@Test func aBridgeThatDoesNotStopIsReportedAndLeftConnected() async throws {
    let profile = try Profile()
    defer { profile.delete() }
    let lifecycle = profile.lifecycle(log: EventLog(), neverStops: true)

    await #expect(throws: AccountLifecycleError.bridgeStillRunning("Telegram")) {
        try await lifecycle.disconnect(telegram)
    }
    #expect(profile.disconnected.isEmpty, "a disconnect that did not happen must not be recorded")
}

@Test func removingSignsOutThenStopsTheBridgeBeforeLeavingItsRoomsAndDeletingItsFiles() async throws {
    let profile = try Profile()
    defer { profile.delete() }
    let log = EventLog()

    let removal = try await profile.lifecycle(log: log).remove(telegram)

    #expect(log.all == ["sign out", "forget telegram"])
    #expect(removal.unfinished.isEmpty)
    #expect(!profile.bridgeFilesExist)
    #expect(try BridgeRuntime(paths: profile.paths).prepared().isEmpty)
    #expect(profile.disconnected.isEmpty)
}

@Test func removingADisconnectedAccountStartsItsBridgeToSignOut() async throws {
    let profile = try Profile()
    defer { profile.delete() }
    try DisconnectedAccountStore(paths: profile.paths).insert("telegram")
    let log = EventLog()

    _ = try await profile.lifecycle(log: log).remove(telegram)

    #expect(log.all == ["sign out", "forget telegram"])
    #expect(!profile.bridgeFilesExist)
}

@Test func aFailedSignOutIsReportedButTheLoginIsStillDeleted() async throws {
    let profile = try Profile()
    defer { profile.delete() }
    let log = EventLog()

    let removal = try await profile.lifecycle(log: log, signOutFails: true).remove(telegram)

    #expect(removal.unfinished.count == 1)
    #expect(removal.unfinished.first?.contains("could not sign out of Telegram") == true)
    #expect(log.all == ["sign out", "forget telegram"])
    #expect(!profile.bridgeFilesExist)
}

@Test func nothingIsDeletedWhileTheBridgeIsStillRunning() async throws {
    let profile = try Profile()
    defer { profile.delete() }
    let log = EventLog()

    await #expect(throws: AccountLifecycleError.bridgeStillRunning("Telegram")) {
        _ = try await profile.lifecycle(log: log, neverStops: true).remove(telegram)
    }

    #expect(log.all == ["sign out"], "its rooms must not be left while the bridge could act on it")
    #expect(profile.bridgeFilesExist)
    #expect(profile.disconnected == ["telegram"], "it stays stopped from the next launch")
}

@Test func iMessageStopsBeingReadWhenDisconnected() async throws {
    let profile = try Profile()
    defer { profile.delete() }
    let log = EventLog()
    let lifecycle = profile.lifecycle(log: log)

    try await lifecycle.disconnect(iMessage)
    #expect(profile.disconnected == ["imessage-local"])
    #expect(try await lifecycle.reconnect(iMessage) == .reconnected)

    #expect(log.all == ["pause", "resume"])
    #expect(profile.disconnected.isEmpty)
}

@Test func iMessageDisconnectedAtLaunchComesBackOnTheNextLaunch() async throws {
    let profile = try Profile()
    defer { profile.delete() }
    try DisconnectedAccountStore(paths: profile.paths).insert("imessage-local")

    let reconnection = try await profile.lifecycle(log: EventLog(), iMessageIsLive: false).reconnect(iMessage)

    #expect(reconnection == .onNextLaunch)
    #expect(profile.disconnected.isEmpty)
}

@Test func aDisconnectedIMessageIsListedWithoutReadingAnything() async throws {
    let snapshot = try await GatewaySelection.disconnectedIMessage().loadSnapshot()

    #expect(snapshot.accounts.map(\.id) == ["imessage-local"])
    #expect(snapshot.conversations.isEmpty)
    #expect(snapshot.messagesByRoute.isEmpty)
}
