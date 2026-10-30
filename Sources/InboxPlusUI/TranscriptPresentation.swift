import Foundation
import InboxPlusCore

public enum TranscriptPresentation {
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
