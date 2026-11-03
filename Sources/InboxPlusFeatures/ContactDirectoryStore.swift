import Darwin
import Foundation
import InboxPlusCore

public enum ContactStorageError: LocalizedError {
    case loadFailed, saveFailed

    public var errorDescription: String? {
        switch self {
        case .loadFailed: "Could not load saved contacts. Your saved data has been kept; linking is disabled until you reopen Inbox+ after resolving the storage problem."
        case .saveFailed: "Could not save contacts. The link was not changed. Check that your profile is writable and try again."
        }
    }
}

public struct ContactDirectoryStore: Sendable {
    private struct Record: Codable {
        var schemaVersion = 1
        let people: [String: InboxPlusPerson]
        let links: [String: PersonLink]
    }

    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() throws -> ContactDirectory {
        do {
            let data: Data
            do { data = try Data(contentsOf: fileURL) }
            catch CocoaError.fileReadNoSuchFile { return ContactDirectory() }
            let record = try JSONDecoder().decode(Record.self, from: data)
            guard record.schemaVersion == 1 else { throw ContactStorageError.loadFailed }
            return try ContactDirectory(people: record.people, links: record.links)
        } catch {
            throw ContactStorageError.loadFailed
        }
    }

    public func save(_ directory: ContactDirectory) throws {
        let parent = fileURL.deletingLastPathComponent()
        let staging = parent.appendingPathComponent(".contacts-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: staging) }
        do {
            try FileManager.default.createDirectory(
                at: parent, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
            )
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: parent.path)
            let encoder = JSONEncoder()
            encoder.outputFormatting = .sortedKeys
            let data = try encoder.encode(Record(people: directory.people, links: directory.links))
            guard FileManager.default.createFile(
                atPath: staging.path, contents: data, attributes: [.posixPermissions: 0o600]
            ), rename(staging.path, fileURL.path) == 0 else {
                throw ContactStorageError.saveFailed
            }
        } catch {
            throw ContactStorageError.saveFailed
        }
    }
}
