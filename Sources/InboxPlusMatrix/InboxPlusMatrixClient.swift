import Foundation
import MatrixRustSDK
import InboxPlusRuntime

public enum InboxPlusMatrixClientError: Error, Equatable, Sendable, CustomStringConvertible {
    case notConnected

    public var description: String {
        switch self {
        case .notConnected:
            "the Matrix client is not connected"
        }
    }
}

/// Owns the Matrix Rust SDK client for Inbox+'s single local account.
///
/// Connecting prefers a restored session so the encrypted store and device identity survive
/// restarts; it only registers and logs in when there is nothing to restore.
public actor InboxPlusMatrixClient {
    public let homeserverURL: URL
    private let store: MatrixClientStore
    private let provisioner: MatrixAccountProvisioner
    private let buildClient: @Sendable () async throws -> Client

    private var connectedClient: Client?
    private var syncService: SyncService?

    public init(
        homeserverURL: URL,
        store: MatrixClientStore,
        provisioner: MatrixAccountProvisioner,
        buildClient: (@Sendable () async throws -> Client)? = nil
    ) {
        self.homeserverURL = homeserverURL
        self.store = store
        self.provisioner = provisioner
        self.buildClient = buildClient ?? {
            try await store.makeClientBuilder(homeserverURL: homeserverURL).build()
        }
    }

    /// Restores a saved session, or registers and logs in when there is none.
    @discardableResult
    public func connect() async throws -> PersistedSession {
        if connectedClient != nil, let saved = try store.loadSession() {
            return saved
        }

        let client = try await buildClient()

        if let saved = try store.loadSession() {
            do {
                try await client.restoreSession(session: saved.session)
                connectedClient = client
                return saved
            } catch {
                // A rejected session means the server no longer honours the token — for example
                // after a profile restore. Fall through to a fresh login rather than dying.
                try store.clearSession()
            }
        }

        let credentials = try await provisioner.ensureRegistered()
        try await client.login(
            username: credentials.localpart,
            password: credentials.password,
            initialDeviceName: "Inbox+",
            deviceId: nil
        )
        let session = PersistedSession(try client.session())
        try store.saveSession(session)
        connectedClient = client
        return session
    }

    public func requireClient() throws -> Client {
        guard let connectedClient else { throw InboxPlusMatrixClientError.notConnected }
        return connectedClient
    }

    /// Starts the SDK sync loop. Idempotent.
    public func startSync() async throws {
        guard syncService == nil else { return }
        let service = try await requireClient().syncService().finish()
        await service.start()
        syncService = service
    }

    public func stopSync() async {
        guard let syncService else { return }
        await syncService.stop()
        self.syncService = nil
    }

    public func disconnect() async {
        await stopSync()
        connectedClient = nil
    }
}
