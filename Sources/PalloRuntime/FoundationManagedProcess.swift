import Darwin
import Foundation

public struct FoundationManagedProcessFactory: ManagedProcessFactory {
    public init() {}

    public func make(_ configuration: ManagedProcessConfiguration) throws -> any ManagedProcess {
        try FoundationManagedProcess(configuration: configuration)
    }
}

public final class FoundationManagedProcess: ManagedProcess, @unchecked Sendable {
    private let configuration: ManagedProcessConfiguration
    private let standardOutput: BoundedRotatingLog
    private let standardError: BoundedRotatingLog
    private let stateLock = NSLock()
    private var storedProcess: Process?
    private var standardOutputPipe: Pipe?
    private var standardErrorPipe: Pipe?

    init(configuration: ManagedProcessConfiguration) throws {
        guard configuration.executable.isFileURL,
              FileManager.default.isExecutableFile(atPath: configuration.executable.path)
        else {
            throw ManagedProcessError.invalidConfiguration("executable is not an executable file URL")
        }
        var isDirectory: ObjCBool = false
        guard configuration.workingDirectory.isFileURL,
              FileManager.default.fileExists(
                atPath: configuration.workingDirectory.path,
                isDirectory: &isDirectory
              ),
              isDirectory.boolValue
        else {
            throw ManagedProcessError.invalidConfiguration("working directory is not a directory")
        }
        guard configuration.standardOutputLog != configuration.standardErrorLog else {
            throw ManagedProcessError.invalidConfiguration("stdout and stderr logs must be distinct")
        }
        guard configuration.maximumLogBytesPerFile > 0,
              configuration.retainedLogFileCount > 0
        else {
            throw ManagedProcessError.invalidConfiguration("log bounds must be positive")
        }

        self.configuration = configuration
        standardOutput = try BoundedRotatingLog(
            file: configuration.standardOutputLog,
            maximumBytesPerFile: configuration.maximumLogBytesPerFile,
            retainedFileCount: configuration.retainedLogFileCount
        )
        standardError = try BoundedRotatingLog(
            file: configuration.standardErrorLog,
            maximumBytesPerFile: configuration.maximumLogBytesPerFile,
            retainedFileCount: configuration.retainedLogFileCount
        )
    }

    public func launch() async throws -> ManagedProcessIdentity {
        let child = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        child.executableURL = configuration.executable
        child.arguments = configuration.arguments
        child.environment = configuration.environment
        child.currentDirectoryURL = configuration.workingDirectory
        child.standardOutput = outputPipe
        child.standardError = errorPipe

        outputPipe.fileHandleForReading.readabilityHandler = { [standardOutput] handle in
            let bytes = handle.availableData
            if bytes.isEmpty {
                handle.readabilityHandler = nil
            } else {
                try? standardOutput.append(bytes)
            }
        }
        errorPipe.fileHandleForReading.readabilityHandler = { [standardError] handle in
            let bytes = handle.availableData
            if bytes.isEmpty {
                handle.readabilityHandler = nil
            } else {
                try? standardError.append(bytes)
            }
        }

        try installBeforeLaunch(child, outputPipe: outputPipe, errorPipe: errorPipe)
        child.terminationHandler = { [weak self, weak child] _ in
            guard let self, let child else { return }
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            self.clearInstalledProcess(child)
        }
        do {
            try child.run()
        } catch {
            clearInstalledProcess(child)
            outputPipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            throw error
        }

        var previousIdentity: ManagedProcessIdentity?
        for _ in 0..<40 {
            if let identity = Self.readIdentity(for: child.processIdentifier) {
                if identity == previousIdentity { return identity }
                previousIdentity = identity
            }
            if !child.isRunning { break }
            _ = await Task.detached(priority: .utility) { usleep(5_000) }.value
        }
        throw ManagedProcessError.launchIdentityUnavailable(child.processIdentifier)
    }

    public func identityStatus(for expected: ManagedProcessIdentity) async -> ManagedProcessIdentityStatus {
        guard let actual = Self.readIdentity(for: expected.processIdentifier) else {
            return .exited
        }
        return actual == expected ? .matching : .mismatched(actual: actual)
    }

    @discardableResult
    public func signal(
        _ signal: ManagedProcessSignal,
        ifMatching expected: ManagedProcessIdentity
    ) async throws -> Bool {
        switch await identityStatus(for: expected) {
        case .exited:
            return false
        case let .mismatched(actual):
            throw RuntimeStateError.processIdentityMismatch(expected: expected, actual: actual)
        case .matching:
            let systemSignal = signal == .terminate ? SIGTERM : SIGKILL
            guard Darwin.kill(expected.processIdentifier, systemSignal) == 0 else {
                if errno == ESRCH { return false }
                throw ManagedProcessError.signalFailed(signal: signal, code: errno)
            }
            return true
        }
    }

