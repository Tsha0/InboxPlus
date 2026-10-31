import Darwin
import Foundation
import InboxPlusBridge
import InboxPlusCore
import InboxPlusRuntime

public enum BridgeRuntimeError: Error, Equatable, Sendable, CustomStringConvertible {
    case nativeAdapterHasNoProcess(String)
    case registrationGenerationFailed(bridge: String, output: String)
    case registrationMissing(URL)
    case notPrepared(String)
    case flowDrift(bridge: String, expected: [String], actual: [String])
    case residueRemains([String])

    public var description: String {
        switch self {
        case let .nativeAdapterHasNoProcess(id):
            "'\(id)' is a native adapter and has no bridge process to run"
        case let .registrationGenerationFailed(bridge, output):
            "'\(bridge)' could not generate its appservice registration: \(output)"
        case let .registrationMissing(url):
            "the bridge did not write a registration at \(url.path)"
        case let .notPrepared(id):
            "bridge '\(id)' has not been prepared for this profile"
        case let .flowDrift(bridge, expected, actual):
            """
            '\(bridge)' advertises login flows \(actual.sorted()) but the pinned version was \
            recorded as offering \(expected.sorted()); the pin must be reviewed
            """
        case let .residueRemains(paths):
            "these files could not be deleted: \(paths.joined(separator: ", "))"
        }
    }
}

/// What preparing one bridge produced, persisted so a later session can supervise it.
public struct PreparedBridge: Codable, Sendable, Equatable {
    public let bridgeID: String
    public let platform: Platform
    public let displayName: String
    public let version: String
    /// Kept so the configuration can be re-rendered without consulting the catalog, which may have
    /// moved on to a newer pin than the one this profile actually has installed.
    public let serverName: String
    public let ownerUserID: String
    public let executable: String
    public let configurationFile: String
    public let registrationFile: String
    public let appservicePort: UInt16
    public let provisioningSecret: String
    public let sha256: String

    public init(
        bridgeID: String,
        platform: Platform,
        displayName: String,
        version: String,
        serverName: String,
        ownerUserID: String,
        executable: String,
        configurationFile: String,
        registrationFile: String,
        appservicePort: UInt16,
        provisioningSecret: String,
        sha256: String
    ) {
        self.bridgeID = bridgeID
        self.platform = platform
        self.displayName = displayName
        self.version = version
        self.serverName = serverName
        self.ownerUserID = ownerUserID
        self.executable = executable
        self.configurationFile = configurationFile
        self.registrationFile = registrationFile
        self.appservicePort = appservicePort
        self.provisioningSecret = provisioningSecret
        self.sha256 = sha256
    }

    public var provisioningBaseURL: URL {
        URL(string: "http://127.0.0.1:\(appservicePort)")!
    }
}

/// Installs, configures, registers and supervises the bridges belonging to one profile.
///
/// Each bridge gets its own directory, database, port, secret, registration and supervisor, so one
/// bridge crashing or being reinstalled cannot disturb another.
public struct BridgeRuntime: Sendable {
    public let paths: RuntimePaths

    private let installer: BridgeInstaller
    private let libolm: LibolmProvisioner
    private let portAllocator: LoopbackPortAllocator
    private let store: PreparedBridgeStore
    private let disconnected: DisconnectedAccountStore

    public init(
        paths: RuntimePaths,
        fetcher: any BridgeArtifactFetching = URLSessionBridgeArtifactFetcher(),
        libolm: LibolmProvisioner = LibolmProvisioner()
    ) {
        self.paths = paths
        installer = BridgeInstaller(paths: paths, fetcher: fetcher)
        self.libolm = libolm
        portAllocator = LoopbackPortAllocator()
        store = PreparedBridgeStore(paths: paths)
        disconnected = DisconnectedAccountStore(paths: paths)
    }

    public func prepared() throws -> [PreparedBridge] { try store.load() }

    public func prepared(for platform: Platform) throws -> PreparedBridge? {
        try store.load().first { $0.platform == platform }
    }

    /// Prepared bridges the user has not disconnected — the ones a session should be running.
    public func bridgesToRun() throws -> [PreparedBridge] {
        let disconnectedIDs = try disconnected.load()
        return try store.load().filter { !disconnectedIDs.contains($0.bridgeID) }
    }

