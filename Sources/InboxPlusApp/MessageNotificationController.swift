import AppKit
import UserNotifications
import InboxPlusCore

/// Native notifications require an application bundle. Keep `swift run` and tests usable too.
@MainActor
final class MessageNotificationController: NSObject, UNUserNotificationCenterDelegate {
    static let shared = MessageNotificationController()
    private var center: UNUserNotificationCenter?
    private var authorizationTask: Task<Bool, Never>?
    private var pendingRoute: ConversationRoute?
    var onOpen: ((ConversationRoute) -> Void)? {
        didSet {
            if let pendingRoute, let onOpen {
                self.pendingRoute = nil
                onOpen(pendingRoute)
            }
        }
    }

    func install() {
        guard Bundle.main.bundleURL.pathExtension == "app", Bundle.main.bundleIdentifier != nil else { return }
        center = UNUserNotificationCenter.current()
        center?.delegate = self
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

    func deliver(_ message: Message, title: String) {
        guard let center else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = message.body.isEmpty ? "New \(message.kind.rawValue) message" : message.body
        content.sound = .default
        content.userInfo = Self.userInfo(for: message.route)
        // Encoding the tuple avoids collisions across accounts, rooms, and event IDs.
        let key = [message.route.accountID, message.route.conversationID, message.id]
        let identifier = (try? JSONEncoder().encode(key).base64EncodedString()) ?? UUID().uuidString
        Task {
            guard await authorizationTask?.value == true else { return }
            do { try await center.add(UNNotificationRequest(identifier: identifier, content: content, trigger: nil)) }
            catch { report(error) }
        }
    }

    static func userInfo(for route: ConversationRoute) -> [String: String] {
        ["accountID": route.accountID, "conversationID": route.conversationID]
    }

    static func route(from userInfo: [AnyHashable: Any]) -> ConversationRoute? {
        guard let account = userInfo["accountID"] as? String, !account.isEmpty,
              let conversation = userInfo["conversationID"] as? String, !conversation.isEmpty else { return nil }
        return ConversationRoute(accountID: account, conversationID: conversation)
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
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier else { return }
        let info = response.notification.request.content.userInfo
        // Extract Sendable values before crossing to the main actor.
        guard let account = info["accountID"] as? String,
              let conversation = info["conversationID"] as? String else { return }
        await open(ConversationRoute(accountID: account, conversationID: conversation))
    }

    private func open(_ route: ConversationRoute) {
        guard !route.accountID.isEmpty, !route.conversationID.isEmpty else { return }
        if let onOpen { onOpen(route) } else { pendingRoute = route }
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func report(_ error: any Error) {
        FileHandle.standardError.write(Data("Inbox+: notification delivery unavailable: \(error.localizedDescription)\n".utf8))
    }
}
