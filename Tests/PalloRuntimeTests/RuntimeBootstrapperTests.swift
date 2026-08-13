import Foundation
import Testing
@testable import PalloRuntime

@Test func bootstrapRecordsInterpreterAndExactPackages() async throws {
    // Break caught: bootstrap records unverified interpreter/package metadata or fails to normalize package names.
    let fixture = try BootstrapFixture()
    defer { fixture.remove() }

    let receipt = try await fixture.bootstrapper.bootstrap(
        python: fixture.basePython,
        manifest: fixture.manifest,
        paths: fixture.paths
    )

    #expect(receipt.pythonExecutable == fixture.cellarPython.path)
    #expect(receipt.pythonVersion == "3.12.7")
    #expect(receipt.synapseVersion == "1.158.0")
    #expect(receipt.requirementsLockSHA256 == fixture.manifest.requirementsLockSHA256)
    #expect(receipt.installedPackages == [
        "matrix-synapse": "1.158.0",
        "pip": "24.2",
        "setuptools": "75.1.0",
    ])

    let receiptURL = fixture.paths.runtime.appendingPathComponent("prepared-runtime.json")
    #expect(try fixture.manifest.validatePreparedRuntime(at: receiptURL) == receipt)
    #expect(try permissions(of: fixture.paths.root) == 0o700)
    #expect(try permissions(of: fixture.paths.profile) == 0o700)
    #expect(try permissions(of: fixture.paths.runtime) == 0o700)
    #expect(try permissions(of: receiptURL) == 0o600)
    #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.paths.runtime.path)
        .filter { $0.hasPrefix(".prepared-runtime.json.") }
        .isEmpty)
}

@Test func bootstrapRejectsPythonOutsideThePinnedMinorBeforeCreatingAProfile() async throws {
    // Break caught: an incompatible interpreter is allowed to create a partially prepared profile.
    let fixture = try BootstrapFixture(pythonVersion: "3.13.1")
    defer { fixture.remove() }

    await #expect(throws: RuntimeBootstrapError.unsupportedPythonVersion("3.13.1", requiredMinor: "3.12")) {
        try await fixture.bootstrapper.bootstrap(
            python: fixture.basePython,
            manifest: fixture.manifest,
            paths: fixture.paths
        )
    }
    #expect(!FileManager.default.fileExists(atPath: fixture.paths.profile.path))
}

@Test func bootstrapRejectsAnExecutableThatClaimsPythonButIsNotCPython() async throws {
    // Break caught: an executable shell/script can pass bootstrap by printing a plausible Python version string.
    let fixture = try BootstrapFixture(pythonImplementation: "posix-shell")
    defer { fixture.remove() }

    await #expect(throws: RuntimeBootstrapError.unsupportedPythonImplementation("posix-shell")) {
        try await fixture.bootstrapper.bootstrap(
            python: fixture.basePython,
            manifest: fixture.manifest,
            paths: fixture.paths
        )
    }
    #expect(!FileManager.default.fileExists(atPath: fixture.paths.profile.path))
}

@Test func bootstrapRejectsPackageExtrasInsteadOfWeakeningTheLock() async throws {
    // Break caught: bootstrap accepts an unpinned transitive package merely because every locked package is present.
    let fixture = try BootstrapFixture(
        frozenPackages: "matrix-synapse==1.158.0\npip==24.2\nsetuptools==75.1.0\nwheel==0.45.1\n"
    )
    defer { fixture.remove() }

    await #expect(throws: RuntimeBootstrapError.packageDrift(
        expected: [
            "matrix-synapse": "1.158.0",
            "pip": "24.2",
            "setuptools": "75.1.0",
        ],
        actual: [
            "matrix-synapse": "1.158.0",
            "pip": "24.2",
            "setuptools": "75.1.0",
            "wheel": "0.45.1",
        ]
    )) {
        try await fixture.bootstrapper.bootstrap(
            python: fixture.basePython,
            manifest: fixture.manifest,
            paths: fixture.paths
        )
    }
}

