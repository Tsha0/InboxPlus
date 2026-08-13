import Foundation
import Testing
@testable import PalloRuntime

@Test func userStopTransitionsHealthyToStoppedWithoutRestart() async throws {
    // Break caught: a user stop relaunches Synapse or omits graceful termination.
    let fixture = SupervisorFixture()
    _ = try await fixture.supervisor.start()
    let stopped = try await fixture.supervisor.stop()
    let metrics = await fixture.process.metrics()

    #expect(stopped.phase == .stopped)
    #expect(stopped.processIdentity == nil)
    #expect(metrics.launchCalls == 1)
    #expect(metrics.signals == [.terminate])
}

@Test func startFromStartingIsRejectedDuringConcurrentLaunch() async throws {
    // Break caught: actor reentrancy launches a second process while the first launch is suspended.
    let launchGate = AsyncGate()
    let fixture = SupervisorFixture(launchGate: launchGate)
    let firstStart = Task { try await fixture.supervisor.start() }
    await waitForPhase(.starting, supervisor: fixture.supervisor)

    await #expect(throws: RuntimeStateError.invalidTransition(from: .starting, to: .starting)) {
        try await fixture.supervisor.start()
    }

    await launchGate.open()
    _ = try await firstStart.value
    _ = try await fixture.supervisor.stop()
    #expect(await fixture.process.metrics().launchCalls == 1)
}

@Test func concurrentStopCannotSignalTheSameIdentityTwice() async throws {
    // Break caught: reentrant stop requests both signal one child or race shutdown state.
    let waitGate = AsyncGate()
    let fixture = SupervisorFixture(waitGate: waitGate)
    _ = try await fixture.supervisor.start()
    let firstStop = Task { try await fixture.supervisor.stop() }
    await waitForPhase(.stopping, supervisor: fixture.supervisor)

    await #expect(throws: RuntimeStateError.invalidTransition(from: .stopping, to: .stopping)) {
        try await fixture.supervisor.stop()
    }

    await waitGate.open()
    _ = try await firstStop.value
    #expect(await fixture.process.metrics().signals == [.terminate])
}

@Test func stopDuringSuspendedLaunchIsRejectedWithoutCorruptingLaunch() async throws {
    // Break caught: stop reenters the actor during launch, loses the pending child identity, and strands the process.
    let launchGate = AsyncGate()
    let fixture = SupervisorFixture(launchGate: launchGate)
    let start = Task { try await fixture.supervisor.start() }
    await waitForPhase(.starting, supervisor: fixture.supervisor)

    await #expect(throws: RuntimeStateError.invalidTransition(from: .starting, to: .stopping)) {
        try await fixture.supervisor.stop()
    }

    await launchGate.open()
    #expect(try await start.value.phase == .healthy)
    #expect(try await fixture.supervisor.stop().phase == .stopped)
}

@Test func processIdentityMismatchNeverReceivesAnySignal() async throws {
    // Break caught: a reused PID is terminated despite a different executable/start token.
    let fixture = SupervisorFixture()
    _ = try await fixture.supervisor.start()
    await fixture.process.replaceCurrentIdentity(with: .replacement)

    await #expect(throws: RuntimeStateError.processIdentityMismatch(
        expected: .expected,
        actual: .replacement
    )) {
        try await fixture.supervisor.stop()
    }

    #expect(await fixture.process.metrics().signals.isEmpty)
    #expect(await fixture.supervisor.status().phase == .failed)
}

@Test func statusDoesNotReportHealthyAfterProcessIdentityChanges() async throws {
    // Break caught: status trusts persisted PID metadata and reports a replacement process as healthy.
    let fixture = SupervisorFixture()
    _ = try await fixture.supervisor.start()
    await fixture.process.replaceCurrentIdentity(with: .replacement)

    let snapshot = await fixture.supervisor.status()

    #expect(snapshot.phase == .failed)
    #expect(snapshot.processIdentity == .expected)
    #expect(await fixture.process.metrics().signals.isEmpty)
}

@Test func gracefulTimeoutEscalatesOnlyAfterReverifyingIdentity() async throws {
    // Break caught: timeout never escalates, or forced termination is sent without a second identity check.
    let fixture = SupervisorFixture(exitOnTerminate: false)
    _ = try await fixture.supervisor.start()

    #expect(try await fixture.supervisor.stop().phase == .stopped)
    let metrics = await fixture.process.metrics()
    #expect(metrics.signals == [.terminate, .kill])
    #expect(metrics.identityChecks >= 4)
}

