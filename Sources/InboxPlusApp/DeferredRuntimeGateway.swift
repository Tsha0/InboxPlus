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
actor DeferredRuntimeGateway: MessagingGateway {
    private let ensureRunning: @Sendable () async throws -> RuntimeProfileState
    private let build: @Sendable (RuntimeProfileState) async throws -> any MessagingGateway

    private var resolved: (any MessagingGateway)?
    private var resolving: Task<any MessagingGateway, any Error>?
    private var stopping: Task<Void, Never>?
    private var generation = 0

    init(
        paths: RuntimePaths,
        profileName: String,
        build: @escaping @Sendable (RuntimeProfileState) async throws -> any MessagingGateway,
        ensureRunning: (@Sendable () async throws -> RuntimeProfileState)? = nil
    ) {
        self.ensureRunning = ensureRunning ?? {
            try await ManagedRuntime.shared.ensureRunning(
                paths: paths,
                profileName: profileName,
                progress: { message in
                    FileHandle.standardError.write(Data("Inbox+: \(message)\n".utf8))
                }
            )
        }
        self.build = build
    }

    deinit { resolving?.cancel() }

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

    func sendText(_ body: String, to route: ConversationRoute) async throws -> SendReceipt {
        try await gateway().sendText(body, to: route)
    }

    func send(_ attachment: OutgoingAttachment, to route: ConversationRoute) async throws -> SendReceipt {
        try await gateway().send(attachment, to: route)
    }

    func stop() async {
        if let stopping { return await stopping.value }
        generation += 1
        let pending = resolving
        pending?.cancel()
        resolving = nil
        let gateway = resolved
        resolved = nil
        let task = Task {
            if let pending, case let .success(built) = await pending.result { await built.stop() }
            await gateway?.stop()
        }
        stopping = task
        await task.value
        stopping = nil
    }

    // MARK: - Resolution

    /// Starts the runtime once, however many callers arrive at the same moment.
    private func gateway() async throws -> any MessagingGateway {
        try Task.checkCancellation()
        if let stopping { await stopping.value }
        try Task.checkCancellation()
        if let resolved { return resolved }
        if let resolving {
            let currentGeneration = generation
            let gateway = try await resolving.value
            try Task.checkCancellation()
            guard generation == currentGeneration else { throw CancellationError() }
            return gateway
        }

        let currentGeneration = generation
        let task = Task<any MessagingGateway, any Error> { [ensureRunning, build] in
            let state = try await ensureRunning()
            try Task.checkCancellation()
            let gateway = try await build(state)
            if Task.isCancelled {
                await gateway.stop()
                throw CancellationError()
            }
            return gateway
        }
        resolving = task

        do {
            let gateway = try await task.value
            guard generation == currentGeneration else {
                await gateway.stop()
                throw CancellationError()
            }
            resolved = gateway
            if generation == currentGeneration { resolving = nil }
            try Task.checkCancellation()
            return gateway
        } catch {
            // Cleared so a retry — the user pressing reload, or the next send — starts again rather
            // than replaying a stored failure forever.
            if generation == currentGeneration { resolving = nil }
            throw error
        }
    }
}
