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

public enum ReplyError: Error, Equatable, LocalizedError {
    case restartingToUpdate
    case refreshingRuntime

    public var errorDescription: String? {
        switch self {
        case .restartingToUpdate: "Inbox+ is restarting to update. Send it again once it reopens."
        case .refreshingRuntime: "Local services are restarting. Your draft is saved; try sending again when setup finishes."
        }
    }
}

/// A message worth telling the user about, with what a notification needs to describe it.
public struct IncomingMessageAlert: Equatable, Sendable {
    public let message: Message
    /// The conversation's title.
    public let title: String
    /// Who sent it, in a group. A one-to-one conversation is already titled with that person.
    public let senderName: String?
    public let canReply: Bool

    public init(message: Message, title: String, senderName: String? = nil, canReply: Bool = false) {
        self.message = message
        self.title = title
        self.senderName = senderName
        self.canReply = canReply
    }
}

/// What the inbox's context menu does to a row. Each applies to every conversation the row groups.
public enum InboxItemAction: Hashable, Sendable {
    case markRead, markUnread, mute(MuteDuration), unmute, hide, unhide
}

public struct DraftSubmission: Sendable {
    public let body: String
    public let route: ConversationRoute
    /// The message this send answers. The text carries the quote when there is any, otherwise
    /// the first attachment does.
    public let replyingTo: String?
    fileprivate let draftRevision: UInt64
    fileprivate let routeGeneration: UInt64

    fileprivate init(
        body: String,
        route: ConversationRoute,
        replyingTo: String?,
        draftRevision: UInt64,
        routeGeneration: UInt64
    ) {
        self.body = body
        self.route = route
        self.replyingTo = replyingTo
        self.draftRevision = draftRevision
        self.routeGeneration = routeGeneration
    }