@Test func existingPackageDriftIsReportedWithoutRepair() async throws {
    // Break caught: a second bootstrap silently reinstalls packages when an existing prepared runtime has drifted.
    let fixture = try BootstrapFixture()
    defer { fixture.remove() }
    _ = try await fixture.bootstrapper.bootstrap(
        python: fixture.basePython,
        manifest: fixture.manifest,
        paths: fixture.paths
    )
    fixture.frozenPackages = "matrix-synapse==1.158.0\npip==24.2\nsetuptools==75.1.0\nwheel==0.45.1\n"
    fixture.rejectMutationCommands = true

    await #expect(throws: RuntimeBootstrapError.packageDrift(
        expected: [
            "matrix-synapse": "1.158.0",
            "pip": "24.2",
            "setuptools": "75.1.0",
        ],
        actual: [
            "matrix-synapse": "1.158.0",
            "pip": "24.2",
            "setuptools": "75.1.0",
            "wheel": "0.45.1",
        ]
    )) {
        try await fixture.bootstrapper.bootstrap(
            python: fixture.basePython,
            manifest: fixture.manifest,
            paths: fixture.paths
        )
    }
}

@Test func validExistingRuntimeReturnsItsOriginalReceiptWithoutReinstalling() async throws {
    // Break caught: idempotent bootstrap mutates or replaces an already verified runtime and receipt.
    let fixture = try BootstrapFixture()
    defer { fixture.remove() }
    let first = try await fixture.bootstrapper.bootstrap(
        python: fixture.basePython,
        manifest: fixture.manifest,
        paths: fixture.paths
    )
    fixture.rejectMutationCommands = true

    let second = try await fixture.bootstrapper.bootstrap(
        python: fixture.basePython,
        manifest: fixture.manifest,
        paths: fixture.paths
    )

    #expect(second == first)
}

@Test func bootstrapVerifiesInstalledModuleWhenSynapseExecutableHasNoVersionFlag() async throws {
    // Break caught: the real Synapse 1.158 executable's unsupported --version flag makes a correctly pinned install unverifiable.
    let fixture = try BootstrapFixture(synapseVersionFlagSupported: false)
    defer { fixture.remove() }

    let receipt = try await fixture.bootstrapper.bootstrap(
        python: fixture.basePython,
        manifest: fixture.manifest,
        paths: fixture.paths
    )

    #expect(receipt.synapseVersion == "1.158.0")
}

@Test func bootstrapRejectsNearMatchForUnsupportedSynapseVersionFlag() async throws {
    // Break caught: a loosely matched argparse error enables module fallback for an unrecognized failure variation.
    let nearMatch = BootstrapFixture.knownUnsupportedVersionStderr
        .replacingOccurrences(of: "unrecognized arguments: --version", with: "unrecognized arguments: --version --other")
    let fixture = try BootstrapFixture(
        synapseVersionFlagSupported: false,
        synapseVersionError: nearMatch
    )
    defer { fixture.remove() }

    await #expect(throws: RuntimeBootstrapError.commandFailed(
        executable: fixture.synapseExecutable.path,
        arguments: ["--version"],
        status: 2,
        standardError: nearMatch
    )) {
        try await fixture.bootstrapper.bootstrap(
            python: fixture.basePython,
            manifest: fixture.manifest,
            paths: fixture.paths
        )
    }
}

@Test func bootstrapRejectsSynapseFallbackForAnotherManifestVersion() async throws {
    // Break caught: the 1.158.0-only compatibility path silently applies to future Synapse releases.
    let fixture = try BootstrapFixture(
        synapseVersion: "1.159.0",
        synapseVersionFlagSupported: false
    )
    defer { fixture.remove() }

    await #expect(throws: RuntimeBootstrapError.commandFailed(
        executable: fixture.synapseExecutable.path,
        arguments: ["--version"],
        status: 2,
        standardError: BootstrapFixture.knownUnsupportedVersionStderr
    )) {
        try await fixture.bootstrapper.bootstrap(
            python: fixture.basePython,
            manifest: fixture.manifest,
            paths: fixture.paths
        )
    }
}

@Test func existingRuntimeRejectsDirectoryPermissionDriftWithoutRepair() async throws {
    // Break caught: idempotent verification accepts or silently chmods a world-traversable profile.
    let fixture = try BootstrapFixture()
    defer { fixture.remove() }
    _ = try await fixture.runBootstrap()
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fixture.paths.profile.path)
    fixture.rejectMutationCommands = true

    await #expect(throws: RuntimeBootstrapError.insecurePermissions(
        fixture.paths.profile,
        expected: 0o700,
        actual: 0o755
    )) {
        try await fixture.runBootstrap()
    }
    #expect(try permissions(of: fixture.paths.profile) == 0o755)
}

