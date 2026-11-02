import Darwin
import Foundation
import Testing
@testable import InboxPlusRuntime

// MARK: - Configuration and path faults

@Test(arguments: ["0.0.0.0", "::", "192.168.1.10", "10.0.0.1"])
func invalidNonLoopbackConfigurationIsRejected(_ address: String) throws {
    let root = try faultRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let paths = try RuntimePaths(root: root, profileName: "alpha")

    #expect(throws: SynapseConfigurationError.nonLoopbackAddress(address)) {
        try SynapseConfiguration(
            profile: paths,
            bindAddress: address,
            port: 18_008,
            credentials: SynapseCredentials(registrationSecret: "secret")
        ).validate()
    }
}

@Test func aMatrixClientCannotBeAimedOffLoopback() {
    #expect(throws: MatrixHTTPError.nonLoopbackBaseURL) {
        try MatrixHTTPClient(baseURL: URL(string: "http://10.0.0.5:8008")!, accessToken: nil)
    }
}

@Test func outOfRootRemovalIsRefused() throws {
    let root = try faultRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    #expect(throws: RuntimePathError.self) {
        try RuntimePaths(root: root, profileName: "../escape")
    }
}

// MARK: - Lifecycle faults

@Test func occupiedPortIsDetectedBeforeUse() async throws {
    // Break caught: launching onto a taken port yields a confusing health failure later.
    let listener = try OccupiedPort()
    defer { listener.close() }

    let presence = await SystemLoopbackListenerChecker().presence(on: listener.port)
    #expect(presence == .present)
}

@Test func anUnusedPortReadsAsAbsent() async throws {
    let allocator = LoopbackPortAllocator()
    let port = try allocator.allocate()
    #expect(await SystemLoopbackListenerChecker().presence(on: port) == .absent)
}

@Test func versionDriftBlocksStartupUntilExplicitBootstrap() throws {
    let manifest = RuntimeManifest(
        schemaVersion: 1,
        pythonMinor: "3.12",
        synapseVersion: "1.158.0",
        requirementsLockSHA256: String(repeating: "a", count: 64)
    )
    let drifted = PreparedRuntimeReceipt(
        pythonExecutable: "/usr/bin/python3",
        pythonVersion: "3.12.7",
        synapseVersion: "1.157.0",
        requirementsLockSHA256: String(repeating: "a", count: 64),
        installedPackages: [:],
        createdAt: Date(timeIntervalSince1970: 0)
    )
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601

    #expect(throws: (any Error).self) {
        try manifest.validatePreparedRuntime(data: try encoder.encode(drifted))
    }
}

@Test func aStaleSnapshotForADeadProcessIsNotTreatedAsRunning() async throws {
    // A recycled or vanished PID must never be reported as a live runtime.
    let identity = ManagedProcessIdentity(
        executablePath: "/usr/bin/true",
        launchTimestamp: Date(timeIntervalSince1970: 1),
        processIdentifier: 999_999,
        startIdentityToken: "999999:1:0"
    )
    #expect(await SynapseHealthChecker.systemIdentityStatus(identity) == .exited)
}

@Test func stopShutsDownAHomeserverItsSessionLeftBehind() async throws {
    // Break caught: a session killed mid-shutdown left Synapse serving with no bridges, and `stop`
    // refused it as belonging to a session that no longer existed.
    let root = try faultRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let leftover = try LeftoverProcess()
    defer { leftover.kill() }
    let (service, store) = try recordRunning(leftover.identity, root: root)

    #expect(try await service.stop() == .stopped)
    #expect(await SynapseHealthChecker.systemIdentityStatus(leftover.identity) == .exited)
    #expect(try store.load()?.snapshot == .stopped)
}

@Test func aLeftoverHomeserverThatIgnoresStopIsReportedNotKilled() async throws {
    let root = try faultRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let leftover = try LeftoverProcess(ignoringTerminate: true)
    defer { leftover.kill() }
    let (service, store) = try recordRunning(leftover.identity, root: root)

    await #expect(throws: RuntimeProfileError.orphanedRuntimeDidNotStop(
        processIdentifier: leftover.identity.processIdentifier
    )) {
        try await service.stop(orphanExitTimeout: .milliseconds(300))
    }
    #expect(await SynapseHealthChecker.systemIdentityStatus(leftover.identity) == .matching)
    #expect(try store.load()?.snapshot.phase == .healthy)
}

