import AppKit
import UserNotifications
import InboxPlusCore
import InboxPlusFeatures

/// A reply typed into a notification, with the conversation it answers.
struct NotificationReply: Equatable, Sendable {
    let route: ConversationRoute
    let text: String
    let conversationTitle: String
}

/// What a click on a notification, or one of its actions, asks for.
enum NotificationResponse: Equatable, Sendable {
    case open(ConversationRoute)
    case reply(NotificationReply)
}

/// Native notifications require an application bundle. Keep `swift run` and tests usable too.
@MainActor
final class MessageNotificationController: NSObject, UNUserNotificationCenterDelegate {
    static let shared = MessageNotificationController()
    nonisolated static let messageCategory = "message"
    nonisolated static let replyAction = "reply"

    private var center: UNUserNotificationCenter?
    private var authorizationTask: Task<Bool, Never>?
    private var pendingRoute: ConversationRoute?
    private var pendingReplies: [NotificationReply] = []
    var onOpen: ((ConversationRoute) -> Void)? {
        didSet {
            if let pendingRoute, let onOpen {
                self.pendingRoute = nil
                onOpen(pendingRoute)
            }
        }
    }

    /// A reply can arrive before the window has set this, when it is what launched Inbox+.
    var onReply: ((NotificationReply) -> Void)? {
        didSet {
            guard let onReply else { return }
            let replies = pendingReplies
            pendingReplies.removeAll()
            replies.forEach(onReply)
        }
    }

    func install() {
        guard Bundle.main.bundleURL.pathExtension == "app", Bundle.main.bundleIdentifier != nil else { return }
        center = UNUserNotificationCenter.current()
        center?.delegate = self
        center?.setNotificationCategories(Self.categories)
    }

    static var categories: Set<UNNotificationCategory> {
        let reply = UNTextInputNotificationAction(
            identifier: replyAction, title: "Reply", options: [],
            textInputButtonTitle: "Send", textInputPlaceholder: "Message"
        )
        return [UNNotificationCategory(identifier: messageCategory, actions: [reply], intentIdentifiers: [], options: [])]
    }

    func requestAuthorization() {
        guard let center, authorizationTask == nil else { return }
        authorizationTask = Task {
            do { return try await center.requestAuthorization(options: [.alert, .sound, .badge]) }
            catch {
                report(error)
                return false
            }
        }
    }

    func deliver(_ alert: IncomingMessageAlert, preferences: NotificationPreferences) {
        guard let content = Self.content(for: alert, preferences: preferences) else { return }
        // Encoding the tuple avoids collisions across accounts, rooms, and event IDs.
        let message = alert.message
        let key = [message.route.accountID, message.route.conversationID, message.id]
        post(content, identifier: (try? JSONEncoder().encode(key).base64EncodedString()) ?? UUID().uuidString)
    }

    /// The reply is repeated in the notification, so words that did not reach anyone are not lost.
    func deliverFailure(of reply: NotificationReply, error: any Error) {
        let content = UNMutableNotificationContent()
        content.title = "Your reply to \(reply.conversationTitle) was not sent"
        content.body = "“\(reply.text)” — \(error.localizedDescription)"
        content.sound = .default
        content.userInfo = Self.userInfo(for: reply.route)
        post(content, identifier: UUID().uuidString)
    }

    private func post(_ content: UNMutableNotificationContent, identifier: String) {
        guard let center else { return }
        Task {
            guard await authorizationTask?.value == true else { return }
            do { try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil)) }
            catch { report(error) }
        }
    }

    /// Nil when notifications are off.
    static func content(
        for alert: IncomingMessageAlert,
        preferences: NotificationPreferences
    ) -> UNMutableNotificationContent? {
        guard preferences.isEnabled else { return nil }
        let message = alert.message
        let content = UNMutableNotificationContent()
        content.title = alert.title
        if let sender = alert.senderName { content.subtitle = sender }
        content.body = !preferences.showsPreviews ? "New message"
            : message.body.isEmpty ? "New \(message.kind.rawValue) message" : message.body
        content.sound = preferences.playsSound ? .default : nil
        content.userInfo = userInfo(for: message.route)
        if alert.canReply { content.categoryIdentifier = messageCategory }
        return content
    }

    static func userInfo(for route: ConversationRoute) -> [String: String] {
        ["accountID": route.accountID, "conversationID": route.conversationID]
    }

    nonisolated static func route(from userInfo: [AnyHashable: Any]) -> ConversationRoute? {
        guard let account = userInfo["accountID"] as? String, !account.isEmpty,
              let conversation = userInfo["conversationID"] as? String, !conversation.isEmpty else { return nil }
        return ConversationRoute(accountID: account, conversationID: conversation)
    }

    nonisolated static func response(
        action: String,
        userInfo: [AnyHashable: Any],
        typedText: String?,
        title: String
    ) -> NotificationResponse? {
        guard let route = route(from: userInfo) else { return nil }
        switch action {
        case UNNotificationDefaultActionIdentifier:
            return .open(route)
        case replyAction:
            guard let typedText, !typedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return .reply(NotificationReply(route: route, text: typedText, conversationTitle: title))
        default:
            return nil
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let content = response.notification.request.content
        // Extract Sendable values before crossing to the main actor.
        guard let action = Self.response(
            action: response.actionIdentifier,
            userInfo: content.userInfo,
            typedText: (response as? UNTextInputNotificationResponse)?.userText,
            title: content.title
        ) else { return }
        await handle(action)
    }

    private func handle(_ response: NotificationResponse) {
        switch response {
        case let .open(route):
            if let onOpen { onOpen(route) } else { pendingRoute = route }
            NSApplication.shared.activate(ignoringOtherApps: true)
        case let .reply(reply):
            if let onReply { onReply(reply) } else { pendingReplies.append(reply) }
        }
    }

    private func report(_ error: any Error) {
        FileHandle.standardError.write(Data("Inbox+: notification delivery unavailable: \(error.localizedDescription)\n".utf8))
    }
}
