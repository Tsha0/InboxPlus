import Foundation
import InboxPlusCore
import InboxPlusGateway
import InboxPlusFeatures

public enum Fixtures {
    public static let whatsAppRoute = ConversationRoute(accountID: "whatsapp-primary", conversationID: "maya-whatsapp")
    public static let instagramRoute = ConversationRoute(accountID: "instagram-primary", conversationID: "maya-instagram")
    public static let telegramRoute = ConversationRoute(accountID: "telegram-primary", conversationID: "family-telegram")

    /// Fixed timestamps so tests can reason about ordering against absolute dates.
    public static let snapshot = makeSnapshot(
        familyActivity: Date(timeIntervalSince1970: 100),
        whatsAppActivity: Date(timeIntervalSince1970: 200),
        instagramActivity: Date(timeIntervalSince1970: 300)
    )

    public static var directory: ContactDirectory {
        var value = ContactDirectory()
        try! value.createPerson(id: "maya", displayName: "Maya")
        try! value.link(remoteIdentityID: "maya-whatsapp-identity", to: "maya")
        try! value.link(remoteIdentityID: "maya-instagram-identity", to: "maya")
        return value
    }

    public static func makeSnapshot(
        familyActivity: Date,
        whatsAppActivity: Date,
        instagramActivity: Date
    ) -> MessagingSnapshot {
        MessagingSnapshot(
            accounts: [
                .init(id: "whatsapp-primary", platform: .whatsApp, displayName: "Personal"),
                .init(id: "instagram-primary", platform: .instagram, displayName: "Personal"),
                .init(id: "telegram-primary", platform: .telegram, displayName: "Personal"),
            ],
            identities: [
                .init(id: "maya-whatsapp-identity", accountID: "whatsapp-primary", displayName: "Maya"),
                .init(id: "maya-instagram-identity", accountID: "instagram-primary", displayName: "@maya"),
                .init(id: "family-telegram-identity", accountID: "telegram-primary", displayName: "Family"),
            ],
            conversations: [
                .init(id: "maya-whatsapp", accountID: "whatsapp-primary", identityID: "maya-whatsapp-identity", title: "Maya", latestPreview: "Are we still meeting tonight?", latestActivity: whatsAppActivity, unreadCount: 1),
                .init(id: "maya-instagram", accountID: "instagram-primary", identityID: "maya-instagram-identity", title: "@maya", latestPreview: "I sent the address here.", latestActivity: instagramActivity, unreadCount: 2),
                .init(id: "family-telegram", accountID: "telegram-primary", identityID: "family-telegram-identity", title: "Family", latestPreview: "Dinner this weekend?", latestActivity: familyActivity, unreadCount: 0),
            ],
            messagesByRoute: [
                whatsAppRoute: [.init(id: "wa-1", route: whatsAppRoute, senderIdentityID: "maya-whatsapp-identity", body: "Are we still meeting tonight?", timestamp: whatsAppActivity, deliveryState: .acknowledged)],
                instagramRoute: [.init(id: "ig-1", route: instagramRoute, senderIdentityID: "maya-instagram-identity", body: "I sent the address here.", timestamp: instagramActivity, deliveryState: .acknowledged)],
                telegramRoute: [.init(id: "tg-1", route: telegramRoute, senderIdentityID: "family-telegram-identity", body: "Dinner this weekend?", timestamp: familyActivity, deliveryState: .acknowledged)],
            ]
        )
    }
}