@Test func existingRuntimeRejectsReceiptPermissionDriftWithoutRepair() async throws {
    // Break caught: idempotent verification reads a receipt visible to other local users or silently repairs it.
    let fixture = try BootstrapFixture()
    defer { fixture.remove() }
    _ = try await fixture.runBootstrap()
    let receipt = fixture.paths.runtime.appendingPathComponent("prepared-runtime.json")
    try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: receipt.path)
    fixture.rejectMutationCommands = true

    await #expect(throws: RuntimeBootstrapError.insecurePermissions(
        receipt,
        expected: 0o600,
        actual: 0o644
    )) {
        try await fixture.runBootstrap()
    }
    #expect(try permissions(of: receipt) == 0o644)
}

@Test func verifiedLockBytesAreTheOnlyRequirementsConsumedByPip() async throws {
    // Break caught: replacing the repository lock after checksum verification changes the packages pip consumes.
    let fixture = try BootstrapFixture(replaceSourceLockDuringVenvCreation: true)
    defer { fixture.remove() }

    let receipt = try await fixture.runBootstrap()

    #expect(receipt.installedPackages["matrix-synapse"] == "1.158.0")
    #expect(try String(contentsOf: fixture.runtimeLock, encoding: .utf8) == BootstrapFixture.lockContents)
    #expect(try permissions(of: fixture.runtimeLock) == 0o600)
}

@Test func ancestorSwapCannotRedirectReceiptPublication() async throws {
    // Break caught: replacing the profile ancestor after validation publishes a trusted receipt outside the profile.
    let fixture = try BootstrapFixture(swapProfileAfterVenvCreation: true)
    defer { fixture.remove() }

    await #expect(throws: RuntimeBootstrapError.runtimePathIdentityChanged(fixture.paths.profile)) {
        try await fixture.runBootstrap()
    }
    #expect(!FileManager.default.fileExists(
        atPath: fixture.outsideDirectory.appendingPathComponent("runtime/prepared-runtime.json").path
    ))
}

@Test func subprocessRequestsExcludeHostilePythonAndPipEnvironment() async throws {
    // Break caught: inherited Python/pip variables or an ambient working directory can shadow modules or alter installation.
    let fixture = try BootstrapFixture(hostEnvironment: [
        "HOME": "/safe-home",
        "TMPDIR": "/safe-tmp",
        "PATH": "/hostile-bin",
        "PYTHONPATH": "/attacker/python",
        "PYTHONHOME": "/attacker/home",
        "PIP_INDEX_URL": "https://attacker.invalid/simple",
        "PIP_CONFIG_FILE": "/attacker/pip.conf",
    ])
    defer { fixture.remove() }

    let receipt = try await fixture.runBootstrap()

    #expect(receipt.synapseVersion == "1.158.0")
}

@Test func explicitRequirementsLockIsIndependentOfAmbientWorkingDirectory() async throws {
    // Break caught: bootstrap silently locates Runtime/Synapse/requirements.lock relative to process CWD.
    let fixture = try BootstrapFixture()
    defer { fixture.remove() }
    let publicBootstrapper = RuntimeBootstrapper(requirementsLock: fixture.lock)

    let receipt = try await fixture.runBootstrap()

    #expect(publicBootstrapper.requirementsLock == fixture.lock.standardizedFileURL)
    #expect(receipt.requirementsLockSHA256 == BootstrapFixture.lockSHA256)
}

private final class BootstrapFixture: @unchecked Sendable {
    static let lockContents = "matrix_synapse==1.158.0\npip==24.2\nsetuptools==75.1.0\n"
    static let lockSHA256 = "27ad29ab8d275b356ead8720ef071f8fb8abeb82c9facd9b5d0f045e3694d5a2"

    static let knownUnsupportedVersionStderr = """
    usage: synapse_homeserver [-h] [-c CONFIG_FILE] [--no-secrets-in-config]
                              [--generate-config | --generate-missing-configs | --generate-missing-and-run]
                              [-H SERVER_NAME] [--report-stats {yes,no}]
                              [--config-directory DIRECTORY]
                              [--data-directory DIRECTORY] [--open-private-ports]
                              [--enable-metrics] [-D] [--print-pidfile]
                              [--manhole PORT] [-d SQLITE_DATABASE_PATH] [-n]
                              [--enable-registration]
    synapse_homeserver: error: unrecognized arguments: --version

    """

