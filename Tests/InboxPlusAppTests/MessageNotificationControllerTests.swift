import Foundation
import ServiceManagement
import Testing
import UserNotifications
import InboxPlusCore
import InboxPlusFeatures
import InboxPlusUI
@testable import InboxPlusApp

@MainActor
@Test func notificationRoutePreservesAccountAndConversation() {
    let route = ConversationRoute(accountID: "instagram/account", conversationID: "!room:server")
    #expect(MessageNotificationController.route(from: MessageNotificationController.userInfo(for: route)) == route)
    #expect(MessageNotificationController.route(from: ["accountID": ""]) == nil)
    #expect(MessageNotificationController.route(from: ["accountID": "a", "conversationID": 42]) == nil)
}

private let route = ConversationRoute(accountID: "instagram", conversationID: "!trip")
private let alert = IncomingMessageAlert(
    message: Message(id: "$1", route: route, senderIdentityID: "maya", body: "See you at 8",
                     timestamp: .now, deliveryState: .acknowledged),
    title: "Weekend Trip", senderName: "Maya", canReply: true
)

@MainActor
@Test func aNotificationFollowsTheNotificationPreferences() throws {
    let full = try #require(MessageNotificationController.content(for: alert, preferences: NotificationPreferences()))
    #expect(full.title == "Weekend Trip")
    #expect(full.subtitle == "Maya")
    #expect(full.body == "See you at 8")
    #expect(full.sound != nil)
    #expect(full.categoryIdentifier == MessageNotificationController.messageCategory)
    #expect(MessageNotificationController.route(from: full.userInfo) == route)

    let quiet = try #require(MessageNotificationController.content(
        for: alert, preferences: NotificationPreferences(showsPreviews: false, playsSound: false)
    ))
    #expect(quiet.body == "New message")
    #expect(quiet.sound == nil)

    #expect(MessageNotificationController.content(for: alert, preferences: NotificationPreferences(isEnabled: false)) == nil)

    // A one-to-one chat is already titled with the sender, and one that cannot take text offers no reply.
    let direct = try #require(MessageNotificationController.content(
        for: IncomingMessageAlert(message: alert.message, title: "Sam"), preferences: NotificationPreferences()
    ))
    #expect(direct.subtitle.isEmpty)
    #expect(direct.categoryIdentifier.isEmpty)
}

@MainActor
@Test func messageNotificationsOfferATypedReply() throws {
    let category = try #require(MessageNotificationController.categories.first)
    #expect(category.identifier == MessageNotificationController.messageCategory)
    let action = try #require(category.actions.first as? UNTextInputNotificationAction)
    #expect(action.identifier == MessageNotificationController.replyAction)
}

@Test func aClickOpensTheConversationAndATypedReplyIsSentToIt() {
    let info: [AnyHashable: Any] = ["accountID": route.accountID, "conversationID": route.conversationID]
    func response(_ action: String, _ text: String? = nil) -> NotificationResponse? {
        MessageNotificationController.response(action: action, userInfo: info, typedText: text, title: "Weekend Trip")
    }
    #expect(response(UNNotificationDefaultActionIdentifier) == .open(route))
    #expect(response(MessageNotificationController.replyAction, "On my way")
        == .reply(NotificationReply(route: route, text: "On my way", conversationTitle: "Weekend Trip")))
    #expect(response(MessageNotificationController.replyAction, "   ") == nil)
    #expect(response(UNNotificationDismissActionIdentifier) == nil)
    #expect(MessageNotificationController.response(
        action: UNNotificationDefaultActionIdentifier, userInfo: [:], typedText: nil, title: ""
    ) == nil)
}

@MainActor
@Test func openingAtLoginIsOnlyOfferedToAnInstalledApp() {
    #expect(LaunchAtLoginController.status(of: .enabled, isAppBundle: false) == .unavailable)
    #expect(LaunchAtLoginController.status(of: .enabled, isAppBundle: true) == .on)
    #expect(LaunchAtLoginController.status(of: .requiresApproval, isAppBundle: true) == .needsApproval)
    #expect(LaunchAtLoginController.status(of: .notRegistered, isAppBundle: true) == .off)
}

@MainActor
@Test func allowingNotificationsAfterAnInitialDenialRestoresDeliveryWithoutRelaunching() async {
    let center = FakeMessageNotificationCenter(status: .denied)
    let controller = MessageNotificationController(center: center)
    controller.requestAuthorization()
    await controller.deliver(alert, preferences: NotificationPreferences())
    #expect(center.requests.isEmpty)
    #expect(controller.status == .denied)

    center.currentStatus = .allowed(soundEnabled: true)
    await controller.deliver(alert, preferences: NotificationPreferences())
    #expect(center.requests.count == 1)
    #expect(center.requests.first?.content.sound != nil)
    #expect(controller.status == .allowed(soundEnabled: true))
    #expect(center.authorizationRequests == 1)

    center.currentStatus = .denied
    await controller.deliver(alert, preferences: NotificationPreferences())
    #expect(center.requests.count == 1)
    #expect(controller.status == .denied)
}

@MainActor
@Test func currentSystemRestrictionsRefreshWithoutRequestingPermissionAgain() async {
    let center = FakeMessageNotificationCenter(status: .allowed(soundEnabled: false))
    let controller = MessageNotificationController(center: center)
    await controller.refreshAuthorization()
    #expect(controller.status == .allowed(soundEnabled: false))

    center.currentStatus = .allowed(soundEnabled: true)
    await controller.refreshAuthorization()
    #expect(controller.status == .allowed(soundEnabled: true))
    #expect(center.authorizationRequests == 0)
}

@MainActor
@Test func deliveryPreservesTheAppsSoundPreferenceAndDisabledNotificationsAreNotPosted() async {
    let center = FakeMessageNotificationCenter(status: .allowed(soundEnabled: true))
    let controller = MessageNotificationController(center: center)
    controller.requestAuthorization()
    await controller.deliver(alert, preferences: NotificationPreferences(playsSound: false))
    #expect(center.requests.count == 1)
    #expect(center.requests.first?.content.sound == nil)

    await controller.deliver(alert, preferences: NotificationPreferences(isEnabled: false))
    #expect(center.requests.count == 1)
}

@MainActor
@Test func notificationSystemSettingsDistinguishDeniedPermissionFromDisabledSound() {
    #expect(MessageNotificationController.status(authorization: .notDetermined, sound: .notSupported) == .notDetermined)
    #expect(MessageNotificationController.status(authorization: .denied, sound: .enabled) == .denied)
    #expect(MessageNotificationController.status(authorization: .authorized, sound: .disabled) == .allowed(soundEnabled: false))
    #expect(MessageNotificationController.status(authorization: .authorized, sound: .enabled) == .allowed(soundEnabled: true))
    #expect(MessageNotificationController.status(authorization: .provisional, sound: .disabled) == .allowed(soundEnabled: false))
}

@MainActor
private final class FakeMessageNotificationCenter: MessageNotificationCenter {
    var currentStatus: SystemNotificationStatus
    private(set) var authorizationRequests = 0
    private(set) var requests: [UNNotificationRequest] = []

    init(status: SystemNotificationStatus) { currentStatus = status }

    func requestAuthorization() async throws { authorizationRequests += 1 }
    func status() async -> SystemNotificationStatus { currentStatus }
    func add(_ request: UNNotificationRequest) async throws { requests.append(request) }
}
