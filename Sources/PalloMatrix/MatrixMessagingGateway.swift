import Foundation
import MatrixRustSDK
import PalloCore
import PalloGateway

/// Bridges the Matrix Rust SDK to Pallo's `MessagingGateway` seam.
///
/// The app layer keeps talking to the protocol it already used for the in-memory fake, so nothing
/// in `PalloFeatures` or `PalloUI` needs to know Matrix exists.
public actor MatrixMessagingGateway: MessagingGateway {
    public static let defaultAccountID = "matrix-local"

    private let client: PalloMatrixClient
    private let normalizer: MatrixEventNormalizer
    private let accountID: String
    private let platform: Platform
    private let initialMessageWait: Duration
    private let initialSyncWait: Duration
    private let invitePolicy: BridgeInvitePolicy
    private let roomDiscoveryInterval: Duration
    private let backfillEventCount: UInt16

    private var streamContinuations: [UUID: AsyncStream<GatewayEvent>.Continuation] = [:]
    private var timelineHandles: [String: TaskHandle] = [:]
    private var observers: [String: RoomTimelineObserver] = [:]
    private var started = false
    private var knownRoomIDs: Set<String> = []
    private var discoveryTask: Task<Void, Never>?

    public init(
        client: PalloMatrixClient,
        accountID: String = MatrixMessagingGateway.defaultAccountID,
        platform: Platform = .matrix,
        initialMessageWait: Duration = .milliseconds(1_500),
        initialSyncWait: Duration = .seconds(10),
        invitePolicy: BridgeInvitePolicy = .trustingNobody,
        roomDiscoveryInterval: Duration = .seconds(3),
        backfillEventCount: UInt16 = 50
    ) {
        self.client = client
        self.accountID = accountID
        self.platform = platform
        self.initialMessageWait = initialMessageWait
        self.initialSyncWait = initialSyncWait
        self.invitePolicy = invitePolicy
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
            let route = normalizer.route(forRoom: room.id())
            knownRoomIDs.insert(room.id())
            await attachTimeline(to: room)

            // Give the timeline a bounded moment to deliver its first batch. A room with nothing
            // yet loaded still appears, just without history, rather than blocking the inbox.
            let messages = await observers[room.id()]?.messages(waitingUpTo: initialMessageWait) ?? []
            let ordered = messages.sorted(by: palloMessageOrdering)
            messagesByRoute[route] = ordered

            for message in ordered {
                guard let senderID = message.senderIdentityID else { continue }
                identities[senderID] = RemoteIdentity(
                    id: senderID,
                    accountID: accountID,
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
                    accountID: accountID,
                    displayName: identityID == room.id() ? title : Self.displayName(forUserID: identityID)
                )
            }

            conversations.append(
                RemoteConversation(
                    id: room.id(),
                    accountID: accountID,
                    identityID: identityID,
                    title: title,
                    latestPreview: ordered.last?.body ?? "",
                    latestActivity: ordered.last?.timestamp ?? Date(timeIntervalSince1970: 0),
                    unreadCount: Int(info.numUnreadMessages)
                )
            )
        }

        return MessagingSnapshot(
            accounts: [
                ConnectedAccount(id: accountID, platform: platform, displayName: "Local Matrix"),
            ],
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

    // MARK: - Lifecycle

    public func start() async throws {
        guard !started else { return }
        _ = try await client.connect()
        try await client.startSync()
        started = true
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
                try? await Task.sleep(for: await self.roomDiscoveryInterval)
                guard !Task.isCancelled else { return }
                await self.discoverNewRooms()
            }
        }
    }

    private func discoverNewRooms() async {
        await acceptTrustedInvites()
        guard let rooms = try? await client.requireClient().rooms() else { return }

        for room in rooms where room.membership() == .joined {
            let roomID = room.id()
            guard !knownRoomIDs.contains(roomID) else { continue }
            knownRoomIDs.insert(roomID)
            await attachTimeline(to: room)

            let messages = await observers[roomID]?
                .messages(waitingUpTo: initialMessageWait)
                .sorted(by: palloMessageOrdering) ?? []
            let info = try? await room.roomInfo()
            let title = info?.displayName ?? info?.rawName ?? roomID
            let identityID = messages.compactMap(\.senderIdentityID).first ?? roomID

            // Order matters: the inbox drops a conversation whose identity it has not seen, so the
            // identity has to arrive first or the room never appears.
            publish(.identityUpserted(
                RemoteIdentity(
                    id: identityID,
                    accountID: accountID,
                    displayName: identityID == roomID ? title : Self.displayName(forUserID: identityID)
                )
            ))
            publish(.conversationUpserted(
                RemoteConversation(
                    id: roomID,
                    accountID: accountID,
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

    // MARK: - Internals

    private func attachTimeline(to room: Room) async {
        let roomID = room.id()
        guard timelineHandles[roomID] == nil else { return }

        let observer = RoomTimelineObserver(roomID: roomID, normalizer: normalizer) { [weak self] event in
            Task { await self?.publish(event) }
        }
        guard let timeline = try? await room.timeline() else { return }
        let handle = await timeline.addListener(listener: observer)
        timelineHandles[roomID] = handle
        observers[roomID] = observer

        // A live timeline begins where this account's view of the room begins. In a room Pallo has
        // only just joined — every bridged portal — that is the join event, so the conversation the
        // bridge backfilled sits entirely behind it and would never be shown. Paginating once pulls
        // that history in.
        _ = try? await timeline.paginateBackwards(numEvents: backfillEventCount)
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
    private let onEvent: @Sendable (GatewayEvent) -> Void

    private let lock = NSLock()
    private var known: [String: Message] = [:]
    private var receivedFirstBatch = false

    init(
        roomID: String,
        normalizer: MatrixEventNormalizer,
        onEvent: @escaping @Sendable (GatewayEvent) -> Void
    ) {
        self.roomID = roomID
        self.normalizer = normalizer
        self.onEvent = onEvent
    }

    func onUpdate(diff: [TimelineDiff]) {
        var produced: [Message] = []
        for change in diff {
            switch change {
            case let .append(values): produced += messages(from: values)
            case let .reset(values): produced += messages(from: values)
            case let .pushBack(value): produced += messages(from: [value])
            case let .pushFront(value): produced += messages(from: [value])
            case let .insert(_, value): produced += messages(from: [value])
            case let .set(_, value): produced += messages(from: [value])
            case .clear, .popFront, .popBack, .remove, .truncate:
                // Removals do not delete Pallo's record: a redaction arrives as its own event, and
                // the design forbids silently dropping a message that was already shown.
                continue
            }
        }

        let fresh: [Message] = lock.withLock {
            receivedFirstBatch = true
            return produced.filter { message in
                // Idempotent by event ID, so duplicate or replayed diffs cannot double-post.
                guard known[message.id] != message else { return false }
                known[message.id] = message
                return true
            }
        }
        for message in fresh { onEvent(.messageUpserted(message)) }
    }

    private func messages(from items: [TimelineItem]) -> [Message] {
        items.compactMap { item in
            guard let event = item.asEvent() else { return nil }
            return normalizer.normalize(event, roomID: roomID).message
        }
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
