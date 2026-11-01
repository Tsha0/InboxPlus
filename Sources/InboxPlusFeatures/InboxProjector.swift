import Foundation
import InboxPlusCore

public struct ConversationSummary: Identifiable, Hashable, Sendable {
    public var id: ConversationRoute { route }
    public let route: ConversationRoute
    public let platform: Platform
    public let title: String
    public let latestPreview: String
    public let latestActivity: Date
    public let unreadCount: Int
    /// What the composer is allowed to offer here.
    public let capabilities: ConversationCapabilities
    public let isFromUnknownSender: Bool

    public init(
        route: ConversationRoute,
        platform: Platform,
        title: String,
        latestPreview: String,
        latestActivity: Date,
        unreadCount: Int,
        capabilities: ConversationCapabilities = .mediaCapable,
        isFromUnknownSender: Bool = false
    ) {
        self.route = route
        self.platform = platform
        self.title = title
        self.latestPreview = latestPreview
        self.latestActivity = latestActivity
        self.unreadCount = unreadCount
        self.capabilities = capabilities
        self.isFromUnknownSender = isFromUnknownSender
    }
}

public struct InboxItem: Identifiable, Hashable, Sendable {
    public enum ID: Hashable, Sendable {
        case person(String)
        case conversation(ConversationRoute)
    }

    public let id: ID
    public let title: String
    public let latestActivity: Date
    public let unreadCount: Int
    public let isFavourite: Bool
    public let conversationSummaries: [ConversationSummary]

    public init(
        id: ID,
        title: String,
        latestActivity: Date,
        unreadCount: Int,
        conversationSummaries: [ConversationSummary],
        isFavourite: Bool = false
    ) {
        self.id = id
        self.isFavourite = isFavourite
        self.title = title
        self.latestActivity = latestActivity
        self.unreadCount = unreadCount
        self.conversationSummaries = conversationSummaries
    }

    /// A person the user linked is someone they know, whatever the network says.
    public var isFromUnknownSender: Bool {
        guard case .conversation = id else { return false }
        return conversationSummaries.contains(where: \.isFromUnknownSender)
    }

    /// The same row seen through one network, or nil when it has no conversation there.
    func narrowed(to platform: Platform) -> InboxItem? {
        let summaries = conversationSummaries.filter { $0.platform == platform }
        guard let latest = summaries.first else { return nil }
        guard summaries.count != conversationSummaries.count else { return self }
        return InboxItem(
            id: id,
            title: title,
            latestActivity: latest.latestActivity,
            unreadCount: summaries.reduce(0) { $0 + $1.unreadCount },
            conversationSummaries: summaries,
            isFavourite: isFavourite
        )
    }
}

/// What the inbox list is narrowed to, apart from the search text.
public struct InboxFilter: Hashable, Sendable {
    public enum Scope: Hashable, Sendable {
        /// Everything except unknown senders, which have a list of their own.
        case all
        case unread
        case unknownSenders
    }

    public var scope: Scope
    /// Nil shows every network.
    public var platform: Platform?

    public init(scope: Scope = .all, platform: Platform? = nil) {
        self.scope = scope
        self.platform = platform
    }

    func includes(_ item: InboxItem) -> Bool {
        switch scope {
        case .all: !item.isFromUnknownSender
        case .unread: !item.isFromUnknownSender && item.unreadCount > 0
        case .unknownSenders: item.isFromUnknownSender
        }
    }
}

/// One message, so a search result can open its conversation scrolled to it.
public struct MessageReference: Hashable, Sendable {
    public let route: ConversationRoute
    public let messageID: String

    public init(route: ConversationRoute, messageID: String) {
        self.route = route
        self.messageID = messageID
    }
}

public struct MessageSearchResult: Identifiable, Hashable, Sendable {
    public let id: MessageReference
    public let platform: Platform
    /// The inbox row's title, so a linked person reads the same in both lists.
    public let title: String
    /// The message on one line, starting near the match so the match is visible.
    public let snippet: String
    public let timestamp: Date

    public init(id: MessageReference, platform: Platform, title: String, snippet: String, timestamp: Date) {
        self.id = id
        self.platform = platform
        self.title = title
        self.snippet = snippet
        self.timestamp = timestamp
    }
}

public extension InboxItem.ID {
    var accessibilityIdentifier: String {
        switch self {
        case let .person(id): "person-\(id)"
        case let .conversation(route): "conversation-\(route.accountID)-\(route.conversationID)"
        }
    }
}

public enum InboxProjector {
    public static func filtered(_ items: [InboxItem], query: String, filter: InboxFilter = .init()) -> [InboxItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        // A person seen through one network sorts by their activity there.
        let scoped = filter.platform.map { platform in
            items.compactMap { $0.narrowed(to: platform) }.sorted(by: inboxOrder)
        } ?? items
        return scoped.filter { item in
            guard filter.includes(item) else { return false }
            guard !trimmed.isEmpty else { return true }
            return item.title.localizedCaseInsensitiveContains(trimmed)
                || item.conversationSummaries.contains {
                    $0.title.localizedCaseInsensitiveContains(trimmed)
                        || $0.latestPreview.localizedCaseInsensitiveContains(trimmed)
                }
        }
    }

