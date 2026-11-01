import Foundation
import InboxPlusCore

/// What a reply shows of the message it answers.
public struct ReplyQuote: Equatable, Sendable {
    public let sender: String?
    public let text: String

    public var accessibilityLabel: String {
        sender.map { "\($0): \(text)" } ?? text
    }
}

public enum TranscriptPresentation {
    /// Offered on every message, ahead of whatever else people have already reacted with.
    public static let quickReactions = ["👍", "❤️", "😂", "😮", "😢", "🙏"]

    public static func reactionChoices(for message: Message) -> [MessageReaction] {
        let quick = quickReactions.map { key in
            message.reactions.first { $0.key == key } ?? MessageReaction(key: key, count: 0, includesMe: false)
        }
        return quick + message.reactions.filter { !quickReactions.contains($0.key) }
    }

    public static func reactionLabel(_ reaction: MessageReaction) -> String {
        reaction.count > 1 ? "\(reaction.key) \(reaction.count)" : reaction.key
    }

    /// The transcript's own copy of the quoted message wins over what arrived with the reply,
    /// because it reflects edits and the names Inbox+ already shows for its sender.
    public static func quote(_ reply: MessageReply, in messages: [Message], identities: [RemoteIdentity]) -> ReplyQuote {
        if let quoted = messages.first(where: { $0.id == reply.messageID }) {
            return ReplyQuote(sender: senderName(quoted, identities: identities), text: quoted.body)
        }
        return ReplyQuote(sender: reply.senderDisplayName, text: reply.body ?? "Original message not loaded")
    }

    public static func replyingToLabel(_ message: Message, identities: [RemoteIdentity]) -> String {
        message.isOutgoing ? "Replying to yourself" : "Replying to \(senderName(message, identities: identities))"
    }

    /// What **Copy Text** copies: what the message says. A filename standing in for the body of an
    /// attachment, or the placeholder for a deleted message, is not that.
    public static func copyableText(_ message: Message) -> String? {
        guard ![.redacted, .encrypted, .membership, .state].contains(message.kind) else { return nil }
        let body = message.body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, !message.attachments.contains(where: { $0.displayName == body }) else { return nil }
        return message.body
    }

    public static func senderName(_ message: Message, identities: [RemoteIdentity]) -> String {
        if message.isOutgoing { return "You" }
        if let name = message.senderDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty {
            return name
        }
        let fallback = identities.first { $0.id == message.senderIdentityID && $0.accountID == message.route.accountID }?.displayName
            ?? message.senderIdentityID ?? "Unknown sender"
        if fallback.hasPrefix("@"), let colon = fallback.firstIndex(of: ":") {
            return String(fallback[fallback.index(after: fallback.startIndex)..<colon])
        }
        return fallback
    }

    /// A chat with one other person is already titled with their name, so labelling every run of
    /// their messages would only repeat it.
    public static func namesSenders(in messages: [Message]) -> Bool {
        var senders = Set<String>()
        for message in messages where !message.isOutgoing {
            if let sender = message.senderIdentityID { senders.insert(sender) }
            if senders.count > 1 { return true }
        }
        return false
    }

    public static func startsDay(_ message: Message, after previous: Message?, calendar: Calendar = .current) -> Bool {
        guard let previous else { return true }
        return !calendar.isDate(message.timestamp, inSameDayAs: previous.timestamp)
    }

    public static func sameRun(_ first: Message?, _ second: Message?, calendar: Calendar = .current) -> Bool {
        guard let first, let second, first.route == second.route,
              first.senderIdentityID == second.senderIdentityID,
              calendar.isDate(first.timestamp, inSameDayAs: second.timestamp) else { return false }
        let interval = second.timestamp.timeIntervalSince(first.timestamp)
        return interval >= 0 && interval <= 300
    }

    public static func dayLabel(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) { return "Yesterday" }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.setLocalizedDateFormatFromTemplate("EEE d MMM yyyy")
        return formatter.string(from: date)
    }
}
