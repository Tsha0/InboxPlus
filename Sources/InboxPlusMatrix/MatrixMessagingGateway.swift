import Foundation
import MatrixRustSDK
import InboxPlusCore
import InboxPlusGateway

/// Bridges the Matrix Rust SDK to Inbox+'s `MessagingGateway` seam.
///
/// The app layer keeps talking to the protocol it already used for the in-memory fake, so nothing
/// in `InboxPlusFeatures` or `InboxPlusUI` needs to know Matrix exists.
public actor MatrixMessagingGateway: MessagingGateway {
    public static let defaultAccountID = "matrix-local"

    private let client: InboxPlusMatrixClient
    private let normalizer: MatrixEventNormalizer
    private let accountID: String
    private let platform: Platform
    private let initialMessageWait: Duration
    private let initialSyncWait: Duration
    private let invitePolicy: BridgeInvitePolicy
    private let bridgeAccounts: [String: BridgeAccountDescriptor]
    private let roomDiscoveryInterval: Duration
    private let backfillEventCount: UInt16

    private let outgoingIdentifiersProvider: @Sendable () async -> [String: Set<String>]
    private var outgoingIdentifiersByAccount: [String: Set<String>] = [:]
    private var identityRefreshTask: Task<[String: Set<String>], Never>?

    private var streamContinuations: [UUID: AsyncStream<GatewayEvent>.Continuation] = [:]
    private var timelineHandles: [String: TaskHandle] = [:]
    private var observers: [String: RoomTimelineObserver] = [:]
    private var started = false
    private var knownRoomIDs: Set<String> = []
    private var discoveryTask: Task<Void, Never>?
    /// Which account each room belongs to, resolved once from its members.
    private var accountIDByRoomID: [String: String] = [:]

    public init(
        client: InboxPlusMatrixClient,
        accountID: String = MatrixMessagingGateway.defaultAccountID,
        platform: Platform = .matrix,
        initialMessageWait: Duration = .milliseconds(1_500),
        initialSyncWait: Duration = .seconds(10),
        invitePolicy: BridgeInvitePolicy = .trustingNobody,
        bridgeAccounts: [BridgeAccountDescriptor] = [],
        roomDiscoveryInterval: Duration = .seconds(3),
        backfillEventCount: UInt16 = 50,
        outgoingIdentifiersProvider: @escaping @Sendable () async -> [String: Set<String>] = { [:] }
    ) {
        self.outgoingIdentifiersProvider = outgoingIdentifiersProvider
        self.client = client
        self.accountID = accountID
        self.platform = platform
        self.initialMessageWait = initialMessageWait
        self.initialSyncWait = initialSyncWait
        self.invitePolicy = invitePolicy
        self.bridgeAccounts = Dictionary(
            bridgeAccounts.map { ($0.bridgeID, $0) }, uniquingKeysWith: { first, _ in first }
        )
        self.roomDiscoveryInterval = roomDiscoveryInterval
        self.backfillEventCount = backfillEventCount
        normalizer = MatrixEventNormalizer(accountID: accountID)
    }

    // MARK: - MessagingGateway

    public func loadSnapshot() async throws -> MessagingSnapshot {
        try await start()
        await acceptTrustedInvites()

        let rooms = try await client.requireClient().rooms()
        var conversations: [RemoteConversation] = []
        var messagesByRoute: [ConversationRoute: [Message]] = [:]
        var identities: [String: RemoteIdentity] = [:]

        for room in rooms where room.membership() == .joined {
            let info = try await room.roomInfo()
            let roomAccountID = await resolvedAccountID(for: room)
            let route = normalizer.route(forRoom: room.id(), accountID: roomAccountID)
            knownRoomIDs.insert(room.id())
            await attachTimeline(to: room)

            // Give the timeline a bounded moment to deliver its first batch. A room with nothing
            // yet loaded still appears, just without history, rather than blocking the inbox.
            let messages = await observers[room.id()]?.messages(waitingUpTo: initialMessageWait) ?? []
            let ordered = messages.sorted(by: inboxplusMessageOrdering)
            messagesByRoute[route] = ordered

            for message in ordered {
                guard let senderID = message.senderIdentityID else { continue }
                identities[senderID] = RemoteIdentity(
                    id: senderID,
                    accountID: roomAccountID,
                    displayName: Self.displayName(forUserID: senderID)
                )
            }

            let title = info.displayName ?? info.rawName ?? room.id()
            // Phase 3 has no contact linking against Matrix identities yet, so a conversation
            // stands for itself when nothing has been received in it.
            let identityID = ordered.compactMap(\.senderIdentityID).first ?? room.id()
            // The inbox drops any conversation whose identity it does not know, so a room that has
            // not delivered a message yet needs one synthesised or it is silently invisible. A
            // freshly bridged conversation is exactly that room.
            if identities[identityID] == nil {
                identities[identityID] = RemoteIdentity(
                    id: identityID,
                    accountID: roomAccountID,
                    displayName: identityID == room.id() ? title : Self.displayName(forUserID: identityID)
                )
            }

            conversations.append(
                RemoteConversation(
                    id: room.id(),
                    accountID: roomAccountID,
                    identityID: identityID,
                    title: title,
                    latestPreview: ordered.last?.body ?? "",
                    latestActivity: ordered.last?.timestamp ?? Date(timeIntervalSince1970: 0),
                    unreadCount: Int(info.numUnreadMessages)
                )
            )
        }

        return MessagingSnapshot(
            accounts: accounts(owning: conversations.map(\.accountID)),
            identities: Array(identities.values),
            conversations: conversations.sorted { $0.latestActivity > $1.latestActivity },
            messagesByRoute: messagesByRoute
        )
    }

    public func events() async -> AsyncStream<GatewayEvent> {
        let id = UUID()
        return AsyncStream { continuation in
            streamContinuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeContinuation(id) }
            }
        }
    }

    public func sendText(_ body: String, to route: ConversationRoute) async throws -> SendReceipt {
        let matrixClient = try await client.requireClient()
        guard let room = try matrixClient.getRoom(roomId: route.conversationID) else {
            throw MatrixGatewayError.unknownRoom(route.conversationID)
        }
        await attachTimeline(to: room)

        let timeline = try await room.timeline()
        let handle = try await timeline.send(msg: messageEventContentFromMarkdown(md: body))

        // Deliberately `pending`. The design forbids showing a successful send before the server
        // confirms it; the timeline listener promotes this to `acknowledged` when the echo lands.
        return SendReceipt(
            messageID: Self.transactionIdentifier(for: handle),
            route: route,
            deliveryState: .pending
        )
    }

    public func send(_ attachment: OutgoingAttachment, to route: ConversationRoute) async throws -> SendReceipt {
        let matrixClient = try await client.requireClient()
        guard let room = try matrixClient.getRoom(roomId: route.conversationID) else {
            throw MatrixGatewayError.unknownRoom(route.conversationID)
        }
        await attachTimeline(to: room)

        let timeline = try await room.timeline()
        let parameters = UploadParameters(
            source: .file(filename: attachment.fileURL.path),
            caption: attachment.caption,
            formattedCaption: nil,
            mentions: nil,
            inReplyTo: nil
        )
        let size = attachment.byteCount > 0 ? UInt64(attachment.byteCount) : nil
        let width = attachment.pixelSize.map { UInt64($0.width) }
        let height = attachment.pixelSize.map { UInt64($0.height) }
        let seconds = attachment.duration.map { Double($0.components.seconds) }

        let handle = switch attachment.kind {
        case .image:
            try timeline.sendImage(
                params: parameters,
                thumbnailSource: nil,
                imageInfo: ImageInfo(
                    height: height, width: width, mimetype: attachment.mimeType, size: size,
                    thumbnailInfo: nil, thumbnailSource: nil, blurhash: nil, isAnimated: nil
                )
            )
        case .video:
            try timeline.sendVideo(
                params: parameters,
                thumbnailSource: nil,
                videoInfo: VideoInfo(
                    duration: seconds, height: height, width: width, mimetype: attachment.mimeType,
                    size: size, thumbnailInfo: nil, thumbnailSource: nil, blurhash: nil
                )
            )
        case .audio:
            try timeline.sendAudio(
                params: parameters,
                audioInfo: AudioInfo(duration: seconds, size: size, mimetype: attachment.mimeType)
            )
        default:
            try timeline.sendFile(
                params: parameters,
                fileInfo: FileInfo(
                    mimetype: attachment.mimeType, size: size,
                    thumbnailInfo: nil, thumbnailSource: nil
                )
            )
        }

        // Upload then send; only after this has the server taken the media at all. The timeline
        // listener still owns promoting the echo to `acknowledged`.
        try await handle.join()

        return SendReceipt(
            messageID: attachment.fileURL.absoluteString,
            route: route,
            deliveryState: .pending
        )
    }

    // MARK: - Lifecycle

    public func start() async throws {
        guard !started else { return }
        _ = try await client.connect()
        try await client.startSync()
        started = true
        await refreshOutgoingIdentifiers()
        await awaitInitialRooms()
        await acceptTrustedInvites()
        startRoomDiscovery()
    }

    /// Waits, briefly, for sliding sync to deliver the first room list.
    ///
    /// `rooms()` reads the local store, which is empty until the first sync response lands. Without
    /// this the very first `loadSnapshot()` returns an empty inbox even though the account has
    /// conversations. An account that genuinely has none simply waits out the deadline once.
    private func awaitInitialRooms() async {
        let deadline = ContinuousClock().now.advanced(by: initialSyncWait)
        while ContinuousClock().now < deadline {
            if let rooms = try? await client.requireClient().rooms(), !rooms.isEmpty { return }
            try? await Task.sleep(for: .milliseconds(200))
        }
    }

    /// Detaches every timeline listener. Sync itself keeps running for the client's lifetime.
    public func stop() async {
        discoveryTask?.cancel()
        discoveryTask = nil
        knownRoomIDs.removeAll()
        for handle in timelineHandles.values { handle.cancel() }
        timelineHandles.removeAll()
        observers.removeAll()
        for continuation in streamContinuations.values { continuation.finish() }
        streamContinuations.removeAll()
        started = false
    }

    // MARK: - Room discovery

    /// Joins portal rooms a trusted bridge has invited this account to.
    ///
    /// A bridge creates a portal and invites the user rather than joining them, so without this an
    /// account can be fully connected and still show nothing at all.
    private func acceptTrustedInvites() async {
        guard !invitePolicy.trustedLocalpartPrefixes.isEmpty else { return }
        guard let rooms = try? await client.requireClient().rooms() else { return }

        for room in rooms where room.membership() == .invited {
            guard let inviter = try? await room.inviter(),
                  invitePolicy.trusts(inviterUserID: inviter.userId)
            else { continue }
            // A failed join is left as an invite rather than retried into a loop; the next
            // discovery pass tries again.
            try? await room.join()
        }
    }

    /// Watches for rooms that appear after the inbox was first loaded.
    ///
    /// Bridges create portals as conversations are discovered, long after startup, so a snapshot
    /// taken once would never show a conversation that began afterwards.
    private func startRoomDiscovery() {
        guard discoveryTask == nil else { return }
        discoveryTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: self.roomDiscoveryInterval)
                guard !Task.isCancelled else { return }
                await self.discoverNewRooms()
            }
        }
    }

    private func discoverNewRooms() async {
        await refreshOutgoingIdentifiers()
        await acceptTrustedInvites()
        guard let rooms = try? await client.requireClient().rooms() else { return }

        for room in rooms where room.membership() == .joined {
            let roomID = room.id()
            guard !knownRoomIDs.contains(roomID) else { continue }
            knownRoomIDs.insert(roomID)
            let roomAccountID = await resolvedAccountID(for: room)
            await attachTimeline(to: room)

            let messages = await observers[roomID]?
                .messages(waitingUpTo: initialMessageWait)
                .sorted(by: inboxplusMessageOrdering) ?? []
            let info = try? await room.roomInfo()
            let title = info?.displayName ?? info?.rawName ?? roomID
            let identityID = messages.compactMap(\.senderIdentityID).first ?? roomID

            // Order matters: the inbox drops a conversation whose identity it has not seen, so the
            // identity has to arrive first or the room never appears.
            publish(.identityUpserted(
                RemoteIdentity(
                    id: identityID,
                    accountID: roomAccountID,
                    displayName: identityID == roomID ? title : Self.displayName(forUserID: identityID)
                )
            ))
            publish(.conversationUpserted(
                RemoteConversation(
                    id: roomID,
                    accountID: roomAccountID,
                    identityID: identityID,
                    title: title,
                    latestPreview: messages.last?.body ?? "",
                    latestActivity: messages.last?.timestamp ?? Date(),
                    unreadCount: Int(info?.numUnreadMessages ?? 0)
                )
            ))
            for message in messages { publish(.messageUpserted(message)) }
        }
    }

    // MARK: - Attribution

    /// Keep confirmed identities for this gateway's lifetime on lookup failure or logout:
    /// historical messages are still ours. Recovery repairs events loaded before the lookup worked.
    private func refreshOutgoingIdentifiers() async {
        // A history batch can deliver many callbacks at once. Share one lookup between them.
        let ownsTask = identityRefreshTask == nil
        let task = identityRefreshTask ?? Task { await outgoingIdentifiersProvider() }
        identityRefreshTask = task
        let resolved = await task.value
        if ownsTask { identityRefreshTask = nil }
        for (account, identifiers) in resolved {
            outgoingIdentifiersByAccount[account, default: []].formUnion(identifiers)
        }
        for (roomID, observer) in observers {
            let account = accountIDByRoomID[roomID] ?? accountID
            observer.updateOutgoingIdentifiers(outgoingIdentifiersByAccount[account] ?? [])
        }
    }

    /// Which account a room belongs to, resolved from who is in it.
    ///
    /// A bridged conversation is a portal room the bridge created, and the bridge's own ghost or
    /// bot is always a member. That membership is the only reliable statement of which network the
    /// conversation really is — the transport is Matrix either way, and reporting Matrix is
    /// reporting the plumbing rather than the thing the user is looking at.
    private func resolvedAccountID(for room: Room) async -> String {
        let roomID = room.id()
        if let cached = accountIDByRoomID[roomID] { return cached }

        var resolved = accountID
        if !bridgeAccounts.isEmpty {
            // The local store first, because it is free. It can legitimately be empty when member
            // state has not been lazily loaded yet, and falling back to Matrix on that would file a
            // bridged conversation under the wrong network for the rest of the session — so a miss
            // is retried against the server rather than accepted.
            if let bridgeID = await bridgeMember(of: room, synchronising: false) {
                resolved = bridgeID
            } else if let bridgeID = await bridgeMember(of: room, synchronising: true) {
                resolved = bridgeID
            }
        }
        accountIDByRoomID[roomID] = resolved
        return resolved
    }

    private func bridgeMember(of room: Room, synchronising: Bool) async -> String? {
        guard let iterator = synchronising
            ? try? await room.members()
            : try? await room.membersNoSync()
        else { return nil }

        while let chunk = iterator.nextChunk(chunkSize: 64), !chunk.isEmpty {
            for member in chunk {
                if let bridgeID = invitePolicy.bridgeID(owning: member.userId),
                   bridgeAccounts[bridgeID] != nil {
                    return bridgeID
                }
            }
        }
        return nil
    }

    /// One line naming what each conversation was attributed to.
    ///
    /// Attribution is invisible when it goes wrong — a bridged chat simply reads "Matrix" — so it
    /// is reported rather than left to be noticed.
    public func attributionSummary() -> [String: String] {
        accountIDByRoomID
    }

    /// The accounts actually worth showing: one per bridge that owns a conversation, plus the local
    /// Matrix account. A prepared bridge with no conversations yet is not presented as connected.
    private func accounts(owning roomAccountIDs: some Collection<String>) -> [ConnectedAccount] {
        var accounts: [ConnectedAccount] = []
        for bridgeID in Set(roomAccountIDs).sorted() {
            guard let descriptor = bridgeAccounts[bridgeID] else { continue }
            accounts.append(
                ConnectedAccount(
                    id: descriptor.bridgeID,
                    platform: descriptor.platform,
                    displayName: descriptor.displayName
                )
            )
        }
        // Always present, because a room that belongs to no bridge is filed against it.
        accounts.append(
            ConnectedAccount(id: accountID, platform: platform, displayName: "Local Matrix")
        )
        return accounts
    }

    // MARK: - Internals

    private func attachTimeline(to room: Room) async {
        let roomID = room.id()
        guard timelineHandles[roomID] == nil else { return }

        // Resolved here rather than passed in, so a timeline attached from a send path is stamped
        // with the same account as one attached from a snapshot.
        let roomAccountID = await resolvedAccountID(for: room)
        guard let timeline = try? await room.timeline(),
              timelineHandles[roomID] == nil, observers[roomID] == nil else { return }
        let observer = RoomTimelineObserver(
            roomID: roomID,
            normalizer: normalizer,
            accountID: roomAccountID,
            outgoingIdentifiers: outgoingIdentifiersByAccount[roomAccountID] ?? []
        ) { [weak self] event in
            Task { await self?.publishTimelineEvent(event, roomID: roomID) }
        }
        // A listener may emit its initial batch before addListener returns. Register the
        // observer first so those callbacks can refresh and read the current attribution.
        observers[roomID] = observer
        let handle = await timeline.addListener(listener: observer)
        timelineHandles[roomID] = handle

        // A live timeline begins where this account's view of the room begins. In a room Inbox+ has
        // only just joined — every bridged portal — that is the join event, so the conversation the
        // bridge backfilled sits entirely behind it and would never be shown. Paginating once pulls
        // that history in.
        _ = try? await timeline.paginateBackwards(numEvents: backfillEventCount)
    }

    private func publishTimelineEvent(_ event: GatewayEvent, roomID: String) async {
        // Some bridges use event-specific attribution. Look up newly persisted native sends
        // before exposing an incoming-looking event, rather than waiting for room discovery.
        if case let .messageUpserted(message) = event, !message.isOutgoing,
           outgoingIdentifiersByAccount[message.route.accountID] != nil {
            await refreshOutgoingIdentifiers()
        }
        // Listener callbacks hop into this actor asynchronously. If ownership changed during
        // that hop, publish the observer's current value so a stale incoming event cannot undo it.
        if case let .messageUpserted(message) = event,
           let current = observers[roomID]?.message(id: message.id) {
            publish(.messageUpserted(current))
        } else {
            publish(event)
        }
    }

    private func publish(_ event: GatewayEvent) {
        for continuation in streamContinuations.values { continuation.yield(event) }
    }

    private func removeContinuation(_ id: UUID) {
        streamContinuations[id] = nil
    }

    static func displayName(forUserID userID: String) -> String {
        // "@alice:server" reads better as "alice" until profile fetching lands.
        guard userID.hasPrefix("@"), let colon = userID.firstIndex(of: ":") else { return userID }
        return String(userID[userID.index(after: userID.startIndex)..<colon])
    }

    private static func transactionIdentifier(for handle: SendHandle) -> String {
        "txn:\(UUID().uuidString)"
    }
}