    public func waitForExit(
        matching expected: ManagedProcessIdentity,
        timeout: Duration
    ) async throws -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        repeat {
            switch await identityStatus(for: expected) {
            case .exited:
                return true
            case let .mismatched(actual):
                throw RuntimeStateError.processIdentityMismatch(expected: expected, actual: actual)
            case .matching:
                if clock.now >= deadline { return false }
                _ = await Task.detached(priority: .utility) { usleep(25_000) }.value
            }
        } while true
    }

    private func installBeforeLaunch(_ process: Process, outputPipe: Pipe, errorPipe: Pipe) throws {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard storedProcess == nil else { throw ManagedProcessError.alreadyLaunched }
        storedProcess = process
        standardOutputPipe = outputPipe
        standardErrorPipe = errorPipe
    }

    private func clearInstalledProcess(_ process: Process) {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard storedProcess === process else { return }
        storedProcess = nil
        standardOutputPipe = nil
        standardErrorPipe = nil
    }

    private static func readIdentity(for processIdentifier: Int32) -> ManagedProcessIdentity? {
        guard processIdentifier > 0 else { return nil }
        var information = proc_bsdinfo()
        let informationSize = Int32(MemoryLayout<proc_bsdinfo>.size)
        let result = proc_pidinfo(
            processIdentifier,
            PROC_PIDTBSDINFO,
            0,
            &information,
            informationSize
        )
        guard result == informationSize, information.pbi_pid == UInt32(processIdentifier) else {
            return nil
        }

        var pathBuffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let pathLength = proc_pidpath(processIdentifier, &pathBuffer, UInt32(pathBuffer.count))
        guard pathLength > 0 else { return nil }
        let executablePath = String(
            decoding: pathBuffer.prefix(Int(pathLength)).map(UInt8.init(bitPattern:)),
            as: UTF8.self
        )
        let seconds = information.pbi_start_tvsec
        let microseconds = information.pbi_start_tvusec
        let launchTimestamp = Date(
            timeIntervalSince1970: TimeInterval(seconds) + TimeInterval(microseconds) / 1_000_000
        )
        return ManagedProcessIdentity(
            executablePath: URL(fileURLWithPath: executablePath).standardizedFileURL.path,
            launchTimestamp: launchTimestamp,
            processIdentifier: processIdentifier,
            startIdentityToken: "\(processIdentifier):\(seconds):\(microseconds)"
        )
    }
}

final class BoundedRotatingLog: @unchecked Sendable {
    private let directoryDescriptor: Int32
    private let fileName: String
    private let maximumBytesPerFile: Int
    private let retainedFileCount: Int
    private let lock = NSLock()

