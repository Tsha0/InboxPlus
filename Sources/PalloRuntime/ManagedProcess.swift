import Foundation

public struct ManagedProcessIdentity: Codable, Sendable, Equatable {
    public let executablePath: String
    public let launchTimestamp: Date
    public let processIdentifier: Int32
    public let startIdentityToken: String

    public init(
        executablePath: String,
        launchTimestamp: Date,
        processIdentifier: Int32,
        startIdentityToken: String
    ) {
        self.executablePath = executablePath
        self.launchTimestamp = launchTimestamp
        self.processIdentifier = processIdentifier
        self.startIdentityToken = startIdentityToken
    }
}

public enum ManagedProcessIdentityStatus: Sendable, Equatable {
    case matching
    case exited
    case mismatched(actual: ManagedProcessIdentity)
}

public enum ManagedProcessSignal: Sendable, Equatable {
    case terminate
    case kill
}

public struct ManagedProcessConfiguration: Sendable, Equatable {
    public let executable: URL
    public let arguments: [String]
    public let environment: [String: String]
    public let workingDirectory: URL
    public let standardOutputLog: URL
    public let standardErrorLog: URL
    public let maximumLogBytesPerFile: Int
    public let retainedLogFileCount: Int

    public init(
        executable: URL,
        arguments: [String],
        environment: [String: String],
        workingDirectory: URL,
        standardOutputLog: URL,
        standardErrorLog: URL,
        maximumLogBytesPerFile: Int = 1_048_576,
        retainedLogFileCount: Int = 3
    ) {
        self.executable = executable.standardizedFileURL
        self.arguments = arguments
        self.environment = environment
        self.workingDirectory = workingDirectory.standardizedFileURL
        self.standardOutputLog = standardOutputLog.standardizedFileURL
        self.standardErrorLog = standardErrorLog.standardizedFileURL
        self.maximumLogBytesPerFile = maximumLogBytesPerFile
        self.retainedLogFileCount = retainedLogFileCount
    }
}

public protocol ManagedProcess: Sendable {
    func launch() async throws -> ManagedProcessIdentity
    func identityStatus(for expected: ManagedProcessIdentity) async -> ManagedProcessIdentityStatus
    @discardableResult
    func signal(_ signal: ManagedProcessSignal, ifMatching expected: ManagedProcessIdentity) async throws -> Bool
    func waitForExit(matching expected: ManagedProcessIdentity, timeout: Duration) async throws -> Bool
}

public protocol ManagedProcessFactory: Sendable {
    func make(_ configuration: ManagedProcessConfiguration) throws -> any ManagedProcess
}

public protocol LoopbackListenerChecking: Sendable {
    func isListening(on port: UInt16) async -> Bool
}

public struct SystemLoopbackListenerChecker: LoopbackListenerChecking {
    public init() {}

    public func isListening(on port: UInt16) async -> Bool {
        await Task.detached(priority: .utility) {
            var address = sockaddr_in()
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            address.sin_family = sa_family_t(AF_INET)
            address.sin_port = port.bigEndian
            address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

            let descriptor = Darwin.socket(AF_INET, SOCK_STREAM, 0)
            guard descriptor >= 0 else { return false }
            defer { _ = Darwin.close(descriptor) }

            var timeout = timeval(tv_sec: 0, tv_usec: 100_000)
            _ = withUnsafePointer(to: &timeout) {
                setsockopt(descriptor, SOL_SOCKET, SO_SNDTIMEO, $0, socklen_t(MemoryLayout<timeval>.size))
            }
            return withUnsafePointer(to: &address) { pointer in
                pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0
                }
            }
        }.value
    }
}

public enum ManagedProcessError: Error, Sendable, Equatable {
    case invalidConfiguration(String)
    case alreadyLaunched
    case launchIdentityUnavailable(Int32)
    case signalFailed(signal: ManagedProcessSignal, code: Int32)
    case logFailure(operation: String, code: Int32)
}
