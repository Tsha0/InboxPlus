import Foundation
import InboxPlusCore

public struct SuggestedContactLink: Identifiable, Equatable, Sendable {
    public let displayName: String
    public let identityIDs: [String]
    public let platforms: [Platform]
    public var id: String { identityIDs.joined(separator: "|") }

    public static func matches(conversations: [RemoteConversation], accounts: [ConnectedAccount]) -> [Self] {
        let candidates = conversations.filter { !$0.isGroup }
        let groups = Dictionary(grouping: candidates) {
            $0.title.trimmingCharacters(in: .whitespacesAndNewlines)
                .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        }
        return groups.compactMap { key, conversations in
            guard !key.isEmpty, key != "unknown", key != "unknown user" else { return nil }
            let platforms = conversations.compactMap { conversation in
                accounts.first { $0.id == conversation.accountID }?.platform
            }
            guard Set(platforms).count > 1, Set(platforms).count == conversations.count else { return nil }
            let ordered = conversations.sorted { $0.identityID < $1.identityID }
            return Self(displayName: ordered[0].title, identityIDs: ordered.map(\.identityID), platforms: platforms)
        }.sorted { $0.id < $1.id }
    }
}
