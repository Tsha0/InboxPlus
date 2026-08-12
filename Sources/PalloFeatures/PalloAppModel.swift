import Foundation
import Observation
import PalloCore
import PalloGateway

public enum DetailSelection: Equatable, Sendable {
    case empty
    case personSummary(String)
    case conversation(ConversationRoute)
}

public enum ServiceHealth: Equatable, Sendable {
    case starting
    case healthy
    case needsAttention(String)
}

public enum PalloAppModelError: Error, Equatable {
    case missingOpenConversation
}

@MainActor
@Observable
public final class PalloAppModel {
    public private(set) var accounts: [ConnectedAccount] = []
    public private(set) var identities: [RemoteIdentity] = []
    public private(set) var conversations: [RemoteConversation] = []
    public private(set) var messagesByRoute: [ConversationRoute: [Message]] = [:]
    public private(set) var inboxItems: [InboxItem] = []
    public private(set) var detailSelection: DetailSelection = .empty
    public private(set) var health: ServiceHealth = .starting
    public var draft = ""

    public var openRoute: ConversationRoute? {
        guard case let .conversation(route) = detailSelection else { return nil }
        return route
    }

    private let gateway: any MessagingGateway
    private var directory: ContactDirectory
    private var eventTask: Task<Void, Never>?

    public init(gateway: any MessagingGateway, directory: ContactDirectory = .init()) {
        self.gateway = gateway
        self.directory = directory
    }

    public func start() async throws {
        let snapshot = try await gateway.loadSnapshot()
        try AccountPolicy.validate(snapshot.accounts)
        apply(snapshot)
        health = .healthy
        let stream = await gateway.events()
        eventTask = Task { [weak self] in
            for await event in stream {
                guard !Task.isCancelled else { return }
                self?.apply(event)
            }
        }
    }

    public func selectInboxItem(_ item: InboxItem) {
        switch item.id {
        case let .person(id):
            detailSelection = .personSummary(id)
        case let .conversation(route):
            detailSelection = .conversation(route)
        }
    }

    public func openConversation(_ route: ConversationRoute) {
        detailSelection = .conversation(route)
    }

    public func sendDraft() async throws {
        guard let route = openRoute else { return }
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        _ = try await gateway.sendText(body, to: route)
        draft = ""
    }

    public func summaries(for personID: String) -> [ConversationSummary] {
        inboxItems.first { $0.id == .person(personID) }?.conversationSummaries ?? []
    }

    public var people: [PalloPerson] {
        directory.people.values.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    public func personID(for route: ConversationRoute) -> String? {
        guard let identityID = conversations.first(where: { $0.route == route })?.identityID else { return nil }
        return directory.personID(linkedTo: identityID)
    }

    public func linkOpenConversation(to personID: String) throws {
        guard
            let route = openRoute,
            let identityID = conversations.first(where: { $0.route == route })?.identityID
        else { throw PalloAppModelError.missingOpenConversation }
        try directory.link(remoteIdentityID: identityID, to: personID)
        rebuildInbox()
        detailSelection = .personSummary(personID)
    }

    @discardableResult
    public func createPersonAndLinkOpenConversation(displayName: String) throws -> String {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ContactDirectoryError.missingPerson }
        let personID = UUID().uuidString
        try directory.createPerson(id: personID, displayName: trimmed)
        do {
            try linkOpenConversation(to: personID)
        } catch {
            directory.removePerson(id: personID)
            throw error
        }
        return personID
    }

    private func apply(_ snapshot: MessagingSnapshot) {
        accounts = snapshot.accounts
        identities = snapshot.identities
        conversations = snapshot.conversations
        messagesByRoute = snapshot.messagesByRoute
        rebuildInbox()
    }

    private func apply(_ event: GatewayEvent) {
        switch event {
        case let .messageUpserted(message):
            messagesByRoute[message.route, default: []].append(message)
        case let .conversationUpserted(conversation):
            conversations.removeAll { $0.id == conversation.id && $0.accountID == conversation.accountID }
            conversations.append(conversation)
            rebuildInbox()
        case let .connectionChanged(_, isConnected):
            health = isConnected ? .healthy : .needsAttention("An account is disconnected")
        }
    }

    private func rebuildInbox() {
        inboxItems = InboxProjector.project(
            accounts: accounts,
            identities: identities,
            conversations: conversations,
            directory: directory
        )
    }
}
