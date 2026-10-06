import Testing
import InboxPlusCore
@testable import InboxPlusApp

@MainActor
@Test func notificationRoutePreservesAccountAndConversation() {
    let route = ConversationRoute(accountID: "instagram/account", conversationID: "!room:server")
    #expect(MessageNotificationController.route(from: MessageNotificationController.userInfo(for: route)) == route)
    #expect(MessageNotificationController.route(from: ["accountID": ""]) == nil)
    #expect(MessageNotificationController.route(from: ["accountID": "a", "conversationID": 42]) == nil)
}
