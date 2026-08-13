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

    #expect(receipt.pythonExecutable == fixture.basePython.standardizedFileURL.path)
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

private final class BootstrapFixture: @unchecked Sendable {
    static let lockContents = "matrix_synapse==1.158.0\npip==24.2\nsetuptools==75.1.0\n"
    static let lockSHA256 = "27ad29ab8d275b356ead8720ef071f8fb8abeb82c9facd9b5d0f045e3694d5a2"

    let directory: URL
    let basePython: URL
    let lock: URL
    let paths: RuntimePaths
    let manifest: RuntimeManifest
    lazy var bootstrapper = RuntimeBootstrapper(
        requirementsLock: lock,
        processRunner: { [weak self] executable, arguments in
            guard let self else { throw FixtureError.deallocated }
            return try self.run(executable: executable, arguments: arguments)
        },
        now: { Date(timeIntervalSinceReferenceDate: 1234) }
    )
    let pythonVersion: String
    let synapseVersionFlagSupported: Bool
    var frozenPackages: String
    var rejectMutationCommands = false

    init(
        pythonVersion: String = "3.12.7",
        frozenPackages: String = "setuptools==75.1.0\nmatrix-synapse==1.158.0\npip==24.2\n",
        synapseVersionFlagSupported: Bool = true
    ) throws {
        directory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
            .appendingPathComponent(".build/RuntimeBootstrapperTests-\(UUID().uuidString)", isDirectory: true)
        basePython = directory.appendingPathComponent("fake-python3.12")
        lock = directory.appendingPathComponent("requirements.lock")
        paths = try RuntimePaths(
            root: directory.appendingPathComponent("profiles", isDirectory: true),
            profileName: "primary"
        )
        manifest = RuntimeManifest(
            schemaVersion: 1,
            pythonMinor: "3.12",
            synapseVersion: "1.158.0",
            requirementsLockSHA256: Self.lockSHA256
        )
        self.pythonVersion = pythonVersion
        self.frozenPackages = frozenPackages
        self.synapseVersionFlagSupported = synapseVersionFlagSupported

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Self.lockContents.write(to: lock, atomically: true, encoding: .utf8)
        try "#!/bin/sh\nexit 1\n".write(to: basePython, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: basePython.path)

    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }

    private func run(executable: URL, arguments: [String]) throws -> RuntimeProcessOutput {
        if executable.standardizedFileURL == basePython.standardizedFileURL, arguments == ["--version"] {
            return .init(status: 0, standardOutput: "Python \(pythonVersion)\n", standardError: "")
        }
        if executable.standardizedFileURL == basePython.standardizedFileURL,
           arguments == ["-m", "venv", paths.runtime.appendingPathComponent("venv").path]
        {
            guard !rejectMutationCommands else { throw FixtureError.unexpectedMutation }
            let bin = paths.runtime.appendingPathComponent("venv/bin", isDirectory: true)
            try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
            for executableName in ["python", "synapse_homeserver"] {
                let url = bin.appendingPathComponent(executableName)
                try "fixture\n".write(to: url, atomically: true, encoding: .utf8)
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
            }
            return .success
        }

        let virtualenvPython = paths.runtime.appendingPathComponent("venv/bin/python")
        if executable == virtualenvPython, arguments == ["--version"] {
            return .init(status: 0, standardOutput: "Python \(pythonVersion)\n", standardError: "")
        }
        if executable == virtualenvPython,
           arguments == ["-m", "pip", "install", "--disable-pip-version-check", "--no-input", "--requirement", lock.path]
        {
            guard !rejectMutationCommands else { throw FixtureError.unexpectedMutation }
            return .success
        }
        if executable == virtualenvPython,
           arguments == ["-m", "pip", "freeze", "--all"]
        {
            return .init(status: 0, standardOutput: frozenPackages, standardError: "")
        }
        if executable == virtualenvPython,
           arguments == ["-c", "import synapse; print(synapse.__version__)"]
        {
            return .init(status: 0, standardOutput: "1.158.0\n", standardError: "")
        }
        if executable == paths.runtime.appendingPathComponent("venv/bin/synapse_homeserver"),
           arguments == ["--version"]
        {
            if synapseVersionFlagSupported {
                return .init(status: 0, standardOutput: "Synapse 1.158.0\n", standardError: "")
            }
            return .init(
                status: 2,
                standardOutput: "",
                standardError: "synapse_homeserver: error: unrecognized arguments: --version\n"
            )
        }
        throw FixtureError.unexpectedCommand(executable.path, arguments)
    }

    enum FixtureError: Error {
        case deallocated
        case unexpectedMutation
        case unexpectedCommand(String, [String])
    }
}

private func permissions(of url: URL) throws -> Int {
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    let permissions = try #require(attributes[.posixPermissions] as? NSNumber)
    return permissions.intValue & 0o777
}
