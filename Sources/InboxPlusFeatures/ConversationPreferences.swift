import Foundation
import InboxPlusCore

public enum MuteDuration: CaseIterable, Hashable, Sendable {
    case oneHour, eightHours, forever

    /// Nil for a mute that never ends on its own.
    public func end(from start: Date) -> Date? {
        switch self {
        case .oneHour: start.addingTimeInterval(60 * 60)
        case .eightHours: start.addingTimeInterval(8 * 60 * 60)
        case .forever: nil
        }
    }
}

/// What the user chose for individual conversations.
///
/// Kept by Inbox+ rather than sent to the networks, so it works the same on every one of them and
/// nobody else learns that a chat was hidden or muted. Stored by route, like favourites.
public struct ConversationPreferences: Codable, Equatable, Sendable {
    public struct Mute: Codable, Hashable, Sendable {
        public let route: ConversationRoute
        /// Nil for a mute with no end.
        public let until: Date?
    }

    public struct Hide: Codable, Hashable, Sendable {
        public let route: ConversationRoute
        /// The conversation's latest activity when it was hidden. Anything newer brings it back.
        public let latestActivity: Date
    }

    /// Shown as unread even when the network counts nothing unread there.
    public var markedUnread: Set<ConversationRoute> = []
    public private(set) var mutes: [Mute] = []
    public private(set) var hides: [Hide] = []

    public init() {}

    public var hidden: Set<ConversationRoute> { Set(hides.map(\.route)) }

    public mutating func hide(_ conversations: some Sequence<(route: ConversationRoute, latestActivity: Date)>) {
        let hiding = Array(conversations)
        unhide(hiding.map(\.route))
        hides += hiding.map { Hide(route: $0.route, latestActivity: $0.latestActivity) }
    }

    public mutating func unhide(_ routes: some Sequence<ConversationRoute>) {
        let routes = Set(routes)
        hides.removeAll { routes.contains($0.route) }
    }

    /// Brings back every hidden conversation something new has arrived in since, including while
    /// Inbox+ was not running, except the muted ones: muting is what keeps a noisy group away.
    public mutating func reviveHidden(in conversations: [RemoteConversation], at date: Date) {
        let latest = Dictionary(conversations.map { ($0.route, $0.latestActivity) }, uniquingKeysWith: max)
        let current = self
        hides.removeAll { hide in
            guard let activity = latest[hide.route] else { return false }
            return activity > hide.latestActivity && !current.isMuted(hide.route, at: date)
        }
    }

    public func isMuted(_ route: ConversationRoute, at date: Date) -> Bool {
        mutes.contains { $0.route == route && ($0.until.map { $0 > date } ?? true) }
    }

    public mutating func mute(_ routes: some Sequence<ConversationRoute>, for duration: MuteDuration, from start: Date) {
        let routes = Set(routes)
        mutes.removeAll { routes.contains($0.route) || $0.until.map { $0 <= start } == true }
        let until = duration.end(from: start)
        mutes += routes.map { Mute(route: $0, until: until) }
    }

    public mutating func unmute(_ routes: some Sequence<ConversationRoute>) {
        let routes = Set(routes)
        mutes.removeAll { routes.contains($0.route) }
    }

    /// The next moment a mute runs out, so the inbox can stop showing it as muted right then.
    public func nextMuteEnd(after date: Date) -> Date? {
        mutes.compactMap(\.until).filter { $0 > date }.min()
    }

    public mutating func forget(accountID: String) {
        hides.removeAll { $0.route.accountID == accountID }
        markedUnread = markedUnread.filter { $0.accountID != accountID }
        mutes.removeAll { $0.route.accountID == accountID }
    }
}

/// Stored beside the messaging profile, next to the favourites.
public struct ConversationPreferenceStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() throws -> ConversationPreferences {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return ConversationPreferences() }
        return try JSONDecoder().decode(ConversationPreferences.self, from: Data(contentsOf: fileURL))
    }

    public func save(_ preferences: ConversationPreferences) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(preferences)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }
}
