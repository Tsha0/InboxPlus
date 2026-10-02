import Foundation
import Observation
import InboxPlusCore
import InboxPlusGateway

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
        case .starting: "Inbox+ is starting"
        case .healthy: "Inbox+ is running"
        case .needsAttention: "Inbox+ needs attention"
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

public enum InboxPlusAppModelError: Error, Equatable {
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
public final class InboxPlusAppModel {
    public private(set) var accounts: [ConnectedAccount] = []
    public private(set) var identities: [RemoteIdentity] = []
    public private(set) var conversations: [RemoteConversation] = []
    public private(set) var messagesByRoute: [ConversationRoute: [Message]] = [:]
    public private(set) var inboxItems: [InboxItem] = []
    public private(set) var summariesByPersonID: [String: [ConversationSummary]] = [:]
    private var summaryByRoute: [ConversationRoute: ConversationSummary] = [:]
    private var conversationIndexByRoute: [ConversationRoute: Int] = [:]
    private var identityIndexByID: [String: Int] = [:]
    private var erasedAccountIDs: Set<String> = []
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

    /// A network the user asked to connect from the menu bar. The main window consumes this —
    /// the login sheet has to present from a window, and the menu bar owns no window of its own.
    public private(set) var pendingConnectionRequest: Platform?

    public func requestConnection(to platform: Platform) {
        pendingConnectionRequest = platform
    }