    /// Deletes everything one bridge keeps in the profile: its binary, configuration, database —
    /// which holds the network login — registration and logs. The bridge must already be stopped.
    public func remove(_ descriptor: BridgeDescriptor) throws {
        let fileManager = FileManager.default
        let logNames = ["\(descriptor.id).out.log", "\(descriptor.id).err.log"]
        let logs = ((try? fileManager.contentsOfDirectory(atPath: paths.logs.path)) ?? [])
            .filter { name in logNames.contains { name == $0 || name.hasPrefix("\($0).") } }
            .map { paths.logs.appendingPathComponent($0, isDirectory: false) }
        let targets = [
            installer.directory(for: descriptor),
            appServiceDirectory.appendingPathComponent("\(descriptor.id).yaml", isDirectory: false),
        ] + logs
        for target in targets where fileManager.fileExists(atPath: target.path) {
            try fileManager.removeItem(at: target)
        }
        let residue = targets.filter { fileManager.fileExists(atPath: $0.path) }
        guard residue.isEmpty else { throw BridgeRuntimeError.residueRemains(residue.map(\.path)) }
        try store.remove(bridgeID: descriptor.id)
    }

    /// Where Synapse looks for appservice registrations.
    public var appServiceDirectory: URL {
        paths.configuration.appendingPathComponent("appservices", isDirectory: true)
    }

    /// Installs and configures one bridge, leaving Synapse able to load its registration.
    ///
    /// This must complete before Synapse starts: `app_service_config_files` is read once at
    /// homeserver startup, so a registration written afterwards is invisible until a restart.
    @discardableResult
    public func prepare(
        _ descriptor: BridgeDescriptor,
        serverName: String,
        homeserverPort: UInt16,
        ownerUserID: String
    ) async throws -> PreparedBridge {
        guard descriptor.runtimeKind == .goBinary else {
            throw BridgeRuntimeError.nativeAdapterHasNoProcess(descriptor.id)
        }
        try BridgeCatalog.validate([descriptor])

        let installed = try await installer.install(descriptor)
        let directory = installer.directory(for: descriptor)
        try await libolm.install(into: directory)

        // Reuse the port and secret when re-preparing: the registration Synapse already loaded
        // names both, and changing them silently would leave a homeserver pointing at nothing.
        let existing = try store.load().first { $0.bridgeID == descriptor.id }
        let appservicePort = try existing?.appservicePort ?? portAllocator.allocate()
        let configuration = BridgeConfiguration(
            bridgeID: descriptor.id,
            displayName: descriptor.displayName,
            directory: directory,
            homeserverURL: URL(string: "http://127.0.0.1:\(homeserverPort)")!,
            serverName: serverName,
            ownerUserID: ownerUserID,
            appservicePort: appservicePort,
            provisioningSecret: existing?.provisioningSecret
                ?? BridgeConfiguration.freshProvisioningSecret()
        )
        try configuration.write()
        try generateRegistration(
            executable: installed.executable,
            configuration: configuration,
            bridgeID: descriptor.id
        )
        // `--generate-registration` mints the tokens and writes them into both files. Re-rendering
        // with them read back makes every later write of this config carry them too.
        let tokens = try BridgeAppserviceTokens.read(
            fromRegistrationAt: configuration.registrationFile
        )
        try configuration.withTokens(tokens).write()
        try publishRegistrationToSynapse(configuration, bridgeID: descriptor.id)

        let record = PreparedBridge(
            bridgeID: descriptor.id,
            platform: descriptor.platform,
            displayName: descriptor.displayName,
            version: descriptor.version,
            serverName: serverName,
            ownerUserID: ownerUserID,
            executable: installed.executable.path,
            configurationFile: configuration.configurationFile.path,
            registrationFile: configuration.registrationFile.path,
            appservicePort: configuration.appservicePort,
            provisioningSecret: configuration.provisioningSecret,
            sha256: installed.sha256
        )
        try store.upsert(record)
        return record
    }

