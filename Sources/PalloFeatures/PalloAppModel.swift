import Foundation
import Observation
import PalloCore
import PalloGateway

public enum DetailSelection: Equatable, Sendable {
    case empty
    case personSummary(String)
    case conversation(ConversationRoute)
}

public enum ServiceHealth: Equatable, Sendable {
    case starting
    case healthy
    case needsAttention(String)
}

public extension ServiceHealth {
    var menuBarTitle: String {
        switch self {
        case .starting: "Pallo is starting"
        case .healthy: "Pallo is running"
        case .needsAttention: "Pallo needs attention"
        }
    }

    var symbolName: String {
        switch self {
        case .starting: "ellipsis.circle"
        case .healthy: "checkmark.circle.fill"
        case .needsAttention: "exclamationmark.triangle.fill"
        }
    }
}

public enum PalloAppModelError: Error, Equatable {
    case missingOpenConversation
}

public struct DraftSubmission: Sendable {
    public let body: String
    public let route: ConversationRoute
    fileprivate let draftRevision: UInt64
    fileprivate let routeGeneration: UInt64

    fileprivate init(
        body: String,
        route: ConversationRoute,
        draftRevision: UInt64,
        routeGeneration: UInt64
    ) {
        self.body = body
        self.route = route
        self.draftRevision = draftRevision
        self.routeGeneration = routeGeneration
    }
}

private final class StartupWaiterCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }

    func isCancelled() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }
}

private struct StartupWaiter {
    let startupID: UUID
    let cancellation: StartupWaiterCancellation
    let continuation: CheckedContinuation<Void, any Error>
}

@MainActor
@Observable
public final class PalloAppModel {
    public private(set) var accounts: [ConnectedAccount] = []
    public private(set) var identities: [RemoteIdentity] = []
    public private(set) var conversations: [RemoteConversation] = []
    public private(set) var messagesByRoute: [ConversationRoute: [Message]] = [:]
    public private(set) var inboxItems: [InboxItem] = []
    public private(set) var detailSelection: DetailSelection = .empty
    public private(set) var health: ServiceHealth = .starting
    public var draft = "" {
        didSet { draftRevision &+= 1 }
    }

    public var openRoute: ConversationRoute? {
        guard case let .conversation(route) = detailSelection else { return nil }
        return route
    }

    public var healthBannerMessage: String? {
        guard case let .needsAttention(message) = health else { return nil }
        return message
    }

    private let gateway: any MessagingGateway
    private var directory: ContactDirectory
    private var draftRevision: UInt64 = 0
    private var disconnectedAccountIDs: Set<String> = []
    private var sendFailuresByRoute: [ConversationRoute: String] = [:]
    private var latestSendGenerationByRoute: [ConversationRoute: UInt64] = [:]
    private var startupID: UUID?
    private var startupTask: Task<Void, Never>?
    private var startupWaiters: [UUID: StartupWaiter] = [:]
    private var eventTask: Task<Void, Never>?
    private var eventTaskID: UUID?
    private var bufferingEventTaskID: UUID?
    private var bufferedStartupEvents: [GatewayEvent] = []

    public init(gateway: any MessagingGateway, directory: ContactDirectory = .init()) {
        self.gateway = gateway
        self.directory = directory
    }

    public func start() async throws {
        if eventTask != nil, startupTask == nil {
            return
        }
        let id = startupID ?? beginStartup()
        try await waitForStartup(id: id)
    }

    public func stop() {
        let id = startupID
        startupID = nil
        startupTask?.cancel()
        startupTask = nil
        if let id {
            cancelStartup(id: id)
        }
        resumeStartupWaiters(throwing: CancellationError(), respectingCallerCancellation: false)
        if id == nil {
            eventTask?.cancel()
            eventTask = nil
            eventTaskID = nil
        }
    }

    public func reportStartupFailure(_ error: any Error) {
        health = .needsAttention("Pallo could not start: \(error.localizedDescription)")
    }

    isolated deinit {
        startupTask?.cancel()
        eventTask?.cancel()
    }