    public func clearConnectionRequest() {
        pendingConnectionRequest = nil
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
    private var queuedEvents: [GatewayEvent] = []
    private var eventFlushTask: Task<Void, Never>?
    private var gatewayStopTask: Task<Void, Never>?

    /// Lazy media loading for the transcript. Without a loader it simply never downloads, which is
    /// what previews and fixture runs want.
    public let media: MediaController

    public init(
        gateway: any MessagingGateway,
        directory: ContactDirectory = .init(),
        media: MediaController = MediaController()
    ) {
        self.gateway = gateway
        self.directory = directory
        self.media = media
    }

    public func start() async throws {
        if eventTask != nil, startupTask == nil {
            return
        }
        let id = startupID ?? beginStartup()
        try await waitForStartup(id: id)
    }

    public func stop() {
        let wasRunning = startupTask != nil || eventTask != nil
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
        eventFlushTask?.cancel()
        eventFlushTask = nil
        queuedEvents.removeAll()
        if wasRunning { scheduleGatewayStop() }
    }

    private func scheduleGatewayStop() {
        let previous = gatewayStopTask
        let gateway = gateway
        gatewayStopTask = Task {
            await previous?.value
            await gateway.stop()
        }
    }

    public func shutdown() async {
        stop()
        await gatewayStopTask?.value
    }

    public func reportStartupFailure(_ error: any Error) {
        health = .needsAttention("Inbox+ could not start: \(error.localizedDescription)")
    }

    isolated deinit {
        startupTask?.cancel()
        eventTask?.cancel()
        eventFlushTask?.cancel()
    }

    public func selectInboxItem(_ item: InboxItem) {
        switch item.id {
        case let .person(id):
            detailSelection = .personSummary(id)
        case let .conversation(route):
            openConversation(route)
        }
    }

    public func selectPerson(_ personID: String) {
        detailSelection = .personSummary(personID)
    }

    public func openConversation(_ route: ConversationRoute) {
        detailSelection = .conversation(route)
        markConversationRead(route)
    }

    public func markConversationRead(_ route: ConversationRoute) {
        guard
            let index = conversationIndexByRoute[route],
            conversations[index].unreadCount != 0
        else { return }
        conversations[index].unreadCount = 0
        rebuildInbox()
    }

    /// Names each loaded account and how many conversations it owns.
    ///
    /// A conversation attributed to the wrong network is invisible as a bug — a bridged Instagram
    /// chat simply reads "Matrix" and looks like a design choice. Stating it once at load makes it
    /// checkable without a screenshot.
    private static func reportLoadedAccounts(_ snapshot: MessagingSnapshot) {
        guard !snapshot.accounts.isEmpty else { return }
        let counts = snapshot.conversations.reduce(into: [String: Int]()) { totals, conversation in
            totals[conversation.accountID, default: 0] += 1
        }
        let described = snapshot.accounts
            .map { "\($0.platform.rawValue)(\($0.id))=\(counts[$0.id] ?? 0)" }
            .sorted()
            .joined(separator: " ")
        FileHandle.standardError.write(Data("Inbox+: conversations by account — \(described)\n".utf8))
    }

    public func isConnected(_ accountID: String) -> Bool {
        !disconnectedAccountIDs.contains(accountID)
    }

    // MARK: - Accounts

    /// When each account last produced traffic, so "connected" can be distinguished from "silent".
    public private(set) var lastActivityByAccount: [String: Date] = [:]

    public func lastActivity(for accountID: String) -> Date? {
        lastActivityByAccount[accountID]
    }

    public var platformsWithAccounts: Set<Platform> {
        Set(accounts.map(\.platform))
    }

    /// Records a newly connected account.
    ///
    /// The one-account-per-platform rule is enforced here as well as in the picker: the picker
    /// disables an already-connected network, but a view is a convenience, not the rule.
    public func addAccount(_ account: ConnectedAccount) throws {
        try AccountPolicy.validate(accounts + [account])
        accounts.append(account)
        erasedAccountIDs.remove(account.id)
        media.allowDownloads(accountID: account.id)
        disconnectedAccountIDs.remove(account.id)
        rebuildInbox()
    }

    /// Marks an account disconnected without touching anything it delivered.
    ///
    /// History stays: a disconnected account is a connection problem, and deleting someone's
    /// messages is never the right response to one.
    public func disconnect(accountID: String) {
        guard accounts.contains(where: { $0.id == accountID }) else { return }
        disconnectedAccountIDs.insert(accountID)
        health = .needsAttention("\(disconnectedAccountIDs.count) account(s) disconnected")
    }

    public func reconnect(accountID: String) {
        disconnectedAccountIDs.remove(accountID)
        if disconnectedAccountIDs.isEmpty { health = .healthy }
    }

    /// Removes an account and everything it brought with it.
    ///
    /// Separate from `disconnect` and destructive on purpose — the caller must have confirmed with
    /// the user, because nothing here can be undone.
    public func eraseAccount(accountID: String) {
        erasedAccountIDs.insert(accountID)
        media.purge(accountID: accountID)
        accounts.removeAll { $0.id == accountID }
        let removedIdentityIDs = Set(
            identities.filter { $0.accountID == accountID }.map(\.id)
        )
        identities.removeAll { $0.accountID == accountID }
        for route in messagesByRoute.keys where route.accountID == accountID {
            messagesByRoute[route] = nil
        }
        conversations.removeAll { $0.accountID == accountID }
        rebuildModelIndexes()
        stagedAttachmentsByRoute = stagedAttachmentsByRoute.filter { $0.key.accountID != accountID }
        sendFailuresByRoute = sendFailuresByRoute.filter { $0.key.accountID != accountID }
        latestSendGenerationByRoute = latestSendGenerationByRoute.filter { $0.key.accountID != accountID }
        for identityID in removedIdentityIDs {
            guard let personID = directory.personID(linkedTo: identityID) else { continue }
            try? directory.unlink(remoteIdentityID: identityID, from: personID)
        }
        disconnectedAccountIDs.remove(accountID)
        lastActivityByAccount[accountID] = nil
        if openRoute?.accountID == accountID { detailSelection = .empty }
        if disconnectedAccountIDs.isEmpty, case .needsAttention = health { health = .healthy }
        rebuildInbox()
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

    // MARK: - Attachment composition

    /// Files staged for the open conversation, kept per route so switching conversations does not
    /// carry someone's photo into a different chat.
    public private(set) var stagedAttachmentsByRoute: [ConversationRoute: [OutgoingAttachment]] = [:]

    public func stagedAttachments(for route: ConversationRoute) -> [OutgoingAttachment] {
        stagedAttachmentsByRoute[route] ?? []
    }

    public func capabilities(for route: ConversationRoute) -> ConversationCapabilities {
        guard let index = conversationIndexByRoute[route] else { return .textOnly }
        return conversations[index].capabilities
    }

    /// Stages a chosen file, rejecting it now rather than failing the send later.
    @discardableResult
    public func stageAttachment(at fileURL: URL, for route: ConversationRoute) -> AttachmentRejection? {
        do {
            let attachment = try OutgoingAttachment.describing(fileURL: fileURL)
            try attachment.validate(against: capabilities(for: route))
            stagedAttachmentsByRoute[route, default: []].append(attachment)
            sendFailuresByRoute[route] = nil
            return nil
        } catch let rejection as AttachmentRejection {
            sendFailuresByRoute[route] = rejection.message
            return rejection
        } catch {
            let rejection = AttachmentRejection.unreadable(error.localizedDescription)
            sendFailuresByRoute[route] = rejection.message
            return rejection
        }
    }

    public func removeStagedAttachment(_ attachment: OutgoingAttachment, for route: ConversationRoute) {
        stagedAttachmentsByRoute[route]?.removeAll { $0 == attachment }
        if stagedAttachmentsByRoute[route]?.isEmpty == true {
            stagedAttachmentsByRoute[route] = nil
        }
    }

    /// Sends everything staged for a route, then the text, in that order.
    ///
    /// A file that fails to send stays staged: dropping it would lose the user's choice with
    /// nothing to show for it.
    public func sendStagedAttachments(to route: ConversationRoute) async throws {
        for attachment in stagedAttachments(for: route) {
            _ = try await gateway.send(attachment, to: route)
            removeStagedAttachment(attachment, for: route)
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
        summariesByPersonID[personID] ?? []
    }

    public func summary(for route: ConversationRoute) -> ConversationSummary? {
        summaryByRoute[route]
    }

    public var people: [InboxPlusPerson] {
        directory.people.values.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    public func personID(for route: ConversationRoute) -> String? {
        guard let index = conversationIndexByRoute[route] else { return nil }
        return directory.personID(linkedTo: conversations[index].identityID)
    }

    public func linkOpenConversation(to personID: String) throws {
        guard
            let route = openRoute,
            let index = conversationIndexByRoute[route]
        else { throw InboxPlusAppModelError.missingOpenConversation }
        try directory.link(remoteIdentityID: conversations[index].identityID, to: personID)
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
        Self.reportLoadedAccounts(snapshot)
        accounts = snapshot.accounts.filter { !erasedAccountIDs.contains($0.id) }
        identities = snapshot.identities.filter { !erasedAccountIDs.contains($0.accountID) }
        conversations = snapshot.conversations.filter { !erasedAccountIDs.contains($0.accountID) }
        rebuildModelIndexes()

        // Gateways bound their snapshot caches. Keep history already displayed for retained routes,
        // and let the snapshot overwrite matching IDs with newer delivery/content information.
        let retainedRoutes = Set(conversations.map(\.route))
        var mergedByRoute: [ConversationRoute: [Message]] = [:]
        for route in retainedRoutes {
            var messages = messagesByRoute[route, default: []]
            var indexByID = Dictionary(messages.enumerated().map { ($0.element.id, $0.offset) },
                                       uniquingKeysWith: { _, latest in latest })
            for message in snapshot.messagesByRoute[route, default: []] {
                if let index = indexByID[message.id] {
                    messages[index] = message
                } else {
                    indexByID[message.id] = messages.count
                    messages.append(message)
                }
            }
            messages.sort { $0.timestamp < $1.timestamp }
            mergedByRoute[route] = messages
        }
        messagesByRoute = mergedByRoute
        lastActivityByAccount = Dictionary(
            conversations.map { ($0.accountID, $0.latestActivity) },
            uniquingKeysWith: max
        )
        rebuildInbox()
    }

    private func performStart(id: UUID) async throws {
        await gatewayStopTask?.value
        try Task.checkCancellation()
        guard startupID == id else { throw CancellationError() }
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
        try AccountPolicy.validate(snapshot.accounts.filter { !erasedAccountIDs.contains($0.id) })
        apply(snapshot)
        disconnectedAccountIDs.removeAll()
        health = .healthy

        let events = bufferedStartupEvents
        bufferedStartupEvents.removeAll()
        applyEvents(events)
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
            scheduleGatewayStop()
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
            queuedEvents.append(event)
            guard eventFlushTask == nil else { return }
            eventFlushTask = Task { @MainActor [weak self] in
                await Task.yield()
                guard !Task.isCancelled, let self, eventTaskID == id else { return }
                let events = queuedEvents
                queuedEvents.removeAll()
                eventFlushTask = nil
                applyEvents(events)
            }
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

    private func applyEvents(_ events: [GatewayEvent]) {
        var needsProjection = false
        for event in events {
            if apply(event) { needsProjection = true }
        }
        if needsProjection { rebuildInbox() }
    }

    /// Returns whether this event changed anything displayed in the inbox.
    private func apply(_ event: GatewayEvent) -> Bool {
        switch event {
        case let .messageUpserted(message):
            return upsertMessages([message])
        case let .messagesUpserted(messages):
            return upsertMessages(messages)
        case let .identityUpserted(identity):
            guard !erasedAccountIDs.contains(identity.accountID) else { return false }
            if let index = identityIndexByID[identity.id] {
                identities[index] = identity
            } else {
                identityIndexByID[identity.id] = identities.count
                identities.append(identity)
            }
            return true
        case let .conversationUpserted(conversation):
            guard !erasedAccountIDs.contains(conversation.accountID) else { return false }
            if let index = conversationIndexByRoute[conversation.route] {
                conversations[index] = conversation
            } else {
                conversationIndexByRoute[conversation.route] = conversations.count
                conversations.append(conversation)
            }
            return true
        case let .connectionChanged(accountID, isConnected):
            guard accounts.contains(where: { $0.id == accountID }) else { return false }
            if isConnected {
                disconnectedAccountIDs.remove(accountID)
            } else {
                disconnectedAccountIDs.insert(accountID)
            }
            health = disconnectedAccountIDs.isEmpty
                ? .healthy
                : .needsAttention("\(disconnectedAccountIDs.count) account(s) disconnected")
            return false
        }
    }

    private func upsertMessages(_ updates: [Message]) -> Bool {
        var needsProjection = false
        for (route, messages) in Dictionary(grouping: updates, by: \.route) {
            guard !erasedAccountIDs.contains(route.accountID) else { continue }
            var stored = messagesByRoute[route, default: []]
            var indexByID = Dictionary(stored.enumerated().map { ($0.element.id, $0.offset) },
                                       uniquingKeysWith: { _, latest in latest })
            var needsSort = false
            for message in messages {
                if let index = indexByID[message.id] {
                    if stored[index].timestamp != message.timestamp { needsSort = true }
                    stored[index] = message
                } else {
                    if let last = stored.last, last.timestamp > message.timestamp { needsSort = true }
                    indexByID[message.id] = stored.count
                    stored.append(message)
                }
                if message.timestamp > lastActivityByAccount[route.accountID] ?? .distantPast {
                    lastActivityByAccount[route.accountID] = message.timestamp
                }
                if let index = conversationIndexByRoute[route],
                   message.timestamp > conversations[index].latestActivity {
                    conversations[index].latestPreview = message.body
                    conversations[index].latestActivity = message.timestamp
                    needsProjection = true
                }
            }
            if needsSort { stored.sort { $0.timestamp < $1.timestamp } }
            messagesByRoute[route] = stored
        }
        return needsProjection
    }

    private func rebuildModelIndexes() {
        conversationIndexByRoute = Dictionary(
            conversations.enumerated().map { ($0.element.route, $0.offset) },
            uniquingKeysWith: { first, _ in first }
        )
        identityIndexByID = Dictionary(
            identities.enumerated().map { ($0.element.id, $0.offset) },
            uniquingKeysWith: { first, _ in first }
        )
    }

    private func rebuildInbox() {
        inboxItems = InboxProjector.project(
            accounts: accounts,
            identities: identities,
            conversations: conversations,
            directory: directory
        )
        summaryByRoute = Dictionary(
            inboxItems.flatMap(\.conversationSummaries).map { ($0.route, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        summariesByPersonID = Dictionary(uniqueKeysWithValues: inboxItems.compactMap { item in
            guard case let .person(personID) = item.id else { return nil }
            return (personID, item.conversationSummaries)
        })
    }
}
