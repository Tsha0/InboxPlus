import Foundation
import InboxPlusBridge
import InboxPlusBridgeService
import InboxPlusCore
import InboxPlusFeatures
import InboxPlusIMessage
import InboxPlusMatrix
import InboxPlusRuntime

protocol AccountRoomForgetting: Sendable {
    func forgetRooms(ofAccount accountID: String) async throws
}

extension MatrixMessagingGateway: AccountRoomForgetting {}

protocol PollingMessageSource: Sendable {
    func pausePolling() async
    func resumePolling() async
}

extension IMessageGateway: PollingMessageSource {}

/// The sources the runtime built, once it has built them.
///
/// The gateway is assembled behind the first snapshot, long after the model was handed its
/// lifecycle, so account changes find the live Matrix and iMessage sources through this.
final class LiveSources: @unchecked Sendable {
    private let lock = NSLock()
    private var rooms: (any AccountRoomForgetting)?
    private var messages: (any PollingMessageSource)?

    var matrix: (any AccountRoomForgetting)? {
        get { lock.withLock { rooms } }
        set { lock.withLock { rooms = newValue } }
    }

    var iMessage: (any PollingMessageSource)? {
        get { lock.withLock { messages } }
        set { lock.withLock { messages = newValue } }
    }
}

enum AccountLifecycleError: Error, Equatable, CustomStringConvertible, LocalizedError {
    case notManaged(String)
    case runtimeNotReady
    case bridgeStillRunning(String)
    case bridgeDidNotStart(String)

    var description: String {
        switch self {
        case let .notManaged(name):
            "Inbox+ has no bridge for \(name) in this profile."
        case .runtimeNotReady:
            "Inbox+ is still starting. Try again once your conversations have loaded."
        case let .bridgeStillRunning(name):
            "The \(name) bridge did not stop. Quit and reopen Inbox+, then try again."
        case let .bridgeDidNotStart(name):
            "The \(name) bridge did not start. Quit and reopen Inbox+, then try again."
        }
    }

    var errorDescription: String? { description }
}

