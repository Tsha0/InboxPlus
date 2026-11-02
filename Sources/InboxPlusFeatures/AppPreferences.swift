import Foundation
import Observation
import InboxPlusCore

public struct NotificationPreferences: Equatable, Sendable {
    public var isEnabled: Bool
    public var showsPreviews: Bool
    public var playsSound: Bool

    public init(isEnabled: Bool = true, showsPreviews: Bool = true, playsSound: Bool = true) {
        self.isEnabled = isEnabled
        self.showsPreviews = showsPreviews
        self.playsSound = playsSound
    }
}

/// How far back an iMessage chat can have gone quiet and still be listed in the inbox.
public enum IMessageHistoryWindow: String, CaseIterable, Identifiable, Sendable {
    case month, quarter, year, all

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .month: "1 month"
        case .quarter: "3 months"
        case .year: "1 year"
        case .all: "All history"
        }
    }

    /// Nil lists every chat the Mac has ever had.
    public var interval: TimeInterval? {
        let day: TimeInterval = 24 * 60 * 60
        switch self {
        case .month: return 30 * day
        case .quarter: return 91 * day
        case .year: return 365 * day
        case .all: return nil
        }
    }
}

/// App-wide choices, kept in the app's own defaults rather than in a messaging profile.
@MainActor
@Observable
public final class AppPreferences {
    public var notifications: NotificationPreferences {
        didSet {
            defaults.set(notifications.isEnabled, forKey: Key.notificationsEnabled)
            defaults.set(notifications.showsPreviews, forKey: Key.notificationPreviews)
            defaults.set(notifications.playsSound, forKey: Key.notificationSound)
        }
    }

    /// The unread count on the Dock icon and beside the menu bar icon.
    public var showsUnreadBadge: Bool {
        didSet { defaults.set(showsUnreadBadge, forKey: Key.unreadBadge) }
    }

    /// Read when the Messages database is opened, so a change applies from the next launch.
    public var iMessageHistory: IMessageHistoryWindow {
        didSet { defaults.set(iMessageHistory.rawValue, forKey: Key.iMessageHistory) }
    }

    /// Handed to the homeserver when Inbox+ starts it, so a change applies from the next launch.
    public var messageRetention: MessageRetention {
        didSet { defaults.set(messageRetention.rawValue, forKey: Key.messageRetention) }
    }

    @ObservationIgnored private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        notifications = NotificationPreferences(
            isEnabled: defaults.object(forKey: Key.notificationsEnabled) as? Bool ?? true,
            showsPreviews: defaults.object(forKey: Key.notificationPreviews) as? Bool ?? true,
            playsSound: defaults.object(forKey: Key.notificationSound) as? Bool ?? true
        )
        showsUnreadBadge = defaults.object(forKey: Key.unreadBadge) as? Bool ?? true
        iMessageHistory = Self.iMessageHistory(in: defaults)
        messageRetention = Self.messageRetention(in: defaults)
    }

    public nonisolated static func iMessageHistory(in defaults: UserDefaults) -> IMessageHistoryWindow {
        defaults.string(forKey: Key.iMessageHistory).flatMap(IMessageHistoryWindow.init(rawValue:)) ?? .year
    }

    public nonisolated static func messageRetention(in defaults: UserDefaults) -> MessageRetention {
        (defaults.object(forKey: Key.messageRetention) as? Int).flatMap(MessageRetention.init(rawValue:)) ?? .standard
    }

    /// Saves a retention the first time Inbox+ launches without one. A profile from before the
    /// setting existed kept 90 days, and the shorter standard would purge that history on the first
    /// launch after updating.
    public nonisolated static func settleMessageRetention(in defaults: UserDefaults, profileExists: Bool) {
        guard defaults.object(forKey: Key.messageRetention) == nil else { return }
        let retention: MessageRetention = profileExists ? .quarter : .standard
        defaults.set(retention.rawValue, forKey: Key.messageRetention)
    }

    private enum Key {
        static let notificationsEnabled = "notifications.enabled"
        static let notificationPreviews = "notifications.showsPreviews"
        static let notificationSound = "notifications.playsSound"
        static let unreadBadge = "unreadBadge.enabled"
        static let iMessageHistory = "imessage.historyWindow"
        static let messageRetention = "messages.retentionDays"
    }
}