    public func selectInboxItem(_ item: InboxItem) {
        switch item.id {
        case let .person(id):
            detailSelection = .personSummary(id)
        case let .conversation(route):
            detailSelection = .conversation(route)
        }
    }

    public func openConversation(_ route: ConversationRoute) {
        detailSelection = .conversation(route)
    }

    public func captureDraft(to route: ConversationRoute) -> DraftSubmission {
        let previousGeneration = latestSendGenerationByRoute[route, default: 0]
        precondition(previousGeneration < UInt64.max, "Send generation exhausted")
        let generation = previousGeneration + 1
        latestSendGenerationByRoute[route] = generation
        return DraftSubmission(
            body: draft,
            route: route,
            draftRevision: draftRevision,
            routeGeneration: generation
        )
    }

    public func sendDraft(_ submission: DraftSubmission) async throws {
        let body = submission.body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        _ = try await gateway.sendText(body, to: submission.route)
        guard isLatest(submission) else { return }
        sendFailuresByRoute[submission.route] = nil
        if draftRevision == submission.draftRevision {
            draft = ""
        }
    }

    public func reportSendFailure(_ error: any Error, for submission: DraftSubmission) {
        guard isLatest(submission) else { return }
        sendFailuresByRoute[submission.route] = error.localizedDescription
    }

    public func sendFailure(for route: ConversationRoute) -> String? {
        sendFailuresByRoute[route]
    }

    private func isLatest(_ submission: DraftSubmission) -> Bool {
        latestSendGenerationByRoute[submission.route] == submission.routeGeneration
    }

    public func summaries(for personID: String) -> [ConversationSummary] {
        inboxItems.first { $0.id == .person(personID) }?.conversationSummaries ?? []
    }

    public var people: [PalloPerson] {
        directory.people.values.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    public func personID(for route: ConversationRoute) -> String? {
        guard let identityID = conversations.first(where: { $0.route == route })?.identityID else { return nil }
        return directory.personID(linkedTo: identityID)
    }

    public func linkOpenConversation(to personID: String) throws {
        guard
            let route = openRoute,
            let identityID = conversations.first(where: { $0.route == route })?.identityID
        else { throw PalloAppModelError.missingOpenConversation }
        try directory.link(remoteIdentityID: identityID, to: personID)
        rebuildInbox()
        detailSelection = .personSummary(personID)
    }

    @discardableResult
    public func createPersonAndLinkOpenConversation(displayName: String) throws -> String {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ContactDirectoryError.missingPerson }
        let personID = UUID().uuidString
        try directory.createPerson(id: personID, displayName: trimmed)
        do {
            try linkOpenConversation(to: personID)
        } catch {
            directory.removePerson(id: personID)
            throw error
        }
        return personID
    }

    private func apply(_ snapshot: MessagingSnapshot) {
        accounts = snapshot.accounts
        identities = snapshot.identities
        conversations = snapshot.conversations
        messagesByRoute = snapshot.messagesByRoute
        rebuildInbox()
    }

    private func performStart(id: UUID) async throws {
        let stream = await gateway.events()
        try Task.checkCancellation()
        guard startupID == id else { throw CancellationError() }

        let subscriptionTask = Task { @MainActor [weak self] in
            for await event in stream {
                guard !Task.isCancelled else { return }
                self?.receive(event, from: id)
            }
        }
        eventTask = subscriptionTask
        eventTaskID = id

        let snapshot = try await gateway.loadSnapshot()
        try Task.checkCancellation()
        guard startupID == id else { throw CancellationError() }
        try AccountPolicy.validate(snapshot.accounts)
        apply(snapshot)
        disconnectedAccountIDs.removeAll()
        health = .healthy

        let events = bufferedStartupEvents
        bufferedStartupEvents.removeAll()
        for event in events {
            apply(event)
        }
        bufferingEventTaskID = nil
    }