    let directory: URL
    let homebrewPrefix: URL
    let cellarVersion: URL
    let cellarPython: URL
    let basePython: URL
    let lock: URL
    let paths: RuntimePaths
    let manifest: RuntimeManifest
    lazy var bootstrapper = RuntimeBootstrapper(
        requirementsLock: lock,
        allowedHomebrewPrefixes: [homebrewPrefix],
        hostEnvironment: hostEnvironment,
        processRunner: { [weak self] request in
            guard let self else { throw FixtureError.deallocated }
            return try self.run(request)
        },
        now: { Date(timeIntervalSinceReferenceDate: 1234) }
    )
    let pythonVersion: String
    let pythonImplementation: String
    let synapseVersionFlagSupported: Bool
    let synapseVersionError: String
    let replaceSourceLockDuringVenvCreation: Bool
    let swapProfileAfterVenvCreation: Bool
    let hostEnvironment: [String: String]
    var frozenPackages: String
    var rejectMutationCommands = false

    var virtualEnvironment: URL { paths.runtime.appendingPathComponent("venv", isDirectory: true) }
    var virtualenvPython: URL { virtualEnvironment.appendingPathComponent("bin/python") }
    var synapseExecutable: URL { virtualEnvironment.appendingPathComponent("bin/synapse_homeserver") }
    var runtimeLock: URL { paths.runtime.appendingPathComponent("requirements.lock") }
    var outsideDirectory: URL { directory.appendingPathComponent("outside", isDirectory: true) }

