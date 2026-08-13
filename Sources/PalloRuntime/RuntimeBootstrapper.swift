import CryptoKit
import Darwin
import Foundation

struct RuntimeProcessOutput: Sendable, Equatable {
    let status: Int32
    let standardOutput: String
    let standardError: String

    static let success = RuntimeProcessOutput(status: 0, standardOutput: "", standardError: "")
}

typealias RuntimeProcessRunner = @Sendable (URL, [String]) async throws -> RuntimeProcessOutput

public struct RuntimeBootstrapper: Sendable {
    public static let directoryPermissions = 0o700
    public static let receiptPermissions = 0o600

    private let requirementsLock: URL
    private let processRunner: RuntimeProcessRunner
    private let now: @Sendable () -> Date

    public init() {
        let sourceRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
        self.init(
            requirementsLock: sourceRoot.appendingPathComponent("Runtime/Synapse/requirements.lock"),
            processRunner: Self.runFoundationProcess,
            now: Date.init
        )
    }

    init(
        requirementsLock: URL,
        processRunner: @escaping RuntimeProcessRunner,
        now: @escaping @Sendable () -> Date
    ) {
        self.requirementsLock = requirementsLock.standardizedFileURL
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

        let pythonVersion = try await detectedPythonVersion(executable: python)
        guard pythonVersion.hasPrefix(manifest.pythonMinor + "."),
              pythonVersion.dropFirst(manifest.pythonMinor.count + 1).allSatisfy({ $0.isASCII && $0.isNumber })
        else {
            throw RuntimeBootstrapError.unsupportedPythonVersion(pythonVersion, requiredMinor: manifest.pythonMinor)
        }

        let lockData = try Data(contentsOf: requirementsLock)
        let actualLockSHA256 = Self.sha256(lockData)
        guard actualLockSHA256 == manifest.requirementsLockSHA256 else {
            throw RuntimeBootstrapError.lockChecksumMismatch(
                expected: manifest.requirementsLockSHA256,
                actual: actualLockSHA256
            )
        }
        let expectedPackages = try Self.parsePinnedPackages(lockData)

        let receiptURL = paths.runtime.appendingPathComponent("prepared-runtime.json", isDirectory: false)
        try Self.validateRuntimeDestination(paths: paths, receipt: receiptURL)

        if FileManager.default.fileExists(atPath: receiptURL.path) {
            return try await verifyExistingRuntime(
                python: python,
                pythonVersion: pythonVersion,
                manifest: manifest,
                expectedPackages: expectedPackages,
                paths: paths,
                receiptURL: receiptURL
            )
        }
        if FileManager.default.fileExists(atPath: paths.runtime.path) {
            throw RuntimeBootstrapError.existingRuntimeDrift("runtime directory exists without a prepared-runtime receipt")
        }

        try Self.createSecureDirectories([paths.root, paths.profile, paths.runtime])
        try Self.validateRuntimeDestination(paths: paths, receipt: receiptURL)

        let virtualEnvironment = paths.runtime.appendingPathComponent("venv", isDirectory: true)
        try await runChecked(python, ["-m", "venv", virtualEnvironment.path])

        let virtualenvPython = virtualEnvironment.appendingPathComponent("bin/python", isDirectory: false)
        guard FileManager.default.isExecutableFile(atPath: virtualenvPython.path) else {
            throw RuntimeBootstrapError.missingRuntimeExecutable(virtualenvPython)
        }
        let virtualenvPythonVersion = try await detectedPythonVersion(executable: virtualenvPython)
        guard virtualenvPythonVersion == pythonVersion else {
            throw RuntimeBootstrapError.existingRuntimeDrift(
                "virtualenv Python \(virtualenvPythonVersion) does not match bootstrap Python \(pythonVersion)"
            )
        }

        try await runChecked(virtualenvPython, [
            "-m", "pip", "install",
            "--disable-pip-version-check",
            "--no-input",
            "--requirement", requirementsLock.path,
        ])

        let installedPackages = try await frozenPackages(using: virtualenvPython)
        guard installedPackages == expectedPackages else {
            throw RuntimeBootstrapError.packageDrift(expected: expectedPackages, actual: installedPackages)
        }

        let synapseExecutable = virtualEnvironment.appendingPathComponent("bin/synapse_homeserver", isDirectory: false)
        try await verifySynapse(
            executable: synapseExecutable,
            using: virtualenvPython,
            expectedVersion: manifest.synapseVersion
        )

        let receipt = PreparedRuntimeReceipt(
            pythonExecutable: python.path,
            pythonVersion: pythonVersion,
            synapseVersion: manifest.synapseVersion,
            requirementsLockSHA256: manifest.requirementsLockSHA256,
            installedPackages: installedPackages,
            createdAt: now()
        )
        try Self.writeReceiptAtomically(receipt, to: receiptURL)
        let validatedReceipt = try manifest.validatePreparedRuntime(at: receiptURL)
        guard validatedReceipt == receipt else {
            throw RuntimeBootstrapError.existingRuntimeDrift("published receipt did not round-trip exactly")
        }
        return validatedReceipt
    }

