import Foundation
import MatrixRustSDK
import InboxPlusCore
import InboxPlusGateway

/// Bridges the Matrix Rust SDK to Inbox+'s `MessagingGateway` seam.
///
/// The app layer keeps talking to the protocol it already used for the in-memory fake, so nothing
/// in `InboxPlusFeatures` or `InboxPlusUI` needs to know Matrix exists.
public actor MatrixMessagingGateway: MessageInteractionGateway {
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
    private let historyWindow: Int
    private let backfillStep: UInt16
    private let backfillEventLimit: Int

    private let outgoingIdentifiersProvider: @Sendable () async -> [String: Set<String>]
    private var outgoingIdentifiersByAccount: [String: Set<String>] = [:]
    private var identityRefreshTask: Task<[String: Set<String>], Never>?

    private var streamContinuations: [UUID: AsyncStream<GatewayEvent>.Continuation] = [:]
    private var timelineHandles: [String: TaskHandle] = [:]
    private var observers: [String: RoomTimelineObserver] = [:]
    /// The timelines those observers watch. A reaction or a request for a quoted message acts on
    /// an item, and only the timeline that loaded the item has it.
    private var timelines: [String: Timeline] = [:]
    /// Replies whose quoted message has been asked for, so a reply is only fetched once.
    private var requestedReplyDetails: Set<String> = []
    private var started = false
    private var knownRoomIDs: Set<String> = []
    private var discoveryTask: Task<Void, Never>?
    /// Which account each room belongs to, resolved once from its members.
    private var accountIDByRoomID: [String: String] = [:]
    /// Each bridge's management room, mapped to the account it reports on.
    private var managementRoomAccountByID: [String: String] = [:]
    private var networkStates: [String: NetworkConnectionState] = [:]
    private var networkStateDates: [String: Date] = [:]

    public init(
        client: InboxPlusMatrixClient,
        accountID: String = MatrixMessagingGateway.defaultAccountID,
        platform: Platform = .matrix,
        initialMessageWait: Duration = .milliseconds(1_500),
        initialSyncWait: Duration = .seconds(10),
        invitePolicy: BridgeInvitePolicy = .trustingNobody,
        bridgeAccounts: [BridgeAccountDescriptor] = [],
        roomDiscoveryInterval: Duration = .seconds(3),
        historyWindow: Int = RecentHistory.messageCount,
        backfillStep: UInt16 = 20,
        backfillEventLimit: Int = 200,
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
        self.historyWindow = historyWindow
        self.backfillStep = backfillStep
        self.backfillEventLimit = backfillEventLimit
        normalizer = MatrixEventNormalizer(accountID: accountID)
    }

    /// Downloads media through this gateway's own client. Only `start()` connects a client, so a
    /// fetcher built on any other one fails every download with `.notConnected`.
    public nonisolated var mediaFetcher: MatrixMediaFetcher { MatrixMediaFetcher(client: client) }

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
            if await setAsideBridgeRoom(room, info: info, accountID: roomAccountID) { continue }
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

            let title = await conversationTitle(of: room, info: info, accountID: roomAccountID)
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

            conversations.append(Self.conversation(
                roomID: room.id(),
                accountID: roomAccountID,
                identityID: identityID,
                title: title,
                messages: ordered,
                unreadCount: Int(info.numUnreadMessages),
                isGroup: isGroup(info, accountID: roomAccountID),
                deepLink: await deepLink(forRoom: room.id(), accountID: roomAccountID)
            ))
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
        _ = try await liveTimeline(for: route).send(msg: messageEventContentFromMarkdown(md: body))

        // Deliberately `pending`. The design forbids showing a successful send before the server
        // confirms it; the timeline listener promotes this to `acknowledged` when the echo lands.
        return SendReceipt(
            messageID: Self.transactionIdentifier(),
            route: route,
            deliveryState: .pending
        )
    }

    public func sendText(_ body: String, to route: ConversationRoute, replyingTo messageID: String) async throws -> SendReceipt {
        try await liveTimeline(for: route).sendReply(msg: messageEventContentFromMarkdown(md: body), eventId: messageID)
        return SendReceipt(messageID: Self.transactionIdentifier(), route: route, deliveryState: .pending)
    }

    public func send(_ attachment: OutgoingAttachment, to route: ConversationRoute) async throws -> SendReceipt {
        try await send(attachment, to: route, inReplyTo: nil)
    }

    public func send(
        _ attachment: OutgoingAttachment,
        to route: ConversationRoute,
        replyingTo messageID: String
    ) async throws -> SendReceipt {
        try await send(attachment, to: route, inReplyTo: messageID)
    }

    public func toggleReaction(_ key: String, to messageID: String, in route: ConversationRoute) async throws {
        _ = try await liveTimeline(for: route).toggleReaction(
            itemId: normalizer.eventOrTransactionID(for: messageID),
            key: key
        )
    }

    private func send(
        _ attachment: OutgoingAttachment,
        to route: ConversationRoute,
        inReplyTo messageID: String?
    ) async throws -> SendReceipt {
        let timeline = try await liveTimeline(for: route)
        let parameters = UploadParameters(
            source: .file(filename: attachment.fileURL.path),
            caption: attachment.caption,
            formattedCaption: nil,
            mentions: nil,
            inReplyTo: messageID
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

    public func markRead(_ route: ConversationRoute) async throws {
        let matrixClient = try await client.requireClient()
        guard let room = try matrixClient.getRoom(roomId: route.conversationID) else {
            throw MatrixGatewayError.unknownRoom(route.conversationID)
        }
        try await room.markAsRead(receiptType: Self.readReceiptType)
    }

    /// Private, so the homeserver's unread count clears without anyone else being told. The
    /// bridges only pass a public `m.read` on to the network (mautrix-go bridgev2
    /// `Portal.handleMatrixReceipts`); a public receipt here would mark the message as seen there.
    static let readReceiptType = ReceiptType.readPrivate

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
        managementRoomAccountByID.removeAll()
        for handle in timelineHandles.values { handle.cancel() }
        timelineHandles.removeAll()
        observers.removeAll()
        timelines.removeAll()
        requestedReplyDetails.removeAll()
        for continuation in streamContinuations.values { continuation.finish() }
        streamContinuations.removeAll()
        started = false
    }

    public func disconnect() async {
        await stop()
        await client.disconnect()
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
            let info = try? await room.roomInfo()
            if let info, await setAsideBridgeRoom(room, info: info, accountID: roomAccountID) { continue }
            await attachTimeline(to: room)

            let messages = await observers[roomID]?
                .messages(waitingUpTo: initialMessageWait)
                .sorted(by: inboxplusMessageOrdering) ?? []
            let title = await conversationTitle(of: room, info: info, accountID: roomAccountID)
            let identityID = messages.compactMap(\.senderIdentityID).first ?? roomID

            // Order matters: the inbox drops a conversation whose account or identity it has not
            // seen, so both have to arrive first or the room never appears. The account is new
            // whenever this is the first conversation of a network connected since launch.
            if let account = bridgeAccount(roomAccountID) {
                publish(.accountUpserted(account))
            }
            publish(.identityUpserted(
                RemoteIdentity(
                    id: identityID,
                    accountID: roomAccountID,
                    displayName: identityID == roomID ? title : Self.displayName(forUserID: identityID)
                )
            ))
            publish(.conversationUpserted(Self.conversation(
                roomID: roomID,
                accountID: roomAccountID,
                identityID: identityID,
                title: title,
                messages: messages,
                unreadCount: Int(info?.numUnreadMessages ?? 0),
                isGroup: info.map { isGroup($0, accountID: roomAccountID) } ?? false,
                deepLink: await deepLink(forRoom: roomID, accountID: roomAccountID)
            )))
            for message in messages { publish(.historicalMessageUpserted(message)) }
        }
    }

    /// A room as the inbox lists it, from its messages in chronological order. Its preview and
    /// time are its newest message's: a bridge sends member and profile events after the history
    /// it backfills, and none of those is a message.
    static func conversation(
        roomID: String,
        accountID: String,
        identityID: String,
        title: String,
        messages ordered: [Message],
        unreadCount: Int,
        isGroup: Bool,
        deepLink: VerifiedDeepLink?
    ) -> RemoteConversation {
        RemoteConversation(
            id: roomID,
            accountID: accountID,
            identityID: identityID,
            title: title,
            latestPreview: ordered.last?.body ?? "",
            latestActivity: ordered.last?.timestamp ?? Date(timeIntervalSince1970: 0),
            unreadCount: unreadCount,
            isGroup: isGroup,
            deepLink: deepLink
        )
    }

    /// Asked only for a network Inbox+ can build a link for, so any other room costs no request.
    private func deepLink(forRoom roomID: String, accountID: String) async -> VerifiedDeepLink? {
        guard let platform = bridgeAccounts[accountID]?.platform, BridgeChannelLink.supports(platform),
              let state = try? await client.roomState(roomID) else { return nil }
        return BridgeChannelLink.link(inRoomState: state, platform: platform)
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

    private func isGroup(_ info: RoomInfo, accountID: String) -> Bool {
        Self.isGroup(
            isDirect: info.isDirect || info.isDm,
            joinedMembers: info.joinedMembersCount,
            serviceMembers: Set(info.serviceMembers),
            ownIdentities: outgoingIdentifiersByAccount[accountID] ?? []
        )
    }

    /// Bridges rarely mark a portal as a direct chat, so the flag alone would make nearly every
    /// bridged conversation a group. What decides it is how many people are left once this
    /// account, the bridge's service members and this account's own network identity are set aside.
    static func isGroup(
        isDirect: Bool,
        joinedMembers: UInt64,
        serviceMembers: Set<String>,
        ownIdentities: Set<String>
    ) -> Bool {
        if isDirect { return false }
        let ownGhost = ownIdentities.contains { $0.hasPrefix("@") && !serviceMembers.contains($0) } ? 1 : 0
        let others = Int(joinedMembers) - serviceMembers.count - 1 - ownGhost
        return others > 1
    }

    /// A room the network left unnamed, such as most bridged one-to-one chats and a group nobody
    /// named, is called after its people. Not the SDK's fallback name: that counts this account's
    /// own network identities as people (WhatsApp has two, by phone number and by LID), so a
    /// one-to-one chat read like a group that included the user.
    private func conversationTitle(of room: Room, info: RoomInfo?, accountID: String) async -> String {
        let fallback = info?.displayName ?? info?.rawName ?? room.id()
        guard let info, info.rawName?.isEmpty ?? true,
              let ownUserID = try? await client.requireClient().userId() else { return fallback }
        let excluded = Set(info.serviceMembers)
            .union(outgoingIdentifiersByAccount[accountID] ?? [])
            .union([ownUserID])
        let members = await joinedMembers(of: room, synchronising: true)
            .map { (userID: $0.userId, displayName: $0.displayName) }
        return Self.memberListTitle(members: members, excluding: excluded) ?? fallback
    }

    /// Everyone in a small room by name, otherwise the first few and how many more.
    static func memberListTitle(
        members: [(userID: String, displayName: String?)],
        excluding excludedIDs: Set<String>
    ) -> String? {
        let people = members.filter { !excludedIDs.contains($0.userID) }
        let names = people.compactMap(\.displayName)
            .filter { !$0.isEmpty }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        guard !names.isEmpty else { return nil }
        let shown = names.prefix(3)
        let list = shown.joined(separator: ", ")
        return switch people.count - shown.count {
        case 0: list
        case 1: "\(list) and 1 other"
        case let more: "\(list) and \(more) others"
        }
    }

    /// Leaves a bridge's own rooms out of the inbox: the spaces it files portals under, and the
    /// management room where its bot talks to this account. Neither is a conversation, and typing
    /// in the management room would send commands to the bot. Its status notices become the
    /// account's network state instead.
    private func setAsideBridgeRoom(_ room: Room, info: RoomInfo, accountID: String) async -> Bool {
        let roomID = room.id()
        if info.isSpace {
            knownRoomIDs.insert(roomID)
            return true
        }
        guard await isManagementRoom(room, info: info) else { return false }
        knownRoomIDs.insert(roomID)
        managementRoomAccountByID[roomID] = accountID
        await attachTimeline(to: room)
        let notices = await observers[roomID]?.messages(waitingUpTo: initialMessageWait) ?? []
        for notice in notices.sorted(by: inboxplusMessageOrdering) {
            recordNetworkState(from: notice, accountID: accountID, publishing: false)
        }
        return true
    }

    private func isManagementRoom(_ room: Room, info: RoomInfo) async -> Bool {
        // Only this account and the bot are in one, so a larger room needs no member lookup.
        guard info.joinedMembersCount <= 2,
              let ownUserID = try? await client.requireClient().userId() else { return false }
        var members = await joinedMembers(of: room, synchronising: false)
        if members.count < 2 { members = await joinedMembers(of: room, synchronising: true) }
        return Self.isManagementRoom(memberIDs: members.map(\.userId), ownUserID: ownUserID, policy: invitePolicy)
    }

    /// Everyone else in the room is a bridge's bot.
    static func isManagementRoom(memberIDs: [String], ownUserID: String, policy: BridgeInvitePolicy) -> Bool {
        let others = memberIDs.filter { $0 != ownUserID }
        return !others.isEmpty && others.allSatisfy(policy.isBridgeBot)
    }

    private func joinedMembers(of room: Room, synchronising: Bool) async -> [RoomMember] {
        guard let iterator = synchronising ? try? await room.members() : try? await room.membersNoSync()
        else { return [] }
        var members: [RoomMember] = []
        while let chunk = iterator.nextChunk(chunkSize: 64), !chunk.isEmpty {
            members += chunk.filter { $0.membership == .join }
        }
        return members
    }

    /// Notices can arrive out of order while history loads, so only a newer one replaces the state.
    private func recordNetworkState(from notice: Message, accountID: String, publishing: Bool) {
        guard let state = BridgeStateNotice.state(in: notice.body),
              notice.timestamp >= networkStateDates[accountID] ?? .distantPast else { return }
        networkStateDates[accountID] = notice.timestamp
        guard networkStates[accountID] != state else { return }
        networkStates[accountID] = state
        if publishing, let account = bridgeAccount(accountID) { publish(.accountUpserted(account)) }
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

    /// Leaves and forgets every room filed under one account — its conversations, its pending
    /// invitations and the bridge's own rooms — so none of it loads again.
    ///
    /// Only once the account's bridge has stopped: a running bridge can take leaving a portal as
    /// leaving that conversation on the network itself.
    public func forgetRooms(ofAccount removedAccountID: String) async throws {
        for room in try await client.requireClient().rooms() {
            let membership = room.membership()
            let owner: String?
            switch membership {
            case .invited:
                owner = (try? await room.inviter()).flatMap { invitePolicy.bridgeID(owning: $0.userId) }
            case .joined, .left, .banned:
                owner = await resolvedAccountID(for: room)
            case .knocked:
                owner = nil
            }
            guard owner == removedAccountID else { continue }

            let roomID = room.id()
            timelineHandles.removeValue(forKey: roomID)?.cancel()
            observers[roomID] = nil
            timelines[roomID] = nil
            knownRoomIDs.remove(roomID)
            managementRoomAccountByID[roomID] = nil
            if membership == .joined || membership == .invited { try await room.leave() }
            try await room.forget()
            accountIDByRoomID[roomID] = nil
        }
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
            guard let account = bridgeAccount(bridgeID) else { continue }
            accounts.append(account)
        }
        // Always present, because a room that belongs to no bridge is filed against it.
        accounts.append(
            ConnectedAccount(id: accountID, platform: platform, displayName: "Local Matrix")
        )
        return accounts
    }

    private func bridgeAccount(_ bridgeID: String) -> ConnectedAccount? {
        guard let descriptor = bridgeAccounts[bridgeID] else { return nil }
        return ConnectedAccount(
            id: descriptor.bridgeID,
            platform: descriptor.platform,
            displayName: descriptor.displayName,
            networkState: networkStates[bridgeID]
        )
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
            outgoingIdentifiers: outgoingIdentifiersByAccount[roomAccountID] ?? [],
            ownUserID: room.ownUserId()
        ) { [weak self] event in
            Task { await self?.publishTimelineEvent(event, roomID: roomID) }
        }
        // A listener may emit its initial batch before addListener returns. Register the
        // observer first so those callbacks can refresh and read the current attribution.
        observers[roomID] = observer
        timelines[roomID] = timeline
        let handle = await timeline.addListener(listener: observer)
        timelineHandles[roomID] = handle

        // A live timeline begins where this account's view of the room begins. In a room Inbox+ has
        // only just joined — every bridged portal — that is the join event, so the conversation the
        // bridge backfilled sits entirely behind it and would never be shown. Paging back pulls
        // that history in.
        await Self.backfill(
            toWindow: historyWindow,
            step: backfillStep,
            eventLimit: backfillEventLimit,
            loadedMessages: { observer.messageCount },
            paginate: { try await timeline.paginateBackwards(numEvents: $0) }
        )
    }

    /// Pages back in small steps until `window` messages are loaded, the room's start is reached,
    /// or `eventLimit` events have been asked for. Counting events instead would stop short in a
    /// group, where member changes can outnumber messages six to one; the limit keeps such a room
    /// from walking its whole history.
    static func backfill(
        toWindow window: Int,
        step: UInt16,
        eventLimit: Int,
        loadedMessages: @Sendable () -> Int,
        paginate: @Sendable (UInt16) async throws -> Bool
    ) async {
        var requested = 0
        while loadedMessages() < window, requested < eventLimit {
            let count = UInt16(min(Int(step), eventLimit - requested))
            requested += Int(count)
            guard let reachedStart = try? await paginate(count), !reachedStart else { return }
        }
    }

    private func publishTimelineEvent(_ event: GatewayEvent, roomID: String) async {
        if let accountID = managementRoomAccountByID[roomID] {
            if case let .messageUpserted(notice) = event {
                recordNetworkState(from: notice, accountID: accountID, publishing: true)
            } else if case let .historicalMessageUpserted(notice) = event {
                recordNetworkState(from: notice, accountID: accountID, publishing: true)
            }
            return
        }
        let message: Message
        let historical: Bool
        switch event {
        case let .messageUpserted(value): message = value; historical = false
        case let .historicalMessageUpserted(value): message = value; historical = true
        default: publish(event); return
        }
        // Some bridges use event-specific attribution. Look up newly persisted native sends
        // before exposing an incoming-looking event, rather than waiting for room discovery.
        if !message.isOutgoing, outgoingIdentifiersByAccount[message.route.accountID] != nil {
            await refreshOutgoingIdentifiers()
        }
        // Listener callbacks hop into this actor asynchronously. If ownership changed during
        // that hop, publish the observer's current value so a stale incoming event cannot undo it.
        let current = observers[roomID]?.message(id: message.id) ?? message
        publish(historical ? .historicalMessageUpserted(current) : .messageUpserted(current))

        // The timeline quotes only a message it has already loaded. An older one has to be asked
        // for, and arrives as an update to the reply.
        if Self.needsQuotedMessage(current), requestedReplyDetails.insert(current.id).inserted,
           let timeline = timelines[roomID] {
            Task { try? await timeline.fetchDetailsForEvent(eventId: current.id) }
        }
    }

    /// Only a reply the server already has can have its quoted message fetched.
    static func needsQuotedMessage(_ message: Message) -> Bool {
        guard let reply = message.replyTo else { return false }
        return reply.body == nil && !message.id.hasPrefix("txn:")
    }

    /// The timeline this gateway watches for a conversation, so an action lands on the same items
    /// the transcript was built from.
    private func liveTimeline(for route: ConversationRoute) async throws -> Timeline {
        let matrixClient = try await client.requireClient()
        guard let room = try matrixClient.getRoom(roomId: route.conversationID) else {
            throw MatrixGatewayError.unknownRoom(route.conversationID)
        }
        await attachTimeline(to: room)
        if let timeline = timelines[route.conversationID] { return timeline }
        return try await room.timeline()
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

    private static func transactionIdentifier() -> String {
        "txn:\(UUID().uuidString)"
    }
}

