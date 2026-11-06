import AppKit
import SwiftUI
import InboxPlusCore
import InboxPlusFeatures
import InboxPlusGateway
import InboxPlusUI

private struct DesktopFixture: Decodable {
    struct Account: Decodable { let id: String; let platform: Platform; let name: String; let identity: String }
    struct Contact: Decodable { let id: String; let name: String; let identities: [String] }
    struct Chat: Decodable {
        let id: String; let account: String; let identity: String; let title: String
        let preview: String; let minutesAgo: Int; let unread: Int; let group: Bool
    }
    struct Text: Decodable {
        let id: String; let account: String; let conversation: String; let body: String
        let minutesAgo: Int; let outgoing: Bool; let sender: String
        let attachments: [Attachment]?
    }
    struct Attachment: Decodable {
        let id: String; let kind: MessageKind; let name: String; let mimeType: String
        let text: String?; let asset: String?
    }
    struct Reaction: Decodable {
        let account: String; let conversation: String; let message: String
        let key: String; let count: Int; let own: Bool
    }
    struct Recipient: Decodable { let name: String; let address: String }
    let accounts: [Account]
    let referenceTime: String
    let contacts: [Contact]
    let conversations: [Chat]
    let messages: [Text]
    let reactions: [Reaction]
    let recipients: [Recipient]

    func snapshot(now: Date) -> MessagingSnapshot {
        let media = FileManager.default.temporaryDirectory.appendingPathComponent("inboxplus-reference-media-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: media, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let chats = conversations.map {
            RemoteConversation(id: $0.id, accountID: $0.account, identityID: $0.identity,
                title: $0.title, latestPreview: $0.preview,
                latestActivity: now.addingTimeInterval(Double(-60 * $0.minutesAgo)),
                unreadCount: $0.unread, isGroup: $0.group)
        }
        var history: [ConversationRoute: [Message]] = [:]
        for text in messages {
            let route = ConversationRoute(accountID: text.account, conversationID: text.conversation)
            let attachments = (text.attachments ?? []).map { attachment in
                let bytes = attachment.asset.map { try! Data(contentsOf: Bundle.main.url(forResource: $0, withExtension: nil)!) }
                    ?? Data(attachment.text!.utf8)
                let file = media.appendingPathComponent(attachment.name)
                try! bytes.write(to: file)
                try! FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
                return MessageAttachment(id: attachment.id, kind: attachment.kind, filename: attachment.name,
                    mimeType: attachment.mimeType, byteCount: bytes.count,
                    source: MediaHandle(source: file.absoluteString, mimeType: attachment.mimeType))
            }
            history[route, default: []].append(Message(id: text.id, route: route,
                senderIdentityID: text.outgoing ? nil : text.sender, body: text.body,
                timestamp: now.addingTimeInterval(Double(-60 * text.minutesAgo)),
                deliveryState: .acknowledged,
                attachments: attachments,
                reactions: reactions.filter { $0.account == text.account && $0.conversation == text.conversation && $0.message == text.id }
                    .map { MessageReaction(key: $0.key, count: $0.count, includesMe: $0.own) },
                senderDisplayName: text.sender))
        }
        return MessagingSnapshot(
            accounts: accounts.map { ConnectedAccount(id: $0.id, platform: $0.platform,
                displayName: $0.name, networkState: .connected, signedInAs: $0.identity) },
            identities: conversations.map { RemoteIdentity(id: $0.identity, accountID: $0.account, displayName: $0.title) },
            conversations: chats, messagesByRoute: history)
    }

    func directory() throws -> ContactDirectory {
        try ContactDirectory(
            people: Dictionary(uniqueKeysWithValues: contacts.map { ($0.id, InboxPlusPerson(id: $0.id, displayName: $0.name)) }),
            links: Dictionary(uniqueKeysWithValues: contacts.map { ($0.id, PersonLink(personID: $0.id, remoteIdentityIDs: Set($0.identities))) }))
    }
}