@Test func identityChangeDuringGracefulWaitPreventsEscalation() async throws {
    // Break caught: forced termination targets a replacement process that appeared after SIGTERM.
    let fixture = SupervisorFixture(exitOnTerminate: false, replaceIdentityAfterFirstWait: true)
    _ = try await fixture.supervisor.start()

    await #expect(throws: RuntimeStateError.processIdentityMismatch(
        expected: .expected,
        actual: .replacement
    )) {
        try await fixture.supervisor.stop()
    }

    #expect(await fixture.process.metrics().signals == [.terminate])
}

@Test func listenerStillPresentAfterProcessExitFailsShutdown() async throws {
    // Break caught: shutdown reports stopped while the associated loopback listener remains reachable.
    let listener = FakeListenerChecker(responses: [true, true, true])
    let fixture = SupervisorFixture(listener: listener, listenerVerificationAttempts: 3)
    _ = try await fixture.supervisor.start()

    await #expect(throws: RuntimeStateError.shutdownIncomplete(processAlive: false, listenerAlive: true)) {
        try await fixture.supervisor.stop()
    }

    #expect(await fixture.supervisor.status().phase == .failed)
    #expect(await listener.checkCount() == 3)
}

@Test func repeatedStartStopCyclesCreateOneProcessPerCycle() async throws {
    // Break caught: stopped state retains stale identity or reuses a prior launch without making a new child.
    let fixture = SupervisorFixture()
    _ = try await fixture.supervisor.start()
    _ = try await fixture.supervisor.stop()
    _ = try await fixture.supervisor.start()
    _ = try await fixture.supervisor.stop()

    let metrics = await fixture.process.metrics()
    #expect(metrics.launchCalls == 2)
    #expect(metrics.signals == [.terminate, .terminate])
}

@Test func boundedLogWriterRotatesWithoutExceedingPerFileLimit() throws {
    // Break caught: a large output chunk bypasses rotation and grows a profile log without bound.
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("PalloBoundedLogTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let log = directory.appendingPathComponent("stdout.log")
    let writer = try BoundedRotatingLog(file: log, maximumBytesPerFile: 8, retainedFileCount: 3)

    try writer.append(Data("abcdefghijklmnopqrst".utf8))

    let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])
    #expect(Set(files.map(\.lastPathComponent)) == ["stdout.log", "stdout.log.1", "stdout.log.2"])
    for file in files {
        let values = try file.resourceValues(forKeys: [.fileSizeKey])
        #expect((values.fileSize ?? 0) <= 8)
    }
    #expect(try Data(contentsOf: log) == Data("qrst".utf8))
}

@Test func boundedLogWriterNormalizesOversizedExistingGenerations() throws {
    // Break caught: an oversized log from a prior crash remains unbounded after the writer takes ownership.
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("PalloExistingLogTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let log = directory.appendingPathComponent("stdout.log")
    try Data(repeating: 1, count: 32).write(to: log)
    try Data(repeating: 2, count: 24).write(to: directory.appendingPathComponent("stdout.log.1"))

    _ = try BoundedRotatingLog(file: log, maximumBytesPerFile: 8, retainedFileCount: 2)

    for file in [log, directory.appendingPathComponent("stdout.log.1")] {
        #expect((try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 8)
    }
}

@Test func foundationManagedProcessCapturesBoundedOutputAndReleasesChild() async throws {
    // Break caught: the production process adapter leaks pipe resources or bypasses bounded stdout/stderr logs.
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("PalloManagedProcessTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let configuration = ManagedProcessConfiguration(
        executable: URL(fileURLWithPath: "/bin/sh"),
        arguments: ["-c", "printf 12345678901234567890; printf abcdefghijklmnopqrst >&2; sleep 0.2"],
        environment: ["PATH": "/usr/bin:/bin"],
        workingDirectory: directory,
        standardOutputLog: directory.appendingPathComponent("stdout.log"),
        standardErrorLog: directory.appendingPathComponent("stderr.log"),
        maximumLogBytesPerFile: 8,
        retainedLogFileCount: 2
    )
    let process = try FoundationManagedProcessFactory().make(configuration)

    let identity = try await process.launch()
    #expect(identity.processIdentifier > 0)
    #expect(!identity.executablePath.isEmpty)
    #expect(!identity.startIdentityToken.isEmpty)
    #expect(try await process.waitForExit(matching: identity, timeout: .seconds(2)))

    try await Task.sleep(for: .milliseconds(50))
    for base in ["stdout.log", "stderr.log"] {
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])
            .filter { $0.lastPathComponent.hasPrefix(base) }
        #expect(!files.isEmpty)
        #expect(files.count <= 2)
        for file in files {
            #expect((try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 8)
        }
    }
}