    /// Runs the bridge's own `--generate-registration`, which is authoritative for its namespaces.
    private func generateRegistration(
        executable: URL,
        configuration: BridgeConfiguration,
        bridgeID: String
    ) throws {
        let process = Process()
        process.executableURL = executable
        process.arguments = [
            "--generate-registration",
            "--config", configuration.configurationFile.path,
            "--registration", configuration.registrationFile.path,
        ]
        process.currentDirectoryURL = configuration.directory
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw BridgeRuntimeError.registrationGenerationFailed(
                bridge: bridgeID,
                output: String(decoding: output.suffix(2_048), as: UTF8.self)
            )
        }
        guard FileManager.default.fileExists(atPath: configuration.registrationFile.path) else {
            throw BridgeRuntimeError.registrationMissing(configuration.registrationFile)
        }
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: configuration.registrationFile.path
        )
    }

    /// Copies the registration where Synapse reads it, rather than pointing Synapse into the
    /// bridge's own directory — the homeserver should not depend on a bridge's file layout.
    private func publishRegistrationToSynapse(
        _ configuration: BridgeConfiguration,
        bridgeID: String
    ) throws {
        try FileManager.default.createDirectory(
            at: appServiceDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let destination = appServiceDirectory
            .appendingPathComponent("\(bridgeID).yaml", isDirectory: false)
        let contents = try Data(contentsOf: configuration.registrationFile)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        guard FileManager.default.createFile(
            atPath: destination.path,
            contents: contents,
            attributes: [.posixPermissions: 0o600]
        ) else { throw BridgeRuntimeError.registrationMissing(destination) }
    }

    // MARK: - Supervision

    /// Re-renders every prepared bridge's configuration against the port Synapse actually got.
    ///
    /// The homeserver takes a fresh ephemeral port on each start, so a config written at prepare
    /// time points somewhere stale by the next session. The appservice port and secret are
    /// deliberately *not* re-rolled — Synapse loaded a registration naming both.
    public func rebindToHomeserver(port: UInt16) throws {
        for record in try store.load() {
            let directory = URL(fileURLWithPath: record.executable).deletingLastPathComponent()
            let configuration = BridgeConfiguration(
                bridgeID: record.bridgeID,
                displayName: record.displayName,
                directory: directory,
                homeserverURL: URL(string: "http://127.0.0.1:\(port)")!,
                serverName: record.serverName,
                ownerUserID: record.ownerUserID,
                appservicePort: record.appservicePort,
                provisioningSecret: record.provisioningSecret,
                tokens: try BridgeAppserviceTokens.read(
                    fromRegistrationAt: URL(fileURLWithPath: record.registrationFile)
                )
            )
            try configuration.write()
        }
    }

    /// Builds a supervisor for a prepared bridge, reusing the Phase 2 state machine unchanged.
    public func makeSupervisor(for record: PreparedBridge) throws -> SynapseSupervisor {
        let directory = URL(fileURLWithPath: record.executable).deletingLastPathComponent()
        // The supervisor's captured streams go to the profile's own logs directory, which it
        // requires be a direct child of the profile root; the bridge's structured JSON log stays
        // beside the bridge, where the bridge itself writes it.
        let logs = paths.logs
        let configuration = ManagedProcessConfiguration(
            executable: URL(fileURLWithPath: record.executable),
            arguments: ["--config", record.configurationFile, "--no-update"],
            environment: [
                "HOME": NSHomeDirectory(),
                "PATH": "/usr/bin:/bin",
                "TZ": "UTC",
            ],
            workingDirectory: directory,
            profileRoot: paths.profile,
            logsDirectory: logs,
            standardOutputLog: logs.appendingPathComponent("\(record.bridgeID).out.log"),
            standardErrorLog: logs.appendingPathComponent("\(record.bridgeID).err.log"),
            sensitiveLogValues: [record.provisioningSecret]
        )
        return SynapseSupervisor(
            configuration: configuration,
            loopbackPort: record.appservicePort,
            healthChecker: try BridgeHealthChecker(
                provisioningBaseURL: record.provisioningBaseURL,
                provisioningSecret: record.provisioningSecret,
                userID: record.ownerUserID
            ),
            // A bridge reaching a remote network needs longer than a local homeserver before its
            // provisioning API answers.
            startupTimeout: .seconds(60)
        )
    }

    public func provisioningClient(for record: PreparedBridge) throws -> BridgeProvisioningClient {
        try BridgeProvisioningClient(
            baseURL: record.provisioningBaseURL,
            provisioningToken: record.provisioningSecret,
            userID: record.ownerUserID
        )
    }

    /// Starts every bridge the profile asks for, runs `body`, then always stops them.
    ///
    /// Each bridge is started and stopped independently: one that fails to come up is reported and
    /// skipped rather than aborting the session, because a broken Instagram bridge is no reason to
    /// take WhatsApp down with it. While `body` runs, a bridge the user disconnects or removes is
    /// stopped, and one they reconnect is started again.
    @discardableResult
    public func withRunningBridges<T>(
        reconcileInterval: Duration = .seconds(1),
        onBridgeReady: @escaping @Sendable (PreparedBridge, RuntimeSnapshot) -> Void = { _, _ in },
        onBridgeStopped: @escaping @Sendable (PreparedBridge) -> Void = { _ in },
        onBridgeFailed: @escaping @Sendable (PreparedBridge, any Error) -> Void = { _, _ in },
        _ body: @Sendable () async throws -> T
    ) async throws -> T {
        let fleet = BridgeFleet(
            eligible: try store.load(),
            wanted: { try bridgesToRun() },
            launch: { try makeSupervisor(for: $0) },
            onReady: onBridgeReady,
            onStopped: onBridgeStopped,
            onFailed: onBridgeFailed
        )
        await fleet.reconcile()
        let reconciler = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: reconcileInterval)
                guard !Task.isCancelled else { return }
                await fleet.reconcile()
            }
        }
        do {
            let value = try await body()
            reconciler.cancel()
            await reconciler.value
            await fleet.stopAll()
            return value
        } catch {
            reconciler.cancel()
            await reconciler.value
            await fleet.stopAll()
            throw error
        }
    }

    /// Compares what a running bridge advertises against what the pinned version was recorded as
    /// offering. Drift is reported, never silently accepted.
    public func detectFlowDrift(
        _ descriptor: BridgeDescriptor,
        advertised: [BridgeLoginFlow]
    ) throws {
        guard !descriptor.expectedLoginFlowIDs.isEmpty else { return }
        let actual = Set(advertised.map(\.id))
        guard actual == Set(descriptor.expectedLoginFlowIDs) else {
            throw BridgeRuntimeError.flowDrift(
                bridge: descriptor.id,
                expected: descriptor.expectedLoginFlowIDs,
                actual: Array(actual)
            )
        }
    }
}

