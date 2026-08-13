import Foundation
import Testing
@testable import PalloRuntime

@Test func runtimeStateAcceptsOnlyDeclaredLifecycleTransitions() throws {
    // Break caught: the lifecycle silently skips a state or allows a stopped runtime to claim health.
    #expect(try RuntimeState(phase: .stopped).transitioning(to: .starting).phase == .starting)
    #expect(try RuntimeState(phase: .starting).transitioning(to: .healthy).phase == .healthy)
    #expect(try RuntimeState(phase: .healthy).transitioning(to: .stopping).phase == .stopping)
    #expect(try RuntimeState(phase: .stopping).transitioning(to: .stopped).phase == .stopped)

    #expect(throws: RuntimeStateError.invalidTransition(from: .stopped, to: .healthy)) {
        try RuntimeState(phase: .stopped).transitioning(to: .healthy)
    }
    #expect(throws: RuntimeStateError.invalidTransition(from: .starting, to: .starting)) {
        try RuntimeState(phase: .starting).transitioning(to: .starting)
    }
}

@Test func runtimeSnapshotRoundTripsStableProcessMetadata() throws {
    // Break caught: persisted status loses the start token needed to distinguish PID reuse.
    let identity = ManagedProcessIdentity(
        executablePath: "/opt/pallo/synapse_homeserver",
        launchTimestamp: Date(timeIntervalSince1970: 1_789_000_000.125),
        processIdentifier: 42,
        startIdentityToken: "42:1789000000:125000"
    )
    let snapshot = RuntimeSnapshot(
        phase: .healthy,
        processIdentity: identity,
        loopbackPort: 18_008,
        restartCount: 0,
        lastHealthResult: nil,
        diagnosticLogDirectory: URL(fileURLWithPath: "/tmp/pallo/logs"),
        lastError: nil
    )

    let encoded = try JSONEncoder().encode(snapshot)
    #expect(try JSONDecoder().decode(RuntimeSnapshot.self, from: encoded) == snapshot)
}

@Test func runtimeExitCodesRemainDistinctForLifecycleSafetyFailures() {
    // Break caught: CLI callers cannot distinguish invalid state, stale identity, and incomplete shutdown.
    #expect(RuntimeExitCode.success.rawValue == 0)
    #expect(RuntimeExitCode.invalidTransition.rawValue != RuntimeExitCode.processIdentityMismatch.rawValue)
    #expect(RuntimeExitCode.processIdentityMismatch.rawValue != RuntimeExitCode.shutdownIncomplete.rawValue)
    #expect(RuntimeExitCode.processLaunchFailed.rawValue != RuntimeExitCode.shutdownIncomplete.rawValue)
}