// MARK: - Backup and restore faults

@Test func interruptedRestoreLeavesOriginalProfileUnchanged() async throws {
    let root = try faultRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let paths = try RuntimePaths(root: root, profileName: "alpha")
    try seedProfile(paths)

    let manager = BackupManager(paths: paths, runtimeSnapshot: { .stopped })
    _ = try await manager.create(name: "safe")

    // Remove a stored file so the restore must abort midway through verification.
    try FileManager.default.removeItem(
        at: paths.backups.appendingPathComponent("safe/files/data/homeserver.db")
    )

    let target = try RuntimePaths(root: root, profileName: "target")
    await #expect(throws: (any Error).self) {
        try await manager.restore(name: "safe", into: target)
    }
    #expect(!FileManager.default.fileExists(atPath: target.profile.path))
    #expect(
        try Data(contentsOf: paths.data.appendingPathComponent("homeserver.db"))
            == Data("original".utf8)
    )
}

@Test func aCorruptedBackupNeverReachesTheTarget() async throws {
    let root = try faultRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let paths = try RuntimePaths(root: root, profileName: "alpha")
    try seedProfile(paths)

    let manager = BackupManager(paths: paths, runtimeSnapshot: { .stopped })
    _ = try await manager.create(name: "safe")
    try Data("tampered".utf8).write(
        to: paths.backups.appendingPathComponent("safe/files/data/homeserver.db")
    )

    let target = try RuntimePaths(root: root, profileName: "target")
    await #expect(throws: BackupError.checksumMismatch) {
        try await manager.restore(name: "safe", into: target)
    }
    #expect(!FileManager.default.fileExists(atPath: target.profile.path))
}

@Test func aNonEmptyRestoreTargetIsRefused() async throws {
    let root = try faultRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let paths = try RuntimePaths(root: root, profileName: "alpha")
    try seedProfile(paths)

    let manager = BackupManager(paths: paths, runtimeSnapshot: { .stopped })
    _ = try await manager.create(name: "safe")

    let target = try RuntimePaths(root: root, profileName: "target")
    try FileManager.default.createDirectory(at: target.data, withIntermediateDirectories: true)
    try Data("keep".utf8).write(to: target.data.appendingPathComponent("existing.txt"))

    await #expect(throws: BackupError.targetNotEmpty(target.profile)) {
        try await manager.restore(name: "safe", into: target)
    }
    #expect(
        try Data(contentsOf: target.data.appendingPathComponent("existing.txt")) == Data("keep".utf8)
    )
}

// MARK: - Benchmark faults

@Test func benchmarkVerdictRefusesToPassOnAnyLoss() {
    let base = benchmarkRunFixture()
    #expect(BenchmarkReporter.evaluate(base).decision == .retainSQLiteProvisionally)

    var lossy = base
    lossy.sqliteIntegrity = "row 42 missing from index"
    #expect(BenchmarkReporter.evaluate(lossy).decision == .requirePostgreSQL)
}

@Test func retriedSendsReuseTheSameTransactionIdentifier() {
    let first = MatrixFixturePlan.transactionIdentifier(seed: 42, roomIndex: 1, messageIndex: 1)
    let second = MatrixFixturePlan.transactionIdentifier(seed: 42, roomIndex: 1, messageIndex: 1)
    #expect(first == second)
}

// MARK: - Helpers