@Test func foundationManagedProcessNeverSignalsWhenStartTokenDoesNotMatch() async throws {
    // Break caught: the production adapter signals a live PID after its start token no longer matches metadata.
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("PalloIdentitySignalTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let process = try FoundationManagedProcessFactory().make(ManagedProcessConfiguration(
        executable: URL(fileURLWithPath: "/bin/sleep"),
        arguments: ["5"],
        environment: [:],
        workingDirectory: directory,
        standardOutputLog: directory.appendingPathComponent("stdout.log"),
        standardErrorLog: directory.appendingPathComponent("stderr.log")
    ))
    let actual = try await process.launch()
    let stale = ManagedProcessIdentity(
        executablePath: actual.executablePath,
        launchTimestamp: actual.launchTimestamp.addingTimeInterval(-1),
        processIdentifier: actual.processIdentifier,
        startIdentityToken: actual.startIdentityToken + "-stale"
    )

    await #expect(throws: RuntimeStateError.processIdentityMismatch(expected: stale, actual: actual)) {
        try await process.signal(.kill, ifMatching: stale)
    }
    #expect(await process.identityStatus(for: actual) == .matching)

    _ = try await process.signal(.kill, ifMatching: actual)
    #expect(try await process.waitForExit(matching: actual, timeout: .seconds(2)))
}

@Test func supervisorGracefullyStopsARealFoundationChild() async throws {
    // Break caught: the lifecycle passes with fakes while the production process adapter cannot terminate and reap its child.
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("PalloRealSupervisorTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let supervisor = SynapseSupervisor(
        configuration: ManagedProcessConfiguration(
            executable: URL(fileURLWithPath: "/bin/sleep"),
            arguments: ["5"],
            environment: [:],
            workingDirectory: directory,
            standardOutputLog: directory.appendingPathComponent("stdout.log"),
            standardErrorLog: directory.appendingPathComponent("stderr.log")
        ),
        loopbackPort: 18_008,
        listenerChecker: FakeListenerChecker(responses: [false]),
        gracefulTerminationTimeout: .seconds(2),
        forcedTerminationTimeout: .seconds(1),
        listenerVerificationAttempts: 1,
        listenerVerificationInterval: .zero
    )

    let started = try await supervisor.start()
    #expect(started.processIdentity != nil)
    #expect(try await supervisor.stop().phase == .stopped)
}

private func waitForPhase(_ phase: RuntimePhase, supervisor: SynapseSupervisor) async {
    for _ in 0..<100 {
        if await supervisor.status().phase == phase { return }
        await Task.yield()
    }
}

private struct SupervisorFixture {
    let process: FakeManagedProcess
    let supervisor: SynapseSupervisor

    init(
        launchGate: AsyncGate? = nil,
        waitGate: AsyncGate? = nil,
        exitOnTerminate: Bool = true,
        replaceIdentityAfterFirstWait: Bool = false,
        listener: FakeListenerChecker = FakeListenerChecker(responses: [false]),
        listenerVerificationAttempts: Int = 1
    ) {
        process = FakeManagedProcess(
            launchGate: launchGate,
            waitGate: waitGate,
            exitOnTerminate: exitOnTerminate,
            replaceIdentityAfterFirstWait: replaceIdentityAfterFirstWait
        )
        let configuration = ManagedProcessConfiguration(
            executable: URL(fileURLWithPath: ManagedProcessIdentity.expected.executablePath),
            arguments: [],
            environment: [:],
            workingDirectory: URL(fileURLWithPath: "/tmp"),
            standardOutputLog: URL(fileURLWithPath: "/tmp/pallo-stdout.log"),
            standardErrorLog: URL(fileURLWithPath: "/tmp/pallo-stderr.log")
        )
        supervisor = SynapseSupervisor(
            configuration: configuration,
            loopbackPort: 18_008,
            processFactory: FakeManagedProcessFactory(process: process),
            listenerChecker: listener,
            gracefulTerminationTimeout: .seconds(5),
            forcedTerminationTimeout: .seconds(1),
            listenerVerificationAttempts: listenerVerificationAttempts,
            listenerVerificationInterval: .zero,
            sleep: { _ in }
        )
    }
}