private actor DesktopReferenceGateway: ConversationStartingGateway, MessageInteractionGateway {
    private let base: InMemoryMessagingGateway
    private var created: [String: StartedConversation] = [:]

    init(seed: MessagingSnapshot) { base = InMemoryMessagingGateway(seed: seed) }

    func loadSnapshot() async throws -> MessagingSnapshot {
        var snapshot = try await base.loadSnapshot()
        snapshot.identities += created.values.map(\.identity)
        snapshot.conversations += created.values.map(\.conversation)
        return snapshot
    }

    func events() async -> AsyncStream<GatewayEvent> { await base.events() }
    func markRead(_ route: ConversationRoute) async throws { try await base.markRead(route) }
    func sendText(_ body: String, to route: ConversationRoute) async throws -> SendReceipt {
        try await base.sendText(body, to: route)
    }
    func send(_ attachment: OutgoingAttachment, to route: ConversationRoute) async throws -> SendReceipt {
        try await base.send(attachment, to: route)
    }
    func sendText(_ body: String, to route: ConversationRoute, replyingTo messageID: String) async throws -> SendReceipt {
        try await base.sendText(body, to: route, replyingTo: messageID)
    }
    func send(_ attachment: OutgoingAttachment, to route: ConversationRoute, replyingTo messageID: String) async throws -> SendReceipt {
        try await base.send(attachment, to: route, replyingTo: messageID)
    }
    func toggleReaction(_ key: String, to messageID: String, in route: ConversationRoute) async throws {
        try await base.toggleReaction(key, to: messageID, in: route)
    }
    func canStartConversation(accountID: String) -> Bool { accountID == "imessage-local" }
    func startConversation(accountID: String, recipient: String) throws -> StartedConversation {
        guard canStartConversation(accountID: accountID), recipient.hasPrefix("+") || recipient.contains("@") else {
            throw ConversationStartError.invalidRecipient
        }
        if let started = created[recipient] { return started }
        let identity = RemoteIdentity(id: recipient, accountID: accountID, displayName: recipient)
        let started = StartedConversation(identity: identity, conversation: RemoteConversation(
            id: "preview-\(recipient)", accountID: accountID, identityID: recipient,
            title: recipient, latestPreview: "", latestActivity: .distantPast, unreadCount: 0, capabilities: .textOnly))
        created[recipient] = started
        return started
    }
}

@MainActor
private final class ReferenceDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.activate(ignoringOtherApps: true)
    }
}

@main
@MainActor
struct DesktopReferenceApp: App {
    @NSApplicationDelegateAdaptor(ReferenceDelegate.self) private var delegate
    @State private var model: InboxPlusAppModel
    @State private var preferences: AppPreferences

    init() {
        let fixtureURL = Bundle.main.url(forResource: "desktop-parity", withExtension: "json")!
        let fixture = try! JSONDecoder().decode(DesktopFixture.self, from: Data(contentsOf: fixtureURL))
        let empty = ProcessInfo.processInfo.environment["INBOXPLUS_REFERENCE_EMPTY"] == "1"
        let snapshot = empty ? MessagingSnapshot.empty : fixture.snapshot(now: ISO8601DateFormatter().date(from: fixture.referenceTime)!)
        _model = State(initialValue: InboxPlusAppModel(gateway: DesktopReferenceGateway(seed: snapshot),
            directory: empty ? ContactDirectory() : try! fixture.directory(),
            localRecipientSource: { .available(fixture.recipients.map { LocalRecipient(name: $0.name, address: $0.address) }) }))
        let defaults = UserDefaults(suiteName: "com.inboxplus.desktop-reference.preferences")!
        let preferences = AppPreferences(defaults: defaults)
        preferences.appearanceMode = .light
        _preferences = State(initialValue: preferences)
    }

    var body: some Scene {
        WindowGroup("Inbox+ reference") {
            RootView(model: model, preferences: preferences,
                settings: AppSettingsServices(notificationStatus: .allowed(soundEnabled: true), launchAtLogin: .off))
                .task { try? await model.start() }
        }
        .defaultSize(width: 1100, height: 732)
        .commands { InboxCommands() }
    }
}
