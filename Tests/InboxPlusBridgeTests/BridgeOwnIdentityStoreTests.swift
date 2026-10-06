import Foundation
import SQLite3
import Testing
@testable import InboxPlusBridgeService

private final class IdentityDatabase {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let url: URL
    private let db: OpaquePointer

    init() throws {
        url = directory.appendingPathComponent("bridge.db")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var pointer: OpaquePointer?
        #expect(sqlite3_open(url.path, &pointer) == SQLITE_OK)
        db = try #require(pointer)
        try execute("""
            PRAGMA journal_mode = WAL;
            CREATE TABLE user_login (bridge_id TEXT DEFAULT '', id TEXT, user_mxid TEXT, metadata TEXT);
            CREATE TABLE message (bridge_id TEXT DEFAULT '', mxid TEXT, room_receiver TEXT, sender_id TEXT, sender_mxid TEXT);
            CREATE TABLE whatsmeow_device (jid TEXT PRIMARY KEY, lid TEXT);
            """)
    }

    deinit {
        sqlite3_close(db)
        try? FileManager.default.removeItem(at: directory)
    }

    func execute(_ sql: String) throws {
        let result = sqlite3_exec(db, sql, nil, nil, nil)
        #expect(result == SQLITE_OK)
        guard result == SQLITE_OK else { throw FixtureError.query }
    }

    func senders(_ bridgeID: String, owner: String = "@owner:local") throws -> Set<String> {
        try BridgeOwnIdentityStore.outgoingIdentifiers(
            database: url, bridgeID: bridgeID, ownerUserID: owner, serverName: "local"
        )
    }
}

private enum FixtureError: Error { case query }

@Test(arguments: ["instagram", "facebookmessenger", "telegram"])
func numericBridgeLoginsResolveOnlyTheOwnersGhosts(_ bridge: String) throws {
    let fixture = try IdentityDatabase()
    try fixture.execute("""
        INSERT INTO user_login (id, user_mxid, metadata) VALUES ('123', '@owner:local', '{}');
        INSERT INTO user_login (id, user_mxid, metadata) VALUES ('456', '@owner:local', '{}');
        INSERT INTO user_login (id, user_mxid, metadata) VALUES ('789', '@other:local', '{}');
        """)
    #expect(try fixture.senders(bridge) == ["@\(bridge)_123:local", "@\(bridge)_456:local"])
    #expect(try fixture.senders(bridge, owner: "@nobody:local").isEmpty)
}

@Test func whatsAppIncludesOnlyTheOwnersPhoneAndLID() throws {
    let fixture = try IdentityDatabase()
    try fixture.execute("""
        INSERT INTO user_login (id, user_mxid, metadata) VALUES ('15551234', '@owner:local', '{"wa_device_id":7}');
        INSERT INTO user_login (id, user_mxid, metadata) VALUES ('15559876', '@other:local', '{"wa_device_id":2}');
        INSERT INTO whatsmeow_device VALUES ('15551234:7@s.whatsapp.net', '998877:7@lid');
        INSERT INTO whatsmeow_device VALUES ('15559876:2@s.whatsapp.net', '112233@lid');
        """)
    #expect(try fixture.senders("whatsapp") == ["@whatsapp_15551234:local", "@whatsapp_lid-998877:local"])
    // Older stores without a LID column still retain the verified phone-number sender.
    try fixture.execute("DROP TABLE whatsmeow_device")
    #expect(try fixture.senders("whatsapp") == ["@whatsapp_15551234:local"])
}

@Test func googleMessagesUsesTheSavedSelfParticipantsWithinEachLoginPrefix() throws {
    let fixture = try IdentityDatabase()
    try fixture.execute("""
        INSERT INTO user_login (id, user_mxid, metadata) VALUES ('phone-A', '@owner:local',
            '{"id_prefix":"A_b","self_participant_ids":["7","8",""]}');
        INSERT INTO user_login (id, user_mxid, metadata) VALUES ('phone-B', '@other:local',
            '{"id_prefix":"someone-else","self_participant_ids":["7"]}');
        """)
    #expect(try fixture.senders("gmessages") == [
        "@gmessages__a__b.1:local", "@gmessages__a__b.7:local", "@gmessages__a__b.8:local"
    ])
    // A login ID is not a Google Messages user ID, and cannot substitute for a missing prefix.
    try fixture.execute("UPDATE user_login SET metadata = '{}' WHERE user_mxid = '@owner:local'")
    #expect(try fixture.senders("gmessages").isEmpty)
}

@Test func googleVoiceUsesConfirmedOutgoingEventsRatherThanTrustingEveryBotMessage() throws {
    let fixture = try IdentityDatabase()
    try fixture.execute("""
        INSERT INTO user_login (id, user_mxid, metadata) VALUES ('own-login', '@owner:local', '{}');
        INSERT INTO user_login (id, user_mxid, metadata) VALUES ('other-login', '@other:local', '{}');
        INSERT INTO message (mxid, room_receiver, sender_id, sender_mxid) VALUES
            ('$outgoing', 'own-login', '', '@gvoicebot:local'),
            ('$incoming', 'own-login', 'prefix.+15551234', '@gvoice_prefix.+15551234:local'),
            ('$other-owner', 'other-login', '', '@gvoicebot:local'),
            ('~fake:placeholder', 'own-login', '', '@gvoicebot:local');
        """)
    #expect(try fixture.senders("gvoice") == ["$outgoing"])
    #expect(try fixture.senders("gvoice", owner: "@nobody:local").isEmpty)
    #expect(try fixture.senders("unknown").isEmpty)
    // New remote sends are confirmed on the next read, without adding the bot as an own sender.
    try fixture.execute("""
        INSERT INTO message (mxid, room_receiver, sender_id, sender_mxid)
        VALUES ('$live', 'own-login', '', '@gvoicebot:local')
        """)
    #expect(try fixture.senders("gvoice") == ["$outgoing", "$live"])
}

@Test func bridgeIdentityReadsSeeCommittedWALUpdatesAndNeverCreateAMissingDatabase() throws {
    let fixture = try IdentityDatabase()
    #expect(try fixture.senders("instagram").isEmpty)
    try fixture.execute("INSERT INTO user_login (id, user_mxid, metadata) VALUES ('123', '@owner:local', '{}')")
    #expect(try fixture.senders("instagram") == ["@instagram_123:local"])
    // An uncommitted login must not become trusted, even while the writer is active.
    try fixture.execute("BEGIN; INSERT INTO user_login (id, user_mxid, metadata) VALUES ('456', '@owner:local', '{}')")
    #expect(try fixture.senders("instagram") == ["@instagram_123:local"])
    try fixture.execute("ROLLBACK")

    let missing = fixture.directory.appendingPathComponent("absent.db")
    #expect(throws: (any Error).self) {
        try BridgeOwnIdentityStore.outgoingIdentifiers(
            database: missing, bridgeID: "instagram", ownerUserID: "@owner:local", serverName: "local"
        )
    }
    #expect(!FileManager.default.fileExists(atPath: missing.path))
}

@Test func matrixLocalpartEncodingMatchesMautrix() {
    #expect(BridgeOwnIdentityStore.encodeLocalpart("Alph@Bet_50up+é") == "_alph=40_bet__50up+=c3=a9")
}
