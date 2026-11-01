/// How much history Inbox+ keeps. A conversation holds its most recent messages, not its whole
/// history: the network keeps the rest, and keeping less keeps the profile small.
public enum RecentHistory {
    /// The messages a conversation opens with: what a bridge backfills, what is read from a local
    /// database, and what a conversation is trimmed back to once it is closed.
    public static let messageCount = 50
    /// Days the homeserver keeps a message. It stops serving an older one and later purges it.
    public static let messageLifetimeDays = 90
    /// Days the homeserver keeps media nobody has opened.
    public static let mediaLifetimeDays = 30
}
