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

    private let store: IMessageStore
    private let sender: IMessageSender
    private let historyLimit: Int
    private let pollInterval: Duration

    private var streamContinuations: [UUID: AsyncStream<GatewayEvent>.Continuation] = [:]
    private var pollTask: Task<Void, Never>?
    private var lastSeenRowID: Int64 = 0
    private var chatsByGUID: [String: IMessageChat] = [:]
    private var knownIdentityIDs: Set<String> = []
    private var newRecipientsByRoute: [String: String] = [:]

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
        historyLimit: Int = 300,
        pollInterval: Duration = .seconds(3)
    ) {
        self.store = store
        self.sender = sender
        self.historyLimit = historyLimit
        self.pollInterval = pollInterval
    }

    deinit { pollTask?.cancel() }

    // MARK: - MessagingGateway

    public func loadSnapshot() async throws -> MessagingSnapshot {
        let chats = try store.chats()
        chatsByGUID = Dictionary(chats.map { ($0.guid, $0) }, uniquingKeysWith: { first, _ in first })

        let rows = try store.recentMessages(limit: historyLimit)
        let highestRowID = try rows.map(\.rowID).max() ?? store.maxMessageRowID()
        lastSeenRowID = max(lastSeenRowID, highestRowID)

        var messagesByRoute: [ConversationRoute: [Message]] = [:]
        var identities: [String: RemoteIdentity] = [:]
        var latestByChat: [String: Message] = [:]

        for row in rows {
            guard let message = message(from: row) else { continue }
            messagesByRoute[message.route, default: []].append(message)
            latestByChat[row.chatGUID] = message
            if let identity = identity(for: row) { identities[identity.id] = identity }
        }

        var conversations: [RemoteConversation] = []
        for chat in chats {
            let route = ConversationRoute(accountID: Self.accountID, conversationID: chat.guid)
            let latest = latestByChat[chat.guid]
            // A conversation with no readable message still needs an identity, or the inbox drops
            // it and the user simply never sees the chat.
            let identityID = identityID(for: chat)
            if identities[identityID] == nil {
                identities[identityID] = RemoteIdentity(
                    id: identityID,
                    accountID: Self.accountID,
                    displayName: displayName(for: chat)
                )
            }
            conversations.append(
                RemoteConversation(
                    id: routeID(for: chat),
                    accountID: Self.accountID,
                    identityID: identityID,
                    title: displayName(for: chat),
                    latestPreview: latest?.body ?? "",
                    latestActivity: latest?.timestamp ?? Date(timeIntervalSince1970: 0),
                    unreadCount: 0,
                    // Messages accepts text through Apple events. Attachments would need a
                    // different mechanism, so the composer does not offer them here.
                    capabilities: ConversationCapabilities(canSendText: true, attachmentKinds: [])
                )
            )
            _ = route
        }

        knownIdentityIDs = Set(identities.keys)
        for key in messagesByRoute.keys {
            messagesByRoute[key]?.sort { $0.timestamp < $1.timestamp }
        }

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

    func pollOnce() async {
        guard let rows = try? store.messages(afterRowID: lastSeenRowID), !rows.isEmpty else { return }
        lastSeenRowID = max(lastSeenRowID, rows.map(\.rowID).max() ?? lastSeenRowID)

        // Refresh the chat map first: a message can arrive in a conversation that did not exist
        // when the snapshot was taken.
        if let chats = try? store.chats() {
            chatsByGUID = Dictionary(chats.map { ($0.guid, $0) }, uniquingKeysWith: { first, _ in first })
        }

        for row in rows {
            guard let message = message(from: row) else { continue }
            // An identity must reach the inbox before any conversation or message naming it.
            if let identity = identity(for: row), knownIdentityIDs.insert(identity.id).inserted {
                publish(.identityUpserted(identity))
            }
            publish(.messageUpserted(message))
        }
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
            displayName: row.handle ?? chatsByGUID[row.chatGUID].map(displayName(for:)) ?? id
        )
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
        return chat.identifier.isEmpty ? "iMessage conversation" : chat.identifier
    }
}
