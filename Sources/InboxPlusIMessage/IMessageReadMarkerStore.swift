import Foundation

/// How far each iMessage conversation has been read in Inbox+, kept beside the messaging profile.
///
/// Inbox+ never writes to the Messages database, so opening a chat cannot clear `is_read` there.
/// The newest message row id the user has been shown is remembered per chat instead, and only
/// unread messages after it are counted.
public struct IMessageReadMarkerStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// The newest message row id read in each chat, keyed by chat GUID.
    public func load() throws -> [String: Int64] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return [:] }
        return try JSONDecoder().decode([String: Int64].self, from: Data(contentsOf: fileURL))
    }

    public func save(_ markers: [String: Int64]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(markers)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }
}
