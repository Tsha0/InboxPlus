import Foundation
import InboxPlusCore
import InboxPlusFeatures
import InboxPlusGateway
import InboxPlusRuntime

/// A gateway that brings the runtime up the first time it is actually used.
///
/// The window has to appear immediately, and a cold runtime takes tens of seconds — Synapse plus a
/// bridge process per network. Doing that work at launch would freeze the app before it drew
/// anything, so it happens behind the first `loadSnapshot()`, which the model already performs
/// asynchronously and already reports as a startup state.
///
/// Everything downstream is built only once the homeserver answers, because a Matrix client
/// constructed against a port nothing is listening on fails in ways that read as a bug in Inbox+.
actor DeferredRuntimeGateway: ConversationStartingGateway, MessageInteractionGateway {
    struct Connection: Sendable {
        let gateway: any MessagingGateway
        let disconnect: @Sendable () async -> Void
    }

    private let ensureRunning: @Sendable () async throws -> RuntimeProfileState
    private let restartRuntime: @Sendable () async throws -> Void
    private let build: @Sendable (RuntimeProfileState) async throws -> Connection

    private typealias Resolved = (state: RuntimeProfileState, connection: Connection)
    private var resolved: Resolved?
    private var resolving: Task<Resolved, any Error>?
    private var refreshing: Task<Void, any Error>?
    private var generation = 0

    init(
        ensureRunning: @escaping @Sendable () async throws -> RuntimeProfileState,
        restartRuntime: @escaping @Sendable () async throws -> Void,
        build: @escaping @Sendable (RuntimeProfileState) async throws -> Connection
    ) {
        self.ensureRunning = ensureRunning
        self.restartRuntime = restartRuntime
        self.build = build
    }

    // MARK: - MessagingGateway

    func loadSnapshot() async throws -> MessagingSnapshot {
        try await gateway().loadSnapshot()
    }

    func events() async -> AsyncStream<GatewayEvent> {
        // A failure here cannot be thrown, and an empty stream would silently mean "no messages
        // ever". The snapshot path reports the real error; this one waits for the gateway that
        // path resolves rather than inventing a second answer.
        guard let gateway = try? await gateway() else { return AsyncStream { $0.finish() } }
        return await gateway.events()
    }

    func loadRecentMessages(in route: ConversationRoute) async throws {
        try await gateway().loadRecentMessages(in: route)
    }

    func sendText(_ body: String, to route: ConversationRoute) async throws -> SendReceipt {
        try await gateway().sendText(body, to: route)
    }

    func send(_ attachment: OutgoingAttachment, to route: ConversationRoute) async throws -> SendReceipt {
        try await gateway().send(attachment, to: route)
    }

    func canStartConversation(accountID: String) async -> Bool {
        guard let source = try? await gateway() as? any ConversationStartingGateway else { return false }
        return await source.canStartConversation(accountID: accountID)
    }

    func startConversation(accountID: String, recipient: String) async throws -> StartedConversation {
        guard let source = try await gateway() as? any ConversationStartingGateway else {
            throw ConversationStartError.unsupported
        }
        return try await source.startConversation(accountID: accountID, recipient: recipient)
    }

    func markRead(_ route: ConversationRoute) async throws {
        try await gateway().markRead(route)
    }

    func sendText(_ body: String, to route: ConversationRoute, replyingTo messageID: String) async throws -> SendReceipt {
        try await interactions().sendText(body, to: route, replyingTo: messageID)
    }

    func send(
        _ attachment: OutgoingAttachment,
        to route: ConversationRoute,
        replyingTo messageID: String
    ) async throws -> SendReceipt {
        try await interactions().send(attachment, to: route, replyingTo: messageID)
    }

    func toggleReaction(_ key: String, to messageID: String, in route: ConversationRoute) async throws {
        try await interactions().toggleReaction(key, to: messageID, in: route)
    }

    private func interactions() async throws -> any MessageInteractionGateway {
        guard let source = try await gateway() as? any MessageInteractionGateway else {
            throw MessageInteractionError.unsupported
        }
        return source
    }

    // MARK: - Resolution

    func runtimeChanged() async throws -> Bool {
        let current = try await ensureRunning()
        guard let resolved else { return false }
        return resolved.state.snapshot.processIdentity != current.snapshot.processIdentity
            || resolved.state.snapshot.loopbackPort != current.snapshot.loopbackPort
            || resolved.state.serverName != current.serverName
    }

    func refreshRuntime(restartServices: Bool = true) async throws {
        if let refreshing { return try await refreshing.value }
        let previous = resolved
        let pending = resolving
        let task = Task { [restartRuntime] in
            let connection = try await pending?.value ?? previous
            await connection?.connection.disconnect()
            if restartServices { try await restartRuntime() }
        }
        generation += 1
        refreshing = task
        resolved = nil
        resolving = nil
        defer { refreshing = nil }
        try await task.value
    }

    private func gateway() async throws -> any MessagingGateway {
        if let refreshing { try await refreshing.value }
        if let resolved { return resolved.connection.gateway }
        if let resolving {
            let generation = generation
            let result = try await resolving.value
            guard generation == self.generation else { return try await gateway() }
            return result.connection.gateway
        }

        let task = Task<Resolved, any Error> { [ensureRunning, build] in
            let state = try await ensureRunning()
            return (state, try await build(state))
        }
        let generation = generation
        resolving = task

        do {
            let connection = try await task.value
            guard generation == self.generation else { return try await gateway() }
            resolved = connection
            resolving = nil
            return connection.connection.gateway
        } catch {
            // Cleared so a retry — the user pressing reload, or the next send — starts again rather
            // than replaying a stored failure forever.
            if generation == self.generation { resolving = nil }
            throw error
        }
    }
}