    init(file: URL, maximumBytesPerFile: Int, retainedFileCount: Int) throws {
        guard file.isFileURL, maximumBytesPerFile > 0, retainedFileCount > 0 else {
            throw ManagedProcessError.invalidConfiguration("invalid rotating log configuration")
        }
        let parent = file.deletingLastPathComponent().standardizedFileURL
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        let descriptor = Darwin.open(parent.path, O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else {
            throw ManagedProcessError.logFailure(operation: "open log directory", code: errno)
        }
        guard Darwin.fchmod(descriptor, mode_t(0o700)) == 0 else {
            let code = errno
            _ = Darwin.close(descriptor)
            throw ManagedProcessError.logFailure(operation: "fchmod log directory", code: code)
        }
        directoryDescriptor = descriptor
        fileName = file.lastPathComponent
        self.maximumBytesPerFile = maximumBytesPerFile
        self.retainedFileCount = retainedFileCount
        try normalizeRetainedFiles()
    }

    deinit {
        _ = Darwin.close(directoryDescriptor)
    }

    func append(_ data: Data) throws {
        guard !data.isEmpty else { return }
        lock.lock()
        defer { lock.unlock() }

        var offset = 0
        while offset < data.count {
            var descriptor = try openCurrentLog()
            var status = stat()
            guard Darwin.fstat(descriptor, &status) == 0 else {
                let code = errno
                _ = Darwin.close(descriptor)
                throw ManagedProcessError.logFailure(operation: "fstat log", code: code)
            }
            guard (status.st_mode & S_IFMT) == S_IFREG, status.st_nlink == 1 else {
                _ = Darwin.close(descriptor)
                throw ManagedProcessError.invalidConfiguration("log must be a regular single-link file")
            }
            var size = Int(status.st_size)
            if size >= maximumBytesPerFile {
                _ = Darwin.close(descriptor)
                try rotate()
                descriptor = try openCurrentLog()
                size = 0
            }

            let count = min(maximumBytesPerFile - size, data.count - offset)
            try data.withUnsafeBytes { rawBuffer in
                guard let base = rawBuffer.baseAddress else { return }
                var written = 0
                while written < count {
                    let result = Darwin.write(
                        descriptor,
                        base.advanced(by: offset + written),
                        count - written
                    )
                    if result > 0 {
                        written += result
                    } else if result < 0, errno == EINTR {
                        continue
                    } else {
                        let code = errno
                        _ = Darwin.close(descriptor)
                        throw ManagedProcessError.logFailure(operation: "write log", code: code)
                    }
                }
            }
            guard Darwin.close(descriptor) == 0 else {
                throw ManagedProcessError.logFailure(operation: "close log", code: errno)
            }
            offset += count
        }
    }

    private func openCurrentLog() throws -> Int32 {
        let descriptor = fileName.withCString {
            Darwin.openat(
                directoryDescriptor,
                $0,
                O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC | O_NOFOLLOW,
                mode_t(0o600)
            )
        }
        guard descriptor >= 0 else {
            throw ManagedProcessError.logFailure(operation: "open log", code: errno)
        }
        guard Darwin.fchmod(descriptor, mode_t(0o600)) == 0 else {
            let code = errno
            _ = Darwin.close(descriptor)
            throw ManagedProcessError.logFailure(operation: "fchmod log", code: code)
        }
        return descriptor
    }

    private func normalizeRetainedFiles() throws {
        for index in 0..<retainedFileCount {
            let name = index == 0 ? fileName : rotatedName(index)
            let descriptor = name.withCString {
                Darwin.openat(directoryDescriptor, $0, O_WRONLY | O_CLOEXEC | O_NOFOLLOW)
            }
            if descriptor < 0, errno == ENOENT { continue }
            guard descriptor >= 0 else {
                throw ManagedProcessError.logFailure(operation: "open retained log", code: errno)
            }
            defer { _ = Darwin.close(descriptor) }

            var status = stat()
            guard Darwin.fstat(descriptor, &status) == 0 else {
                throw ManagedProcessError.logFailure(operation: "fstat retained log", code: errno)
            }
            guard (status.st_mode & S_IFMT) == S_IFREG, status.st_nlink == 1 else {
                throw ManagedProcessError.invalidConfiguration("retained log must be a regular single-link file")
            }
            guard Darwin.fchmod(descriptor, mode_t(0o600)) == 0 else {
                throw ManagedProcessError.logFailure(operation: "fchmod retained log", code: errno)
            }
            if status.st_size > maximumBytesPerFile {
                guard Darwin.ftruncate(descriptor, off_t(maximumBytesPerFile)) == 0 else {
                    throw ManagedProcessError.logFailure(operation: "truncate retained log", code: errno)
                }
            }
        }
    }

    private func rotate() throws {
        if retainedFileCount == 1 {
            try unlinkIfPresent(fileName)
            return
        }
        try unlinkIfPresent(rotatedName(retainedFileCount - 1))
        if retainedFileCount > 2 {
            for index in stride(from: retainedFileCount - 2, through: 1, by: -1) {
                try renameIfPresent(from: rotatedName(index), to: rotatedName(index + 1))
            }
        }
        try renameIfPresent(from: fileName, to: rotatedName(1))
    }

    private func rotatedName(_ index: Int) -> String { "\(fileName).\(index)" }

    private func unlinkIfPresent(_ name: String) throws {
        let result = name.withCString { Darwin.unlinkat(directoryDescriptor, $0, 0) }
        guard result == 0 || errno == ENOENT else {
            throw ManagedProcessError.logFailure(operation: "unlink rotated log", code: errno)
        }
    }

    private func renameIfPresent(from source: String, to destination: String) throws {
        let result = source.withCString { sourcePointer in
            destination.withCString { destinationPointer in
                Darwin.renameat(directoryDescriptor, sourcePointer, directoryDescriptor, destinationPointer)
            }
        }
        guard result == 0 || errno == ENOENT else {
            throw ManagedProcessError.logFailure(operation: "rotate log", code: errno)
        }
    }
}
