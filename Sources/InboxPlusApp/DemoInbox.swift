import Foundation
import InboxPlusCore
import InboxPlusFeatures

/// A demo inbox that someone asked for explicitly, for exploring the app without any account.
///
/// `INBOXPLUS_DEMO=1` runs the app on made-up conversations held in memory. It never resolves a
/// profile, starts the runtime, reads the Messages database or the Keychain, or contacts a network,
/// even when a real profile exists on this Mac, and the window title says "Demo". Without the
/// variable nothing changes: a bare executable still starts empty, because demo people sitting
/// beside real conversations are indistinguishable from a bug.
enum DemoInbox {
    static let environmentKey = "INBOXPLUS_DEMO"

    static func isRequested(environment: [String: String]) -> Bool {
        environment[environmentKey] == "1"
    }

    static let isActive = isRequested(environment: ProcessInfo.processInfo.environment)

    // Each account is a different network: the app allows one account per platform.
    static let accounts: [ConnectedAccount] = [
        .init(id: "demo-whatsapp", platform: .whatsApp, displayName: "Personal"),
        .init(id: "demo-instagram", platform: .instagram, displayName: "Personal"),
        .init(id: "demo-messenger", platform: .facebookMessenger, displayName: "Personal"),
        .init(id: "demo-telegram", platform: .telegram, displayName: "Personal"),
        .init(id: "demo-imessage", platform: .iMessage, displayName: "iCloud"),
    ]

    /// The linked person: Maya is reachable on two networks, which is what Contacts groups.
    static func makeDirectory() -> ContactDirectory {
        var directory = ContactDirectory()
        // Fixed data that cannot conflict. The tests check the result, so a mistake here fails
        // there rather than being silently skipped at launch.
        try? directory.createPerson(id: "demo-maya", displayName: "Maya Chen")
        try? directory.link(remoteIdentityID: "demo-maya-whatsapp", to: "demo-maya")
        try? directory.link(remoteIdentityID: "demo-maya-instagram", to: "demo-maya")
        return directory
    }

    /// Conversations chosen to exercise the interface: unread and read threads, a linked person,
    /// a long thread to scroll, a title too long to fit, a failed send to retry, a conversation
    /// without attachments, one that cannot send at all, and a long message with a link.
    static func makeSnapshot(now: Date = Date()) -> MessagingSnapshot {
        func ago(minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }

        let identities: [RemoteIdentity] = [
            .init(id: "demo-maya-whatsapp", accountID: "demo-whatsapp", displayName: "Maya Chen"),
            .init(id: "demo-maya-instagram", accountID: "demo-instagram", displayName: "@maya.chen"),
            .init(id: "demo-family", accountID: "demo-telegram", displayName: "Family"),
            .init(id: "demo-design", accountID: "demo-telegram", displayName: "Design crit"),
            .init(id: "demo-sam", accountID: "demo-imessage", displayName: "Sam"),
            .init(id: "demo-leo", accountID: "demo-messenger", displayName: "Leo Martín"),
            .init(id: "demo-priya", accountID: "demo-whatsapp", displayName: "Priya"),
            .init(id: "demo-noah", accountID: "demo-instagram", displayName: "@noah"),
        ]

        typealias Entry = (from: String?, body: String, minutesAgo: Double, state: MessageDeliveryState)
        var conversations: [RemoteConversation] = []
        var messages: [ConversationRoute: [Message]] = [:]

        func add(
            _ id: String, account: String, identity: String, title: String, unread: Int,
            capabilities: ConversationCapabilities = .mediaCapable,
            _ thread: [Entry]
        ) {
            let route = ConversationRoute(accountID: account, conversationID: id)
            let transcript = thread.enumerated().map { index, entry in
                Message(
                    id: "\(id)-\(index)", route: route, senderIdentityID: entry.from, body: entry.body,
                    timestamp: ago(minutes: entry.minutesAgo), deliveryState: entry.state
                )
            }
            let latest = transcript.max { $0.timestamp < $1.timestamp }
            conversations.append(.init(
                id: id, accountID: account, identityID: identity, title: title,
                latestPreview: latest?.body ?? "", latestActivity: latest?.timestamp ?? now,
                unreadCount: unread, capabilities: capabilities
            ))
            messages[route] = transcript
        }

        add("demo-maya-whatsapp", account: "demo-whatsapp", identity: "demo-maya-whatsapp",
            title: "Maya Chen", unread: 2, [
                (nil, "Running 10 minutes late, sorry!", 32, .acknowledged),
                ("demo-maya-whatsapp", "No worries 😊", 30, .acknowledged),
                ("demo-maya-whatsapp", "Are we still meeting tonight?", 6, .acknowledged),
                ("demo-maya-whatsapp", "I can book the table for 7:30.", 5, .acknowledged),
            ])
        add("demo-maya-instagram", account: "demo-instagram", identity: "demo-maya-instagram",
            title: "@maya.chen", unread: 1, [
                ("demo-maya-instagram", "Sent you the address 📍 14 Harbour Street", 41, .acknowledged),
            ])
        let familyLines = [
            "Dinner this weekend?", "Saturday works for us", "Who's bringing dessert?",
            "I can do the salad", "Grandma wants the dumplings again", "Of course she does 😄",
            "What time?", "6pm?", "Make it 6:30, traffic", "Ok see everyone then",
        ]
        add("demo-family", account: "demo-telegram", identity: "demo-family", title: "Family",
            unread: 0, (0..<40).map { index -> Entry in
                let sender: String? = index.isMultiple(of: 3) ? nil : "demo-family"
                return (sender, familyLines[index % familyLines.count], Double(200 - index * 4), .acknowledged)
            })
        add("demo-design", account: "demo-telegram", identity: "demo-design",
            title: "Design crit — Inbox+ redesign, round three, everyone please bring your notes and mockups",
            unread: 12, [
                ("demo-design", "Uploaded the new navigation rail mockups", 190, .acknowledged),
                ("demo-design", "Can we review the empty states too?", 180, .acknowledged),
            ])
        add("demo-sam", account: "demo-imessage", identity: "demo-sam", title: "Sam", unread: 0, [
            ("demo-sam", "Can you send me the slides?", 1_500, .acknowledged),
            (nil, "Sure, sending now", 1_490, .acknowledged),
            (nil, "Here they are, let me know if the link doesn't work", 1_480, .failed("Not delivered")),
        ])
        add("demo-leo", account: "demo-messenger", identity: "demo-leo", title: "Leo Martín", unread: 0,
            capabilities: .textOnly, [
                ("demo-leo", "Messenger here only takes text, no files.", 3_000, .acknowledged),
            ])
        add("demo-priya", account: "demo-whatsapp", identity: "demo-priya", title: "Priya", unread: 0,
            capabilities: ConversationCapabilities(canSendText: false, attachmentKinds: []), [
                ("demo-priya", "This chat is read-only in the demo: nothing can be sent here.", 7_200, .acknowledged),
            ])
        add("demo-noah", account: "demo-instagram", identity: "demo-noah", title: "@noah", unread: 0, [
            ("demo-noah", """
            Long message to check wrapping and selection. The trip plan is: fly out Friday morning, \
            pick up the car, drive the coast road and stop wherever looks good. Details and the map are \
            at https://www.instagram.com/ — open it when you get a chance.

            Second paragraph: bring a jacket, it gets cold at night.
            """, 10_000, .acknowledged),
        ])

        return MessagingSnapshot(
            accounts: accounts, identities: identities,
            conversations: conversations, messagesByRoute: messages
        )
    }
}
