import Foundation
import SQLite3
import InboxPlusCore

public enum IMessageStoreError: Error, Equatable, CustomStringConvertible {
    case fullDiskAccessRequired(String)
    case databaseMissing(String)
    case openFailed(String)
    case queryFailed(String)

    public var description: String {
        switch self {
        case let .fullDiskAccessRequired(path):
            "Inbox+ needs Full Disk Access to read \(path)"
        case let .databaseMissing(path):
            "no Messages database at \(path)"
        case let .openFailed(message):
            "could not open the Messages database: \(message)"
        case let .queryFailed(message):
            "could not read the Messages database: \(message)"
        }
    }
}

public struct IMessageChat: Equatable, Sendable {
    public let rowID: Int64
    /// `iMessage;-;+15555550123` — what Messages needs to address a reply.
    public let guid: String
    /// The phone number, email, or group identifier.
    public let identifier: String
    public let displayName: String?
    public let service: String
    /// True for a group conversation, where a reply goes to the room rather than a person.
    public let isGroup: Bool
}

public struct IMessageRow: Equatable, Sendable {
    public let rowID: Int64
    public let guid: String
    public let chatGUID: String
    public let text: String?
    public let attributedBody: Data?
    public let handle: String?
    public let isFromMe: Bool
    public let date: Date?
    public var attachments: [MessageAttachment] = []
    public var reactions: [String] = []
    public var attachmentCount: Int { attachments.count }

    /// The body as it should be displayed, preferring whichever column actually holds it.
    public var body: String? {
        if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return text }
        guard let attributedBody else { return nil }
        return TypedStreamText.text(fromAttributedBody: attributedBody)
    }
}

/// Read-only access to the local Messages database.
///
/// Opened read-only and against a copy of the URI with `immutable=1` deliberately *not* set: the
/// live database is being written by Messages, so it must be read with normal locking or a
/// concurrent write produces a malformed page error.
public final class IMessageStore {
    public static var defaultDatabaseURL: URL {
        URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Messages/chat.db")
    }

    private let handle: OpaquePointer
    public let url: URL

    public init(url: URL = IMessageStore.defaultDatabaseURL) throws {
        self.url = url
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw IMessageStoreError.databaseMissing(url.path)
        }
        // The only honest test for Full Disk Access is to attempt the read it gates; macOS exposes
        // no API that answers the question directly.
        guard (try? FileHandle(forReadingFrom: url)) != nil else {
            throw IMessageStoreError.fullDiskAccessRequired(url.path)
        }

