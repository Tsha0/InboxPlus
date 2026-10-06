import Foundation
import SQLite3

/// Resolves only the authenticated owner's bridge senders, never an entire ghost namespace.
///
/// bridgev2 `user_login.user_mxid` is the ownership boundary. The provisioning `whoami` response
/// omits the per-login metadata needed by Google Messages and WhatsApp LIDs, so read the local
/// database instead. Select only identity fields, using normal read-only locking (including WAL),
/// so this works for historical messages even when a bridge process is offline.
///
/// Contracts verified against the catalog pins: mautrix-go v0.28.0/v0.29.0 database/userlogin.go;
/// meta/telegram v0.2607.0 connector/client.go; whatsapp v0.2607.0 connector/id.go and waid/id.go;
/// gmessages v0.2605.0 connector/{id,dbmeta,client}.go; gvoice v0.2605.0 connector/handlegvoice.go.
public enum BridgeOwnIdentityStore {
    /// Matrix sender user IDs (`@...`) and individual outgoing event IDs (`$...`). These
    /// namespaces cannot collide; event IDs are used when a bot also posts non-message notices.
    public static func outgoingIdentifiers(
        database: URL,
        bridgeID: String,
        ownerUserID: String,
        serverName: String
    ) throws -> Set<String> {
        guard ["instagram", "facebookmessenger", "telegram", "whatsapp", "gmessages", "gvoice"]
            .contains(bridgeID) else { return [] }

        var pointer: OpaquePointer?
        guard sqlite3_open_v2(database.path, &pointer, SQLITE_OPEN_READONLY, nil) == SQLITE_OK,
              let db = pointer else {
            if let pointer { sqlite3_close(pointer) }
            throw IdentityStoreError.unavailable
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 100)

        // Do not fetch session credentials stored alongside these fields.
        let rows = try query(db, sql: """
            SELECT id, json_extract(metadata, '$.id_prefix'),
                   json_extract(metadata, '$.self_participant_ids'),
                   json_extract(metadata, '$.wa_device_id')
            FROM user_login WHERE user_mxid = ?
            """, arguments: [ownerUserID])
        var remoteIDs: Set<String> = []
        for row in rows {
            guard let loginID = row[0], !loginID.isEmpty else { continue }
            switch bridgeID {
            case "instagram", "facebookmessenger", "telegram":
                remoteIDs.insert(loginID)
            case "whatsapp":
                remoteIDs.insert(loginID)
                // The phone-number login and the LID are distinct senders. Match only this
                // owner's registered device, not every LID known to the bridge.
                if let storedDevice = row[3], let deviceID = UInt16(storedDevice) {
                    let jid = deviceID == 0 ? "\(loginID)@s.whatsapp.net"
                        : "\(loginID):\(deviceID)@s.whatsapp.net"
                    if let devices = try? query(db, sql: "SELECT lid FROM whatsmeow_device WHERE jid = ?", arguments: [jid]) {
                        for device in devices {
                            if let lid = device[0], lid.hasSuffix("@lid"),
                               let address = lid.split(separator: "@").first,
                               let user = address.split(separator: ":").first,
                               !user.isEmpty {
                                remoteIDs.insert("lid-\(user)")
                            }
                        }
                    }
                }
            case "gmessages":
                guard let prefix = row[1], !prefix.isEmpty else { continue }
                // Participant 1 is always self; multi-SIM/RCS identities are explicitly saved
                // as self_participant_ids by the connector, rather than inferred from members.
                var participants: Set<String> = ["1"]
                if let json = row[2], let data = json.data(using: .utf8),
                   let saved = try? JSONDecoder().decode([String].self, from: data) {
                    participants.formUnion(saved.filter { !$0.isEmpty })
                }
                remoteIDs.formUnion(participants.map { "\(prefix).\($0)" })
            default:
                break
            }
        }
        var matrixIDs = Set(remoteIDs.map { "@\(bridgeID)_\(encodeLocalpart($0)):\(serverName)" })
        if bridgeID == "gvoice", !rows.isEmpty {
            // Voice's IsFromMe events have an empty sender_id and fall back to the bot.
            // The bot also posts system notices, so trust only events saved as remote messages
            // in an owned login's portals. Incoming people have nonempty ghost sender IDs.
            let messages = try query(db, sql: """
                SELECT m.mxid FROM message m
                JOIN user_login ul ON m.bridge_id = ul.bridge_id AND m.room_receiver = ul.id
                WHERE ul.user_mxid = ? AND m.sender_id = '' AND m.sender_mxid = ?
                """, arguments: [ownerUserID, "@gvoicebot:\(serverName)"])
            matrixIDs.formUnion(messages.compactMap { $0[0] }.filter { $0.hasPrefix("$") })
        }
        return matrixIDs
    }

    private static func query(_ db: OpaquePointer, sql: String, arguments: [String]) throws -> [[String?]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw IdentityStoreError.unavailable
        }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (offset, argument) in arguments.enumerated() {
            guard sqlite3_bind_text(statement, Int32(offset + 1), argument, -1, transient) == SQLITE_OK else {
                throw IdentityStoreError.unavailable
            }
        }
        var rows: [[String?]] = []
        while true {
            switch sqlite3_step(statement) {
            case SQLITE_ROW:
                rows.append((0..<sqlite3_column_count(statement)).map { column in
                    sqlite3_column_text(statement, column).map { String(cString: $0) }
                })
            case SQLITE_DONE:
                return rows
            default:
                throw IdentityStoreError.unavailable
            }
        }
    }

    /// mautrix id.EncodeUserLocalpart, applied to the remote ID before username_template.
    static func encodeLocalpart(_ value: String) -> String {
        var result = ""
        for byte in value.utf8 {
            switch byte {
            case 65...90: result += "_" + String(UnicodeScalar(byte + 32))
            case 95: result += "__"
            case 97...122, 48...57, 43, 45, 46: result += String(UnicodeScalar(byte))
            default: result += String(format: "=%02x", byte)
            }
        }
        return result
    }
}

private enum IdentityStoreError: Error {
    case unavailable
}