    init(
        pythonVersion: String = "3.12.7",
        pythonImplementation: String = "cpython",
        synapseVersion: String = "1.158.0",
        frozenPackages: String = "setuptools==75.1.0\nmatrix-synapse==1.158.0\npip==24.2\n",
        synapseVersionFlagSupported: Bool = true,
        synapseVersionError: String = BootstrapFixture.knownUnsupportedVersionStderr,
        replaceSourceLockDuringVenvCreation: Bool = false,
        swapProfileAfterVenvCreation: Bool = false,
        hostEnvironment: [String: String] = ["HOME": "/safe-home", "TMPDIR": "/safe-tmp"]
    ) throws {
        directory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(".build/RuntimeBootstrapperTests-\(UUID().uuidString)", isDirectory: true)
        homebrewPrefix = directory.appendingPathComponent("homebrew", isDirectory: true)
        cellarVersion = homebrewPrefix.appendingPathComponent("Cellar/python@3.12/3.12.7", isDirectory: true)
        cellarPython = cellarVersion.appendingPathComponent("bin/python3.12")
        basePython = homebrewPrefix.appendingPathComponent("opt/python@3.12/bin/python3.12")
        lock = directory.appendingPathComponent("requirements.lock")
        paths = try RuntimePaths(
            root: directory.appendingPathComponent("profiles", isDirectory: true),
            profileName: "primary"
        )
        manifest = RuntimeManifest(
            schemaVersion: 1,
            pythonMinor: "3.12",
            synapseVersion: synapseVersion,
            requirementsLockSHA256: Self.lockSHA256
        )
        self.pythonVersion = pythonVersion
        self.pythonImplementation = pythonImplementation
        self.frozenPackages = frozenPackages
        self.synapseVersionFlagSupported = synapseVersionFlagSupported
        self.synapseVersionError = synapseVersionError
        self.replaceSourceLockDuringVenvCreation = replaceSourceLockDuringVenvCreation
        self.swapProfileAfterVenvCreation = swapProfileAfterVenvCreation
        self.hostEnvironment = hostEnvironment

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Self.lockContents.write(to: lock, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: cellarPython.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "#!/bin/sh\nexit 1\n".write(to: cellarPython, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cellarPython.path)
        let optDirectory = homebrewPrefix.appendingPathComponent("opt", isDirectory: true)
        try FileManager.default.createDirectory(at: optDirectory, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: optDirectory.appendingPathComponent("python@3.12", isDirectory: true),
            withDestinationURL: cellarVersion
        )

    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }

    func runBootstrap() async throws -> PreparedRuntimeReceipt {
        try await bootstrapper.bootstrap(python: basePython, manifest: manifest, paths: paths)
    }

    private func run(_ request: RuntimeProcessRequest) throws -> RuntimeProcessOutput {
        try validateIsolation(request)
        let executable = request.executable
        let arguments = request.arguments
        if executable.standardizedFileURL == basePython.standardizedFileURL,
           arguments.count == 4,
           Array(arguments.prefix(3)) == ["-I", "-S", "-c"]
        {
            return .init(status: 0, standardOutput: pythonFacts(runtime: false), standardError: "")
        }
        if executable.standardizedFileURL == basePython.standardizedFileURL,
           arguments == ["-I", "-m", "venv", virtualEnvironment.path]
        {
            guard !rejectMutationCommands else { throw FixtureError.unexpectedMutation }
            let bin = virtualEnvironment.appendingPathComponent("bin", isDirectory: true)
            try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(at: virtualenvPython, withDestinationURL: cellarPython)
            try "fixture\n".write(to: synapseExecutable, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: synapseExecutable.path)
            if replaceSourceLockDuringVenvCreation {
                try "matrix-synapse==9.9.9\n".write(to: lock, atomically: true, encoding: .utf8)
            }
            if swapProfileAfterVenvCreation {
                let relocated = directory.appendingPathComponent("relocated-profile", isDirectory: true)
                try FileManager.default.moveItem(at: paths.profile, to: relocated)
                try FileManager.default.createDirectory(at: outsideDirectory, withIntermediateDirectories: true)
                try FileManager.default.createSymbolicLink(at: paths.profile, withDestinationURL: outsideDirectory)
            }
            return .success
        }

        if executable == virtualenvPython,
           arguments.count == 3,
           Array(arguments.prefix(2)) == ["-I", "-c"],
           arguments[2].contains("sys.implementation.name")
        {
            return .init(status: 0, standardOutput: pythonFacts(runtime: true), standardError: "")
        }
        if executable == virtualenvPython,
           arguments == ["-I", "-m", "pip", "install", "--disable-pip-version-check", "--no-input", "--requirement", runtimeLock.path]
        {
            guard !rejectMutationCommands else { throw FixtureError.unexpectedMutation }
            guard try String(contentsOf: runtimeLock, encoding: .utf8) == Self.lockContents else {
                throw FixtureError.unverifiedLockConsumed
            }
            return .success
        }
        if executable == virtualenvPython,
           arguments == ["-I", "-m", "pip", "freeze", "--all"]
        {
            return .init(status: 0, standardOutput: frozenPackages, standardError: "")
        }
        if executable == virtualenvPython,
           arguments == ["-I", "-c", "import synapse; print(synapse.__version__)"]
        {
            return .init(status: 0, standardOutput: "1.158.0\n", standardError: "")
        }
        if executable == paths.runtime.appendingPathComponent("venv/bin/synapse_homeserver"),
           arguments == ["--version"]
        {
            if synapseVersionFlagSupported {
                return .init(status: 0, standardOutput: "Synapse 1.158.0\n", standardError: "")
            }
            return .init(status: 2, standardOutput: "", standardError: synapseVersionError)
        }
        throw FixtureError.unexpectedCommand(executable.path, arguments)
    }

    private func pythonFacts(runtime: Bool) -> String {
        let prefix = runtime ? virtualEnvironment.path : cellarVersion.path
        let executable = runtime ? virtualenvPython.path : basePython.path
        let basePrefix = runtime
            ? homebrewPrefix.appendingPathComponent("opt/python@3.12", isDirectory: true).path
            : cellarVersion.path
        return """
        {"implementation":"\(pythonImplementation)","version":"\(pythonVersion)","executable":"\(executable)","executableRealPath":"\(cellarPython.path)","prefix":"\(prefix)","basePrefix":"\(basePrefix)"}
        """
    }

    private func validateIsolation(_ request: RuntimeProcessRequest) throws {
        let forbidden = request.environment.keys.filter {
            $0 == "PYTHONPATH" || $0 == "PYTHONHOME" || $0.hasPrefix("PIP_")
        }
        guard forbidden.isEmpty else {
            throw FixtureError.hostileEnvironmentLeaked(forbidden.sorted())
        }
        guard request.environment["PATH"] == "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
              request.workingDirectory.isFileURL,
              request.workingDirectory.path.hasPrefix(directory.path)
        else {
            throw FixtureError.unsanitizedRequest
        }
    }

    enum FixtureError: Error {
        case deallocated
        case unexpectedMutation
        case unverifiedLockConsumed
        case hostileEnvironmentLeaked([String])
        case unsanitizedRequest
        case unexpectedCommand(String, [String])
    }
}

private func permissions(of url: URL) throws -> Int {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    let permissions = try #require(attributes[.posixPermissions] as? NSNumber)
    return permissions.intValue & 0o777
}