private actor AsyncGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var isOpen = false

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { continuation = $0 }
    }

    func open() {
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
}

private actor FakeManagedProcess: ManagedProcess {
    struct Metrics: Sendable {
        var launchCalls = 0
        var signals: [ManagedProcessSignal] = []
        var identityChecks = 0
    }

    private let launchGate: AsyncGate?
    private let waitGate: AsyncGate?
    private let exitOnTerminate: Bool
    private let replaceIdentityAfterFirstWait: Bool
    private var currentIdentity: ManagedProcessIdentity?
    private var state = Metrics()
    private var waitCalls = 0

    init(
        launchGate: AsyncGate?,
        waitGate: AsyncGate?,
        exitOnTerminate: Bool,
        replaceIdentityAfterFirstWait: Bool
    ) {
        self.launchGate = launchGate
        self.waitGate = waitGate
        self.exitOnTerminate = exitOnTerminate
        self.replaceIdentityAfterFirstWait = replaceIdentityAfterFirstWait
    }

    func launch() async throws -> ManagedProcessIdentity {
        state.launchCalls += 1
        if let launchGate { await launchGate.wait() }
        currentIdentity = .expected
        return .expected
    }

    func identityStatus(for expected: ManagedProcessIdentity) async -> ManagedProcessIdentityStatus {
        state.identityChecks += 1
        guard let currentIdentity else { return .exited }
        return currentIdentity == expected ? .matching : .mismatched(actual: currentIdentity)
    }

    func signal(_ signal: ManagedProcessSignal, ifMatching expected: ManagedProcessIdentity) async throws -> Bool {
        switch await identityStatus(for: expected) {
        case .matching:
            state.signals.append(signal)
            if signal == .kill || exitOnTerminate { currentIdentity = nil }
            return true
        case .exited:
            return false
        case let .mismatched(actual):
            throw RuntimeStateError.processIdentityMismatch(expected: expected, actual: actual)
        }
    }

    func waitForExit(matching expected: ManagedProcessIdentity, timeout: Duration) async throws -> Bool {
        waitCalls += 1
        if let waitGate { await waitGate.wait() }
        if replaceIdentityAfterFirstWait, waitCalls == 1 { currentIdentity = .replacement }
        switch await identityStatus(for: expected) {
        case .exited: return true
        case .matching: return false
        case let .mismatched(actual):
            throw RuntimeStateError.processIdentityMismatch(expected: expected, actual: actual)
        }
    }

    func replaceCurrentIdentity(with identity: ManagedProcessIdentity) {
        currentIdentity = identity
    }

    func metrics() -> Metrics { state }
}

private struct FakeManagedProcessFactory: ManagedProcessFactory, Sendable {
    let process: FakeManagedProcess
    func make(_ configuration: ManagedProcessConfiguration) throws -> any ManagedProcess { process }
}

private actor FakeListenerChecker: LoopbackListenerChecking {
    private let responses: [Bool]
    private var index = 0

    init(responses: [Bool]) { self.responses = responses }

    func isListening(on port: UInt16) async -> Bool {
        defer { index += 1 }
        return responses[min(index, responses.count - 1)]
    }

    func checkCount() -> Int { index }
}

private extension ManagedProcessIdentity {
    static let expected = ManagedProcessIdentity(
        executablePath: "/opt/pallo/synapse_homeserver",
        launchTimestamp: Date(timeIntervalSince1970: 1_789_000_000),
        processIdentifier: 42,
        startIdentityToken: "42:1789000000:0"
    )
    static let replacement = ManagedProcessIdentity(
        executablePath: "/usr/bin/unrelated",
        launchTimestamp: Date(timeIntervalSince1970: 1_789_000_001),
        processIdentifier: 42,
        startIdentityToken: "42:1789000001:0"
    )
}
