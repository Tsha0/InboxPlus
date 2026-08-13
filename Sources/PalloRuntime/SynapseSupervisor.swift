import Foundation

public actor SynapseSupervisor {
    public typealias Sleep = @Sendable (Duration) async throws -> Void

    private let configuration: ManagedProcessConfiguration
    private let loopbackPort: UInt16
    private let processFactory: any ManagedProcessFactory
    private let listenerChecker: any LoopbackListenerChecking
    private let gracefulTerminationTimeout: Duration
    private let forcedTerminationTimeout: Duration
    private let listenerVerificationAttempts: Int
    private let listenerVerificationInterval: Duration
    private let sleep: Sleep

    private var snapshot: RuntimeSnapshot
    private var managedProcess: (any ManagedProcess)?

    public init(
        configuration: ManagedProcessConfiguration,
        loopbackPort: UInt16,
        processFactory: any ManagedProcessFactory = FoundationManagedProcessFactory(),
        listenerChecker: any LoopbackListenerChecking = SystemLoopbackListenerChecker(),
        initialSnapshot: RuntimeSnapshot = .stopped,
        gracefulTerminationTimeout: Duration = .seconds(5),
        forcedTerminationTimeout: Duration = .seconds(1),
        listenerVerificationAttempts: Int = 20,
        listenerVerificationInterval: Duration = .milliseconds(50),
        sleep: @escaping Sleep = { try await Task.sleep(for: $0) }
    ) {
        precondition(listenerVerificationAttempts > 0)
        self.configuration = configuration
        self.loopbackPort = loopbackPort
        self.processFactory = processFactory
        self.listenerChecker = listenerChecker
        self.snapshot = initialSnapshot
        self.gracefulTerminationTimeout = gracefulTerminationTimeout
        self.forcedTerminationTimeout = forcedTerminationTimeout
        self.listenerVerificationAttempts = listenerVerificationAttempts
        self.listenerVerificationInterval = listenerVerificationInterval
        self.sleep = sleep
    }

    public func start() async throws -> RuntimeSnapshot {
        try transition(to: .starting)
        do {
            let process = try processFactory.make(configuration)
            managedProcess = process
            let identity = try await process.launch()
            snapshot = RuntimeSnapshot(
                phase: .healthy,
                processIdentity: identity,
                loopbackPort: loopbackPort,
                restartCount: snapshot.restartCount,
                lastHealthResult: snapshot.lastHealthResult,
                diagnosticLogDirectory: configuration.standardOutputLog.deletingLastPathComponent(),
                lastError: nil
            )
            return snapshot
        } catch {
            fail(with: error)
            throw error
        }
    }

    public func stop() async throws -> RuntimeSnapshot {
        if snapshot.phase == .stopped { return snapshot }
        _ = try RuntimeState(phase: snapshot.phase).transitioning(to: .stopping)
        guard let process = managedProcess, let identity = snapshot.processIdentity else {
            let error = RuntimeStateError.shutdownIncomplete(
                processAlive: false,
                listenerAlive: await listenerChecker.isListening(on: loopbackPort)
            )
            fail(with: error)
            throw error
        }
        try transition(to: .stopping)

        do {
            switch await process.identityStatus(for: identity) {
            case .exited:
                break
            case let .mismatched(actual):
                throw RuntimeStateError.processIdentityMismatch(expected: identity, actual: actual)
            case .matching:
                _ = try await process.signal(.terminate, ifMatching: identity)
                let exitedGracefully = try await process.waitForExit(
                    matching: identity,
                    timeout: gracefulTerminationTimeout
                )
                if !exitedGracefully {
                    _ = try await process.signal(.kill, ifMatching: identity)
                    _ = try await process.waitForExit(
                        matching: identity,
                        timeout: forcedTerminationTimeout
                    )
                }
            }

            let processAlive: Bool
            switch await process.identityStatus(for: identity) {
            case .exited:
                processAlive = false
            case let .mismatched(actual):
                throw RuntimeStateError.processIdentityMismatch(expected: identity, actual: actual)
            case .matching:
                processAlive = true
            }
            let listenerAlive = await waitForListenerDisappearance()
            guard !processAlive, !listenerAlive else {
                throw RuntimeStateError.shutdownIncomplete(
                    processAlive: processAlive,
                    listenerAlive: listenerAlive
                )
            }

            managedProcess = nil
            snapshot = RuntimeSnapshot(
                phase: .stopped,
                processIdentity: nil,
                loopbackPort: nil,
                restartCount: snapshot.restartCount,
                lastHealthResult: snapshot.lastHealthResult,
                diagnosticLogDirectory: snapshot.diagnosticLogDirectory,
                lastError: nil
            )
            return snapshot
        } catch {
            fail(with: error)
            throw error
        }
    }

    public func status() async -> RuntimeSnapshot {
        let observedPhase = snapshot.phase
        guard observedPhase == .healthy || observedPhase == .degraded,
              let process = managedProcess,
              let identity = snapshot.processIdentity
        else {
            return snapshot
        }

        let identityStatus = await process.identityStatus(for: identity)
        guard snapshot.phase == observedPhase, snapshot.processIdentity == identity else {
            return snapshot
        }
        switch identityStatus {
        case .matching:
            break
        case .exited:
            fail(with: RuntimeStateError.processExitedUnexpectedly(identity))
        case let .mismatched(actual):
            fail(with: RuntimeStateError.processIdentityMismatch(expected: identity, actual: actual))
        }
        return snapshot
    }

    private func transition(to next: RuntimePhase) throws {
        let state = try RuntimeState(phase: snapshot.phase).transitioning(to: next)
        snapshot = RuntimeSnapshot(
            phase: state.phase,
            processIdentity: snapshot.processIdentity,
            loopbackPort: snapshot.loopbackPort,
            restartCount: snapshot.restartCount,
            lastHealthResult: snapshot.lastHealthResult,
            diagnosticLogDirectory: snapshot.diagnosticLogDirectory,
            lastError: snapshot.lastError
        )
    }

    private func waitForListenerDisappearance() async -> Bool {
        for attempt in 0..<listenerVerificationAttempts {
            if !(await listenerChecker.isListening(on: loopbackPort)) { return false }
            if attempt + 1 < listenerVerificationAttempts {
                try? await sleep(listenerVerificationInterval)
            }
        }
        return true
    }

    private func fail(with error: any Error) {
        snapshot = RuntimeSnapshot(
            phase: .failed,
            processIdentity: snapshot.processIdentity,
            loopbackPort: snapshot.loopbackPort ?? loopbackPort,
            restartCount: snapshot.restartCount,
            lastHealthResult: snapshot.lastHealthResult,
            diagnosticLogDirectory: snapshot.diagnosticLogDirectory
                ?? configuration.standardOutputLog.deletingLastPathComponent(),
            lastError: String(describing: error)
        )
    }
}
