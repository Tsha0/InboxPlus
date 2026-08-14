import Darwin
import Foundation

/// Allocates a free loopback port by binding an ephemeral socket and reading it back.
public struct LoopbackPortAllocator: Sendable {
    public init() {}

    public func allocate() throws -> UInt16 {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw RuntimeProfileError.portAllocationFailed }
        defer { _ = close(descriptor) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else { throw RuntimeProfileError.portAllocationFailed }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let read = withUnsafeMutablePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(descriptor, $0, &length)
            }
        }
        guard read == 0 else { throw RuntimeProfileError.portAllocationFailed }
        return UInt16(bigEndian: address.sin_port)
    }
}

/// Assembles the pinned runtime, configuration, supervisor, and persisted session for one profile.
///
/// The CLI stays a thin adapter by delegating every multi-step operation here.
public struct RuntimeProfileService: Sendable {
    public let paths: RuntimePaths
    public let packageRoot: URL

    private let store: RuntimeProfileStore
    private let portAllocator: LoopbackPortAllocator

    public init(paths: RuntimePaths, packageRoot: URL) {
        self.paths = paths
        self.packageRoot = packageRoot.standardizedFileURL
        store = RuntimeProfileStore(paths: paths)
        portAllocator = LoopbackPortAllocator()
    }

    /// `~/Library/Application Support/Pallo/DeveloperRuntime`, overridable for disposable runs.
    public static func developerRuntimeRoot(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws -> URL {
        if let override = environment["PALLO_RUNTIME_ROOT"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true).standardizedFileURL
        }
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return support
            .appendingPathComponent("Pallo", isDirectory: true)
            .appendingPathComponent("DeveloperRuntime", isDirectory: true)
            .standardizedFileURL
    }

    /// Repository root holding `Runtime/Synapse`, overridable for installed or relocated runs.
    public static func resolvedPackageRoot(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL {
        if let override = environment["PALLO_RUNTIME_PACKAGE_ROOT"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true).standardizedFileURL
        }
        return URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
    }

    public var manifestFile: URL {
        packageRoot.appendingPathComponent("Runtime/Synapse/runtime-manifest.json")
    }

    public var requirementsLockFile: URL {
        packageRoot.appendingPathComponent("Runtime/Synapse/requirements.lock")
    }

    public func loadManifest() throws -> RuntimeManifest {
        guard FileManager.default.fileExists(atPath: manifestFile.path) else {
            throw RuntimeProfileError.missingRuntimeManifest(manifestFile)
        }
        return try RuntimeManifest.load(from: manifestFile)
    }

    public func loadState() throws -> RuntimeProfileState? { try store.load() }

    // MARK: - Bootstrap

    public func bootstrap(python: URL) async throws -> PreparedRuntimeReceipt {
        let manifest = try loadManifest()
        try createProfileDirectories()

        let receipt = try await RuntimeBootstrapper(requirementsLock: requirementsLockFile)
            .bootstrap(python: python, manifest: manifest, paths: paths)

        let existing = try store.load()
        let registrationSecret = existing?.registrationSecret ?? Self.freshRegistrationSecret()
        let virtualPython = paths.runtime.appendingPathComponent("venv/bin/python")

        // Rendering with a placeholder port is enough to generate the signing keys; `start`
        // re-renders the file with the port it actually allocates.
        let configuration = SynapseConfiguration(
            profile: paths,
            port: try portAllocator.allocate(),
            credentials: SynapseCredentials(registrationSecret: registrationSecret)
        )
        let configurationFile = try configuration.write()
        try generateSigningKeys(python: virtualPython, configurationFile: configurationFile)

        try store.save(
            RuntimeProfileState(
                serverName: configuration.serverName,
                registrationSecret: registrationSecret,
                launchExecutable: try Self.stableLaunchExecutable(virtualPython: virtualPython).path,
                virtualEnvironmentPython: virtualPython.path,
                configurationFile: configurationFile.path,
                snapshot: .stopped
            )
        )
        return receipt
    }

    // MARK: - Lifecycle