private func faultRoot() throws -> URL {
    let root = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        .appendingPathComponent("Library/Caches", isDirectory: true)
        .appendingPathComponent("InboxPlusFaultTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

private func recordRunning(
    _ identity: ManagedProcessIdentity,
    root: URL
) throws -> (RuntimeProfileService, RuntimeProfileStore) {
    let paths = try RuntimePaths(root: root, profileName: "leftover")
    let store = RuntimeProfileStore(paths: paths)
    try store.save(RuntimeProfileState(
        serverName: "inboxplus.localhost",
        registrationSecret: "registration-secret",
        launchExecutable: identity.executablePath,
        virtualEnvironmentPython: identity.executablePath,
        configurationFile: paths.configuration.appendingPathComponent("homeserver.yaml").path,
        snapshot: try RuntimeSnapshot(
            phase: .healthy,
            processIdentity: identity,
            loopbackPort: 8008,
            restartCount: 0,
            lastHealthResult: "healthy",
            diagnosticLogDirectory: paths.logs,
            lastError: nil
        )
    ))
    return (RuntimeProfileService(paths: paths, packageRoot: root), store)
}

/// A process whose launcher has already exited, as Synapse is once the session that started it
/// dies: reparented to launchd and nobody's child.
private struct LeftoverProcess {
    let identity: ManagedProcessIdentity

    init(ignoringTerminate: Bool = false) throws {
        let trap = ignoringTerminate ? "trap '' TERM; " : ""
        let launcher = Process()
        launcher.executableURL = URL(fileURLWithPath: "/bin/sh")
        launcher.arguments = ["-c", "(\(trap)exec /bin/sleep 120) </dev/null >/dev/null 2>&1 & echo $!"]
        let output = Pipe()
        launcher.standardOutput = output
        try launcher.run()
        let printed = output.fileHandleForReading.readDataToEndOfFile()
        launcher.waitUntilExit()
        let pid = try #require(pid_t(
            String(decoding: printed, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        ))
        // The background shell only becomes `sleep` once it execs.
        let deadline = Date().addingTimeInterval(10)
        var identity = FoundationManagedProcess.readIdentity(for: pid)
        while identity?.executablePath != "/bin/sleep", Date() < deadline {
            usleep(10_000)
            identity = FoundationManagedProcess.readIdentity(for: pid)
        }
        self.identity = try #require(identity.flatMap { $0.executablePath == "/bin/sleep" ? $0 : nil })
    }

    func kill() {
        guard FoundationManagedProcess.readIdentity(for: identity.processIdentifier) == identity else { return }
        Darwin.kill(identity.processIdentifier, SIGKILL)
    }
}

private func seedProfile(_ paths: RuntimePaths) throws {
    try FileManager.default.createDirectory(
        at: paths.data,
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700]
    )
    try Data("original".utf8).write(to: paths.data.appendingPathComponent("homeserver.db"))
}

private func benchmarkRunFixture() -> BenchmarkRun {
    var samples = LatencySamples()
    samples.warmTimelineReads = [0.01, 0.02]
    samples.committedEventVisibility = [0.05]
    samples.heartbeatDelays = [0.001]
    return BenchmarkRun(
        workload: .reduced(seed: 1, rooms: 2, messages: 10, importWorkers: 2),
        samples: samples,
        reconciliation: BenchmarkReconciliation(
            expectedEventCount: 10,
            observedEventCount: 10,
            missingEventIDs: [],
            duplicateEventIDs: [],
            missingRoomIDs: []
        ),
        importPartitionSizes: [1, 1],
        importedEventCount: 10,
        liveTrafficEventCount: 1,
        unrecoverableFailureCount: 0,
        elapsedSeconds: 1,
        sqliteIntegrity: "ok",
        recoveryVerified: true
    )
}

/// Binds and listens on a loopback port so presence checks observe a real listener.
private final class OccupiedPort {
    let port: UInt16
    private let descriptor: Int32

    init() throws {
        let socketDescriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard socketDescriptor >= 0 else { throw RuntimeProfileError.portAllocationFailed }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(socketDescriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0, listen(socketDescriptor, 1) == 0 else {
            _ = Darwin.close(socketDescriptor)
            throw RuntimeProfileError.portAllocationFailed
        }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let read = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(socketDescriptor, $0, &length)
            }
        }
        guard read == 0 else {
            _ = Darwin.close(socketDescriptor)
            throw RuntimeProfileError.portAllocationFailed
        }
        descriptor = socketDescriptor
        port = UInt16(bigEndian: address.sin_port)
    }

    func close() { _ = Darwin.close(descriptor) }
}
