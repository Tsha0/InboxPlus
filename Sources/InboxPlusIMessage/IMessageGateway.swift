import Foundation
import InboxPlusCore
import InboxPlusGateway

/// Brings the local Messages database into Inbox+ as an ordinary gateway.
///
/// iMessage never touches Matrix: there is no bridge process, no homeserver room, and no
/// credential. Reads come from the local database and sends go to Messages itself, so this
/// implements the same seam the Matrix gateway does and the app layer cannot tell the difference.
public actor IMessageGateway: ConversationStartingGateway {
    public static let accountID = "imessage-local"
    /// How long a chat can go without a message before it is left out of the inbox. A Mac's
    /// Messages history goes back years, and listing every chat ever started buries the ones still
    /// going. A new message brings a chat back.
    static let activityWindow: TimeInterval = 365 * 24 * 60 * 60

    private let store: IMessageStore
    private let sender: IMessageSender
    private let contacts: any IMessageContactSource
    private let historyLimit: Int
    private let pollInterval: Duration
    private let readMarkerStore: IMessageReadMarkerStore?

    private var streamContinuations: [UUID: AsyncStream<GatewayEvent>.Continuation] = [:]
    private var pollTask: Task<Void, Never>?
    private var lastSeenRowID: Int64 = 0
    private var chatsByGUID: [String: IMessageChat] = [:]
    private var publishedChatGUIDs: Set<String> = []
    private var loadedHistoryChatGUIDs: Set<String> = []
    private var knownIdentityIDs: Set<String> = []
    private var newRecipientsByRoute: [String: String] = [:]
    private var readMarkers: [String: Int64] = [:]
    private var contactBook = IMessageContactBook()

    public func canStartConversation(accountID: String) async -> Bool {
        accountID == Self.accountID
    }

    public func startConversation(accountID: String, recipient: String) async throws -> StartedConversation {
        guard accountID == Self.accountID else { throw ConversationStartError.unavailable }
        let address = try Self.normalizeRecipient(recipient)
        let existing = try existingChat(with: address)
        let guid = newRecipientsByRoute.first { $0.value == address }?.key
            ?? existing?.guid ?? "iMessage;-;\(address)"
        if existing == nil { newRecipientsByRoute[guid] = address }
        let identity = RemoteIdentity(id: existing.map(identityID(for:)) ?? address,
                                      accountID: accountID, displayName: existing.map(displayName(for:)) ?? address)
        return StartedConversation(identity: identity, conversation: RemoteConversation(
            id: guid, accountID: accountID, identityID: identity.id,
            title: identity.displayName, latestActivity: .now, unreadCount: 0, capabilities: .textOnly
        ))
    }

    static func normalizeRecipient(_ value: String) throws -> String {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.range(of: #"^[A-Za-z0-9.!#$%&'*+/=?^_`{|}~-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+$"#, options: .regularExpression) != nil {
            return value.lowercased()
        }
        let phone = value.filter { !" ()-.".contains($0) }
        guard phone.range(of: #"^\+[1-9][0-9]{6,14}$"#, options: .regularExpression) != nil else {
            throw ConversationStartError.invalidRecipient
        }
        return phone
    }

    public init(
        store: IMessageStore,
        sender: IMessageSender = IMessageSender(),
        contacts: any IMessageContactSource = IMessageContactBook(),
        historyLimit: Int = 50,
        pollInterval: Duration = .seconds(3),
        readMarkerStore: IMessageReadMarkerStore? = nil
    ) {
        self.store = store
        self.sender = sender
        self.contacts = contacts
        self.historyLimit = historyLimit
        self.pollInterval = pollInterval
        self.readMarkerStore = readMarkerStore
    }

    deinit { pollTask?.cancel() }

    // MARK: - MessagingGateway

    public func loadSnapshot() async throws -> MessagingSnapshot {
        // Read before anything is titled. The first time, this waits for the Contacts prompt.
        contactBook = await contacts.contactBook()
        let chats = try store.chats()
        chatsByGUID = Dictionary(chats.map { ($0.guid, $0) }, uniquingKeysWith: { first, _ in first })

        // Each active chat arrives with only its newest message: history for every chat would be
        // every message in the database, so a chat's history waits until it is opened.
        // The row id is read before those messages, so one arriving meanwhile is polled, not missed.
        lastSeenRowID = max(lastSeenRowID, try store.maxMessageRowID())
        let activeSince = activeSince()
        var messagesByRoute: [ConversationRoute: [Message]] = [:]
        var identities: [String: RemoteIdentity] = [:]
        let unreadByChat = try unreadCounts()
        var conversations: [RemoteConversation] = []

        for row in try store.latestMessages() {
            guard let chat = chatsByGUID[row.chatGUID], let date = row.date, date >= activeSince
            else { continue }
            let latest = message(from: row)
            if let latest {
                messagesByRoute[latest.route] = [latest]
                if let identity = identity(for: row) { identities[identity.id] = identity }
            }
            // A conversation whose own identity is unknown is dropped by the inbox, and a group's
            // identity is the chat itself rather than any sender.
            let chatIdentity = identity(for: chat)
            if identities[chatIdentity.id] == nil { identities[chatIdentity.id] = chatIdentity }
            conversations.append(conversation(
                for: chat, preview: latest?.body ?? "", at: date, unreadCount: unreadByChat[chat.guid] ?? 0
            ))
        }

        knownIdentityIDs = Set(identities.keys)
        publishedChatGUIDs = Set(conversations.map(\.id))
        loadedHistoryChatGUIDs = []

        startPolling()

        return MessagingSnapshot(
            accounts: [
                ConnectedAccount(id: Self.accountID, platform: .iMessage, displayName: "iMessage"),
            ],
            identities: Array(identities.values),
            conversations: conversations.sorted { $0.latestActivity > $1.latestActivity },
            messagesByRoute: messagesByRoute
        )
    }

    public func events() async -> AsyncStream<GatewayEvent> {
        AsyncStream { continuation in
            let id = UUID()
            streamContinuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeContinuation(id) }
            }
        }
    }

    public func loadRecentMessages(in route: ConversationRoute) async throws {
        guard !loadedHistoryChatGUIDs.contains(route.conversationID),
              let chat = chatsByGUID[route.conversationID]
        else { return }
        let rows = try store.recentMessages(inChat: chat.rowID, limit: historyLimit)
        loadedHistoryChatGUIDs.insert(chat.guid)
        for row in rows {
            guard let message = message(from: row) else { continue }
            if let identity = identity(for: row) { publishIfNew(identity) }
            publish(.historicalMessageUpserted(message))
        }
    }

    public func sendText(_ body: String, to route: ConversationRoute) async throws -> SendReceipt {
        guard route.accountID == Self.accountID else { throw ConversationStartError.unavailable }
        if let recipient = newRecipientsByRoute[route.conversationID] {
            if let chat = try existingChat(with: recipient) {
                try sender.send(body, toChatGUID: chat.guid)
            } else {
                try sender.send(body, toNewRecipient: recipient)
            }
        } else {
            try sender.send(body, toChatGUID: route.conversationID)
        }
        // Deliberately pending. Messages has accepted the request; the sent message appears in the
        // database once it is really sent, and the poll promotes it then. Reporting success here
        // would claim delivery Inbox+ has not observed.
        return SendReceipt(messageID: UUID().uuidString, route: route, deliveryState: .pending)
    }

    public func send(_ attachment: OutgoingAttachment, to route: ConversationRoute) async throws -> SendReceipt {
        throw IMessageSendError.messagesReportedFailure(
            "Inbox+ cannot send attachments to iMessage yet."
        )
    }

    /// Everything Inbox+ has shown in the chat is now read. A message written to the database since
    /// the last poll has not been shown yet, so it stays unread.
    public func markRead(_ route: ConversationRoute) async throws {
        let chatGUID = route.conversationID
        guard lastSeenRowID > readMarkers[chatGUID] ?? 0 else { return }
        var updated = readMarkers
        updated[chatGUID] = lastSeenRowID
        try readMarkerStore?.save(updated)
        readMarkers = updated
    }

    private func unreadCounts() throws -> [String: Int] {
        if let readMarkerStore { readMarkers = try readMarkerStore.load() }
        return try store.unreadCounts(after: readMarkers)
    }

    // MARK: - Polling

    /// The Messages database has no change notification, so new messages are noticed by watching
    /// the row id advance.
    private func startPolling() {
        guard pollTask == nil else { return }
        pollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: self.pollInterval)
                guard !Task.isCancelled else { return }
                await self.pollOnce()
            }
        }
    }

    /// Stops reading the Messages database. What was already read stays on screen.
    public func pausePolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// Reads again from where `pausePolling()` stopped, so nothing that arrived meanwhile is missed.
    public func resumePolling() {
        startPolling()
    }

    func pollOnce() async {
        guard let rows = try? store.messages(afterRowID: lastSeenRowID), !rows.isEmpty else { return }
        lastSeenRowID = max(lastSeenRowID, rows.map(\.rowID).max() ?? lastSeenRowID)

        // Refresh the chat map first: a message can arrive in a conversation that did not exist
        // when the snapshot was taken.
        if let chats = try? store.chats() {
            chatsByGUID = Dictionary(chats.map { ($0.guid, $0) }, uniquingKeysWith: { first, _ in first })
        }

        for row in rows {
            guard let message = message(from: row), publishConversationIfNeeded(for: message)
            else { continue }
            // An identity must reach the inbox before any conversation or message naming it.
            if let identity = identity(for: row) { publishIfNew(identity) }
            publish(.messageUpserted(message))
        }
    }

    /// Brings a chat into the inbox with its first new message, whether the snapshot left it out as
    /// quiet or it was started since, and reports whether the message now has a chat to land in.
    /// Old history still arriving from iCloud does not count, or a sync would bring back every
    /// quiet chat.
    private func publishConversationIfNeeded(for message: Message) -> Bool {
        let guid = message.route.conversationID
        guard !publishedChatGUIDs.contains(guid) else { return true }
        guard message.timestamp >= activeSince(), let chat = chatsByGUID[guid] else { return false }
        publishIfNew(identity(for: chat))
        publish(.conversationUpserted(conversation(for: chat, preview: message.body, at: message.timestamp)))
        publishedChatGUIDs.insert(guid)
        return true
    }

    private func publishIfNew(_ identity: RemoteIdentity) {
        if knownIdentityIDs.insert(identity.id).inserted { publish(.identityUpserted(identity)) }
    }

    private func activeSince() -> Date {
        Date().addingTimeInterval(-Self.activityWindow)
    }

    private func publish(_ event: GatewayEvent) {
        for continuation in streamContinuations.values { continuation.yield(event) }
    }

    private func removeContinuation(_ id: UUID) { streamContinuations[id] = nil }

    // MARK: - Mapping

    // Keep an open compose route stable if Messages assigns a different GUID on first send.
    private func routeID(for chat: IMessageChat) -> String {
        guard !chat.isGroup, let address = try? Self.normalizeRecipient(chat.identifier) else { return chat.guid }
        return newRecipientsByRoute.first { $0.value == address }?.key ?? chat.guid
    }

    /// Recent macOS files one-to-one chats under an `any;-;` GUID whatever service carries them, so
    /// the service name cannot decide whether a chat with this person already exists.
    private func existingChat(with address: String) throws -> IMessageChat? {
        let matches = try store.chats().filter {
            !$0.isGroup && (try? Self.normalizeRecipient($0.identifier)) == address
        }
        return matches.first { $0.service == "iMessage" } ?? matches.first
    }

    private func conversation(
        for chat: IMessageChat, preview: String, at date: Date, unreadCount: Int = 0
    ) -> RemoteConversation {
        RemoteConversation(
            id: routeID(for: chat),
            accountID: Self.accountID,
            identityID: identityID(for: chat),
            title: displayName(for: chat),
            latestPreview: preview,
            latestActivity: date,
            unreadCount: unreadCount,
            // Messages accepts text through Apple events. Attachments would need a
            // different mechanism, so the composer does not offer them here.
            capabilities: ConversationCapabilities(canSendText: true, attachmentKinds: []),
            isGroup: chat.isGroup
        )
    }

    private func message(from row: IMessageRow) -> Message? {
        guard let timestamp = row.date else { return nil }
        let body = row.body ?? placeholder(for: row)
        guard let body else { return nil }
        return Message(
            id: row.guid.isEmpty ? "imessage-\(row.rowID)" : row.guid,
            route: ConversationRoute(accountID: Self.accountID, conversationID: chatsByGUID[row.chatGUID].map(routeID(for:)) ?? row.chatGUID),
            senderIdentityID: row.isFromMe ? nil : identityID(for: row),
            body: body,
            timestamp: timestamp,
            deliveryState: .acknowledged,
            kind: row.attachmentCount > 0 ? .file : .text
        )
    }

    /// An attachment-only message has no text at all. Dropping it would leave a visible gap in a
    /// conversation, so it becomes a visible note about what was sent.
    private func placeholder(for row: IMessageRow) -> String? {
        guard row.attachmentCount > 0 else { return nil }
        return row.attachmentCount == 1
            ? "Sent an attachment"
            : "Sent \(row.attachmentCount) attachments"
    }

    private func identity(for row: IMessageRow) -> RemoteIdentity? {
        guard !row.isFromMe else { return nil }
        let id = identityID(for: row)
        return RemoteIdentity(
            id: id,
            accountID: Self.accountID,
            displayName: row.handle.map(contactBook.name(forHandle:))
                ?? chatsByGUID[row.chatGUID].map(displayName(for:)) ?? id
        )
    }

    private func identity(for chat: IMessageChat) -> RemoteIdentity {
        RemoteIdentity(id: identityID(for: chat), accountID: Self.accountID, displayName: displayName(for: chat))
    }

    private func identityID(for row: IMessageRow) -> String {
        row.handle ?? "imessage-chat-\(row.chatGUID)"
    }

    /// A group has no single person behind it, so the conversation stands for itself.
    private func identityID(for chat: IMessageChat) -> String {
        chat.isGroup || chat.identifier.isEmpty
            ? "imessage-chat-\(chat.guid)"
            : chat.identifier
    }

    private func displayName(for chat: IMessageChat) -> String {
        if let name = chat.displayName, !name.trimmingCharacters(in: .whitespaces).isEmpty {
            return name
        }
        // An unnamed group's identifier is an internal id such as `chat123456789`, so it is titled
        // after the people in it, as Messages does.
        if chat.isGroup {
            let participants = (try? store.participants(inChat: chat.rowID)) ?? []
            return contactBook.groupTitle(forHandles: participants) ?? "Group conversation"
        }
        return chat.identifier.isEmpty ? "iMessage conversation" : contactBook.name(forHandle: chat.identifier)
    }
}
