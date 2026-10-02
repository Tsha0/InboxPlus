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

    let client: InboxPlusMatrixClient
    private let normalizer: MatrixEventNormalizer
    private let accountID: String
    private let platform: Platform
    private let initialMessageWait: Duration
    private let initialSyncWait: Duration
    private let invitePolicy: BridgeInvitePolicy
    private let bridgeAccounts: [String: BridgeAccountDescriptor]
    private let roomDiscoveryInterval: Duration
    private let backfillEventCount: UInt16
    private let startupConcurrency: Int
    private let initialHistoryRoomLimit: Int

    private var streamContinuations: [UUID: AsyncStream<GatewayEvent>.Continuation] = [:]
    private var timelineHandles: [String: TaskHandle] = [:]
    private var observers: [String: RoomTimelineObserver] = [:]
    private var observerEventTasks: [String: Task<Void, Never>] = [:]
    private var attachmentTasks: [String: Task<Void, Never>] = [:]
    private var startingTask: Task<Void, any Error>?
    private var stoppingTask: Task<Void, Never>?
    private var lifecycleGeneration = 0
    private var started = false
    private var knownRoomIDs: Set<String> = []
    private var discoveryTask: Task<Void, Never>?
    private var backfillTask: Task<Void, Never>?
    private var pendingBackfillRooms: [Room] = []
    private var backfilledRoomIDs: Set<String> = []
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
        startupConcurrency: Int = 4,
        initialHistoryRoomLimit: Int = 20
    ) {
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
        self.startupConcurrency = max(1, startupConcurrency)
        self.initialHistoryRoomLimit = max(0, initialHistoryRoomLimit)
        normalizer = MatrixEventNormalizer(accountID: accountID)
    }

    deinit {
        discoveryTask?.cancel()
        backfillTask?.cancel()
        startingTask?.cancel()
        attachmentTasks.values.forEach { $0.cancel() }
        observerEventTasks.values.forEach { $0.cancel() }
        timelineHandles.values.forEach { $0.cancel() }
        observers.values.forEach { $0.finish() }
    }

    // MARK: - MessagingGateway

    public func loadSnapshot() async throws -> MessagingSnapshot {
        try await start()
        try Task.checkCancellation()
        await acceptTrustedInvites()

        let generation = lifecycleGeneration
        let rooms = try await client.requireClient().rooms().filter { $0.membership() == .joined }
        knownRoomIDs.formUnion(rooms.map { $0.id() })
        let summaries = try await boundedConcurrentMap(rooms, limit: startupConcurrency) { room in
            RoomSummary(room: room, info: try await room.roomInfo(), latest: await room.latestEvent())
        }.sorted {
            let lhs = Self.latestTimestamp($0.latest), rhs = Self.latestTimestamp($1.latest)
            return lhs == rhs ? $0.room.id() < $1.room.id() : lhs > rhs
        }
        let loaded = try await boundedConcurrentMap(Array(summaries.enumerated()), limit: startupConcurrency) { entry in
            try await self.snapshot(for: entry.element, preloadHistory: entry.offset < self.initialHistoryRoomLimit,
                                    generation: generation)
        }
        guard started, generation == lifecycleGeneration else { throw CancellationError() }
        var conversations: [RemoteConversation] = []
        var messagesByRoute: [ConversationRoute: [Message]] = [:]
        var identities: [String: RemoteIdentity] = [:]

        for loadedRoom in loaded {
            let room = loadedRoom.summary.room
            let info = loadedRoom.summary.info
            let roomAccountID = loadedRoom.accountID
            let route = normalizer.route(forRoom: room.id(), accountID: roomAccountID)
            let ordered = loadedRoom.messages
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
                    latestPreview: ordered.last?.body ?? preview(for: loadedRoom.summary.latest),
                    latestActivity: ordered.last?.timestamp ?? Self.date(for: loadedRoom.summary.latest),
                    unreadCount: Int(info.numUnreadMessages)
                )
            )
        }

        enqueueBackfill(summaries.dropFirst(initialHistoryRoomLimit).map(\.room))

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
            startBackfill()
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
        _ = try await timeline.send(msg: messageEventContentFromMarkdown(md: body))

        // Deliberately `pending`. The design forbids showing a successful send before the server
        // confirms it; the timeline listener promotes this to `acknowledged` when the echo lands.
        return SendReceipt(
            // The SDK SendHandle does not expose the transaction ID; the timeline owns the echo.
            messageID: "txn:\(UUID().uuidString)",
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
        try Task.checkCancellation()
        if let stoppingTask { await stoppingTask.value }
        try Task.checkCancellation()
        if let startingTask {
            let generation = lifecycleGeneration
            try await startingTask.value
            try Task.checkCancellation()
            guard generation == lifecycleGeneration else { throw CancellationError() }
            return
        }
        guard !started else { return }
        let generation = lifecycleGeneration
        let task = Task { [weak self] in
            guard let self else { return }
            try await self.performStart(generation: generation)
        }
        startingTask = task
        do { try await task.value } catch {
            if generation == lifecycleGeneration { startingTask = nil }
            throw error
        }
        guard generation == lifecycleGeneration else { throw CancellationError() }
        startingTask = nil
        try Task.checkCancellation()
    }

    private func performStart(generation: Int) async throws {
        _ = try await client.connect()
        try Task.checkCancellation()
        try await client.startSync()
        guard generation == lifecycleGeneration else { throw CancellationError() }
        started = true
        await awaitInitialRooms()
        await acceptTrustedInvites()
        guard started, generation == lifecycleGeneration else { throw CancellationError() }
        startRoomDiscovery()
    }

    /// Waits, briefly, for sliding sync to deliver the first room list.
    ///
    /// `rooms()` reads the local store, which is empty until the first sync response lands. Without
    /// this the very first `loadSnapshot()` returns an empty inbox even though the account has
    /// conversations. An account that genuinely has none simply waits out the deadline once.
    private func awaitInitialRooms() async {
        let deadline = ContinuousClock().now.advanced(by: initialSyncWait)
        while started, !Task.isCancelled, ContinuousClock().now < deadline {
            if let rooms = try? await client.requireClient().rooms(), !rooms.isEmpty { return }
            do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
        }
    }

    /// Detaches listeners and stops the shared authenticated client's sync loop.
    public func stop() async {
        if let stoppingTask { return await stoppingTask.value }
        lifecycleGeneration += 1
        started = false
        let starting = startingTask
        starting?.cancel()
        startingTask = nil
        let discovery = discoveryTask
        discovery?.cancel()
        discoveryTask = nil
        let backfill = backfillTask
        backfill?.cancel()
        backfillTask = nil
        pendingBackfillRooms.removeAll()
        backfilledRoomIDs.removeAll()
        let attachments = Array(attachmentTasks.values)
        attachments.forEach { $0.cancel() }
        attachmentTasks.removeAll()
        let forwarding = Array(observerEventTasks.values)
        forwarding.forEach { $0.cancel() }
        observerEventTasks.removeAll()
        knownRoomIDs.removeAll()
        accountIDByRoomID.removeAll()
        for handle in timelineHandles.values { handle.cancel() }
        timelineHandles.removeAll()
        observers.values.forEach { $0.finish() }
        observers.removeAll()
        for continuation in streamContinuations.values { continuation.finish() }
        streamContinuations.removeAll()
        let task = Task { [client] in
            _ = await starting?.result
            await discovery?.value
            await backfill?.value
            for task in attachments { await task.value }
            for task in forwarding { await task.value }
            await client.disconnect()
        }
        stoppingTask = task
        await task.value
        stoppingTask = nil
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
            guard started, !Task.isCancelled else { return }
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
        let interval = roomDiscoveryInterval
        discoveryTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: interval) } catch { return }
                guard !Task.isCancelled else { return }
                guard let self else { return }
                await self.discoverNewRooms()
            }
        }
    }

    private func discoverNewRooms() async {
        let generation = lifecycleGeneration
        await acceptTrustedInvites()
        guard let rooms = try? await client.requireClient().rooms() else { return }

        for room in rooms where room.membership() == .joined {
            guard started, generation == lifecycleGeneration, !Task.isCancelled else { return }
            let roomID = room.id()
            guard !knownRoomIDs.contains(roomID) else { continue }
            knownRoomIDs.insert(roomID)
            let roomAccountID = await resolvedAccountID(for: room)
            await attachTimeline(to: room)
            await backfillHistory(for: room)

            let messages = await observers[roomID]?
                .messages(waitingUpTo: initialMessageWait)
                .sorted(by: inboxplusMessageOrdering) ?? []
            let info = try? await room.roomInfo()
            guard started, generation == lifecycleGeneration, !Task.isCancelled else { return }
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
            if !messages.isEmpty { publish(.messagesUpserted(messages)) }
        }
    }

    // MARK: - Attribution

    /// Which account a room belongs to, resolved from who is in it.
    ///
    /// A bridged conversation is a portal room the bridge created, and the bridge's own ghost or
    /// bot is always a member. That membership is the only reliable statement of which network the
    /// conversation really is — the transport is Matrix either way, and reporting Matrix is
    /// reporting the plumbing rather than the thing the user is looking at.
    private func resolvedAccountID(for room: Room) async -> String {
        let generation = lifecycleGeneration
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
        if started, generation == lifecycleGeneration { accountIDByRoomID[roomID] = resolved }
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
        if let task = attachmentTasks[roomID] { return await task.value }
        let generation = lifecycleGeneration
        let task = Task { [weak self] in
            guard let self else { return }
            await self.performTimelineAttachment(to: room, generation: generation)
        }
        attachmentTasks[roomID] = task
        await task.value
        if generation == lifecycleGeneration { attachmentTasks[roomID] = nil }
    }

    private func performTimelineAttachment(to room: Room, generation: Int) async {
        guard started, generation == lifecycleGeneration, !Task.isCancelled else { return }
        let roomID = room.id()

        // Resolved here rather than passed in, so a timeline attached from a send path is stamped
        // with the same account as one attached from a snapshot.
        let roomAccountID = await resolvedAccountID(for: room)
        let observer = RoomTimelineObserver(
            roomID: roomID,
            normalizer: normalizer,
            accountID: roomAccountID
        )
        guard let timeline = try? await room.timeline() else { return }
        let handle = await timeline.addListener(listener: observer)
        guard started, generation == lifecycleGeneration, !Task.isCancelled else {
            handle.cancel()
            observer.finish()
            return
        }
        timelineHandles[roomID] = handle
        observers[roomID] = observer
        observerEventTasks[roomID] = Task { [weak self, batches = observer.batches] in
            for await batch in batches {
                guard !Task.isCancelled else { return }
                await self?.publish(.messagesUpserted(batch))
            }
        }
    }

    private func backfillHistory(for room: Room) async {
        let generation = lifecycleGeneration
        let roomID = room.id()
        guard started, !Task.isCancelled, !backfilledRoomIDs.contains(roomID) else { return }
        backfilledRoomIDs.insert(roomID)
        guard let timeline = try? await room.timeline() else {
            if generation == lifecycleGeneration { backfilledRoomIDs.remove(roomID) }
            return
        }
        guard started, generation == lifecycleGeneration, !Task.isCancelled else { return }

        // A live timeline begins where this account's view of the room begins. In a room Inbox+ has
        // only just joined — every bridged portal — that is the join event, so the conversation the
        // bridge backfilled sits entirely behind it and would never be shown. Paginating once pulls
        // that history in.
        do { _ = try await timeline.paginateBackwards(numEvents: backfillEventCount) }
        catch {
            if generation == lifecycleGeneration { backfilledRoomIDs.remove(roomID) }
        }
    }

    private func enqueueBackfill(_ rooms: [Room]) {
        guard !rooms.isEmpty else { return }
        let pending = Set(pendingBackfillRooms.map { $0.id() })
        pendingBackfillRooms.append(contentsOf: rooms.reversed().filter {
            !pending.contains($0.id()) && !backfilledRoomIDs.contains($0.id())
        })
        startBackfill()
    }

    private func startBackfill() {
        // Older history is delivered after a subscriber is present, so deferred batches cannot
        // disappear between loadSnapshot() and events(). The app subscribes before its snapshot.
        guard !pendingBackfillRooms.isEmpty, !streamContinuations.isEmpty else { return }
        guard backfillTask == nil else { return }
        backfillTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let room = await self?.nextBackfillRoom() else { return }
                await self?.backfillHistory(for: room)
            }
        }
    }

    private func nextBackfillRoom() -> Room? {
        guard let room = pendingBackfillRooms.popLast() else {
            backfillTask = nil
            return nil
        }
        return room
    }

    private struct RoomSummary: Sendable {
        let room: Room
        let info: RoomInfo
        let latest: LatestEventValue
    }

    private struct LoadedRoom: Sendable {
        let summary: RoomSummary
        let accountID: String
        let messages: [Message]
    }

    private func snapshot(for summary: RoomSummary, preloadHistory: Bool, generation: Int) async throws -> LoadedRoom {
        try Task.checkCancellation()
        guard started, generation == lifecycleGeneration else { throw CancellationError() }
        let accountID = await resolvedAccountID(for: summary.room)
        await attachTimeline(to: summary.room)
        if preloadHistory { await backfillHistory(for: summary.room) }
        let messages = await observers[summary.room.id()]?
            .messages(waitingUpTo: preloadHistory ? initialMessageWait : .zero) ?? []
        guard started, generation == lifecycleGeneration else { throw CancellationError() }
        return LoadedRoom(summary: summary, accountID: accountID, messages: messages.sorted(by: inboxplusMessageOrdering))
    }

    static func latestTimestamp(_ latest: LatestEventValue) -> Timestamp {
        switch latest {
        case .none: 0
        case let .remote(timestamp, _, _, _, _), let .remoteInvite(timestamp, _, _), let .local(timestamp, _, _, _, _): timestamp
        }
    }

    private static func date(for latest: LatestEventValue) -> Date {
        MatrixEventNormalizer.date(from: latestTimestamp(latest))
    }

    private func preview(for latest: LatestEventValue) -> String {
        switch latest {
        case let .remote(_, _, _, _, content), let .local(_, _, _, content, _):
            normalizer.describe(content, identifier: "preview")?.body ?? ""
        case .none, .remoteInvite: ""
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
    /// Lossless batches use one forwarding task per room, avoiding a task per individual message.
    /// AsyncStream intentionally remains unbounded: imposing a buffer limit here would drop events.
    let batches: AsyncStream<[Message]>
    private let batchContinuation: AsyncStream<[Message]>.Continuation
    private let snapshotMessageLimit: Int

    private let lock = NSLock()
    private var known: [String: Message] = [:]
    private var receivedFirstBatch = false
    private var finished = false

    init(
        roomID: String,
        normalizer: MatrixEventNormalizer,
        accountID: String,
        snapshotMessageLimit: Int = 512
    ) {
        self.roomID = roomID
        self.normalizer = normalizer
        self.accountID = accountID
        self.snapshotMessageLimit = max(1, snapshotMessageLimit)
        let pair = AsyncStream<[Message]>.makeStream()
        batches = pair.stream
        batchContinuation = pair.continuation
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
                // Removals do not delete Inbox+'s record: a redaction arrives as its own event, and
                // the design forbids silently dropping a message that was already shown.
                continue
            }
        }

        receive(produced)
    }

    /// Keeps a bounded recent snapshot/dedup cache; every fresh event is still forwarded, including
    /// events older than this cache. The SDK's encrypted SQLite event store owns durable history.
    func receive(_ produced: [Message]) {
        lock.withLock {
            guard !finished else { return }
            receivedFirstBatch = true
            let fresh = produced.filter { message in
                // Idempotent by event ID, so duplicate or replayed diffs cannot double-post.
                guard known[message.id] != message else { return false }
                known[message.id] = message
                return true
            }
            let excess = known.count - snapshotMessageLimit
            if excess > 0 {
                for message in known.values.sorted(by: inboxplusMessageOrdering).prefix(excess) {
                    known[message.id] = nil
                }
            }
            if !fresh.isEmpty { batchContinuation.yield(fresh) }
        }
    }

    func finish() {
        lock.withLock {
            finished = true
            known.removeAll()
            batchContinuation.finish()
        }
    }

    private func messages(from items: [TimelineItem]) -> [Message] {
        items.compactMap { item in
            guard let event = item.asEvent() else { return nil }
            return normalizer.normalize(event, roomID: roomID, accountID: accountID)
        }
    }

    /// Current messages, waiting briefly for the timeline's first batch to arrive.
    func messages(waitingUpTo timeout: Duration) async -> [Message] {
        let deadline = ContinuousClock().now.advanced(by: timeout)
        while !Task.isCancelled, ContinuousClock().now < deadline {
            let snapshot: [Message]? = lock.withLock {
                receivedFirstBatch || finished ? Array(known.values) : nil
            }
            if let snapshot { return snapshot }
            do { try await Task.sleep(for: .milliseconds(50)) } catch { break }
        }
        return lock.withLock { Array(known.values) }
    }
}
