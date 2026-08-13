import Foundation

public enum RuntimePhase: String, Codable, Sendable, CaseIterable {
    case unprepared
    case stopped
    case starting
    case healthy
    case degraded
    case recovering
    case stopping
    case failed
}

public struct RuntimeState: Sendable, Equatable {
    public let phase: RuntimePhase

    public init(phase: RuntimePhase) {
        self.phase = phase
    }

    public func transitioning(to next: RuntimePhase) throws -> RuntimeState {
        guard Self.allowedTransitions[phase, default: []].contains(next) else {
            throw RuntimeStateError.invalidTransition(from: phase, to: next)
        }
        return RuntimeState(phase: next)
    }

    private static let allowedTransitions: [RuntimePhase: Set<RuntimePhase>] = [
        .unprepared: [.stopped, .failed],
        .stopped: [.starting],
        .starting: [.healthy, .degraded, .failed],
        .healthy: [.degraded, .stopping, .recovering, .failed],
        .degraded: [.healthy, .recovering, .stopping, .failed],
        .recovering: [.starting, .healthy, .degraded, .stopping, .failed],
        .stopping: [.stopped, .failed],
        .failed: [.stopping, .stopped, .recovering],
    ]
}

public struct RuntimeSnapshot: Codable, Sendable, Equatable {
    public let phase: RuntimePhase
    public let processIdentity: ManagedProcessIdentity?
    public let loopbackPort: UInt16?
    public let restartCount: Int
    public let lastHealthResult: String?
    public let diagnosticLogDirectory: URL?
    public let lastError: String?

    public init(
        phase: RuntimePhase,
        processIdentity: ManagedProcessIdentity?,
        loopbackPort: UInt16?,
        restartCount: Int,
        lastHealthResult: String?,
        diagnosticLogDirectory: URL?,
        lastError: String?
    ) {
        self.phase = phase
        self.processIdentity = processIdentity
        self.loopbackPort = loopbackPort
        self.restartCount = restartCount
        self.lastHealthResult = lastHealthResult
        self.diagnosticLogDirectory = diagnosticLogDirectory
        self.lastError = lastError
    }

    public static let stopped = RuntimeSnapshot(
        phase: .stopped,
        processIdentity: nil,
        loopbackPort: nil,
        restartCount: 0,
        lastHealthResult: nil,
        diagnosticLogDirectory: nil,
        lastError: nil
    )
}

public enum RuntimeExitCode: Int32, Codable, Sendable, CaseIterable {
    case success = 0
    case invalidTransition = 20
    case unprepared = 21
    case processLaunchFailed = 22
    case processIdentityMismatch = 23
    case shutdownIncomplete = 24
}

public enum RuntimeStateError: Error, Sendable, Equatable {
    case invalidTransition(from: RuntimePhase, to: RuntimePhase)
    case processExitedUnexpectedly(ManagedProcessIdentity)
    case processIdentityMismatch(expected: ManagedProcessIdentity, actual: ManagedProcessIdentity)
    case uncontrolledProcess(ManagedProcessIdentity)
    case shutdownIncomplete(processAlive: Bool, listenerPresence: LoopbackListenerPresence)
}