    private func verifyExistingRuntime(
        python: URL,
        pythonVersion: String,
        manifest: RuntimeManifest,
        expectedPackages: [String: String],
        paths: RuntimePaths,
        receiptURL: URL
    ) async throws -> PreparedRuntimeReceipt {
        let receipt = try manifest.validatePreparedRuntime(at: receiptURL)
        guard receipt.pythonExecutable == python.path else {
            throw RuntimeBootstrapError.existingRuntimeDrift(
                "receipt interpreter \(receipt.pythonExecutable) does not match requested interpreter \(python.path)"
            )
        }
        guard receipt.pythonVersion == pythonVersion else {
            throw RuntimeBootstrapError.existingRuntimeDrift(
                "receipt Python \(receipt.pythonVersion) does not match interpreter Python \(pythonVersion)"
            )
        }
        guard receipt.installedPackages == expectedPackages else {
            throw RuntimeBootstrapError.packageDrift(expected: expectedPackages, actual: receipt.installedPackages)
        }

        let virtualEnvironment = paths.runtime.appendingPathComponent("venv", isDirectory: true)
        let virtualenvPython = virtualEnvironment.appendingPathComponent("bin/python", isDirectory: false)
        guard FileManager.default.isExecutableFile(atPath: virtualenvPython.path) else {
            throw RuntimeBootstrapError.missingRuntimeExecutable(virtualenvPython)
        }
        let runtimePythonVersion = try await detectedPythonVersion(executable: virtualenvPython)
        guard runtimePythonVersion == receipt.pythonVersion else {
            throw RuntimeBootstrapError.existingRuntimeDrift(
                "runtime Python \(runtimePythonVersion) does not match receipt Python \(receipt.pythonVersion)"
            )
        }

        let installedPackages = try await frozenPackages(using: virtualenvPython)
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
            expectedVersion: receipt.synapseVersion
        )
        return receipt
    }

    private func detectedPythonVersion(executable: URL) async throws -> String {
        let output = try await runChecked(executable, ["--version"])
        let text = Self.combinedOutput(output).trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.hasPrefix("Python ") else {
            throw RuntimeBootstrapError.malformedPythonVersion(text)
        }
        let version = String(text.dropFirst("Python ".count))
        let components = version.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 3,
              components.allSatisfy({ !$0.isEmpty && $0.allSatisfy { $0.isASCII && $0.isNumber } })
        else {
            throw RuntimeBootstrapError.malformedPythonVersion(text)
        }
        return version
    }

    private func frozenPackages(using python: URL) async throws -> [String: String] {
        let output = try await runChecked(python, ["-m", "pip", "freeze", "--all"])
        return try Self.parsePinnedPackages(Data(output.standardOutput.utf8))
    }

    private func verifySynapse(
        executable: URL,
        using python: URL,
        expectedVersion: String
    ) async throws {
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw RuntimeBootstrapError.missingRuntimeExecutable(executable)
        }
        let executableProbe = try await processRunner(executable, ["--version"])
        let output: RuntimeProcessOutput
        if executableProbe.status == 0 {
            output = executableProbe
        } else if executableProbe.status == 2,
                  executableProbe.standardError.contains("unrecognized arguments: --version")
        {
            output = try await runChecked(
                python,
                ["-c", "import synapse; print(synapse.__version__)"]
            )
        } else {
            throw RuntimeBootstrapError.commandFailed(
                executable: executable.path,
                arguments: ["--version"],
                status: executableProbe.status,
                standardError: executableProbe.standardError
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
    private func runChecked(_ executable: URL, _ arguments: [String]) async throws -> RuntimeProcessOutput {
        let output = try await processRunner(executable, arguments)
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

    private static func parsePinnedPackages(_ data: Data) throws -> [String: String] {
        guard let contents = String(data: data, encoding: .utf8) else {
            throw RuntimeBootstrapError.invalidPackageListing("package listing is not UTF-8")
        }
        var packages: [String: String] = [:]
        for rawLine in contents.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty || line.hasPrefix("#") {
                continue
            }
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

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func validateRuntimeDestination(paths: RuntimePaths, receipt: URL) throws {
        let root = paths.root.standardizedFileURL
        let profile = paths.profile.standardizedFileURL
        let runtime = paths.runtime.standardizedFileURL
        let receipt = receipt.standardizedFileURL
        guard root.isFileURL, profile.isFileURL, runtime.isFileURL, receipt.isFileURL,
              isContained(profile, by: root),
              isContained(runtime, by: profile),
              receipt == runtime.appendingPathComponent("prepared-runtime.json", isDirectory: false)
        else {
            throw RuntimeBootstrapError.runtimeEscapesProfile(runtime)
        }
        try rejectSymlinkedAncestors(of: receipt)
    }

    private static func createSecureDirectories(_ directories: [URL]) throws {
        for directory in directories {
            try rejectSymlinkedAncestors(of: directory)
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: directoryPermissions]
            )
            try FileManager.default.setAttributes(
                [.posixPermissions: directoryPermissions],
                ofItemAtPath: directory.path
            )
            try rejectSymlinkedAncestors(of: directory)
        }
    }

    private static func writeReceiptAtomically(_ receipt: PreparedRuntimeReceipt, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(receipt)
        let temporaryURL = url.deletingLastPathComponent()
            .appendingPathComponent(".prepared-runtime.json.\(UUID().uuidString).tmp", isDirectory: false)
        var published = false
        defer {
            if !published {
                _ = Darwin.unlink(temporaryURL.path)
            }
        }

        let descriptor = Darwin.open(
            temporaryURL.path,
            O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW,
            mode_t(receiptPermissions)
        )
        guard descriptor >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        guard Darwin.fchmod(descriptor, mode_t(receiptPermissions)) == 0 else {
            let error = POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            _ = Darwin.close(descriptor)
            throw error
        }

        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        do {
            try handle.write(contentsOf: data)
            try handle.synchronize()
            try handle.close()
        } catch {
            try? handle.close()
            throw error
        }

        guard Darwin.rename(temporaryURL.path, url.path) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        published = true
    }

    private static func rejectSymlinkedAncestors(of url: URL) throws {
        var ancestor = URL(fileURLWithPath: "/", isDirectory: true)
        for component in url.pathComponents.dropFirst() {
            ancestor.appendPathComponent(component)
            var metadata = stat()
            guard Darwin.lstat(ancestor.path, &metadata) == 0 else {
                if errno != ENOENT {
                    throw RuntimeBootstrapError.cannotInspectRuntimePath(ancestor)
                }
                break
            }
            if metadata.st_mode & S_IFMT == S_IFLNK {
                throw RuntimeBootstrapError.symlinkedRuntimeAncestor(ancestor)
            }
        }
    }

    private static func isContained(_ child: URL, by root: URL) -> Bool {
        root.path == "/" ? child.path.hasPrefix("/") : child.path.hasPrefix(root.path + "/")
    }

    private static func combinedOutput(_ output: RuntimeProcessOutput) -> String {
        if output.standardOutput.isEmpty {
            return output.standardError
        }
        if output.standardError.isEmpty {
            return output.standardOutput
        }
        return output.standardOutput + "\n" + output.standardError
    }

    private static func runFoundationProcess(
        executable: URL,
        arguments: [String]
    ) async throws -> RuntimeProcessOutput {
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
        process.executableURL = executable
        process.arguments = arguments
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

public enum RuntimeBootstrapError: Error, Equatable, Sendable {
    case pythonNotExecutable(URL)
    case malformedPythonVersion(String)
    case unsupportedPythonVersion(String, requiredMinor: String)
    case lockChecksumMismatch(expected: String, actual: String)
    case invalidPackageListing(String)
    case packageDrift(expected: [String: String], actual: [String: String])
    case missingRuntimeExecutable(URL)
    case synapseVersionMismatch(expected: String, output: String)
    case commandFailed(executable: String, arguments: [String], status: Int32, standardError: String)
    case existingRuntimeDrift(String)
    case runtimeEscapesProfile(URL)
    case symlinkedRuntimeAncestor(URL)
    case cannotInspectRuntimePath(URL)
}