public enum MatrixGatewayError: Error, Equatable, Sendable, CustomStringConvertible, LocalizedError {
    case unknownRoom(String)

    public var description: String {
        switch self {
        case let .unknownRoom(roomID): "no such conversation: \(roomID)"
        }
    }

    public var errorDescription: String? {
        switch self {
        case .unknownRoom: "This conversation isn't available anymore."
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
    private let ownUserID: String?
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
        ownUserID: String? = nil,
        onEvent: @escaping @Sendable (GatewayEvent) -> Void
    ) {
        self.roomID = roomID
        self.normalizer = normalizer
        self.accountID = accountID
        self.ownUserID = ownUserID
        self.onEvent = onEvent
        self.outgoingIdentifiers = outgoingIdentifiers
    }

    func onUpdate(diff: [TimelineDiff]) {
        // Only tail additions after the initial batch can represent new traffic. Backward
        // pagination, resets, edits, and decryption replacements still update the transcript.
        let updates: [GatewayEvent] = lock.withLock {
            var updates: [GatewayEvent] = []
            for change in diff {
                let items: [TimelineItem]
                let live: Bool
                switch change {
                case let .append(values): items = values; live = receivedFirstBatch
                case let .pushBack(value): items = [value]; live = receivedFirstBatch
                case let .reset(values): items = values; live = false
                case let .pushFront(value), let .insert(_, value), let .set(_, value):
                    items = [value]; live = false
                case .clear, .popFront, .popBack, .remove, .truncate: continue
                }
                for item in items {
                    guard let event = item.asEvent() else { continue }
                    let id = normalizer.identifier(for: event.eventOrTransactionId)
                    guard let message = normalizer.normalize(
                        event, roomID: roomID, accountID: accountID,
                        outgoingIdentifiers: outgoingIdentifiers, ownUserID: ownUserID
                    ) else { continue }
                    events[id] = event
                    guard known[id] != message else { continue }
                    let isNew = known[id] == nil
                    known[id] = message
                    updates.append(live && isNew && event.origin == .sync
                        ? .messageUpserted(message) : .historicalMessageUpserted(message))
                }
            }
            receivedFirstBatch = true
            return updates
        }
        for update in updates { onEvent(update) }
    }

    func updateOutgoingIdentifiers(_ identifiers: Set<String>) {
        let updated: [Message] = lock.withLock {
            guard identifiers != outgoingIdentifiers else { return [] }
            outgoingIdentifiers = identifiers
            return events.values.compactMap { event in
                guard let message = normalizer.normalize(
                    event, roomID: roomID, accountID: accountID,
                    outgoingIdentifiers: identifiers, ownUserID: ownUserID
                ), known[message.id] != message else { return nil }
                known[message.id] = message
                return message
            }
        }
        for message in updated { onEvent(.historicalMessageUpserted(message)) }
    }

    func message(id: String) -> Message? {
        lock.withLock { known[id] }
    }

    /// Events with nothing to show, such as member changes, are not among these.
    var messageCount: Int {
        lock.withLock { known.count }
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