extension PreparedBridge: Hashable {}

/// `<profile>/state/bridges.json`, written `0600` beside the runtime's own state.
struct PreparedBridgeStore: Sendable {
    static let filePermissions = 0o600
    let paths: RuntimePaths

    var file: URL {
        paths.state.appendingPathComponent("bridges.json", isDirectory: false)
    }

    func load() throws -> [PreparedBridge] {
        guard let data = try? Data(contentsOf: file) else { return [] }
        return (try? JSONDecoder().decode([SupportedRecord].self, from: data))?
            .compactMap(\.bridge) ?? []
    }

    /// Removed platforms must not prevent the other accounts in an existing profile from loading.
    private struct SupportedRecord: Decodable {
        let bridge: PreparedBridge?

        private enum CodingKeys: String, CodingKey { case platform }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let platform = try container.decode(String.self, forKey: .platform)
            guard let supportedPlatform = Platform(rawValue: platform),
                  BridgeCatalog.descriptor(for: supportedPlatform) != nil else {
                bridge = nil
                return
            }
            bridge = try PreparedBridge(from: decoder)
        }
    }

    func upsert(_ record: PreparedBridge) throws {
        var records = try load()
        records.removeAll { $0.bridgeID == record.bridgeID }
        records.append(record)
        try save(records)
    }

    func remove(bridgeID: String) throws {
        var records = try load()
        records.removeAll { $0.bridgeID == bridgeID }
        try save(records)
    }

    func save(_ records: [PreparedBridge]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        try publishStateFile(encoder.encode(records), to: file, in: paths)
    }
}

/// `<profile>/state/disconnected-accounts.json`: the accounts the user disconnected.
///
/// Read by the runtime session, which keeps a disconnected network's bridge stopped — including
/// the next time Inbox+ opens — and by the app, which shows the account as disconnected.
public struct DisconnectedAccountStore: Sendable {
    public let paths: RuntimePaths

    public init(paths: RuntimePaths) {
        self.paths = paths
    }

    var file: URL {
        paths.state.appendingPathComponent("disconnected-accounts.json", isDirectory: false)
    }

    public func load() throws -> Set<String> {
        guard FileManager.default.fileExists(atPath: file.path) else { return [] }
        return Set(try JSONDecoder().decode([String].self, from: Data(contentsOf: file)))
    }

    public func insert(_ accountID: String) throws {
        var accountIDs = try load()
        guard accountIDs.insert(accountID).inserted else { return }
        try save(accountIDs)
    }

    public func remove(_ accountID: String) throws {
        var accountIDs = try load()
        guard accountIDs.remove(accountID) != nil else { return }
        try save(accountIDs)
    }

    private func save(_ accountIDs: Set<String>) throws {
        try publishStateFile(JSONEncoder().encode(accountIDs.sorted()), to: file, in: paths)
    }
}

/// Writes a `0600` state file atomically, so a session reading it never sees half of one.
private func publishStateFile(_ data: Data, to file: URL, in paths: RuntimePaths) throws {
    try FileManager.default.createDirectory(
        at: paths.state,
        withIntermediateDirectories: true,
        attributes: [.posixPermissions: 0o700]
    )
    let staging = paths.state.appendingPathComponent(
        ".\(file.lastPathComponent).\(UUID().uuidString).tmp",
        isDirectory: false
    )
    guard FileManager.default.createFile(
        atPath: staging.path,
        contents: data,
        attributes: [.posixPermissions: PreparedBridgeStore.filePermissions]
    ) else { throw BridgeInstallError.cannotWrite(file) }
    do {
        _ = try FileManager.default.replaceItemAt(file, withItemAt: staging)
    } catch {
        try? FileManager.default.removeItem(at: staging)
        throw error
    }
    try FileManager.default.setAttributes(
        [.posixPermissions: PreparedBridgeStore.filePermissions],
        ofItemAtPath: file.path
    )
}
