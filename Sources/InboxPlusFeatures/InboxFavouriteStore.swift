import Foundation
import InboxPlusCore

/// Stored beside the messaging profile, using routes rather than transient contact IDs.
public struct InboxFavouriteStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() throws -> Set<ConversationRoute> {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        return Set(try JSONDecoder().decode([ConversationRoute].self, from: Data(contentsOf: fileURL)))
    }

    public func save(_ routes: Set<ConversationRoute>) throws {
        let sorted = routes.sorted {
            if $0.accountID != $1.accountID { return $0.accountID < $1.accountID }
            return $0.conversationID < $1.conversationID
        }
        let data = try JSONEncoder().encode(sorted)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }
}