    fileprivate var hasText: Bool { !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
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
    public private(set) var loadingMessageRoutes: Set<ConversationRoute> = []
    public private(set) var failedMessageRoutes: Set<ConversationRoute> = []
    public private(set) var detailSelection: DetailSelection = .empty {
        didSet {
            if case let .conversation(closed) = oldValue, closed != openRoute { trimToRecentWindow(closed) }
        }
    }
    public private(set) var health: ServiceHealth = .starting

    /// Unsent text, one per conversation, so a reply half-written to one person never follows you
    /// into another chat.
    private var draftsByRoute: [ConversationRoute: String] = [:]
    private var draftRevisionsByRoute: [ConversationRoute: UInt64] = [:]

    /// Conversations holding a draft worth keeping. Kept apart from the text itself so the inbox
    /// redraws when a draft starts or ends, not on every keystroke.
    public private(set) var routesWithDrafts: Set<ConversationRoute> = []

    public func draft(for route: ConversationRoute) -> String {
        draftsByRoute[route] ?? ""
    }

    public func setDraft(_ text: String, for route: ConversationRoute) {
        draftsByRoute[route] = text.isEmpty ? nil : text
        draftRevisionsByRoute[route, default: 0] &+= 1
        let hasDraft = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if hasDraft, !routesWithDrafts.contains(route) {
            routesWithDrafts.insert(route)
        } else if !hasDraft, routesWithDrafts.contains(route) {
            routesWithDrafts.remove(route)
        }
    }

    public var openRoute: ConversationRoute? {
        guard case let .conversation(route) = detailSelection else { return nil }
        return route
    }

    /// Prevent update restarts from discarding an unsent composer or interrupting a pending send.
    public var hasUnfinishedMessagingWork: Bool {
        sendsInFlight > 0 || !routesWithDrafts.isEmpty
            || stagedAttachmentsByRoute.values.contains { !$0.isEmpty }
            || messagesByRoute.values.contains { $0.contains { $0.deliveryState == .pending } }
    }

    public var isPreparingForUpdate = false
    public private(set) var isRefreshingRuntime = false

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

    /// Not called for a muted conversation.
    public var onIncomingMessage: ((IncomingMessageAlert) -> Void)?
    private var notificationsStartedAt = Date.distantFuture

    private let gateway: any MessagingGateway
    private let localRecipientSource: @Sendable () async -> LocalRecipientSnapshot
    public private(set) var favouriteError: String?
    private let favouriteStore: InboxFavouriteStore?
    private var favouriteRoutes: Set<ConversationRoute> = []
    public private(set) var preferenceError: String?
    private let preferenceStore: ConversationPreferenceStore?
    private var preferences = ConversationPreferences()
    private var muteEndTask: Task<Void, Never>?
    /// The message the composer is answering in each conversation.
    private var replyTargetIDByRoute: [ConversationRoute: String] = [:]
    private var directory: ContactDirectory
    public private(set) var contactError: String?
    private let contactStore: ContactDirectoryStore?
    private var contactLoadFailed = false
    private let composerFiles: ComposerFileStore
    private var sendsInFlight = 0
    private var disconnectedAccountIDs: Set<String> = []
    private let accountLifecycle: (any AccountLifecycle)?
    private var sendFailuresByRoute: [ConversationRoute: String] = [:]
    private var latestSendGenerationByRoute: [ConversationRoute: UInt64] = [:]
    private var startupID: UUID?
    private var startupTask: Task<Void, Never>?
    private var startupWaiters: [UUID: StartupWaiter] = [:]
    private var eventTask: Task<Void, Never>?
    private var eventTaskID: UUID?
    private var bufferingEventTaskID: UUID?
    private var bufferedStartupEvents: [GatewayEvent] = []
    private var pendingHistoricalMessages: [Message] = []
    private var historyFlushTask: Task<Void, Never>?
    private var recentMessageLoads: [ConversationRoute: Task<Void, Never>] = [:]
    private var recentMessageLoadIDs: [ConversationRoute: UUID] = [:]
    private var recentMessageLoadRevisions: [ConversationRoute: UInt64] = [:]

    /// Lazy media loading for the transcript. Without a loader it simply never downloads, which is
    /// what previews and fixture runs want.
    public let media: MediaController

    public init(
        gateway: any MessagingGateway,
        directory: ContactDirectory = .init(),
        contactStore: ContactDirectoryStore? = nil,
        media: MediaController = MediaController(),
        favouriteStore: InboxFavouriteStore? = nil,
        preferenceStore: ConversationPreferenceStore? = nil,
        accountLifecycle: (any AccountLifecycle)? = nil,
        composerFiles: ComposerFileStore = .temporary(),
        localRecipientSource: @escaping @Sendable () async -> LocalRecipientSnapshot = { .accessUnavailable }
    ) {
        self.gateway = gateway
        self.localRecipientSource = localRecipientSource
        self.directory = directory
        self.contactStore = contactStore
        self.media = media
        self.favouriteStore = favouriteStore
        self.preferenceStore = preferenceStore
        self.accountLifecycle = accountLifecycle
        self.composerFiles = composerFiles
        if let contactStore {
            do { self.directory = try contactStore.load() }
            catch {
                contactLoadFailed = true
                contactError = ContactStorageError.loadFailed.localizedDescription
            }
        }
        do { favouriteRoutes = try favouriteStore?.load() ?? [] }
        catch { favouriteError = "Could not load favourites: \(error.localizedDescription)" }
        do { preferences = try preferenceStore?.load() ?? ConversationPreferences() }
        catch { preferenceError = "Could not load hidden and muted conversations: \(error.localizedDescription)" }
    }

    public func start() async throws {
        if eventTask != nil, startupTask == nil {
            return
        }
        let id = startupID ?? beginStartup()
        try await waitForStartup(id: id)
    }

    public func stop() {
        historyFlushTask?.cancel()
        historyFlushTask = nil
        pendingHistoricalMessages.removeAll()
        recentMessageLoads.values.forEach { $0.cancel() }
        recentMessageLoads.removeAll()
        recentMessageLoadIDs.removeAll()
        recentMessageLoadRevisions.removeAll()
        loadingMessageRoutes.removeAll()
        failedMessageRoutes.removeAll()
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

    public func refreshRuntime(
        timeout: Duration = .seconds(90),
        _ refresh: @Sendable () async throws -> Void
    ) async throws {
        guard !isRefreshingRuntime, !isPreparingForUpdate else { throw ReplyError.refreshingRuntime }
        isRefreshingRuntime = true
        defer { isRefreshingRuntime = false }
        try await start()
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while sendsInFlight > 0 || messagesByRoute.values.contains(where: { $0.contains { $0.deliveryState == .pending } }) {
            guard clock.now < deadline else {
                throw NSError(domain: "InboxPlus.Setup", code: 2, userInfo: [
                    NSLocalizedDescriptionKey: "Messages are still sending. Let them finish, then try connecting again. Your drafts and attachments are saved."
                ])
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        stop()
        do {
            try await refresh()
            try await start()
            if let route = openRoute { try await gateway.loadRecentMessages(in: route) }
        } catch {
            health = .needsAttention("Setup could not reconnect the inbox: \(error.localizedDescription)")
            throw error
        }
    }

    public func refreshConversations() async throws {
        let snapshot = try await gateway.loadSnapshot()
        for account in snapshot.accounts { apply(.accountUpserted(account)) }
        for identity in snapshot.identities { apply(.identityUpserted(identity)) }
        for conversation in snapshot.conversations { apply(.conversationUpserted(conversation)) }
        for messages in snapshot.messagesByRoute.values {
            for message in messages { apply(.historicalMessageUpserted(message)) }
        }
    }

    public func reportStartupFailure(_ error: any Error) {
        health = .needsAttention("Inbox+ could not start: \(error.localizedDescription)")
    }

    isolated deinit {
        startupTask?.cancel()
        eventTask?.cancel()
        muteEndTask?.cancel()
        historyFlushTask?.cancel()
        recentMessageLoads.values.forEach { $0.cancel() }
    }

    /// A person is favourite when any route is saved; toggling applies to the whole current group.
    public func toggleFavourite(_ item: InboxItem) {
        guard let current = inboxItems.first(where: { $0.id == item.id }) else { return }
        var updated = favouriteRoutes
        let routes = current.conversationSummaries.map(\.route)
        if current.isFavourite { updated.subtract(routes) }
        else { updated.formUnion(routes) }
        do {
            try favouriteStore?.save(updated)
            favouriteRoutes = updated
            favouriteError = nil
            rebuildInbox()
        } catch {
            favouriteError = "Could not save favourites: \(error.localizedDescription)"
        }
    }

    // MARK: - Notifications

    /// The on/off mute in a conversation's header and in Settings: muting there lasts until
    /// it is undone, like **Mute → Forever** in the inbox.
    public func setMuted(_ muted: Bool, for route: ConversationRoute) {
        updatePreferences { muted ? $0.mute([route], for: .forever, from: Date()) : $0.unmute([route]) }
        rebuildInbox()
    }

    /// Muted conversations still in the inbox, so they can be unmuted by name.
    public var mutedConversations: [ConversationSummary] {
        inboxItems.flatMap(\.conversationSummaries)
            .filter { isMuted($0.route) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    /// The count on the Dock and in the menu bar. A muted conversation is left out, or one busy
    /// group would hold the badge up for good.
    public var unreadBadgeCount: Int {
        inboxItems.flatMap(\.conversationSummaries)
            .filter { !isMuted($0.route) }
            .reduce(0) { $0 + $1.unreadCount }
    }

    /// Sends a reply typed into a notification, leaving the composer's draft exactly as it was.
    public func sendReply(_ text: String, to route: ConversationRoute) async throws {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        guard !isPreparingForUpdate else { throw ReplyError.restartingToUpdate }
        guard !isRefreshingRuntime else { throw ReplyError.refreshingRuntime }
        sendsInFlight += 1
        defer { sendsInFlight -= 1 }
        do {
            _ = try await gateway.sendText(body, to: route)
        } catch {
            sendFailuresByRoute[route] = error.localizedDescription
            throw error
        }
        markConversationRead(route)
    }

    private func alert(for message: Message) -> IncomingMessageAlert {
        let conversation = conversations.first { $0.route == message.route }
        let sender = message.senderDisplayName.flatMap { $0.isEmpty ? nil : $0 }
            ?? identities.first {
                $0.id == message.senderIdentityID && $0.accountID == message.route.accountID
            }?.displayName
        return IncomingMessageAlert(
            message: message,
            title: conversation?.title ?? sender ?? "New message",
            senderName: conversation?.isGroup == true ? sender : nil,
            canReply: conversation?.capabilities.canSendText ?? false
        )
    }

    /// The inbox as listed: everything the user has not hidden.
    public var listedInboxItems: [InboxItem] { inboxItems.filter { !$0.isHidden } }

    public var hiddenInboxItems: [InboxItem] { inboxItems.filter(\.isHidden) }

    public func perform(_ action: InboxItemAction, on item: InboxItem) {
        guard let current = inboxItems.first(where: { $0.id == item.id }) else { return }
        let summaries = current.conversationSummaries
        let routes = summaries.map(\.route)
        switch action {
        case .markRead:
            routes.forEach(markConversationRead)
        case .markUnread:
            // The most recent conversation is enough to make the whole row read as unread.
            if let route = routes.first { markConversationUnread(route) }
        case let .mute(duration):
            updatePreferences { $0.mute(routes, for: duration, from: Date()) }
        case .unmute:
            updatePreferences { $0.unmute(routes) }
        case .hide:
            updatePreferences { $0.hide(summaries.map { ($0.route, $0.latestActivity) }) }
        case .unhide:
            updatePreferences { $0.unhide(routes) }
        }
        rebuildInbox()
    }

    public func isMuted(_ route: ConversationRoute) -> Bool {
        preferences.isMuted(route, at: Date())
    }

    /// A change that cannot be saved still applies until Inbox+ quits, so a badge the user cleared
    /// does not stay stuck because of a disk error.
    private func updatePreferences(_ change: (inout ConversationPreferences) -> Void) {
        var updated = preferences
        change(&updated)
        guard updated != preferences else { return }
        preferences = updated
        do {
            try preferenceStore?.save(updated)
            preferenceError = nil
        } catch {
            preferenceError = "Could not save hidden and muted conversations: \(error.localizedDescription)"
        }
    }

    /// Redraws the inbox when the soonest mute runs out, so the row stops reading as muted then.
    private func scheduleMuteEnd() {
        muteEndTask?.cancel()
        guard let end = preferences.nextMuteEnd(after: Date()) else { return }
        muteEndTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(end.timeIntervalSinceNow))
            guard !Task.isCancelled else { return }
            self?.rebuildInbox()
        }
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

    /// The message a search result opened, which the transcript keeps in view and marks.
    public private(set) var highlightedMessage: MessageReference?

    public func openMessage(_ message: MessageReference) {
        openConversation(message.route)
        highlightedMessage = message
    }

    /// Reading messages only while there is a query keeps every new message from redrawing the
    /// inbox list.
    public func messageMatches(query: String, filter: InboxFilter) -> [MessageSearchResult] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        return InboxProjector.messageMatches(
            messagesByRoute,
            in: InboxProjector.filtered(inboxItems, query: "", filter: filter),
            query: query
        )
    }

    public func openConversation(_ route: ConversationRoute) {
        highlightedMessage = nil
        detailSelection = .conversation(route)
        loadRecentMessages(in: route)
        markConversationRead(route)
    }

    public func recipientContacts(accountID: String) async -> LocalRecipientSnapshot {
        guard accounts.first(where: { $0.id == accountID })?.platform == .iMessage,
              await canStartConversation(accountID: accountID) else { return .available([]) }
        return await localRecipientSource()
    }

    public func canStartConversation(accountID: String) async -> Bool {
        guard isConnected(accountID), let source = gateway as? any ConversationStartingGateway else { return false }
        return await source.canStartConversation(accountID: accountID)
    }

    public func startConversation(accountID: String, recipient: String) async throws {
        guard accounts.contains(where: { $0.id == accountID }), isConnected(accountID) else {
            throw ConversationStartError.unavailable
        }
        guard let source = gateway as? any ConversationStartingGateway else { throw ConversationStartError.unsupported }
        let started = try await source.startConversation(accountID: accountID, recipient: recipient)
        guard isConnected(accountID), accounts.contains(where: { $0.id == accountID }) else {
            throw ConversationStartError.unavailable
        }
        if !identities.contains(where: { $0.id == started.identity.id && $0.accountID == accountID }) {
            identities.append(started.identity)
        }
        if !conversations.contains(where: { $0.route == started.conversation.route }) {
            conversations.append(started.conversation)
        }
        rebuildInbox()
        openConversation(started.conversation.route)
    }

    /// A source may leave history out of its snapshot, so opening a conversation is what asks for
    /// it. The messages arrive as ordinary gateway events.
    public func loadRecentMessages(in route: ConversationRoute) {
        guard recentMessageLoads[route] == nil else { return }
        let id = UUID()
        recentMessageLoadIDs[route] = id
        recentMessageLoadRevisions[route] = 0
        loadingMessageRoutes.insert(route)
        failedMessageRoutes.remove(route)
        recentMessageLoads[route] = Task { [weak self, gateway] in
            var failed = false
            do {
                try await gateway.loadRecentMessages(in: route)
                try Task.checkCancellation()
            } catch {
                failed = !Task.isCancelled
            }
            // The gateway can return while its yielded history is still being consumed.
            while let self, self.recentMessageLoadIDs[route] == id {
                let revision = self.recentMessageLoadRevisions[route]
                try? await Task.sleep(for: .milliseconds(16))
                guard self.recentMessageLoadIDs[route] == id else { return }
                self.flushHistoricalMessages()
                guard self.recentMessageLoadRevisions[route] == revision else { continue }
                self.loadingMessageRoutes.remove(route)
                if failed { self.failedMessageRoutes.insert(route) }
                self.recentMessageLoads[route] = nil
                self.recentMessageLoadIDs[route] = nil
                self.recentMessageLoadRevisions[route] = nil
                return
            }
        }
    }

    public func markConversationRead(_ route: ConversationRoute) {
        guard let index = conversations.firstIndex(where: { $0.route == route }) else { return }
        // Saved even when the badge already reads zero: a message that arrives while Inbox+ is
        // running does not raise the badge, but the source still counts it as unread.
        saveReadState(of: route)
        updatePreferences { $0.markedUnread.remove(route) }
        guard conversations[index].unreadCount != 0 else { return }
        conversations[index].unreadCount = 0
        rebuildInbox()
    }

    public func toggleConversationUnread(_ route: ConversationRoute) {
        guard let index = conversations.firstIndex(where: { $0.route == route }) else { return }
        if conversations[index].unreadCount > 0 {
            markConversationRead(route)
        } else {
            markConversationUnread(route)
        }
    }

    /// Remembered by Inbox+ rather than the network, so the badge survives a relaunch and a source
    /// that reports nothing unread there.
    private func markConversationUnread(_ route: ConversationRoute) {
        guard let index = conversations.firstIndex(where: { $0.route == route }) else { return }
        updatePreferences { $0.markedUnread.insert(route) }
        conversations[index] = keepingUnreadMark(conversations[index])
        rebuildInbox()
    }

    private func keepingUnreadMark(_ conversation: RemoteConversation) -> RemoteConversation {
        guard preferences.markedUnread.contains(conversation.route) else { return conversation }
        var marked = conversation
        marked.unreadCount = max(marked.unreadCount, 1)
        return marked
    }

    public func navigateConversation(forward: Bool, query: String, filter: InboxFilter) {
        let routes = InboxProjector.filtered(listedInboxItems, query: query, filter: filter)
            .flatMap { $0.conversationSummaries.map(\.route) }
        guard !routes.isEmpty else { return }
        let index: Int
        if let route = openRoute, let current = routes.firstIndex(of: route) {
            index = (current + (forward ? 1 : routes.count - 1)) % routes.count
        } else {
            index = forward ? 0 : routes.count - 1
        }
        openConversation(routes[index])
    }

    private func saveReadState(of route: ConversationRoute) {
        Task { [gateway] in
            do {
                try await gateway.markRead(route)
            } catch {
                FileHandle.standardError.write(Data("Inbox+: could not save read state: \(error)\n".utf8))
            }
        }
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

    /// The accounts the user connected. The local Matrix account is Inbox+'s own homeserver, which
    /// carries the bridges; it is not something the user signed in to, so it is not listed.
    public var userAccounts: [ConnectedAccount] {
        accounts.filter { $0.platform != .matrix }
    }

    public var platformsWithAccounts: Set<Platform> {
        Set(userAccounts.map(\.platform))
    }

    private var signedInNames: [String: String] = [:]

    /// The username, phone number or address an account is signed in as, when it is known.
    public func signedInName(for account: ConnectedAccount) -> String? {
        account.signedInAs ?? signedInNames[account.id]
    }

    public func refreshSignedInNames() async {
        guard let accountLifecycle else { return }
        signedInNames = await accountLifecycle.signedInNames()
    }

    /// Records a newly connected account.
    ///
    /// The one-account-per-platform rule is enforced here as well as in the picker: the picker
    /// disables an already-connected network, but a view is a convenience, not the rule.
    ///
    /// The gateway may already have reported this same account, as soon as the bridge delivered its
    /// first conversation and before the login sheet was dismissed; that is not a second account.
    public func addAccount(_ account: ConnectedAccount) throws {
        try AccountPolicy.validate(accounts.filter { $0.id != account.id } + [account])
        upsert(account)
        disconnectedAccountIDs.remove(account.id)
        rebuildInbox()
        Task { await refreshSignedInNames() }
    }

    private func upsert(_ account: ConnectedAccount) {
        if let index = accounts.firstIndex(where: { $0.id == account.id }) {
            accounts[index] = account
        } else {
            accounts.append(account)
        }
    }

    /// Accounts with a disconnect, reconnect or removal still under way.
    public private(set) var accountIDsChanging: Set<String> = []

    /// Stops an account delivering anything, without touching anything it already delivered.
    ///
    /// History stays: a disconnected account is a connection problem, and deleting someone's
    /// messages is never the right response to one. The account only shows as disconnected once
    /// its bridge has actually stopped.
    public func disconnect(accountID: String) async throws {
        guard let account = beginChange(accountID, allowedFor: \.canDisconnect) else { return }
        defer { accountIDsChanging.remove(accountID) }
        try await accountLifecycle?.disconnect(account)
        disconnectedAccountIDs.insert(accountID)
        reportDisconnections()
    }

    @discardableResult
    public func reconnect(accountID: String) async throws -> AccountReconnection {
        guard let account = beginChange(accountID, allowedFor: \.canDisconnect) else { return .reconnected }
        defer { accountIDsChanging.remove(accountID) }
        let reconnection = try await accountLifecycle?.reconnect(account) ?? .reconnected
        disconnectedAccountIDs.remove(accountID)
        reportDisconnections()
        return reconnection
    }

    /// Removes an account and everything it brought with it.
    ///
    /// Separate from `disconnect` and destructive on purpose — the caller must have confirmed with
    /// the user, because nothing here can be undone. Nothing leaves the screen until the lifecycle
    /// has signed out and deleted it, so an account never looks removed while it is still there.
    @discardableResult
    public func eraseAccount(accountID: String) async throws -> AccountRemoval {
        guard let account = beginChange(accountID, allowedFor: \.canRemove) else { return AccountRemoval() }
        defer { accountIDsChanging.remove(accountID) }
        var removal = try await accountLifecycle?.remove(account) ?? AccountRemoval()

        accounts.removeAll { $0.id == accountID }
        let removedIdentityIDs = Set(
            identities.filter { $0.accountID == accountID }.map(\.id)
        )
        identities.removeAll { $0.accountID == accountID }
        for route in messagesByRoute.keys where route.accountID == accountID {
            messagesByRoute[route] = nil
        }
        conversations.removeAll { $0.accountID == accountID }
        var updatedDirectory = directory
        for identityID in removedIdentityIDs {
            guard let personID = updatedDirectory.personID(linkedTo: identityID) else { continue }
            try? updatedDirectory.unlink(remoteIdentityID: identityID, from: personID)
        }
        if updatedDirectory.links != directory.links {
            do { try saveContactDirectory(updatedDirectory) }
            catch { removal.unfinished.append("Contact links could not be removed from saved contacts.") }
        }
        disconnectedAccountIDs.remove(accountID)
        lastActivityByAccount[accountID] = nil
        for (route, attachments) in stagedAttachmentsByRoute where route.accountID == accountID {
            attachments.forEach { composerFiles.discard($0.fileURL) }
        }
        stagedAttachmentsByRoute = stagedAttachmentsByRoute.filter { $0.key.accountID != accountID }
        replyTargetIDByRoute = replyTargetIDByRoute.filter { $0.key.accountID != accountID }
        draftsByRoute = draftsByRoute.filter { $0.key.accountID != accountID }
        routesWithDrafts = routesWithDrafts.filter { $0.accountID != accountID }
        if openRoute?.accountID == accountID { detailSelection = .empty }
        reportDisconnections()
        let remainingFavourites = favouriteRoutes.filter { $0.accountID != accountID }
        if remainingFavourites != favouriteRoutes {
            do {
                try favouriteStore?.save(remainingFavourites)
                favouriteRoutes = remainingFavourites
            } catch {
                favouriteError = "Could not save favourites: \(error.localizedDescription)"
            }
        }
        updatePreferences { $0.forget(accountID: accountID) }
        rebuildInbox()

        do { try await media.purge(accountID: accountID) }
        catch {
            removal.unfinished.append(
                "Its downloaded photos and files could not be deleted: \(error.localizedDescription)"
            )
        }
        return removal
    }

    /// One change per account at a time: a second click must not race the first one's bridge.
    private func beginChange(
        _ accountID: String,
        allowedFor isAllowed: (ConnectedAccount) -> Bool
    ) -> ConnectedAccount? {
        guard let account = accounts.first(where: { $0.id == accountID }), isAllowed(account),
              accountIDsChanging.insert(accountID).inserted
        else { return nil }
        return account
    }

    /// The banner counts disconnected accounts, so it follows every change to them.
    private func reportDisconnections() {
        health = disconnectedAccountIDs.isEmpty
            ? .healthy
            : .needsAttention("\(disconnectedAccountIDs.count) account(s) disconnected")
    }

    public func captureDraft(to route: ConversationRoute) -> DraftSubmission {
        // Replying is back at the newest message, where the reply will appear.
        if highlightedMessage?.route == route { highlightedMessage = nil }
        let previousGeneration = latestSendGenerationByRoute[route, default: 0]
        precondition(previousGeneration < UInt64.max, "Send generation exhausted")
        let generation = previousGeneration + 1
        latestSendGenerationByRoute[route] = generation
        return DraftSubmission(
            body: draft(for: route),
            route: route,
            replyingTo: replyTargetIDByRoute[route],
            draftRevision: draftRevisionsByRoute[route, default: 0],
            routeGeneration: generation
        )
    }

    public func sendDraft(_ submission: DraftSubmission) async throws {
        guard !isRefreshingRuntime else { throw ReplyError.refreshingRuntime }
        let body = submission.body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        sendsInFlight += 1
        defer { sendsInFlight -= 1 }
        if let messageID = submission.replyingTo {
            _ = try await interactions().sendText(body, to: submission.route, replyingTo: messageID)
            finishReply(to: messageID, in: submission.route)
        } else {
            _ = try await gateway.sendText(body, to: submission.route)
        }
        guard isLatest(submission) else { return }
        sendFailuresByRoute[submission.route] = nil
        if draftRevisionsByRoute[submission.route, default: 0] == submission.draftRevision {
            setDraft("", for: submission.route)
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
        conversations.first { $0.route == route }?.capabilities ?? .textOnly
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

    /// Stages a picture that has no file of its own, such as a screenshot on the clipboard.
    ///
    /// The bytes are kept only until the picture is sent or taken back.
    @discardableResult
    public func stageAttachment(
        _ data: Data,
        named filename: String,
        for route: ConversationRoute
    ) -> AttachmentRejection? {
        let fileURL: URL
        do {
            fileURL = try composerFiles.write(data, named: filename)
        } catch {
            let rejection = AttachmentRejection.unreadable("Inbox+ could not keep a copy of it to send")
            sendFailuresByRoute[route] = rejection.message
            return rejection
        }
        let rejection = stageAttachment(at: fileURL, for: route)
        if rejection != nil { composerFiles.discard(fileURL) }
        return rejection
    }

    public func removeStagedAttachment(_ attachment: OutgoingAttachment, for route: ConversationRoute) {
        stagedAttachmentsByRoute[route]?.removeAll { $0 == attachment }
        if stagedAttachmentsByRoute[route]?.isEmpty == true {
            stagedAttachmentsByRoute[route] = nil
        }
        composerFiles.discard(attachment.fileURL)
    }

    /// Sends everything staged for a route, then the text, in that order.
    ///
    /// A file that fails to send stays staged: dropping it would lose the user's choice with
    /// nothing to show for it.
    public func sendStagedAttachments(for submission: DraftSubmission) async throws {
        guard !isRefreshingRuntime else { throw ReplyError.refreshingRuntime }
        let route = submission.route
        sendsInFlight += 1
        defer { sendsInFlight -= 1 }
        var replyingTo = submission.hasText ? nil : submission.replyingTo
        for attachment in stagedAttachments(for: route) {
            if let messageID = replyingTo {
                _ = try await interactions().send(attachment, to: route, replyingTo: messageID)
                finishReply(to: messageID, in: route)
                replyingTo = nil
            } else {
                _ = try await gateway.send(attachment, to: route)
            }
            removeStagedAttachment(attachment, for: route)
        }
    }

    // MARK: - Replies and reactions

    public func canReply(to message: Message) -> Bool {
        capabilities(for: message.route).canReply && message.acceptsResponses
    }

    public func canReact(to message: Message) -> Bool {
        capabilities(for: message.route).canReact && message.acceptsResponses
    }

    /// The message the composer is answering, while it is still in the transcript.
    public func replyTarget(in route: ConversationRoute) -> Message? {
        guard let messageID = replyTargetIDByRoute[route] else { return nil }
        return messagesByRoute[route]?.first { $0.id == messageID }
    }

    public func beginReply(to message: Message) {
        guard canReply(to: message) else { return }
        replyTargetIDByRoute[message.route] = message.id
    }

    public func cancelReply(in route: ConversationRoute) {
        replyTargetIDByRoute[route] = nil
    }

    public func toggleReaction(_ key: String, on message: Message) async throws {
        guard canReact(to: message) else { throw MessageInteractionError.unsupported }
        try await interactions().toggleReaction(key, to: message.id, in: message.route)
    }

    /// Clears the reply once it has gone, unless the user has since chosen another message.
    private func finishReply(to messageID: String, in route: ConversationRoute) {
        if replyTargetIDByRoute[route] == messageID { replyTargetIDByRoute[route] = nil }
    }

    private func interactions() throws -> any MessageInteractionGateway {
        guard let source = gateway as? any MessageInteractionGateway else { throw MessageInteractionError.unsupported }
        return source
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

    public var people: [InboxPlusPerson] {
        directory.people.values.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    public func personID(for route: ConversationRoute) -> String? {
        guard let identityID = conversations.first(where: { $0.route == route })?.identityID else { return nil }
        return directory.personID(linkedTo: identityID)
    }

    public func canLinkConversation(_ route: ConversationRoute) -> Bool {
        conversations.contains { $0.route == route && !$0.isGroup }
    }

    public var suggestedContactLinks: [SuggestedContactLink] {
        SuggestedContactLink.matches(conversations: conversations.filter {
            directory.personID(linkedTo: $0.identityID) == nil
        }, accounts: accounts)
    }

    public func acceptSuggestedContactLink(_ suggestion: SuggestedContactLink) throws {
        guard suggestedContactLinks.contains(suggestion) else { return }
        let personID = UUID().uuidString
        var updated = directory
        try updated.createPerson(id: personID, displayName: suggestion.displayName)
        for identityID in suggestion.identityIDs {
            try updated.link(remoteIdentityID: identityID, to: personID)
        }
        try saveContactDirectory(updated)
        rebuildInbox()
        detailSelection = .personSummary(personID)
    }

    public func renamePerson(_ personID: String, displayName: String) throws {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw ContactDirectoryError.missingPerson }
        var updated = directory
        try updated.renamePerson(id: personID, displayName: name)
        try saveContactDirectory(updated)
        rebuildInbox()
    }

    public func removePerson(_ personID: String) throws {
        var updated = directory
        updated.removePerson(id: personID)
        try saveContactDirectory(updated)
        rebuildInbox()
        detailSelection = .empty
    }

    public func changePerson(for route: ConversationRoute, to personID: String?) throws {
        guard canLinkConversation(route),
              let identityID = conversations.first(where: { $0.route == route })?.identityID
        else { throw InboxPlusAppModelError.missingOpenConversation }
        var updated = directory
        if let oldID = updated.personID(linkedTo: identityID) {
            try updated.unlink(remoteIdentityID: identityID, from: oldID)
        }
        if let personID { try updated.link(remoteIdentityID: identityID, to: personID) }
        try saveContactDirectory(updated)
        rebuildInbox()
    }

    public func linkOpenConversation(to personID: String) throws {
        let identityID = try openIdentityForLinking()
        var updated = directory
        try updated.link(remoteIdentityID: identityID, to: personID)
        try saveContactDirectory(updated)
        rebuildInbox()
        detailSelection = .personSummary(personID)
    }

    private func openIdentityForLinking() throws -> String {
        guard
            let route = openRoute,
            canLinkConversation(route),
            let identityID = conversations.first(where: { $0.route == route })?.identityID
        else { throw InboxPlusAppModelError.missingOpenConversation }
        return identityID
    }

    @discardableResult
    public func createPersonAndLinkOpenConversation(displayName: String) throws -> String {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ContactDirectoryError.missingPerson }
        let personID = UUID().uuidString
        let identityID = try openIdentityForLinking()
        var updated = directory
        try updated.createPerson(id: personID, displayName: trimmed)
        try updated.link(remoteIdentityID: identityID, to: personID)
        try saveContactDirectory(updated)
        rebuildInbox()
        detailSelection = .personSummary(personID)
        return personID
    }

    private func saveContactDirectory(_ updated: ContactDirectory) throws {
        guard !contactLoadFailed else { throw ContactStorageError.loadFailed }
        do { try contactStore?.save(updated) }
        catch {
            contactError = ContactStorageError.saveFailed.localizedDescription
            throw ContactStorageError.saveFailed
        }
        directory = updated
        contactError = nil
    }

    private func apply(_ snapshot: MessagingSnapshot) {
        Self.reportLoadedAccounts(snapshot)
        accounts = snapshot.accounts
        identities = snapshot.identities
        conversations = snapshot.conversations.map(keepingUnreadMark)
        messagesByRoute = snapshot.messagesByRoute.mapValues { $0.sorted { $0.timestamp < $1.timestamp } }
        for route in messagesByRoute.keys where route != openRoute { trimToRecentWindow(route) }
        lastActivityByAccount = Dictionary(
            snapshot.conversations.map { ($0.accountID, $0.latestActivity) },
            uniquingKeysWith: max
        )
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
        // A disconnect outlives the session: its bridge stays stopped, so it has to read as stopped.
        let disconnected = try await accountLifecycle?.disconnectedAccountIDs() ?? []
        try Task.checkCancellation()
        guard startupID == id else { throw CancellationError() }
        try AccountPolicy.validate(snapshot.accounts)
        apply(snapshot)
        disconnectedAccountIDs = disconnected.intersection(snapshot.accounts.map(\.id))
        reportDisconnections()
        Task { await refreshSignedInNames() }

        let events = bufferedStartupEvents
        bufferedStartupEvents.removeAll()
        bufferingEventTaskID = nil
        for event in events {
            receive(event, from: id)
        }
        flushHistoricalMessages()
    }

    private func beginStartup() -> UUID {
        let id = UUID()
        startupID = id
        notificationsStartedAt = Date()
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
        } else if case let .historicalMessageUpserted(message) = event {
            if let revision = recentMessageLoadRevisions[message.route] {
                recentMessageLoadRevisions[message.route] = revision &+ 1
            }
            pendingHistoricalMessages.append(message)
            guard historyFlushTask == nil else { return }
            historyFlushTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .milliseconds(16))
                guard !Task.isCancelled else { return }
                self?.flushHistoricalMessages()
            }
        } else {
            flushHistoricalMessages()
            apply(event)
        }
    }

    private func flushHistoricalMessages() {
        historyFlushTask?.cancel()
        historyFlushTask = nil
        guard !pendingHistoricalMessages.isEmpty else { return }
        let messages = pendingHistoricalMessages
        pendingHistoricalMessages.removeAll(keepingCapacity: true)
        applyMessages(messages, isLive: false)
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
        case let .messageUpserted(message), let .historicalMessageUpserted(message):
            let isLive: Bool
            if case .messageUpserted = event { isLive = true } else { isLive = false }
            applyMessages([message], isLive: isLive)
        case let .messagesRemoved(route, messageIDs):
            messagesByRoute[route]?.removeAll { messageIDs.contains($0.id) }
        case let .identityUpserted(identity):
            if let index = identities.firstIndex(where: { $0.id == identity.id }) {
                identities[index] = identity
            } else {
                identities.append(identity)
            }
            rebuildInbox()
        case let .conversationUpserted(conversation):
            conversations.removeAll { $0.id == conversation.id && $0.accountID == conversation.accountID }
            conversations.append(keepingUnreadMark(conversation))
            rebuildInbox()
        case let .conversationTitleChanged(route, title):
            guard let index = conversations.firstIndex(where: { $0.route == route }) else { return }
            conversations[index].title = title
            rebuildInbox()
        case let .accountUpserted(account):
            upsert(account)
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

    private func applyMessages(_ updates: [Message], isLive: Bool) {
        var needsInboxRebuild = false
        for (route, updates) in Dictionary(grouping: updates, by: \.route) {
            let existing = messagesByRoute[route] ?? []
            var orderedIDs = existing.map(\.id)
            var byID = Dictionary(existing.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
            var changed = false
            for message in updates {
                let isNew = byID[message.id] == nil
                guard byID[message.id] != message else { continue }
                changed = true
                if isNew { orderedIDs.append(message.id) }
                if isLive, isNew, !message.isOutgoing, message.kind != .membership,
                   message.timestamp >= notificationsStartedAt, !isMuted(message.route) {
                    onIncomingMessage?(alert(for: message))
                }
                if isLive, isNew, !message.isOutgoing, message.route == openRoute {
                    saveReadState(of: message.route)
                }
                byID[message.id] = message
                let accountID = message.route.accountID
                if message.timestamp > lastActivityByAccount[accountID] ?? .distantPast {
                    lastActivityByAccount[accountID] = message.timestamp
                }
                // Writing back is what makes a stranger someone the user talks to.
                if message.isOutgoing,
                   let index = conversations.firstIndex(where: { $0.route == message.route && $0.isFromUnknownSender }) {
                    conversations[index].isFromUnknownSender = false
                    needsInboxRebuild = true
                }
                if
                    let conversationIndex = conversations.firstIndex(where: { $0.route == message.route }),
                    message.timestamp > conversations[conversationIndex].latestActivity
                {
                    conversations[conversationIndex].latestPreview = message.body
                    conversations[conversationIndex].latestActivity = message.timestamp
                    needsInboxRebuild = true
                }
            }
            guard changed else { continue }
            var messages = orderedIDs.compactMap { byID[$0] }.sorted { $0.timestamp < $1.timestamp }
            if route != openRoute {
                let cutoff = messages.count - RecentHistory.messageCount
                if cutoff > 0 {
                    messages = messages.enumerated()
                        .filter { $0.offset >= cutoff || $0.element.deliveryState != .acknowledged }
                        .map(\.element)
                }
            }
            messagesByRoute[route] = messages
        }
        if needsInboxRebuild { rebuildInbox() }
    }

    /// A closed conversation keeps only its recent window, so a long session does not hold every
    /// message it has seen. One not yet confirmed stays whatever its age: it is still the user's.
    private func trimToRecentWindow(_ route: ConversationRoute) {
        guard let messages = messagesByRoute[route] else { return }
        let cutoff = messages.count - RecentHistory.messageCount
        guard cutoff > 0 else { return }
        messagesByRoute[route] = messages.enumerated()
            .filter { $0.offset >= cutoff || $0.element.deliveryState != .acknowledged }
            .map(\.element)
    }

    private func rebuildInbox() {
        let now = Date()
        updatePreferences { $0.reviveHidden(in: conversations, at: now) }
        inboxItems = InboxProjector.project(
            accounts: accounts,
            identities: identities,
            conversations: conversations,
            directory: directory,
            favouriteRoutes: favouriteRoutes,
            preferences: preferences,
            now: now
        )
        scheduleMuteEnd()
    }
}