    /// The networks the inbox has conversations on, in a fixed order so the chips never move.
    public static func platforms(in items: [InboxItem]) -> [Platform] {
        let present = Set(items.flatMap { $0.conversationSummaries.map(\.platform) })
        return Platform.allCases.filter(present.contains)
    }

    /// Loaded messages that contain the query, newest first, from the conversations `items` lists.
    public static func messageMatches(
        _ messagesByRoute: [ConversationRoute: [Message]],
        in items: [InboxItem],
        query: String,
        limit: Int = 100
    ) -> [MessageSearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        var results: [MessageSearchResult] = []
        for item in items {
            for summary in item.conversationSummaries {
                for message in messagesByRoute[summary.route] ?? [] where message.kind != .membership {
                    guard let snippet = snippet(of: message.body, matching: trimmed) else { continue }
                    results.append(MessageSearchResult(
                        id: MessageReference(route: summary.route, messageID: message.id),
                        platform: summary.platform,
                        title: item.title,
                        snippet: snippet,
                        timestamp: message.timestamp
                    ))
                }
            }
        }
        return Array(results.sorted { $0.timestamp > $1.timestamp }.prefix(limit))
    }

    /// The body on one line, or nil when it does not contain the query. A one-line row would cut
    /// off a match far into a long message, so the snippet then starts a few words before it.
    static func snippet(of body: String, matching query: String) -> String? {
        let line = body.split(whereSeparator: \.isNewline).joined(separator: " ")
        guard let match = line.range(of: query, options: .caseInsensitive, locale: .current) else { return nil }
        guard line.distance(from: line.startIndex, to: match.lowerBound) > 40 else { return line }
        var start = line.index(match.lowerBound, offsetBy: -20)
        if let space = line[start..<match.lowerBound].firstIndex(of: " ") {
            start = line.index(after: space)
        }
        return "…" + line[start...]
    }

    private static func inboxOrder(_ lhs: InboxItem, _ rhs: InboxItem) -> Bool {
        if lhs.isFavourite != rhs.isFavourite { return lhs.isFavourite }
        if lhs.latestActivity == rhs.latestActivity {
            return String(describing: lhs.id) < String(describing: rhs.id)
        }
        return lhs.latestActivity > rhs.latestActivity
    }

    public static func project(
        accounts: [ConnectedAccount],
        identities: [RemoteIdentity],
        conversations: [RemoteConversation],
        directory: ContactDirectory,
        favouriteRoutes: Set<ConversationRoute> = []
    ) -> [InboxItem] {
        let accountByID = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })
        let identityByID = Dictionary(uniqueKeysWithValues: identities.map { ($0.id, $0) })
        let summaries = conversations.compactMap { conversation -> (RemoteIdentity, ConversationSummary)? in
            guard
                let identity = identityByID[conversation.identityID],
                let account = accountByID[conversation.accountID],
                identity.accountID == conversation.accountID
            else {
                return nil
            }

            return (
                identity,
                ConversationSummary(
                    route: conversation.route,
                    platform: account.platform,
                    title: conversation.title,
                    latestPreview: conversation.latestPreview,
                    latestActivity: conversation.latestActivity,
                    unreadCount: conversation.unreadCount,
                    capabilities: conversation.capabilities,
                    isFromUnknownSender: conversation.isFromUnknownSender
                )
            )
        }

        var grouped: [InboxItem.ID: [ConversationSummary]] = [:]
        for (identity, summary) in summaries {
            let id = directory.personID(linkedTo: identity.id).map(InboxItem.ID.person) ?? .conversation(summary.route)
            grouped[id, default: []].append(summary)
        }

        return grouped.map { id, values in
            let sorted = values.sorted {
                if $0.latestActivity != $1.latestActivity {
                    return $0.latestActivity > $1.latestActivity
                }
                if $0.route.accountID != $1.route.accountID {
                    return $0.route.accountID < $1.route.accountID
                }
                return $0.route.conversationID < $1.route.conversationID
            }
            let title: String
            switch id {
            case let .person(personID):
                title = directory.people[personID]?.displayName ?? sorted[0].title
            case .conversation:
                title = sorted[0].title
            }
            return InboxItem(
                id: id,
                title: title,
                latestActivity: sorted[0].latestActivity,
                unreadCount: sorted.reduce(0) { $0 + $1.unreadCount },
                conversationSummaries: sorted,
                isFavourite: sorted.contains { favouriteRoutes.contains($0.route) }
            )
        }
        .sorted(by: inboxOrder)
    }
}