        var pointer: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI
        guard sqlite3_open_v2(url.absoluteString, &pointer, flags, nil) == SQLITE_OK,
              let pointer else {
            let message = pointer.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown error"
            if let pointer { sqlite3_close_v2(pointer) }
            throw IMessageStoreError.openFailed(message)
        }
        handle = pointer
    }

    deinit { sqlite3_close_v2(handle) }

    // MARK: - Queries

    public func chats() throws -> [IMessageChat] {
        // `style` 43 is a group chat and 45 a one-to-one, which is what decides whether a reply is
        // addressed to a room or a person.
        let sql = """
        SELECT ROWID, guid, chat_identifier, display_name, service_name, style
        FROM chat
        ORDER BY ROWID
        """
        return try rows(sql) { statement in
            IMessageChat(
                rowID: sqlite3_column_int64(statement, 0),
                guid: Self.string(statement, 1) ?? "",
                identifier: Self.string(statement, 2) ?? "",
                displayName: Self.string(statement, 3),
                service: Self.string(statement, 4) ?? "iMessage",
                isGroup: sqlite3_column_int64(statement, 5) == 43
            )
        }
    }

    /// The most recent messages across every conversation.
    ///
    /// Ordered newest-first in SQL so the limit keeps recent history rather than the oldest
    /// messages ever sent, then reversed so callers get chronological order.
    public func recentMessages(limit: Int = 200) throws -> [IMessageRow] {
        try messages(where: "", limit: limit).reversed()
    }

    /// Everything newer than a row id, which is how new messages are noticed.
    public func messages(afterRowID rowID: Int64) throws -> [IMessageRow] {
        try messages(where: """
        AND (message.ROWID > \(rowID) OR message.guid IN (
            SELECT CASE WHEN associated_message_guid LIKE 'bp:%' THEN substr(associated_message_guid, 4)
                WHEN instr(associated_message_guid, '/') > 0
                THEN substr(associated_message_guid, instr(associated_message_guid, '/') + 1)
                ELSE associated_message_guid END
            FROM message WHERE ROWID > \(rowID) AND associated_message_guid IS NOT NULL
        ))
        """, limit: Int.max).reversed()
    }

    public func maxMessageRowID() throws -> Int64 {
        try rows("SELECT COALESCE(MAX(ROWID), 0) FROM message") { sqlite3_column_int64($0, 0) }
            .first ?? 0
    }

    private func messages(where clause: String, limit: Int) throws -> [IMessageRow] {
        let sql = """
        SELECT message.ROWID, message.guid, chat.guid, message.text, message.attributedBody,
               handle.id, message.is_from_me, message.date
        FROM message
        JOIN chat_message_join ON chat_message_join.message_id = message.ROWID
        JOIN chat ON chat.ROWID = chat_message_join.chat_id
        LEFT JOIN handle ON handle.ROWID = message.handle_id
        WHERE (message.associated_message_guid IS NULL OR message.associated_message_guid = '') \(clause)
        ORDER BY message.ROWID DESC
        LIMIT \(limit)
        """
        let result = try rows(sql) { statement in
            IMessageRow(
                rowID: sqlite3_column_int64(statement, 0),
                guid: Self.string(statement, 1) ?? "",
                chatGUID: Self.string(statement, 2) ?? "",
                text: Self.string(statement, 3),
                attributedBody: Self.blob(statement, 4),
                handle: Self.string(statement, 5),
                isFromMe: sqlite3_column_int64(statement, 6) == 1,
                date: AppleTimestamp.date(fromAppleTime: sqlite3_column_int64(statement, 7))
            )
        }
        let reactionsByGUID = try reactions(
            messageGUIDs: Set(result.map(\.guid)), afterRowID: (result.map(\.rowID).min() ?? 1) - 1
        )
        return try result.map { row in
            var row = row
            row.attachments = try attachments(messageID: row.rowID)
            row.reactions = reactionsByGUID[row.guid] ?? []
            return row
        }
    }

    private func attachments(messageID: Int64) throws -> [MessageAttachment] {
        try rows("""
        SELECT attachment.ROWID, attachment.filename, attachment.mime_type, attachment.transfer_name
        FROM attachment JOIN message_attachment_join ON attachment.ROWID = attachment_id
        WHERE message_id = \(messageID) ORDER BY attachment.ROWID
        """) { statement in
            let path = Self.string(statement, 1)
            let mime = Self.string(statement, 2)
            let kind: MessageKind = mime?.hasPrefix("image/") == true ? .image
                : mime?.hasPrefix("video/") == true ? .video
                : mime?.hasPrefix("audio/") == true ? .audio : .file
            let url = path.flatMap { path -> URL? in
                let expanded = (path as NSString).expandingTildeInPath
                return expanded.hasPrefix("/") ? URL(fileURLWithPath: expanded) : nil
            }
            return MessageAttachment(
                id: "imessage-attachment-\(sqlite3_column_int64(statement, 0))",
                kind: kind,
                filename: Self.string(statement, 3) ?? path.map { ($0 as NSString).lastPathComponent },
                mimeType: mime,
                source: url.map { MediaHandle(source: $0.absoluteString, mimeType: mime) },
                reportedDescription: url == nil ? "This attachment is not available on this Mac." : nil
            )
        }
    }

    /// A tapback is always stored after the message it reacts to, so only rows after the oldest
    /// loaded message can hold one. Without that bound every poll would scan every tapback ever.
    private func reactions(messageGUIDs: Set<String>, afterRowID rowID: Int64) throws -> [String: [String]] {
        guard !messageGUIDs.isEmpty else { return [:] }
        let events = try rows("""
        SELECT handle_id, is_from_me, associated_message_type, associated_message_emoji,
               associated_message_guid
        FROM message
        WHERE ROWID > \(rowID)
          AND associated_message_guid IS NOT NULL AND associated_message_guid != ''
        ORDER BY ROWID
        """) { statement in
            (sqlite3_column_int64(statement, 0), sqlite3_column_int64(statement, 1),
             Int(sqlite3_column_int64(statement, 2)), Self.string(statement, 3), Self.string(statement, 4) ?? "")
        }
        var active: [String: [String: String]] = [:]
        for (sender, fromMe, type, emoji, target) in events {
            let guid = target.hasPrefix("bp:") ? String(target.dropFirst(3))
                : target.split(separator: "/", maxSplits: 1).last.map(String.init) ?? target
            guard messageGUIDs.contains(guid) else { continue }
            let key = "\(fromMe == 1 ? "me" : String(sender)):\(target)"
            if (3000...3007).contains(type) {
                active[guid, default: [:]][key] = nil
            } else if type == 2006, let emoji, !emoji.isEmpty {
                active[guid, default: [:]][key] = emoji
            } else if (2000...2005).contains(type) {
                active[guid, default: [:]][key] = ["❤️", "👍", "👎", "😂", "‼️", "❓"][type - 2000]
            }
        }
        return active.mapValues { $0.sorted { $0.key < $1.key }.map(\.value) }
    }

    // MARK: - Plumbing

    private func rows<T>(_ sql: String, _ decode: (OpaquePointer) -> T) throws -> [T] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw IMessageStoreError.queryFailed(String(cString: sqlite3_errmsg(handle)))
        }
        defer { sqlite3_finalize(statement) }

        var results: [T] = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_ROW {
                results.append(decode(statement))
            } else if step == SQLITE_DONE {
                break
            } else {
                throw IMessageStoreError.queryFailed(String(cString: sqlite3_errmsg(handle)))
            }
        }
        return results
    }

    private static func string(_ statement: OpaquePointer, _ column: Int32) -> String? {
        guard let raw = sqlite3_column_text(statement, column) else { return nil }
        return String(cString: raw)
    }

    private static func blob(_ statement: OpaquePointer, _ column: Int32) -> Data? {
        guard let raw = sqlite3_column_blob(statement, column) else { return nil }
        let count = Int(sqlite3_column_bytes(statement, column))
        guard count > 0 else { return nil }
        return Data(bytes: raw, count: count)
    }
}