    /// Launches Synapse and supervises it for as long as this process lives.
    ///
    /// The supervisor only ever controls its own direct child, so the owning process must stay
    /// alive for the whole session. `onReady` fires once the runtime is healthy; the session then
    /// runs until `interrupt` resolves or supervision reaches a terminal state, and always stops
    /// the child before returning.
    public func runForegroundSession(
        interrupt: @Sendable @escaping () async -> Void,
        onReady: @Sendable (RuntimeSnapshot) -> Void = { _ in }
    ) async throws -> RuntimeSnapshot {
        try await withRunningRuntime(onReady: onReady) { supervisor, _ in
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await supervisor.supervise() }
                group.addTask { await interrupt() }
                await group.next()
                group.cancelAll()
                await group.waitForAll()
            }
        }
        return try store.load()?.snapshot ?? .stopped
    }

    /// Starts Synapse, runs `body` against the healthy runtime, then always stops it.
    ///
    /// Every command that needs a live Synapse (benchmark, fixture verification, recovery
    /// exercises) owns the full lifecycle inside one process through this entry point.
    @discardableResult
    public func withRunningRuntime<T>(
        onReady: @Sendable (RuntimeSnapshot) -> Void = { _ in },
        _ body: @Sendable (SynapseSupervisor, RuntimeContext) async throws -> T
    ) async throws -> T {
        let state = try requirePreparedState()
        let port = try portAllocator.allocate()
        let configuration = SynapseConfiguration(
            profile: paths,
            port: port,
            credentials: SynapseCredentials(registrationSecret: state.registrationSecret)
        )
        _ = try configuration.write()

        let supervisor = try makeSupervisor(state: state, port: port, snapshot: state.snapshot)
        let started = try await supervisor.start()
        try store.save(state.replacing(snapshot: started))
        onReady(started)

        let context = RuntimeContext(
            baseURL: URL(string: "http://127.0.0.1:\(port)")!,
            serverName: configuration.serverName,
            registrationSecret: state.registrationSecret,
            port: port,
            paths: paths
        )
        do {
            let value = try await body(supervisor, context)
            try await stopAndPersist(supervisor: supervisor, state: state)
            return value
        } catch {
            try? await stopAndPersist(supervisor: supervisor, state: state)
            throw error
        }
    }

    @discardableResult
    private func stopAndPersist(
        supervisor: SynapseSupervisor,
        state: RuntimeProfileState
    ) async throws -> RuntimeSnapshot {
        do {
            let stopped = try await supervisor.stop()
            try store.save(state.replacing(snapshot: stopped))
            return stopped
        } catch {
            try? store.save(state.replacing(snapshot: await supervisor.status()))
            throw error
        }
    }

    /// Reports the persisted phase reconciled against the live process, without controlling it.
    ///
    /// Observation is safe from any process; only control requires direct-child ownership. This
    /// never persists, so it cannot race the session that owns the runtime.
    public func status() async throws -> RuntimeSnapshot {
        let state = try requirePreparedState()
        guard let identity = state.snapshot.processIdentity,
              let port = state.snapshot.loopbackPort
        else {
            return state.snapshot
        }
        switch await SynapseHealthChecker.systemIdentityStatus(identity) {
        case .matching:
            break
        case .exited, .mismatched:
            return .stopped
        case let .indeterminate(failure):
            throw failure
        }

        // Probe health directly rather than through the supervisor: the supervisor reports any
        // process it does not own as `uncontrolledProcess`, which is a statement about control
        // authority, not about the runtime's health.
        let checker = try SynapseHealthChecker(
            baseURL: URL(string: "http://127.0.0.1:\(port)")!,
            serverName: state.serverName,
            registrationSecret: state.registrationSecret,
            credentialStore: try SynapseProbeCredentialStore(profileRoot: paths.profile)
        )
        switch await checker.check(snapshot: state.snapshot) {
        case .healthy:
            return try RuntimeSnapshot(
                phase: .healthy,
                processIdentity: identity,
                loopbackPort: port,
                restartCount: state.snapshot.restartCount,
                lastHealthResult: "healthy",
                diagnosticLogDirectory: paths.logs,
                lastError: nil
            )
        case let .degraded(failure):
            return try RuntimeSnapshot(
                phase: .degraded,
                processIdentity: identity,
                loopbackPort: port,
                restartCount: state.snapshot.restartCount,
                lastHealthResult: "degraded",
                diagnosticLogDirectory: paths.logs,
                lastError: String(describing: failure)
            )
        case .stopped:
            return .stopped
        }
    }

    /// Reconciles a profile whose owning session is gone.
    ///
    /// A live runtime belongs to the foreground session that launched it, so this refuses to act
    /// while that session still owns the child rather than signalling a process it does not own.
    public func stop() async throws -> RuntimeSnapshot {
        let state = try requirePreparedState()
        guard let identity = state.snapshot.processIdentity else {
            let snapshot = RuntimeSnapshot.stopped
            try store.save(state.replacing(snapshot: snapshot))
            return snapshot
        }
        switch await SynapseHealthChecker.systemIdentityStatus(identity) {
        case .matching:
            throw RuntimeProfileError.runtimeOwnedByForegroundSession(
                processIdentifier: identity.processIdentifier
            )
        case .exited, .mismatched:
            try store.save(state.replacing(snapshot: .stopped))
            return .stopped
        case let .indeterminate(failure):
            throw failure
        }
    }

    // MARK: - Verification

    /// Validates the prepared runtime receipt and the rendered loopback-only configuration.
    public func verifyPreparedRuntime() throws -> PreparedRuntimeReceipt {
        let manifest = try loadManifest()
        let state = try requirePreparedState()
        let receipt = try manifest.validatePreparedRuntime(
            at: paths.runtime.appendingPathComponent(RuntimeBootstrapper.receiptName)
        )
        let configurationFile = URL(fileURLWithPath: state.configurationFile)
        let rendered = try String(contentsOf: configurationFile, encoding: .utf8)
        guard rendered.contains("bind_addresses: ['127.0.0.1']") else {
            throw SynapseConfigurationError.nonLoopbackAddress("configuration is not loopback-only")
        }
        return receipt
    }

    /// Provisions deterministic fixture rooms against a live runtime and reconciles them back.
    public func verifyFixtures(seed: UInt64, rooms: Int) async throws -> FixtureVerification {
        try await withRunningRuntime { _, context in
            let provisioner = try MatrixFixtureProvisioner(
                baseURL: context.baseURL,
                serverName: context.serverName,
                registrationSecret: context.registrationSecret
            )
            let fixture = try await provisioner.prepare(seed: seed, roomCount: rooms)
            let client = try MatrixHTTPClient(
                baseURL: context.baseURL,
                accessToken: fixture.accessToken
            )
            let joined: JoinedRoomsResponse = try await client.send(
                .get,
                path: ["_matrix", "client", "v3", "joined_rooms"],
                idempotent: true
            )
            let expected = Set(fixture.roomIDs)
            return FixtureVerification(
                seed: seed,
                requestedRooms: rooms,
                createdRooms: fixture.roomIDs.count,
                reconciledRooms: expected.intersection(joined.joinedRooms).count,
                missingRooms: expected.subtracting(joined.joinedRooms).sorted()
            )
        }
    }

    /// Provisions fixtures, runs the workload against a live runtime, and reconciles the result.
    ///
    /// SQLite integrity is checked after the runtime stops, because `PRAGMA integrity_check`
    /// is only meaningful against a database no longer being written.
    public func runBenchmark(_ workload: BenchmarkWorkload) async throws -> BenchmarkReport {
        let state = try requirePreparedState()
        var run = try await withRunningRuntime { _, context in
            let provisioner = try MatrixFixtureProvisioner(
                baseURL: context.baseURL,
                serverName: context.serverName,
                registrationSecret: context.registrationSecret
            )
            let fixture = try await provisioner.prepare(
                seed: workload.seed,
                roomCount: workload.roomCount
            )
            let client = try MatrixHTTPClient(
                baseURL: context.baseURL,
                accessToken: fixture.accessToken
            )
            return try await BenchmarkRunner(
                operations: LiveBenchmarkOperations(client: client, rooms: fixture.roomIDs)
            ).run(workload)
        }

        let manifest = try loadManifest()
        let receipt = try manifest.validatePreparedRuntime(
            at: paths.runtime.appendingPathComponent(RuntimeBootstrapper.receiptName)
        )
        run.sqliteIntegrity = try checkSQLiteIntegrity()
        run.environment = BenchmarkEnvironmentCollector().collect(
            receipt: receipt,
            manifest: manifest,
            databaseURL: databaseURL
        )

        let reporter = BenchmarkReporter(sensitiveValues: [state.registrationSecret])
        let verdict = BenchmarkReporter.evaluate(run)
        _ = try reporter.write(
            run,
            verdict: verdict,
            to: paths.reports,
            name: "benchmark-\(workload.seed)-\(workload.roomCount)x\(workload.messageCount)"
        )
        return BenchmarkReport(run: run, verdict: verdict, generatedAt: Date())
    }

    public var databaseURL: URL {
        paths.data.appendingPathComponent("homeserver.db")
    }

    /// Runs SQLite's own quick and full integrity checks against the stopped database.
    public func checkSQLiteIntegrity() throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [databaseURL.path, "PRAGMA quick_check; PRAGMA integrity_check;"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return "unavailable" }
        let lines = String(decoding: data, as: UTF8.self)
            .split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return lines.allSatisfy { $0 == "ok" } ? "ok" : lines.joined(separator: "; ")
    }

    // MARK: - Assembly

    public func makeSupervisor(
        state: RuntimeProfileState,
        port: UInt16,
        snapshot: RuntimeSnapshot
    ) throws -> SynapseSupervisor {
        let healthChecker = try SynapseHealthChecker(
            baseURL: URL(string: "http://127.0.0.1:\(port)")!,
            serverName: state.serverName,
            registrationSecret: state.registrationSecret,
            credentialStore: try SynapseProbeCredentialStore(profileRoot: paths.profile)
        )
        return SynapseSupervisor(
            configuration: managedProcessConfiguration(state: state),
            loopbackPort: port,
            healthChecker: healthChecker,
            initialSnapshot: snapshot
        )
    }

    public func managedProcessConfiguration(
        state: RuntimeProfileState
    ) -> ManagedProcessConfiguration {
        let virtualPython = URL(fileURLWithPath: state.virtualEnvironmentPython)
        return ManagedProcessConfiguration(
            executable: URL(fileURLWithPath: state.launchExecutable),
            arguments: [
                "-m", "synapse.app.homeserver",
                "--config-path", state.configurationFile,
            ],
            environment: [
                "PATH": virtualPython.deletingLastPathComponent().path + ":/usr/bin:/bin",
                "PYTHONUNBUFFERED": "1",
                "__PYVENV_LAUNCHER__": virtualPython.path,
            ],
            workingDirectory: paths.profile,
            profileRoot: paths.profile,
            logsDirectory: paths.logs,
            standardOutputLog: paths.logs.appendingPathComponent("stdout.log"),
            standardErrorLog: paths.logs.appendingPathComponent("stderr.log"),
            sensitiveLogValues: [state.registrationSecret]
        )
    }

    public func acquireProfileLock() throws -> ProfileLock {
        try FileManager.default.createDirectory(
            at: paths.state,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        return try ProfileLock.acquire(at: paths.state.appendingPathComponent("profile.lock"))
    }

    // MARK: - Helpers

    private func requirePreparedState() throws -> RuntimeProfileState {
        guard let state = try store.load() else {
            throw RuntimeProfileError.profileNotPrepared(paths.profile)
        }
        return state
    }

    private func createProfileDirectories() throws {
        // `paths.runtime` is deliberately absent: RuntimeBootstrapper owns it and treats a
        // pre-existing runtime directory without a receipt as drift.
        for directory in [
            paths.profile, paths.configuration,
            paths.data, paths.logs, paths.backups, paths.reports, paths.state,
        ] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        }
    }

    private static func freshRegistrationSecret() -> String {
        UUID().uuidString + UUID().uuidString
    }

    private func generateSigningKeys(python: URL, configurationFile: URL) throws {
        let process = Process()
        process.executableURL = python
        process.arguments = [
            "-m", "synapse.app.homeserver",
            "--config-path", configurationFile.path,
            "--generate-keys",
        ]
        process.environment = [
            "PATH": python.deletingLastPathComponent().path + ":/usr/bin:/bin",
        ]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw RuntimeProfileError.keyGenerationFailed(
                status: process.terminationStatus,
                output: String(data: data, encoding: .utf8) ?? ""
            )
        }
    }

    /// Synapse must be launched through the framework's `Python.app` stub so the child keeps a
    /// stable executable path for identity verification.
    static func stableLaunchExecutable(virtualPython: URL) throws -> URL {
        let process = Process()
        process.executableURL = virtualPython
        process.arguments = ["-c", "import sys; print(sys._base_executable)"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = Pipe()
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0,
              let path = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
              path.hasPrefix("/")
        else {
            throw RuntimeProfileError.pythonExecutableUnavailable
        }
        let applicationExecutable = URL(fileURLWithPath: path)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Resources/Python.app/Contents/MacOS/Python")
        guard FileManager.default.isExecutableFile(atPath: applicationExecutable.path) else {
            throw RuntimeProfileError.pythonExecutableUnavailable
        }
        return applicationExecutable
    }
}

