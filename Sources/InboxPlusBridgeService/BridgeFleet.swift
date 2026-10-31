import Foundation
import InboxPlusRuntime

/// What a session needs from one bridge's supervisor.
protocol BridgeProcessSupervising: Sendable {
    func start() async throws -> RuntimeSnapshot
    func stop() async throws -> RuntimeSnapshot
}

extension SynapseSupervisor: BridgeProcessSupervising {}

/// The bridges one runtime session runs, kept in step with what the profile asks for.
///
/// Disconnecting or removing an account is a change the app makes to the profile while this
/// session owns the bridge processes; reconciling is how that change reaches the process.
///
/// Only bridges prepared before the session began are ever started. Synapse reads appservice
/// registrations once, at startup, so a bridge prepared since cannot work until the next session.
actor BridgeFleet {
    private let eligible: Set<PreparedBridge>
    private let wanted: @Sendable () throws -> [PreparedBridge]
    private let launch: @Sendable (PreparedBridge) throws -> any BridgeProcessSupervising
    private let onReady: @Sendable (PreparedBridge, RuntimeSnapshot) -> Void
    private let onStopped: @Sendable (PreparedBridge) -> Void
    private let onFailed: @Sendable (PreparedBridge, any Error) -> Void

    private var running: [PreparedBridge: any BridgeProcessSupervising] = [:]
    /// Not retried on every pass: disconnecting and reconnecting the account is the retry.
    private var failed: Set<PreparedBridge> = []

    init(
        eligible: [PreparedBridge],
        wanted: @escaping @Sendable () throws -> [PreparedBridge],
        launch: @escaping @Sendable (PreparedBridge) throws -> any BridgeProcessSupervising,
        onReady: @escaping @Sendable (PreparedBridge, RuntimeSnapshot) -> Void,
        onStopped: @escaping @Sendable (PreparedBridge) -> Void,
        onFailed: @escaping @Sendable (PreparedBridge, any Error) -> Void
    ) {
        self.eligible = Set(eligible)
        self.wanted = wanted
        self.launch = launch
        self.onReady = onReady
        self.onStopped = onStopped
        self.onFailed = onFailed
    }

    var runningBridgeIDs: Set<String> { Set(running.keys.map(\.bridgeID)) }

    /// Stops what is no longer wanted, then starts what is wanted and not running.
    ///
    /// A profile that cannot be read changes nothing: stopping every bridge over a read error would
    /// be as wrong as starting one the user disconnected.
    func reconcile() async {
        guard let wanted = try? Set(wanted()).intersection(eligible) else { return }
        for (record, supervisor) in running where !wanted.contains(record) {
            running[record] = nil
            do {
                _ = try await supervisor.stop()
                onStopped(record)
            } catch {
                onFailed(record, error)
            }
        }
        failed.formIntersection(wanted)
        for record in wanted.sorted(by: { $0.bridgeID < $1.bridgeID })
        where running[record] == nil && !failed.contains(record) {
            guard !Task.isCancelled else { return }
            do {
                let supervisor = try launch(record)
                let snapshot = try await supervisor.start()
                running[record] = supervisor
                onReady(record, snapshot)
            } catch {
                failed.insert(record)
                onFailed(record, error)
            }
        }
    }

    func stopAll() async {
        let stopping = running
        running.removeAll()
        for (record, supervisor) in stopping {
            do {
                _ = try await supervisor.stop()
                onStopped(record)
            } catch {
                onFailed(record, error)
            }
        }
    }
}