/// Disconnects, reconnects and removes accounts in one runtime profile.
///
/// The bridge processes belong to the runtime session, not to the app, so nothing here signals a
/// process. A change is recorded in the profile, the session stops or starts the bridge to match,
/// and this waits until the bridge's provisioning API agrees before reporting success.
actor ProfileAccountLifecycle: AccountLifecycle {
    private let paths: RuntimePaths
    private let sources: LiveSources
    private let transport: any SynapseHTTPTransport
    private let stopTimeout: Duration
    private let startTimeout: Duration
    private let pollInterval: Duration

    init(
        paths: RuntimePaths,
        sources: LiveSources,
        transport: any SynapseHTTPTransport = URLSessionSynapseHTTPTransport(),
        // A session reconciles every second but can be busy starting another bridge, which may
        // take its full sixty-second startup allowance.
        stopTimeout: Duration = .seconds(90),
        startTimeout: Duration = .seconds(90),
        pollInterval: Duration = .milliseconds(500)
    ) {
        self.paths = paths
        self.sources = sources
        self.transport = transport
        self.stopTimeout = stopTimeout
        self.startTimeout = startTimeout
        self.pollInterval = pollInterval
    }

    private var disconnected: DisconnectedAccountStore { DisconnectedAccountStore(paths: paths) }
    private var runtime: BridgeRuntime { BridgeRuntime(paths: paths) }

    func disconnectedAccountIDs() throws -> Set<String> {
        try disconnected.load()
    }

    func disconnect(_ account: ConnectedAccount) async throws {
        guard account.id != IMessageGateway.accountID else {
            try disconnected.insert(account.id)
            await sources.iMessage?.pausePolling()
            return
        }
        let bridge = try provisioning(for: account)
        try disconnected.insert(account.id)
        guard await wait(for: bridge, running: false, within: stopTimeout) else {
            try disconnected.remove(account.id)
            throw AccountLifecycleError.bridgeStillRunning(account.displayName)
        }
    }

    func reconnect(_ account: ConnectedAccount) async throws -> AccountReconnection {
        guard account.id != IMessageGateway.accountID else {
            try disconnected.remove(account.id)
            guard let iMessage = sources.iMessage else { return .onNextLaunch }
            await iMessage.resumePolling()
            return .reconnected
        }
        let bridge = try provisioning(for: account)
        try disconnected.remove(account.id)
        guard await wait(for: bridge, running: true, within: startTimeout) else {
            try disconnected.insert(account.id)
            throw AccountLifecycleError.bridgeDidNotStart(account.displayName)
        }
        return .reconnected
    }

    /// Signs out, stops the bridge, leaves its rooms, then deletes its files — in that order.
    ///
    /// Signing out needs the bridge running, and leaving a portal needs it stopped, or the bridge
    /// could carry the leave to the network. Each step can be retried: a removal that fails part
    /// way leaves the bridge disconnected rather than half deleted and still running.
    func remove(_ account: ConnectedAccount) async throws -> AccountRemoval {
        guard let descriptor = BridgeCatalog.all.first(where: { $0.id == account.id }),
              descriptor.runtimeKind == .goBinary
        else { throw AccountLifecycleError.notManaged(account.displayName) }
        guard let matrix = sources.matrix else { throw AccountLifecycleError.runtimeNotReady }

        var removal = AccountRemoval()
        if try runtime.prepared().contains(where: { $0.bridgeID == account.id }) {
            let bridge = try provisioning(for: account)
            if let failure = await signOut(account, through: bridge) {
                removal.unfinished.append(failure)
            }
            try disconnected.insert(account.id)
            guard await wait(for: bridge, running: false, within: stopTimeout) else {
                throw AccountLifecycleError.bridgeStillRunning(account.displayName)
            }
        }
        try await matrix.forgetRooms(ofAccount: account.id)
        try runtime.remove(descriptor)
        try disconnected.remove(account.id)
        return removal
    }

    /// Ends the session on the network itself, starting a disconnected bridge to do it.
    ///
    /// Returns what went wrong rather than throwing: the saved login is deleted with the bridge
    /// either way, so a failed sign-out is something to tell the user, not a reason to keep it.
    private func signOut(
        _ account: ConnectedAccount,
        through bridge: BridgeProvisioningClient
    ) async -> String? {
        let reason: String
        do {
            if try disconnected.load().contains(account.id) {
                try disconnected.remove(account.id)
                guard await wait(for: bridge, running: true, within: startTimeout) else {
                    throw AccountLifecycleError.bridgeDidNotStart(account.displayName)
                }
            }
            try await bridge.logOutEverywhere()
            return nil
        } catch AccountLifecycleError.bridgeDidNotStart {
            reason = "its bridge did not start"
        } catch {
            reason = String(describing: error)
        }
        return """
        Inbox+ could not sign out of \(account.displayName) (\(reason)). Its saved login is \
        deleted, but \(account.displayName) may still list Inbox+ as a signed-in device until you \
        remove it there.
        """
    }

    private func provisioning(for account: ConnectedAccount) throws -> BridgeProvisioningClient {
        guard let record = try runtime.prepared().first(where: { $0.bridgeID == account.id }) else {
            throw AccountLifecycleError.notManaged(account.displayName)
        }
        return try BridgeProvisioningClient(
            baseURL: record.provisioningBaseURL,
            provisioningToken: record.provisioningSecret,
            userID: record.ownerUserID,
            transport: transport
        )
    }

    private func wait(
        for bridge: BridgeProvisioningClient,
        running expected: Bool,
        within timeout: Duration
    ) async -> Bool {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while await bridge.isRunning() != expected {
            guard ContinuousClock.now < deadline else { return false }
            try? await Task.sleep(for: pollInterval)
        }
        return true
    }
}
