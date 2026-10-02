import Foundation
import Testing
import InboxPlusBridge
import InboxPlusCore
import InboxPlusRuntime
@testable import InboxPlusBridgeService

private actor LifecycleRecorder {
    private var starts: [String: Int] = [:]
    private var activeStarts = 0
    private var activeStops = 0
    private var maximumStarts = 0
    private var maximumStops = 0
    private var stoppedCount = 0
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var stopWaiter: CheckedContinuation<Void, Never>?
    let paired: Bool

    init(paired: Bool = false) { self.paired = paired }
    func launch(_ id: String) async {
        starts[id, default: 0] += 1
        activeStarts += 1
        maximumStarts = max(maximumStarts, activeStarts)
        if paired {
            if let waiter = startWaiter { startWaiter = nil; waiter.resume() }
            else { await withCheckedContinuation { startWaiter = $0 } }
        }
        activeStarts -= 1
    }
    func stop() async {
        stoppedCount += 1
        activeStops += 1
        maximumStops = max(maximumStops, activeStops)
        if paired {
            if let waiter = stopWaiter { stopWaiter = nil; waiter.resume() }
            else { await withCheckedContinuation { stopWaiter = $0 } }
        }
        activeStops -= 1
    }
    func launches(_ id: String) -> Int { starts[id, default: 0] }
    func stops() -> Int { stoppedCount }
    func maxima() -> (Int, Int) { (maximumStarts, maximumStops) }
}

private actor LifecycleProcess: ManagedProcess {
    let id: String
    let recorder: LifecycleRecorder
    private var alive = false
    private let identity = ManagedProcessIdentity(
        executablePath: "/unused/bridge", launchTimestamp: .distantPast,
        processIdentifier: 42, startIdentityToken: "test-child"
    )
    init(id: String, recorder: LifecycleRecorder) { self.id = id; self.recorder = recorder }
    func launch() async throws -> ManagedProcessIdentity {
        await recorder.launch(id)
        alive = true
        return identity
    }
    func identityStatus(for expected: ManagedProcessIdentity) async -> ManagedProcessIdentityStatus {
        alive ? .matching : .exited
    }
    func ownership(for expected: ManagedProcessIdentity) async -> ManagedProcessOwnership { .directChild }
    func signal(_ signal: ManagedProcessSignal, ifMatching expected: ManagedProcessIdentity) async throws -> Bool {
        await recorder.stop()
        alive = false
        return true
    }
    func waitForExit(matching expected: ManagedProcessIdentity, timeout: Duration) async throws -> Bool {
        alive = false
        return true
    }
}

private struct LifecycleFactory: ManagedProcessFactory {
    let process: LifecycleProcess
    func make(_ configuration: ManagedProcessConfiguration) throws -> any ManagedProcess { process }
    func rehydrate(_ configuration: ManagedProcessConfiguration, expectedIdentity: ManagedProcessIdentity) throws -> any ManagedProcess {
        process
    }
}
private struct NoListener: LoopbackListenerChecking {
    func presence(on port: UInt16) async -> LoopbackListenerPresence { .absent }
}
private actor LifecycleHealth: SynapseHealthChecking {
    private var crashPending = false
    private var failurePending: HealthFailure?
    func crash() { crashPending = true }
    func fail() { failurePending = .processIdentityIndeterminate(.processIdentityUnavailable(42)) }
    func check(snapshot: RuntimeSnapshot) async -> HealthResult {
        if let failurePending { return .degraded(failurePending) }
        if crashPending { crashPending = false; return .stopped }
        return .healthy(latency: .milliseconds(1))
    }
}

