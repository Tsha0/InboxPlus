/// How much history Inbox+ keeps. A conversation holds its most recent messages, not its whole
/// history: the network keeps the rest, and keeping less keeps the profile small.
public enum RecentHistory {
    /// The messages a conversation opens with: what a bridge backfills, what is read from a local
    /// database, and what a conversation is trimmed back to once it is closed.
    public static let messageCount = 50
    /// Days the homeserver keeps media nobody has opened.
    public static let mediaLifetimeDays = 30
}

/// How long the homeserver keeps a message. It stops serving an older one and later purges it,
/// so shortening this removes history from the profile while the network keeps its copy.
public enum MessageRetention: Int, CaseIterable, Identifiable, Sendable {
    case day = 1
    case week = 7
    case month = 30
    case quarter = 90
    case year = 365

    /// What a profile keeps until someone chooses otherwise.
    public static let standard = MessageRetention.week

    public var id: Int { rawValue }

    public var days: Int { rawValue }

    public var title: String {
        switch self {
        case .day: "1 day"
        case .week: "1 week"
        case .month: "1 month"
        case .quarter: "3 months"
        case .year: "1 year"
        }
    }
}