public enum MatrixGatewayError: Error, Equatable, Sendable, CustomStringConvertible {
    case unknownRoom(String)

    public var description: String {
        switch self {
        case let .unknownRoom(roomID): "no such conversation: \(roomID)"
        }
    }
}

/// Receives timeline diffs for one room and republishes them as gateway events.
final class RoomTimelineObserver: TimelineListener, @unchecked Sendable {
    private let roomID: String
    private let normalizer: MatrixEventNormalizer
    /// The account this room belongs to. Live messages must be stamped with it too, or a bridged
    /// conversation loads as Instagram and then every new message arrives as Matrix.
    private let accountID: String
    private let onEvent: @Sendable (GatewayEvent) -> Void

    private let lock = NSLock()
    private var outgoingIdentifiers: Set<String>
    private var events: [String: EventTimelineItem] = [:]
    private var known: [String: Message] = [:]
    private var receivedFirstBatch = false

    init(
        roomID: String,
        normalizer: MatrixEventNormalizer,
        accountID: String,
        outgoingIdentifiers: Set<String> = [],
        onEvent: @escaping @Sendable (GatewayEvent) -> Void
    ) {
        self.roomID = roomID
        self.normalizer = normalizer
        self.accountID = accountID
        self.onEvent = onEvent
        self.outgoingIdentifiers = outgoingIdentifiers
    }

