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
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
        )
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        if let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
           attributes[.type] as? FileAttributeType == .typeSymbolicLink {
            throw CocoaError(.fileWriteNoPermission)
        }
        try data.write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
}
