import Foundation

public actor SynapseSupervisor {
    public typealias Sleep = @Sendable (Duration) async throws -> Void

    private struct OperationToken: Equatable {
        let value: UInt64
    }

    private struct ObservationContext {
        let stateGeneration: UInt64
        let processGeneration: UInt64
        let phase: RuntimePhase
        let identity: ManagedProcessIdentity
    }

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
    private let snapshotValidationFailure: RuntimeStateError?
    private var stateGeneration: UInt64 = 0
    private var processGeneration: UInt64 = 0
    private var nextOperationValue: UInt64 = 0
    private var activeOperation: OperationToken?

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
        let validationFailure = initialSnapshot.structuralValidationError
        snapshotValidationFailure = validationFailure
        if let validationFailure {
            snapshot = RuntimeSnapshot(
                uncheckedPhase: .failed,
                processIdentity: nil,
                loopbackPort: nil,
                restartCount: max(0, initialSnapshot.restartCount),
                lastHealthResult: initialSnapshot.lastHealthResult,
                diagnosticLogDirectory: initialSnapshot.diagnosticLogDirectory ?? configuration.logsDirectory,
                lastError: String(describing: validationFailure)
            )
        } else {
            snapshot = initialSnapshot
        }
        self.gracefulTerminationTimeout = gracefulTerminationTimeout
        self.forcedTerminationTimeout = forcedTerminationTimeout
        self.listenerVerificationAttempts = listenerVerificationAttempts
        self.listenerVerificationInterval = listenerVerificationInterval
        self.sleep = sleep
    }

    public func start() async throws -> RuntimeSnapshot {
        if let snapshotValidationFailure { throw snapshotValidationFailure }
        let operation = try beginOperation(transitioningTo: .starting)
        defer { endOperation(operation) }
        do {
            let process = try processFactory.make(configuration)
            replaceManagedProcess(with: process)
            let identity = try await process.launch()
            try requireCurrent(operation)
            let lifecycleFailure = await process.lifecycleFailure()
            try requireCurrent(operation)
            if let lifecycleFailure { throw lifecycleFailure }
            updateSnapshot(RuntimeSnapshot(
                uncheckedPhase: .healthy,
                processIdentity: identity,
                loopbackPort: loopbackPort,
                restartCount: snapshot.restartCount,
                lastHealthResult: snapshot.lastHealthResult,
                diagnosticLogDirectory: configuration.logsDirectory,
                lastError: nil
            ))
            return snapshot
        } catch {
            if isCurrent(operation) {
                replaceManagedProcess(with: nil)
                fail(with: error)
            }
            throw error
        }
    }

    public func stop() async throws -> RuntimeSnapshot {
        if let snapshotValidationFailure { throw snapshotValidationFailure }
        if snapshot.phase == .stopped { return snapshot }
        if snapshot.phase == .failed || snapshot.phase == .recovering {
            return try await stopWithoutRuntimeAuthority()
        }
        let operation = try beginOperation(transitioningTo: .stopping)
        defer { endOperation(operation) }

        do {
            guard let identity = snapshot.processIdentity else {
                let listenerPresence = await waitForListenerDisappearance()
                try requireCurrent(operation)
                guard listenerPresence == .absent else {
                    throw RuntimeStateError.shutdownIncomplete(
                        processAlive: false,
                        listenerPresence: listenerPresence
                    )
                }
                replaceManagedProcess(with: nil)
                return stoppedSnapshot()
            }
            let process = try rehydratedProcessIfNeeded(identity: identity)

            let initialIdentityStatus = await process.identityStatus(for: identity)
            try requireCurrent(operation)
            switch initialIdentityStatus {
            case .exited:
                let ownership = await process.ownership(for: identity)
                try requireCurrent(operation)
                if ownership == .directChild {
                    _ = try await process.waitForExit(matching: identity, timeout: .zero)
                    try requireCurrent(operation)
                }
            case let .mismatched(actual):
                throw RuntimeStateError.processIdentityMismatch(expected: identity, actual: actual)
            case let .indeterminate(failure):
                throw failure
            case .matching:
                let ownership = await process.ownership(for: identity)
                try requireCurrent(operation)
                guard ownership == .directChild else {
                    throw RuntimeStateError.uncontrolledProcess(identity)
                }
                _ = try await process.signal(.terminate, ifMatching: identity)
                try requireCurrent(operation)
                let exitedGracefully = try await process.waitForExit(
                    matching: identity,
                    timeout: gracefulTerminationTimeout
                )
                try requireCurrent(operation)
                if !exitedGracefully {
                    _ = try await process.signal(.kill, ifMatching: identity)
                    try requireCurrent(operation)
                    _ = try await process.waitForExit(
                        matching: identity,
                        timeout: forcedTerminationTimeout
                    )
                    try requireCurrent(operation)
                }
            }

            let processAlive: Bool
            let finalIdentityStatus = await process.identityStatus(for: identity)
            try requireCurrent(operation)
            switch finalIdentityStatus {
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
            try requireCurrent(operation)
            guard !processAlive, listenerPresence == .absent else {
                throw RuntimeStateError.shutdownIncomplete(
                    processAlive: processAlive,
                    listenerPresence: listenerPresence
                )
            }

            replaceManagedProcess(with: nil)
            return stoppedSnapshot()
        } catch {
            if isCurrent(operation) { fail(with: error) }
            throw error
        }
    }

    public func status() async -> RuntimeSnapshot {
        if snapshotValidationFailure != nil || activeOperation != nil { return snapshot }
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
        let observation = observationContext(phase: observedPhase, identity: identity)

        let lifecycleFailure = await process.lifecycleFailure()
        guard observationIsCurrent(observation) else { return snapshot }
        if let lifecycleFailure {
            await cleanUpAfterLifecycleFailure(
                process: process,
                identity: identity,
                failure: lifecycleFailure,
                observation: observation
            )
            return snapshot
        }
        let identityStatus = await process.identityStatus(for: identity)
        guard observationIsCurrent(observation) else { return snapshot }
        switch identityStatus {
        case .matching:
            let ownership = await process.ownership(for: identity)
            guard observationIsCurrent(observation) else { return snapshot }
            if ownership == .observedOnly {
                updateSnapshot(RuntimeSnapshot(
                    uncheckedPhase: .degraded,
                    processIdentity: identity,
                    loopbackPort: snapshot.loopbackPort,
                    restartCount: snapshot.restartCount,
                    lastHealthResult: snapshot.lastHealthResult,
                    diagnosticLogDirectory: snapshot.diagnosticLogDirectory,
                    lastError: String(describing: RuntimeStateError.uncontrolledProcess(identity))
                ))
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
        replaceManagedProcess(with: process)
        return process
    }

    private func cleanUpAfterLifecycleFailure(
        process: any ManagedProcess,
        identity: ManagedProcessIdentity,
        failure: ManagedProcessError,
        observation: ObservationContext
    ) async {
        let ownership = await process.ownership(for: identity)
        guard observationIsCurrent(observation),
              let operation = beginObservationOperation(observation)
        else {
            return
        }
        defer { endOperation(operation) }
        if ownership == .directChild {
            do {
                let signalled = try await process.signal(.kill, ifMatching: identity)
                guard isCurrent(operation) else { return }
                if signalled {
                    _ = try await process.waitForExit(matching: identity, timeout: forcedTerminationTimeout)
                    guard isCurrent(operation) else { return }
                }
            } catch {
                if isCurrent(operation) { fail(with: error) }
                return
            }
        }
        if isCurrent(operation) { fail(with: failure) }
    }

    private func transition(to next: RuntimePhase) throws {
        let state = try RuntimeState(phase: snapshot.phase).transitioning(to: next)
        updateSnapshot(RuntimeSnapshot(
            uncheckedPhase: state.phase,
            processIdentity: snapshot.processIdentity,
            loopbackPort: snapshot.loopbackPort,
            restartCount: snapshot.restartCount,
            lastHealthResult: snapshot.lastHealthResult,
            diagnosticLogDirectory: snapshot.diagnosticLogDirectory,
            lastError: snapshot.lastError
        ))
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

    private func stopWithoutRuntimeAuthority() async throws -> RuntimeSnapshot {
        let operation = try beginOperationWithoutPublishingTransition(validating: .stopping)
        defer { endOperation(operation) }
        do {
            let listenerPresence = await waitForListenerDisappearance()
            try requireCurrent(operation)
            guard listenerPresence == .absent else {
                throw RuntimeStateError.shutdownIncomplete(
                    processAlive: false,
                    listenerPresence: listenerPresence
                )
            }
            replaceManagedProcess(with: nil)
            return stoppedSnapshot()
        } catch {
            if isCurrent(operation) { fail(with: error) }
            throw error
        }
    }

    private func stoppedSnapshot() -> RuntimeSnapshot {
        updateSnapshot(RuntimeSnapshot(
            uncheckedPhase: .stopped,
            processIdentity: nil,
            loopbackPort: nil,
            restartCount: snapshot.restartCount,
            lastHealthResult: snapshot.lastHealthResult,
            diagnosticLogDirectory: snapshot.diagnosticLogDirectory,
            lastError: nil
        ))
        return snapshot
    }

    private func fail(with error: any Error) {
        replaceManagedProcess(with: nil)
        updateSnapshot(RuntimeSnapshot(
            uncheckedPhase: .failed,
            processIdentity: nil,
            loopbackPort: nil,
            restartCount: snapshot.restartCount,
            lastHealthResult: snapshot.lastHealthResult,
            diagnosticLogDirectory: snapshot.diagnosticLogDirectory ?? configuration.logsDirectory,
            lastError: String(describing: error)
        ))
    }

    private func beginOperation(transitioningTo phase: RuntimePhase) throws -> OperationToken {
        guard activeOperation == nil else {
            throw RuntimeStateError.invalidTransition(from: snapshot.phase, to: phase)
        }
        nextOperationValue &+= 1
        let operation = OperationToken(value: nextOperationValue)
        activeOperation = operation
        do {
            try transition(to: phase)
            return operation
        } catch {
            activeOperation = nil
            throw error
        }
    }

    private func beginObservationOperation(_ observation: ObservationContext) -> OperationToken? {
        guard activeOperation == nil, observationIsCurrent(observation) else { return nil }
        nextOperationValue &+= 1
        let operation = OperationToken(value: nextOperationValue)
        activeOperation = operation
        return operation
    }

    private func beginOperationWithoutPublishingTransition(
        validating phase: RuntimePhase
    ) throws -> OperationToken {
        guard activeOperation == nil else {
            throw RuntimeStateError.invalidTransition(from: snapshot.phase, to: phase)
        }
        _ = try RuntimeState(phase: snapshot.phase).transitioning(to: phase)
        nextOperationValue &+= 1
        let operation = OperationToken(value: nextOperationValue)
        activeOperation = operation
        return operation
    }

    private func endOperation(_ operation: OperationToken) {
        if activeOperation == operation { activeOperation = nil }
    }

    private func isCurrent(_ operation: OperationToken) -> Bool {
        activeOperation == operation
    }

    private func requireCurrent(_ operation: OperationToken) throws {
        guard isCurrent(operation) else { throw CancellationError() }
    }

    private func observationContext(
        phase: RuntimePhase,
        identity: ManagedProcessIdentity
    ) -> ObservationContext {
        ObservationContext(
            stateGeneration: stateGeneration,
            processGeneration: processGeneration,
            phase: phase,
            identity: identity
        )
    }

    private func observationIsCurrent(_ observation: ObservationContext) -> Bool {
        activeOperation == nil
            && stateGeneration == observation.stateGeneration
            && processGeneration == observation.processGeneration
            && snapshot.phase == observation.phase
            && snapshot.processIdentity == observation.identity
    }

    private func updateSnapshot(_ nextSnapshot: RuntimeSnapshot) {
        precondition(nextSnapshot.structuralValidationError == nil)
        snapshot = nextSnapshot
        stateGeneration &+= 1
    }

    private func replaceManagedProcess(with process: (any ManagedProcess)?) {
        managedProcess = process
        processGeneration &+= 1
    }
}