public struct FixtureVerification: Sendable, Equatable {
    public let seed: UInt64
    public let requestedRooms: Int
    public let createdRooms: Int
    public let reconciledRooms: Int
    public let missingRooms: [String]

    public var reconciledExactly: Bool {
        missingRooms.isEmpty && createdRooms == requestedRooms && reconciledRooms == requestedRooms
    }
}

struct JoinedRoomsResponse: Decodable {
    let joinedRooms: [String]

    private enum CodingKeys: String, CodingKey {
        case joinedRooms = "joined_rooms"
    }
}

/// Everything a command needs to talk to the running Synapse it was handed.
public struct RuntimeContext: Sendable {
    public let baseURL: URL
    public let serverName: String
    public let registrationSecret: String
    public let port: UInt16
    public let paths: RuntimePaths

    public init(
        baseURL: URL,
        serverName: String,
        registrationSecret: String,
        port: UInt16,
        paths: RuntimePaths
    ) {
        self.baseURL = baseURL
        self.serverName = serverName
        self.registrationSecret = registrationSecret
        self.port = port
        self.paths = paths
    }
}

/// Resolves when the process receives an interactive interrupt or a termination request.
public final class InterruptMonitor: @unchecked Sendable {
    private let sources: [DispatchSourceSignal]
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Void, Never>?
    private var fired = false

