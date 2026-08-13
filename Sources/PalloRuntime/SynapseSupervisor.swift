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
        snapshot = initialSnapshot
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
            if let failure = await process.lifecycleFailure() { throw failure }
            snapshot = RuntimeSnapshot(
                phase: .healthy,
                processIdentity: identity,
                loopbackPort: loopbackPort,
                restartCount: snapshot.restartCount,
                lastHealthResult: snapshot.lastHealthResult,
                diagnosticLogDirectory: configuration.logsDirectory,
                lastError: nil
            )
            return snapshot
        } catch {
            managedProcess = nil
            fail(with: error)
            throw error
        }
    }

    public func stop() async throws -> RuntimeSnapshot {
        if snapshot.phase == .stopped { return snapshot }
        _ = try RuntimeState(phase: snapshot.phase).transitioning(to: .stopping)

        do {
            guard let identity = snapshot.processIdentity else {
                let listenerPresence = await waitForListenerDisappearance()
                guard listenerPresence == .absent else {
                    throw RuntimeStateError.shutdownIncomplete(
                        processAlive: false,
                        listenerPresence: listenerPresence
                    )
                }
                managedProcess = nil
                return stoppedSnapshot()
            }
            let process = try rehydratedProcessIfNeeded(identity: identity)
            try transition(to: .stopping)

            switch await process.identityStatus(for: identity) {
            case .exited:
                if await process.ownership(for: identity) == .directChild {
                    _ = try await process.waitForExit(matching: identity, timeout: .zero)
                }
            case let .mismatched(actual):
                throw RuntimeStateError.processIdentityMismatch(expected: identity, actual: actual)
            case let .indeterminate(failure):
                throw failure
            case .matching:
                guard await process.ownership(for: identity) == .directChild else {
                    throw RuntimeStateError.uncontrolledProcess(identity)
                }
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
            case let .indeterminate(failure):
                throw failure
            case .matching:
                processAlive = true
            }
            let listenerPresence = await waitForListenerDisappearance()
            guard !processAlive, listenerPresence == .absent else {
                throw RuntimeStateError.shutdownIncomplete(
                    processAlive: processAlive,
                    listenerPresence: listenerPresence
                )
            }

            managedProcess = nil
            return stoppedSnapshot()
        } catch {
            fail(with: error)
            throw error
        }
    }

    public func status() async -> RuntimeSnapshot {
        let observedPhase = snapshot.phase
        guard observedPhase == .healthy || observedPhase == .degraded,
              let identity = snapshot.processIdentity
        else {
            return snapshot
        }

        let process: any ManagedProcess
        do {
            process = try rehydratedProcessIfNeeded(identity: identity)
        } catch {
            fail(with: error)
            return snapshot
        }

        if let failure = await process.lifecycleFailure() {
            await cleanUpAfterLifecycleFailure(process: process, identity: identity, failure: failure)
            return snapshot
        }
        let identityStatus = await process.identityStatus(for: identity)
        guard snapshot.phase == observedPhase, snapshot.processIdentity == identity else {
            return snapshot
        }
        switch identityStatus {
        case .matching:
            if await process.ownership(for: identity) == .observedOnly {
                snapshot = RuntimeSnapshot(
                    phase: .degraded,
                    processIdentity: identity,
                    loopbackPort: snapshot.loopbackPort,
                    restartCount: snapshot.restartCount,
                    lastHealthResult: snapshot.lastHealthResult,
                    diagnosticLogDirectory: snapshot.diagnosticLogDirectory,
                    lastError: String(describing: RuntimeStateError.uncontrolledProcess(identity))
                )
            }
        case .exited:
            fail(with: RuntimeStateError.processExitedUnexpectedly(identity))
        case let .mismatched(actual):
            fail(with: RuntimeStateError.processIdentityMismatch(expected: identity, actual: actual))
        case let .indeterminate(failure):
            fail(with: failure)
        }
        return snapshot
    }

    private func rehydratedProcessIfNeeded(
        identity: ManagedProcessIdentity
    ) throws -> any ManagedProcess {
        if let managedProcess { return managedProcess }
        let process = try processFactory.rehydrate(configuration, expectedIdentity: identity)
        managedProcess = process
        return process
    }

    private func cleanUpAfterLifecycleFailure(
        process: any ManagedProcess,
        identity: ManagedProcessIdentity,
        failure: ManagedProcessError
    ) async {
        if await process.ownership(for: identity) == .directChild {
            do {
                let signalled = try await process.signal(.kill, ifMatching: identity)
                if signalled {
                    _ = try await process.waitForExit(matching: identity, timeout: forcedTerminationTimeout)
                }
            } catch {
                fail(with: error)
                return
            }
        }
        fail(with: failure)
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

    private func waitForListenerDisappearance() async -> LoopbackListenerPresence {
        var lastPresence: LoopbackListenerPresence = .indeterminate(.timeout)
        for attempt in 0..<listenerVerificationAttempts {
            lastPresence = await listenerChecker.presence(on: loopbackPort)
            if lastPresence == .absent { return .absent }
            if attempt + 1 < listenerVerificationAttempts {
                try? await sleep(listenerVerificationInterval)
            }
        }
        return lastPresence
    }

    private func stoppedSnapshot() -> RuntimeSnapshot {
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
    }

    private func fail(with error: any Error) {
        snapshot = RuntimeSnapshot(
            phase: .failed,
            processIdentity: snapshot.processIdentity,
            loopbackPort: snapshot.loopbackPort ?? loopbackPort,
            restartCount: snapshot.restartCount,
            lastHealthResult: snapshot.lastHealthResult,
            diagnosticLogDirectory: snapshot.diagnosticLogDirectory ?? configuration.logsDirectory,
            lastError: String(describing: error)
        )
    }
}