    private func beginStartup() -> UUID {
        let id = UUID()
        startupID = id
        bufferingEventTaskID = id
        bufferedStartupEvents.removeAll()
        startupTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.performStart(id: id)
                self.finishStartup(id: id)
            } catch {
                self.finishStartup(id: id, throwing: error)
            }
        }
        return id
    }

    private func waitForStartup(id: UUID) async throws {
        let waiterID = UUID()
        let cancellation = StartupWaiterCancellation()
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, any Error>) in
                if cancellation.isCancelled() || Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else if startupID == id {
                    startupWaiters[waiterID] = StartupWaiter(
                        startupID: id,
                        cancellation: cancellation,
                        continuation: continuation
                    )
                } else if eventTask != nil {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: CancellationError())
                }
            }
        } onCancel: {
            cancellation.cancel()
            Task { @MainActor [weak self] in
                self?.cancelStartupWaiter(waiterID, startupID: id)
            }
        }
    }

    private func finishStartup(id: UUID, throwing error: (any Error)? = nil) {
        guard startupID == id else { return }
        if error != nil {
            cancelStartup(id: id)
        }
        startupID = nil
        startupTask = nil
        resumeStartupWaiters(throwing: error, respectingCallerCancellation: true)
    }

    private func receive(_ event: GatewayEvent, from id: UUID) {
        guard eventTaskID == id else { return }
        if bufferingEventTaskID == id {
            bufferedStartupEvents.append(event)
        } else {
            apply(event)
        }
    }

    private func cancelStartup(id: UUID) {
        if eventTaskID == id {
            eventTask?.cancel()
            eventTask = nil
            eventTaskID = nil
        }
        if bufferingEventTaskID == id {
            bufferingEventTaskID = nil
            bufferedStartupEvents.removeAll()
        }
    }

    private func cancelStartupWaiter(_ waiterID: UUID, startupID: UUID) {
        guard
            let waiter = startupWaiters[waiterID],
            waiter.startupID == startupID
        else { return }
        startupWaiters[waiterID] = nil
        waiter.continuation.resume(throwing: CancellationError())
    }

    private func resumeStartupWaiters(
        throwing error: (any Error)? = nil,
        respectingCallerCancellation: Bool
    ) {
        let waiters = Array(startupWaiters.values)
        startupWaiters.removeAll()
        for waiter in waiters {
            if respectingCallerCancellation, waiter.cancellation.isCancelled() {
                waiter.continuation.resume(throwing: CancellationError())
            } else if let error {
                waiter.continuation.resume(throwing: error)
            } else {
                waiter.continuation.resume()
            }
        }
    }

    private func apply(_ event: GatewayEvent) {
        switch event {
        case let .messageUpserted(message):
            var messages = messagesByRoute[message.route, default: []]
            if let index = messages.firstIndex(where: { $0.id == message.id }) {
                messages[index] = message
            } else {
                messages.append(message)
            }
            messagesByRoute[message.route] = messages
            if
                let conversationIndex = conversations.firstIndex(where: { $0.route == message.route }),
                message.timestamp > conversations[conversationIndex].latestActivity
            {
                conversations[conversationIndex].latestPreview = message.body
                conversations[conversationIndex].latestActivity = message.timestamp
                rebuildInbox()
            }
        case let .conversationUpserted(conversation):
            conversations.removeAll { $0.id == conversation.id && $0.accountID == conversation.accountID }
            conversations.append(conversation)
            rebuildInbox()
        case let .connectionChanged(accountID, isConnected):
            guard accounts.contains(where: { $0.id == accountID }) else { return }
            if isConnected {
                disconnectedAccountIDs.remove(accountID)
            } else {
                disconnectedAccountIDs.insert(accountID)
            }
            health = disconnectedAccountIDs.isEmpty
                ? .healthy
                : .needsAttention("\(disconnectedAccountIDs.count) account(s) disconnected")
        }
    }

    private func rebuildInbox() {
        inboxItems = InboxProjector.project(
            accounts: accounts,
            identities: identities,
            conversations: conversations,
            directory: directory
        )
    }
}