    public init(signals: [Int32] = [SIGINT, SIGTERM]) {
        for number in signals { Darwin.signal(number, SIG_IGN) }
        sources = signals.map { number in
            DispatchSource.makeSignalSource(signal: number, queue: .global())
        }
        for source in sources {
            source.setEventHandler { [weak self] in self?.fire() }
            source.resume()
        }
    }

    deinit {
        for source in sources { source.cancel() }
    }

    public func wait() async {
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                let resumeImmediately: Bool = lock.withLock {
                    if fired { return true }
                    self.continuation = continuation
                    return false
                }
                if resumeImmediately { continuation.resume() }
            }
        } onCancel: {
            fire()
        }
    }

    private func fire() {
        let waiting: CheckedContinuation<Void, Never>? = lock.withLock {
            guard !fired else { return nil }
            fired = true
            let waiting = continuation
            continuation = nil
            return waiting
        }
        waiting?.resume()
    }
}

public enum RuntimeProfileError: Error, Equatable, Sendable, CustomStringConvertible {
    case missingRuntimeManifest(URL)
    case profileNotPrepared(URL)
    case portAllocationFailed
    case pythonExecutableUnavailable
    case keyGenerationFailed(status: Int32, output: String)
    case runtimeOwnedByForegroundSession(processIdentifier: Int32)
    case profileLockedByAnotherSession

    public var description: String {
        switch self {
        case let .missingRuntimeManifest(url):
            "no runtime manifest at \(url.path); run from the package root or set PALLO_RUNTIME_PACKAGE_ROOT"
        case let .profileNotPrepared(url):
            "profile at \(url.path) is not prepared; run 'bootstrap' first"
        case .portAllocationFailed:
            "could not allocate a loopback port"
        case .pythonExecutableUnavailable:
            "could not resolve a stable Python application executable for the prepared runtime"
        case let .keyGenerationFailed(status, output):
            "Synapse key generation failed with status \(status): \(output)"
        case let .runtimeOwnedByForegroundSession(processIdentifier):
            """
            the runtime is live as process \(processIdentifier) and belongs to the session that \
            started it; interrupt that 'start' session to stop it
            """
        case .profileLockedByAnotherSession:
            "another Pallo runtime session already holds this profile; interrupt it first"
        }
    }
}