    func onUpdate(diff: [TimelineDiff]) {
        var incoming: [EventTimelineItem] = []
        for change in diff {
            let items: [TimelineItem]
            switch change {
            case let .append(values), let .reset(values): items = values
            case let .pushBack(value), let .pushFront(value), let .insert(_, value), let .set(_, value):
                items = [value]
            case .clear, .popFront, .popBack, .remove, .truncate:
                // A redaction arrives as an event; removal diffs do not delete displayed history.
                continue
            }
            incoming += items.compactMap { $0.asEvent() }
        }
        ingest(incoming)
    }

    /// History batches and live diffs share this path, including the attribution cache.
    private func ingest(_ incoming: [EventTimelineItem]) {
        let fresh: [Message] = lock.withLock {
            receivedFirstBatch = true
            return incoming.compactMap { event in
                let id = normalizer.identifier(for: event.eventOrTransactionId)
                guard let message = normalizer.normalize(
                    event, roomID: roomID, accountID: accountID, outgoingIdentifiers: outgoingIdentifiers
                ) else { return nil }
                events[id] = event
                guard known[id] != message else { return nil }
                known[id] = message
                return message
            }
        }
        for message in fresh { onEvent(.messageUpserted(message)) }
    }

    func updateOutgoingIdentifiers(_ identifiers: Set<String>) {
        let updated: [Message] = lock.withLock {
            guard identifiers != outgoingIdentifiers else { return [] }
            outgoingIdentifiers = identifiers
            return events.values.compactMap { event in
                guard let message = normalizer.normalize(
                    event, roomID: roomID, accountID: accountID, outgoingIdentifiers: identifiers
                ), known[message.id] != message else { return nil }
                known[message.id] = message
                return message
            }
        }
        for message in updated { onEvent(.messageUpserted(message)) }
    }

    func message(id: String) -> Message? {
        lock.withLock { known[id] }
    }

    /// Current messages, waiting briefly for the timeline's first batch to arrive.
    func messages(waitingUpTo timeout: Duration) async -> [Message] {
        let deadline = ContinuousClock().now.advanced(by: timeout)
        while ContinuousClock().now < deadline {
            let (ready, snapshot) = lock.withLock { (receivedFirstBatch, Array(known.values)) }
            if ready { return snapshot }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return lock.withLock { Array(known.values) }
    }
}
