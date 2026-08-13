import CryptoKit
import Darwin
import Foundation

struct RuntimeProcessRequest: Sendable, Equatable {
    let executable: URL
    let arguments: [String]
    let environment: [String: String]
    let workingDirectory: URL
}

struct RuntimeProcessOutput: Sendable, Equatable {
    let status: Int32
    let standardOutput: String
    let standardError: String

    static let success = RuntimeProcessOutput(status: 0, standardOutput: "", standardError: "")
}

typealias RuntimeProcessRunner = @Sendable (RuntimeProcessRequest) async throws -> RuntimeProcessOutput

public struct RuntimeBootstrapper: Sendable {
    public static let directoryPermissions = 0o700
    public static let receiptPermissions = 0o600

    fileprivate static let runtimeLockName = "requirements.lock"
    fileprivate static let receiptName = "prepared-runtime.json"
    private static let pythonFactsScript = """
    import json, pathlib, sys
    print(json.dumps({
        "implementation": sys.implementation.name,
        "version": ".".join(map(str, sys.version_info[:3])),
        "executable": sys.executable,
        "executableRealPath": str(pathlib.Path(sys.executable).resolve()),
        "prefix": sys.prefix,
        "basePrefix": sys.base_prefix,
    }, sort_keys=True))
    """
    private static let knownSynapse1158UnsupportedVersionStderr = """
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

    public let requirementsLock: URL
    private let allowedHomebrewPrefixes: [URL]
    private let environment: [String: String]
    private let processRunner: RuntimeProcessRunner
    private let now: @Sendable () -> Date

    public init(requirementsLock: URL) {
        self.init(
            requirementsLock: requirementsLock,
            allowedHomebrewPrefixes: [
                URL(fileURLWithPath: "/opt/homebrew", isDirectory: true),
                URL(fileURLWithPath: "/usr/local", isDirectory: true),
            ],
            hostEnvironment: ProcessInfo.processInfo.environment,
            processRunner: Self.runFoundationProcess,
            now: Date.init
        )
    }

    init(
        requirementsLock: URL,
        allowedHomebrewPrefixes: [URL],
        hostEnvironment: [String: String],
        processRunner: @escaping RuntimeProcessRunner,
        now: @escaping @Sendable () -> Date
    ) {
        self.requirementsLock = requirementsLock.standardizedFileURL
        self.allowedHomebrewPrefixes = allowedHomebrewPrefixes.map(\.standardizedFileURL)
        environment = Self.sanitizedEnvironment(from: hostEnvironment)
        self.processRunner = processRunner
        self.now = now
    }

    public func bootstrap(
        python: URL,
        manifest: RuntimeManifest,
        paths: RuntimePaths
    ) async throws -> PreparedRuntimeReceipt {
        let python = python.standardizedFileURL
        guard python.isFileURL, FileManager.default.isExecutableFile(atPath: python.path) else {
            throw RuntimeBootstrapError.pythonNotExecutable(python)
        }
        guard requirementsLock.isFileURL else {
            throw RuntimeBootstrapError.nonFileRequirementsLock(requirementsLock)
        }

        let baseFacts = try await inspectBasePython(python, manifest: manifest)
        let lockData = try Self.readRegularFileNoFollow(at: requirementsLock)
        let actualLockSHA256 = Self.sha256(lockData)
        guard actualLockSHA256 == manifest.requirementsLockSHA256 else {
            throw RuntimeBootstrapError.lockChecksumMismatch(
                expected: manifest.requirementsLockSHA256,
                actual: actualLockSHA256
            )
        }
        let expectedPackages = try Self.parsePinnedPackages(lockData)

        let filesystem = try SecureRuntimeFilesystem.openOrCreate(paths: paths)
        if filesystem.receiptExists {
            try filesystem.validateExistingLayout()
            try filesystem.validateRuntimeLock(expected: lockData)
            return try await verifyExistingRuntime(
                baseFacts: baseFacts,
                manifest: manifest,
                expectedPackages: expectedPackages,
                filesystem: filesystem
            )
        }
        guard filesystem.runtimeWasCreated else {
            throw RuntimeBootstrapError.existingRuntimeDrift("runtime directory exists without a prepared-runtime receipt")
        }

        try filesystem.secureNewLayout()
        try filesystem.writeRuntimeLock(lockData)
        try filesystem.validateIdentity()

        let virtualEnvironment = paths.runtime.appendingPathComponent("venv", isDirectory: true)
        try await runChecked(
            executable: python,
            arguments: ["-I", "-m", "venv", virtualEnvironment.path],
            workingDirectory: paths.runtime,
            filesystem: filesystem
        )

        let virtualenvPython = virtualEnvironment.appendingPathComponent("bin/python", isDirectory: false)
        guard FileManager.default.isExecutableFile(atPath: virtualenvPython.path) else {
            throw RuntimeBootstrapError.missingRuntimeExecutable(virtualenvPython)
        }
        let runtimeFacts = try await inspectRuntimePython(
            virtualenvPython,
            virtualEnvironment: virtualEnvironment,
            baseFacts: baseFacts,
            filesystem: filesystem
        )
        guard runtimeFacts.version == baseFacts.version else {
            throw RuntimeBootstrapError.existingRuntimeDrift(
                "virtualenv Python \(runtimeFacts.version) does not match bootstrap Python \(baseFacts.version)"
            )
        }

        let runtimeLock = paths.runtime.appendingPathComponent(Self.runtimeLockName)
        try await runChecked(
            executable: virtualenvPython,
            arguments: [
                "-I", "-m", "pip", "install",
                "--disable-pip-version-check",
                "--no-input",
                "--requirement", runtimeLock.path,
            ],
            workingDirectory: paths.runtime,
            filesystem: filesystem
        )

        let installedPackages = try await frozenPackages(
            using: virtualenvPython,
            filesystem: filesystem
        )
        guard installedPackages == expectedPackages else {
            throw RuntimeBootstrapError.packageDrift(expected: expectedPackages, actual: installedPackages)
        }

        let synapseExecutable = virtualEnvironment.appendingPathComponent("bin/synapse_homeserver", isDirectory: false)
        try await verifySynapse(
            executable: synapseExecutable,
            using: virtualenvPython,
            expectedVersion: manifest.synapseVersion,
            filesystem: filesystem
        )

        let receipt = PreparedRuntimeReceipt(
            pythonExecutable: baseFacts.executableRealPath,
            pythonVersion: baseFacts.version,
            synapseVersion: manifest.synapseVersion,
            requirementsLockSHA256: manifest.requirementsLockSHA256,
            installedPackages: installedPackages,
            createdAt: now()
        )
        try filesystem.validateIdentity()
        try filesystem.writeReceipt(receipt)
        try filesystem.validateIdentity()
        let receiptURL = paths.runtime.appendingPathComponent(Self.receiptName)
        let validatedReceipt = try manifest.validatePreparedRuntime(at: receiptURL)
        guard validatedReceipt == receipt else {
            throw RuntimeBootstrapError.existingRuntimeDrift("published receipt did not round-trip exactly")
        }
        return validatedReceipt
    }

    private func verifyExistingRuntime(
        baseFacts: PythonFacts,
        manifest: RuntimeManifest,
        expectedPackages: [String: String],
        filesystem: SecureRuntimeFilesystem
    ) async throws -> PreparedRuntimeReceipt {
        try filesystem.validateIdentity()
        let receiptURL = filesystem.paths.runtime.appendingPathComponent(Self.receiptName)
        let receipt = try manifest.validatePreparedRuntime(at: receiptURL)
        guard receipt.pythonExecutable == baseFacts.executableRealPath else {
            throw RuntimeBootstrapError.existingRuntimeDrift(
                "receipt interpreter \(receipt.pythonExecutable) does not match canonical interpreter \(baseFacts.executableRealPath)"
            )
        }
        guard receipt.pythonVersion == baseFacts.version else {
            throw RuntimeBootstrapError.existingRuntimeDrift(
                "receipt Python \(receipt.pythonVersion) does not match interpreter Python \(baseFacts.version)"
            )
        }
        guard receipt.installedPackages == expectedPackages else {
            throw RuntimeBootstrapError.packageDrift(expected: expectedPackages, actual: receipt.installedPackages)
        }

        let virtualEnvironment = filesystem.paths.runtime.appendingPathComponent("venv", isDirectory: true)
        let virtualenvPython = virtualEnvironment.appendingPathComponent("bin/python", isDirectory: false)
        guard FileManager.default.isExecutableFile(atPath: virtualenvPython.path) else {
            throw RuntimeBootstrapError.missingRuntimeExecutable(virtualenvPython)
        }
        let runtimeFacts = try await inspectRuntimePython(
            virtualenvPython,
            virtualEnvironment: virtualEnvironment,
            baseFacts: baseFacts,
            filesystem: filesystem
        )
        guard runtimeFacts.version == receipt.pythonVersion else {
            throw RuntimeBootstrapError.existingRuntimeDrift(
                "runtime Python \(runtimeFacts.version) does not match receipt Python \(receipt.pythonVersion)"
            )
        }

        let installedPackages = try await frozenPackages(using: virtualenvPython, filesystem: filesystem)
        guard installedPackages == expectedPackages else {
            throw RuntimeBootstrapError.packageDrift(expected: expectedPackages, actual: installedPackages)
        }
        guard installedPackages == receipt.installedPackages else {
            throw RuntimeBootstrapError.packageDrift(expected: receipt.installedPackages, actual: installedPackages)
        }

        let synapseExecutable = virtualEnvironment.appendingPathComponent("bin/synapse_homeserver", isDirectory: false)
        try await verifySynapse(
            executable: synapseExecutable,
            using: virtualenvPython,
            expectedVersion: receipt.synapseVersion,
            filesystem: filesystem
        )
        try filesystem.validateIdentity()
        return receipt
    }

    private func inspectBasePython(_ executable: URL, manifest: RuntimeManifest) async throws -> PythonFacts {
        let facts = try await inspectPython(
            executable,
            omitSite: true,
            workingDirectory: requirementsLock.deletingLastPathComponent(),
            filesystem: nil
        )
        guard facts.implementation == "cpython" else {
            throw RuntimeBootstrapError.unsupportedPythonImplementation(facts.implementation)
        }
        try Self.validateVersion(facts.version, requiredMinor: manifest.pythonMinor)

        let canonicalInput = try Self.canonicalExistingURL(executable)
        guard facts.executableRealPath == canonicalInput.path,
              let homebrewPrefix = allowedHomebrewPrefixes.first(where: { prefix in
                  let optPackage = prefix.appendingPathComponent("opt/python@3.12", isDirectory: true)
                  let cellarPackage = prefix.appendingPathComponent("Cellar/python@3.12", isDirectory: true)
                  return (Self.isContained(executable, by: optPackage) || Self.isContained(executable, by: cellarPackage))
                      && Self.isContained(canonicalInput, by: cellarPackage)
                      && Self.isContained(URL(fileURLWithPath: facts.basePrefix), by: cellarPackage)
                      && Self.isContained(URL(fileURLWithPath: facts.prefix), by: cellarPackage)
              })
        else {
            throw RuntimeBootstrapError.pythonNotFromHomebrew312(executable)
        }
        _ = homebrewPrefix
        return facts
    }

    private func inspectRuntimePython(
        _ executable: URL,
        virtualEnvironment: URL,
        baseFacts: PythonFacts,
        filesystem: SecureRuntimeFilesystem
    ) async throws -> PythonFacts {
        let facts = try await inspectPython(
            executable,
            omitSite: false,
            workingDirectory: filesystem.paths.runtime,
            filesystem: filesystem
        )
        guard facts.implementation == "cpython" else {
            throw RuntimeBootstrapError.unsupportedPythonImplementation(facts.implementation)
        }
        let runtimeBasePrefix = try Self.canonicalExistingURL(URL(fileURLWithPath: facts.basePrefix))
        let expectedBasePrefix = try Self.canonicalExistingURL(URL(fileURLWithPath: baseFacts.basePrefix))
        guard runtimeBasePrefix == expectedBasePrefix,
              URL(fileURLWithPath: facts.prefix).standardizedFileURL == virtualEnvironment.standardizedFileURL,
              facts.executableRealPath == baseFacts.executableRealPath
        else {
            throw RuntimeBootstrapError.invalidPythonProvenance("virtualenv provenance does not match the Homebrew base interpreter")
        }
        return facts
    }

    private func inspectPython(
        _ executable: URL,
        omitSite: Bool,
        workingDirectory: URL,
        filesystem: SecureRuntimeFilesystem?
    ) async throws -> PythonFacts {
        let arguments = omitSite
            ? ["-I", "-S", "-c", Self.pythonFactsScript]
            : ["-I", "-c", Self.pythonFactsScript]
        let output = try await runChecked(
            executable: executable,
            arguments: arguments,
            workingDirectory: workingDirectory,
            filesystem: filesystem
        )
        do {
            return try JSONDecoder().decode(PythonFacts.self, from: Data(output.standardOutput.utf8))
        } catch {
            throw RuntimeBootstrapError.invalidPythonProvenance(
                output.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }

    private func frozenPackages(
        using python: URL,
        filesystem: SecureRuntimeFilesystem
    ) async throws -> [String: String] {
        let output = try await runChecked(
            executable: python,
            arguments: ["-I", "-m", "pip", "freeze", "--all"],
            workingDirectory: filesystem.paths.runtime,
            filesystem: filesystem
        )
        return try Self.parsePinnedPackages(Data(output.standardOutput.utf8))
    }

    private func verifySynapse(
        executable: URL,
        using python: URL,
        expectedVersion: String,
        filesystem: SecureRuntimeFilesystem
    ) async throws {
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw RuntimeBootstrapError.missingRuntimeExecutable(executable)
        }
        let probe = try await runRaw(
            executable: executable,
            arguments: ["--version"],
            workingDirectory: filesystem.paths.runtime,
            filesystem: filesystem
        )
        let output: RuntimeProcessOutput
        if probe.status == 0 {
            output = probe
        } else if expectedVersion == "1.158.0",
                  probe.status == 2,
                  Self.normalizedDiagnostic(probe.standardError)
                    == Self.normalizedDiagnostic(Self.knownSynapse1158UnsupportedVersionStderr)
        {
            output = try await runChecked(
                executable: python,
                arguments: ["-I", "-c", "import synapse; print(synapse.__version__)"],
                workingDirectory: filesystem.paths.runtime,
                filesystem: filesystem
            )
        } else {
            throw RuntimeBootstrapError.commandFailed(
                executable: executable.path,
                arguments: ["--version"],
                status: probe.status,
                standardError: probe.standardError
            )
        }

        let text = Self.combinedOutput(output).trimmingCharacters(in: .whitespacesAndNewlines)
        let punctuation = CharacterSet(charactersIn: "(),:[]")
        let versions = text.split(whereSeparator: \.isWhitespace).compactMap { token -> String? in
            let candidate = String(token).trimmingCharacters(in: punctuation)
            guard candidate.range(of: "^[0-9]+\\.[0-9]+\\.[0-9]+$", options: .regularExpression) != nil else {
                return nil
            }
            return candidate
        }
        guard versions == [expectedVersion] else {
            throw RuntimeBootstrapError.synapseVersionMismatch(expected: expectedVersion, output: text)
        }
    }

    @discardableResult
    private func runChecked(
        executable: URL,
        arguments: [String],
        workingDirectory: URL,
        filesystem: SecureRuntimeFilesystem?
    ) async throws -> RuntimeProcessOutput {
        let output = try await runRaw(
            executable: executable,
            arguments: arguments,
            workingDirectory: workingDirectory,
            filesystem: filesystem
        )
        guard output.status == 0 else {
            throw RuntimeBootstrapError.commandFailed(
                executable: executable.path,
                arguments: arguments,
                status: output.status,
                standardError: output.standardError
            )
        }
        return output
    }

    private func runRaw(
        executable: URL,
        arguments: [String],
        workingDirectory: URL,
        filesystem: SecureRuntimeFilesystem?
    ) async throws -> RuntimeProcessOutput {
        try filesystem?.validateIdentity()
        let output = try await processRunner(RuntimeProcessRequest(
            executable: executable,
            arguments: arguments,
            environment: environment,
            workingDirectory: workingDirectory.standardizedFileURL
        ))
        try filesystem?.validateIdentity()
        return output
    }

    private static func validateVersion(_ version: String, requiredMinor: String) throws {
        let components = version.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 3,
              components.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } })
        else {
            throw RuntimeBootstrapError.malformedPythonVersion(version)
        }
        guard version.hasPrefix(requiredMinor + ".") else {
            throw RuntimeBootstrapError.unsupportedPythonVersion(version, requiredMinor: requiredMinor)
        }
    }

    private static func sanitizedEnvironment(from host: [String: String]) -> [String: String] {
        var sanitized = [
            "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
            "LANG": "C.UTF-8",
            "LC_ALL": "C.UTF-8",
        ]
        for key in ["HOME", "TMPDIR"] {
            if let value = host[key], value.hasPrefix("/") {
                sanitized[key] = value
            }
        }
        return sanitized
    }

    private static func readRegularFileNoFollow(at url: URL) throws -> Data {
        let descriptor = Darwin.open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        var metadata = stat()
        guard Darwin.fstat(descriptor, &metadata) == 0, metadata.st_mode & S_IFMT == S_IFREG else {
            let code = errno == 0 ? EINVAL : errno
            _ = Darwin.close(descriptor)
            throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        do {
            let data = try handle.readToEnd() ?? Data()
            try handle.close()
            return data
        } catch {
            try? handle.close()
            throw error
        }
    }

    private static func parsePinnedPackages(_ data: Data) throws -> [String: String] {
        guard let contents = String(data: data, encoding: .utf8) else {
            throw RuntimeBootstrapError.invalidPackageListing("package listing is not UTF-8")
        }
        var packages: [String: String] = [:]
        for rawLine in contents.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") { continue }
            let components = line.components(separatedBy: "==")
            guard components.count == 2,
                  !components[0].isEmpty,
                  !components[1].isEmpty,
                  components[0].range(of: "^[A-Za-z0-9._-]+$", options: .regularExpression) != nil,
                  components[1].rangeOfCharacter(from: .whitespacesAndNewlines) == nil
            else {
                throw RuntimeBootstrapError.invalidPackageListing(line)
            }
            let name = components[0]
                .lowercased()
                .replacingOccurrences(of: "[._-]+", with: "-", options: .regularExpression)
            guard packages.updateValue(components[1], forKey: name) == nil else {
                throw RuntimeBootstrapError.invalidPackageListing("duplicate normalized package \(name)")
            }
        }
        return packages
    }

    private static func normalizedDiagnostic(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: "\n")
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func canonicalExistingURL(_ url: URL) throws -> URL {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard Darwin.realpath(url.path, &buffer) != nil else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return URL(fileURLWithPath: String(decoding: bytes, as: UTF8.self))
    }

    private static func isContained(_ child: URL, by root: URL) -> Bool {
        let child = child.standardizedFileURL.path
        let root = root.standardizedFileURL.path
        return child == root || child.hasPrefix(root + "/")
    }

    private static func combinedOutput(_ output: RuntimeProcessOutput) -> String {
        if output.standardOutput.isEmpty { return output.standardError }
        if output.standardError.isEmpty { return output.standardOutput }
        return output.standardOutput + "\n" + output.standardError
    }

    private static func runFoundationProcess(_ request: RuntimeProcessRequest) async throws -> RuntimeProcessOutput {
        let temporaryDirectory = FileManager.default.temporaryDirectory
        let stdoutURL = temporaryDirectory.appendingPathComponent("pallo-runtime-stdout-\(UUID().uuidString)")
        let stderrURL = temporaryDirectory.appendingPathComponent("pallo-runtime-stderr-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: stdoutURL)
            try? FileManager.default.removeItem(at: stderrURL)
        }
        try Data().write(to: stdoutURL, options: .withoutOverwriting)
        try Data().write(to: stderrURL, options: .withoutOverwriting)
        let stdout = try FileHandle(forWritingTo: stdoutURL)
        let stderr = try FileHandle(forWritingTo: stderrURL)
        defer {
            try? stdout.close()
            try? stderr.close()
        }

        let process = Process()
        process.executableURL = request.executable
        process.arguments = request.arguments
        process.environment = request.environment
        process.currentDirectoryURL = request.workingDirectory
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        try stdout.synchronize()
        try stderr.synchronize()
        return RuntimeProcessOutput(
            status: process.terminationStatus,
            standardOutput: String(decoding: try Data(contentsOf: stdoutURL), as: UTF8.self),
            standardError: String(decoding: try Data(contentsOf: stderrURL), as: UTF8.self)
        )
    }
}

private struct PythonFacts: Codable, Sendable, Equatable {
    let implementation: String
    let version: String
    let executable: String
    let executableRealPath: String
    let prefix: String
    let basePrefix: String
}

private final class SecureRuntimeFilesystem: @unchecked Sendable {
    let paths: RuntimePaths
    let runtimeWasCreated: Bool
    let receiptExists: Bool

    private let rootDescriptor: Int32
    private let profileDescriptor: Int32
    private let runtimeDescriptor: Int32

    private init(
        paths: RuntimePaths,
        rootDescriptor: Int32,
        profileDescriptor: Int32,
        runtimeDescriptor: Int32,
        runtimeWasCreated: Bool,
        receiptExists: Bool
    ) {
        self.paths = paths
        self.rootDescriptor = rootDescriptor
        self.profileDescriptor = profileDescriptor
        self.runtimeDescriptor = runtimeDescriptor
        self.runtimeWasCreated = runtimeWasCreated
        self.receiptExists = receiptExists
    }

    deinit {
        _ = Darwin.close(runtimeDescriptor)
        _ = Darwin.close(profileDescriptor)
        _ = Darwin.close(rootDescriptor)
    }

    static func openOrCreate(paths: RuntimePaths) throws -> SecureRuntimeFilesystem {
        let rootDescriptor = try openOrCreateAbsoluteDirectory(paths.root)
        do {
            let (profileDescriptor, _) = try openOrCreateChild(
                parent: rootDescriptor,
                name: paths.profile.lastPathComponent
            )
            do {
                let (runtimeDescriptor, runtimeCreated) = try openOrCreateChild(
                    parent: profileDescriptor,
                    name: paths.runtime.lastPathComponent
                )
                let receiptExists = try entryExists(
                    parent: runtimeDescriptor,
                    name: RuntimeBootstrapper.receiptName
                )
                return SecureRuntimeFilesystem(
                    paths: paths,
                    rootDescriptor: rootDescriptor,
                    profileDescriptor: profileDescriptor,
                    runtimeDescriptor: runtimeDescriptor,
                    runtimeWasCreated: runtimeCreated,
                    receiptExists: receiptExists
                )
            } catch {
                _ = Darwin.close(profileDescriptor)
                throw error
            }
        } catch {
            _ = Darwin.close(rootDescriptor)
            throw error
        }
    }

    func secureNewLayout() throws {
        try setPermissions(rootDescriptor, url: paths.root, expected: RuntimeBootstrapper.directoryPermissions)
        try setPermissions(profileDescriptor, url: paths.profile, expected: RuntimeBootstrapper.directoryPermissions)
        try setPermissions(runtimeDescriptor, url: paths.runtime, expected: RuntimeBootstrapper.directoryPermissions)
        try validateIdentity()
    }

    func validateExistingLayout() throws {
        try Self.validateDirectory(rootDescriptor, url: paths.root, expected: RuntimeBootstrapper.directoryPermissions)
        try Self.validateDirectory(profileDescriptor, url: paths.profile, expected: RuntimeBootstrapper.directoryPermissions)
        try Self.validateDirectory(runtimeDescriptor, url: paths.runtime, expected: RuntimeBootstrapper.directoryPermissions)
        try validateRegularEntry(
            name: RuntimeBootstrapper.receiptName,
            url: paths.runtime.appendingPathComponent(RuntimeBootstrapper.receiptName),
            expected: RuntimeBootstrapper.receiptPermissions
        )
        try validateIdentity()
    }

    func validateRuntimeLock(expected data: Data) throws {
        let url = paths.runtime.appendingPathComponent(RuntimeBootstrapper.runtimeLockName)
        try validateRegularEntry(
            name: RuntimeBootstrapper.runtimeLockName,
            url: url,
            expected: RuntimeBootstrapper.receiptPermissions
        )
        let actual = try readEntry(name: RuntimeBootstrapper.runtimeLockName)
        guard actual == data else {
            throw RuntimeBootstrapError.existingRuntimeDrift("profile requirements.lock differs from the authenticated lock")
        }
    }

    func writeRuntimeLock(_ data: Data) throws {
        try writeExclusive(
            data,
            name: RuntimeBootstrapper.runtimeLockName,
            permissions: RuntimeBootstrapper.receiptPermissions
        )
    }

    func writeReceipt(_ receipt: PreparedRuntimeReceipt) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(receipt)
        let temporaryName = ".prepared-runtime.json.\(UUID().uuidString).tmp"
        try writeExclusive(data, name: temporaryName, permissions: RuntimeBootstrapper.receiptPermissions)
        var published = false
        defer {
            if !published {
                _ = Darwin.unlinkat(runtimeDescriptor, temporaryName, 0)
            }
        }
        guard Darwin.renameat(
            runtimeDescriptor,
            temporaryName,
            runtimeDescriptor,
            RuntimeBootstrapper.receiptName
        ) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        guard Darwin.fsync(runtimeDescriptor) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        published = true
    }

    func validateIdentity() throws {
        try compareIdentity(rootDescriptor, url: paths.root)
        try compareIdentity(profileDescriptor, url: paths.profile)
        try compareIdentity(runtimeDescriptor, url: paths.runtime)
    }

    private func writeExclusive(_ data: Data, name: String, permissions: Int) throws {
        let descriptor = Darwin.openat(
            runtimeDescriptor,
            name,
            O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
            mode_t(permissions)
        )
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        do {
            guard Darwin.fchmod(descriptor, mode_t(permissions)) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            try handle.write(contentsOf: data)
            try handle.synchronize()
            try handle.close()
        } catch {
            try? handle.close()
            throw error
        }
    }

    private func readEntry(name: String) throws -> Data {
        let descriptor = Darwin.openat(runtimeDescriptor, name, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        do {
            let data = try handle.readToEnd() ?? Data()
            try handle.close()
            return data
        } catch {
            try? handle.close()
            throw error
        }
    }

    private func validateRegularEntry(name: String, url: URL, expected: Int) throws {
        var metadata = stat()
        guard Darwin.fstatat(runtimeDescriptor, name, &metadata, AT_SYMLINK_NOFOLLOW) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        guard metadata.st_mode & S_IFMT == S_IFREG else {
            throw RuntimeBootstrapError.notRegularFile(url)
        }
        let actual = Int(metadata.st_mode & 0o777)
        guard actual == expected else {
            throw RuntimeBootstrapError.insecurePermissions(url, expected: expected, actual: actual)
        }
    }

    private static func openOrCreateAbsoluteDirectory(_ url: URL) throws -> Int32 {
        var descriptor = Darwin.open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        for component in url.standardizedFileURL.pathComponents.dropFirst() {
            do {
                let (next, created) = try openOrCreateChild(parent: descriptor, name: component)
                if created {
                    guard Darwin.fchmod(next, mode_t(RuntimeBootstrapper.directoryPermissions)) == 0 else {
                        let code = errno
                        _ = Darwin.close(next)
                        throw POSIXError(POSIXErrorCode(rawValue: code) ?? .EIO)
                    }
                }
                _ = Darwin.close(descriptor)
                descriptor = next
            } catch {
                _ = Darwin.close(descriptor)
                throw error
            }
        }
        return descriptor
    }

    private static func openOrCreateChild(parent: Int32, name: String) throws -> (Int32, Bool) {
        let created: Bool
        if Darwin.mkdirat(parent, name, mode_t(RuntimeBootstrapper.directoryPermissions)) == 0 {
            created = true
        } else if errno == EEXIST {
            created = false
        } else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        let descriptor = Darwin.openat(
            parent,
            name,
            O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW
        )
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        return (descriptor, created)
    }

    private static func entryExists(parent: Int32, name: String) throws -> Bool {
        var metadata = stat()
        if Darwin.fstatat(parent, name, &metadata, AT_SYMLINK_NOFOLLOW) == 0 { return true }
        if errno == ENOENT { return false }
        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }

    private func setPermissions(_ descriptor: Int32, url: URL, expected: Int) throws {
        guard Darwin.fchmod(descriptor, mode_t(expected)) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        try Self.validateDirectory(descriptor, url: url, expected: expected)
    }

    private static func validateDirectory(_ descriptor: Int32, url: URL, expected: Int) throws {
        var metadata = stat()
        guard Darwin.fstat(descriptor, &metadata) == 0, metadata.st_mode & S_IFMT == S_IFDIR else {
            throw RuntimeBootstrapError.runtimePathIdentityChanged(url)
        }
        let actual = Int(metadata.st_mode & 0o777)
        guard actual == expected else {
            throw RuntimeBootstrapError.insecurePermissions(url, expected: expected, actual: actual)
        }
    }

    private func compareIdentity(_ descriptor: Int32, url: URL) throws {
        var anchored = stat()
        var path = stat()
        guard Darwin.fstat(descriptor, &anchored) == 0,
              Darwin.lstat(url.path, &path) == 0,
              path.st_mode & S_IFMT == S_IFDIR,
              anchored.st_dev == path.st_dev,
              anchored.st_ino == path.st_ino
        else {
            throw RuntimeBootstrapError.runtimePathIdentityChanged(url)
        }
    }
}

public enum RuntimeBootstrapError: Error, Equatable, Sendable {
    case pythonNotExecutable(URL)
    case nonFileRequirementsLock(URL)
    case malformedPythonVersion(String)
    case unsupportedPythonVersion(String, requiredMinor: String)
    case unsupportedPythonImplementation(String)
    case invalidPythonProvenance(String)
    case pythonNotFromHomebrew312(URL)
    case lockChecksumMismatch(expected: String, actual: String)
    case invalidPackageListing(String)
    case packageDrift(expected: [String: String], actual: [String: String])
    case missingRuntimeExecutable(URL)
    case synapseVersionMismatch(expected: String, output: String)
    case commandFailed(executable: String, arguments: [String], status: Int32, standardError: String)
    case existingRuntimeDrift(String)
    case insecurePermissions(URL, expected: Int, actual: Int)
    case notRegularFile(URL)
    case runtimePathIdentityChanged(URL)
}
