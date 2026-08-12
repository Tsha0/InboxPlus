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

    fileprivate init(body: String, route: ConversationRoute, draftRevision: UInt64) {
        self.body = body
        self.route = route
        self.draftRevision = draftRevision
    }
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
    private var startupID: UUID?
    private var startupWaiters: [CheckedContinuation<Void, Error>] = []
    private var eventTask: Task<Void, Never>?
    private var eventTaskID: UUID?
    private var bufferingEventTaskID: UUID?
    private var bufferedStartupEvents: [GatewayEvent] = []

    public init(gateway: any MessagingGateway, directory: ContactDirectory = .init()) {
        self.gateway = gateway
        self.directory = directory
    }

    public func start() async throws {
        if startupID != nil {
            try await withCheckedThrowingContinuation {
                startupWaiters.append($0)
            }
            return
        }
        guard eventTask == nil else { return }

        let id = UUID()
        startupID = id
        bufferingEventTaskID = id
        bufferedStartupEvents.removeAll()

        do {
            try await performStart(id: id)
            if startupID == id {
                startupID = nil
                resumeStartupWaiters()
            }
        } catch {
            if startupID == id {
                cancelStartup(id: id)
                startupID = nil
                resumeStartupWaiters(throwing: error)
            }
            throw error
        }
    }

    public func stop() {
        resumeStartupWaiters(throwing: CancellationError())
        startupID = nil
        bufferingEventTaskID = nil
        bufferedStartupEvents.removeAll()
        eventTask?.cancel()
        eventTask = nil
        eventTaskID = nil
    }

    public func reportStartupFailure(_ error: any Error) {
        health = .needsAttention("Pallo could not start: \(error.localizedDescription)")
    }

    isolated deinit {
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
        DraftSubmission(body: draft, route: route, draftRevision: draftRevision)
    }

    public func sendDraft(_ submission: DraftSubmission) async throws {
        let body = submission.body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        _ = try await gateway.sendText(body, to: submission.route)
        sendFailuresByRoute[submission.route] = nil
        if draftRevision == submission.draftRevision {
            draft = ""
        }
    }

    public func reportSendFailure(_ error: any Error, for route: ConversationRoute) {
        sendFailuresByRoute[route] = error.localizedDescription
    }

    public func sendFailure(for route: ConversationRoute) -> String? {
        sendFailuresByRoute[route]
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

    private func resumeStartupWaiters(throwing error: (any Error)? = nil) {
        let waiters = startupWaiters
        startupWaiters.removeAll()
        for waiter in waiters {
            if let error {
                waiter.resume(throwing: error)
            } else {
                waiter.resume()
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
