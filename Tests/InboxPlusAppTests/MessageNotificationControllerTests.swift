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