private struct BridgeLifecycleFixture: Sendable {
    let root: URL
    let paths: RuntimePaths
    let records: [PreparedBridge]
    init(count: Int) throws {
        root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent(".build/BridgeLifecycleTests-\(UUID().uuidString)")
        paths = try RuntimePaths(root: root, profileName: "test")
        records = [BridgeCatalog.instagram, BridgeCatalog.whatsApp, BridgeCatalog.telegram, BridgeCatalog.facebookMessenger].prefix(count).map {
            PreparedBridge(
                bridgeID: $0.id, platform: $0.platform, displayName: $0.displayName,
                version: "test", serverName: "mimo.localhost", ownerUserID: "@mimo:mimo.localhost",
                executable: "/unused/bridge", configurationFile: "/unused/config",
                registrationFile: "/unused/registration", appservicePort: 29337,
                provisioningSecret: "test", sha256: String(repeating: "a", count: 64)
            )
        }
        try PreparedBridgeStore(paths: paths).save(records)
    }
    func supervisor(record: PreparedBridge, recorder: LifecycleRecorder, health: LifecycleHealth) -> SynapseSupervisor {
        SynapseSupervisor(
            configuration: ManagedProcessConfiguration(
                executable: URL(fileURLWithPath: record.executable), arguments: [], environment: [:],
                workingDirectory: paths.profile, profileRoot: paths.profile, logsDirectory: paths.logs,
                standardOutputLog: paths.logs.appendingPathComponent("out"),
                standardErrorLog: paths.logs.appendingPathComponent("err")
            ),
            loopbackPort: record.appservicePort,
            processFactory: LifecycleFactory(process: LifecycleProcess(id: record.bridgeID, recorder: recorder)),
            listenerChecker: NoListener(), healthChecker: health,
            healthPollInterval: .milliseconds(1), recoverySleep: { _ in },
            now: { .zero }
        )
    }
}

@Test func bridgeStartupAndShutdownUseBoundedConcurrency() async throws {
    let fixture = try BridgeLifecycleFixture(count: 4)
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let recorder = LifecycleRecorder(paired: true)
    let runtime = BridgeRuntime(paths: fixture.paths, maximumConcurrentOperations: 2) { record in
        fixture.supervisor(record: record, recorder: recorder, health: LifecycleHealth())
    }
    try await runtime.withRunningBridges { running in #expect(running.count == 4) }
    let (starts, stops) = await recorder.maxima()
    #expect(starts == 2)
    #expect(stops == 2)
}

@Test func oneBridgeCrashRecoversWithoutRestartingOtherNetworks() async throws {
    let fixture = try BridgeLifecycleFixture(count: 2)
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let recorder = LifecycleRecorder()
    let crashingHealth = LifecycleHealth()
    let otherHealth = LifecycleHealth()
    let firstID = fixture.records[0].bridgeID
    let otherID = fixture.records[1].bridgeID
    let runtime = BridgeRuntime(paths: fixture.paths) { record in
        fixture.supervisor(record: record, recorder: recorder,
                           health: record.bridgeID == firstID ? crashingHealth : otherHealth)
    }
    try await runtime.withRunningBridges { _ in
        await crashingHealth.crash()
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while await recorder.launches(firstID) < 2, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(1))
        }
        #expect(await recorder.launches(firstID) == 2)
        #expect(await recorder.launches(otherID) == 1)
    }
}

private final class BridgeFailureRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var ids: [String] = []
    func record(_ id: String) { lock.withLock { ids.append(id) } }
    func recordedIDs() -> [String] { lock.withLock { ids } }
}

@Test func terminalBridgeFailureIsReportedWhileOtherNetworksKeepRunning() async throws {
    let fixture = try BridgeLifecycleFixture(count: 2)
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let recorder = LifecycleRecorder()
    let failures = BridgeFailureRecorder()
    let failingHealth = LifecycleHealth()
    let firstID = fixture.records[0].bridgeID
    let otherID = fixture.records[1].bridgeID
    let runtime = BridgeRuntime(paths: fixture.paths) { record in
        fixture.supervisor(record: record, recorder: recorder,
                           health: record.bridgeID == firstID ? failingHealth : LifecycleHealth())
    }
    try await runtime.withRunningBridges(onBridgeFailed: { record, _ in failures.record(record.bridgeID) }) { running in
        await failingHealth.fail()
        let deadline = ContinuousClock.now.advanced(by: .seconds(2))
        while failures.recordedIDs().isEmpty, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(1))
        }
        #expect(failures.recordedIDs() == [firstID])
        let other = try #require(running.first { $0.key.bridgeID == otherID }?.value)
        #expect(await other.status().phase == .healthy)
        #expect(await recorder.launches(otherID) == 1)
    }
}

private enum BridgeBodyFailure: Error, Equatable { case injected }

@Test func throwingBridgeSessionStopsEveryStartedChild() async throws {
    let fixture = try BridgeLifecycleFixture(count: 2)
    defer { try? FileManager.default.removeItem(at: fixture.root) }
    let recorder = LifecycleRecorder()
    let runtime = BridgeRuntime(paths: fixture.paths) { record in
        fixture.supervisor(record: record, recorder: recorder, health: LifecycleHealth())
    }
    await #expect(throws: BridgeBodyFailure.injected) {
        try await runtime.withRunningBridges { _ in throw BridgeBodyFailure.injected }
    }
    #expect(await recorder.stops() == 2)
}
