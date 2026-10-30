import Foundation
import SQLite3
import Testing
import InboxPlusCore
import InboxPlusGateway
@testable import InboxPlusIMessage

private let chatA = "iMessage;-;a@example.com"
private let chatB = "iMessage;-;b@example.com"

/// Row ids follow insertion order: 1 read, 2 and 3 unread, 4 a tapback, 5 mine, 6 in the other chat.
private let fixture = """
INSERT INTO handle (id, service) VALUES ('a@example.com', 'iMessage');
INSERT INTO handle (id, service) VALUES ('b@example.com', 'iMessage');
INSERT INTO chat (guid, style, chat_identifier, service_name)
  VALUES ('\(chatA)', 45, 'a@example.com', 'iMessage');
INSERT INTO chat (guid, style, chat_identifier, service_name)
  VALUES ('\(chatB)', 45, 'b@example.com', 'iMessage');
INSERT INTO message (guid, text, handle_id, date, is_from_me, is_read)
  VALUES ('read', 'already read on another device', 1, 731160000000000000, 0, 1);
INSERT INTO message (guid, text, handle_id, date, is_from_me, is_read)
  VALUES ('unread-1', 'first', 1, 731160001000000000, 0, 0);
INSERT INTO message (guid, text, handle_id, date, is_from_me, is_read)
  VALUES ('unread-2', 'second', 1, 731160002000000000, 0, 0);
INSERT INTO message (guid, text, handle_id, date, is_from_me, is_read, associated_message_guid)
  VALUES ('tapback', 'Liked "second"', 1, 731160003000000000, 0, 0, 'p:0/unread-2');
INSERT INTO message (guid, text, handle_id, date, is_from_me, is_read)
  VALUES ('mine', 'reply', 0, 731160004000000000, 1, 0);
INSERT INTO message (guid, text, handle_id, date, is_from_me, is_read)
  VALUES ('other-chat', 'hello', 2, 731160005000000000, 0, 0);
INSERT INTO chat_message_join VALUES (1, 1), (1, 2), (1, 3), (1, 4), (1, 5), (2, 6);
"""

/// Stands in for Messages writing to its own database while Inbox+ has it open.
private func messagesWrites(_ sql: String, to url: URL) throws {
    var database: OpaquePointer?
    defer { sqlite3_close(database) }
    try #require(sqlite3_open(url.path, &database) == SQLITE_OK)
    try #require(sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK)
}

private func makeGateway(_ url: URL, markers: IMessageReadMarkerStore?) throws -> IMessageGateway {
    IMessageGateway(store: try IMessageStore(url: url), pollInterval: .seconds(3_600), readMarkerStore: markers)
}

private func unreadCounts(in snapshot: MessagingSnapshot) -> [String: Int] {
    Dictionary(uniqueKeysWithValues: snapshot.conversations.map { ($0.id, $0.unreadCount) })
}

@Test func onlyIncomingMessagesMessagesHasNotMarkedReadAreCounted() throws {
    let url = try makeDatabase(fixture)
    defer { cleanUp(url) }

    #expect(try IMessageStore(url: url).unreadCounts(after: [:]) == [chatA: 2, chatB: 1])
}

@Test func unreadMessagesUpToAChatsReadMarkerAreNotCounted() throws {
    let url = try makeDatabase(fixture)
    defer { cleanUp(url) }

    #expect(try IMessageStore(url: url).unreadCounts(after: [chatA: 2]) == [chatA: 1, chatB: 1])
    #expect(try IMessageStore(url: url).unreadCounts(after: [chatA: 6]) == [chatB: 1])
}

@Test func anUnreadIMessageShowsABadge() async throws {
    let url = try makeDatabase(fixture)
    defer { cleanUp(url) }

    let snapshot = try await makeGateway(url, markers: nil).loadSnapshot()

    #expect(unreadCounts(in: snapshot) == [chatA: 2, chatB: 1])
}

@Test func aChatReadInInboxPlusStaysReadAfterARelaunchWithoutWritingToMessages() async throws {
    let url = try makeDatabase(fixture)
    defer { cleanUp(url) }
    let markers = IMessageReadMarkerStore(
        fileURL: url.deletingLastPathComponent().appendingPathComponent("profile/imessage-read-markers.json")
    )
    let gateway = try makeGateway(url, markers: markers)
    _ = try await gateway.loadSnapshot()

    try await gateway.markRead(ConversationRoute(accountID: IMessageGateway.accountID, conversationID: chatA))

    let relaunched = try makeGateway(url, markers: markers)
    #expect(unreadCounts(in: try await relaunched.loadSnapshot()) == [chatA: 0, chatB: 1])
    #expect(try IMessageStore(url: url).unreadCounts(after: [:]) == [chatA: 2, chatB: 1])
}

@Test func aMessageInboxPlusHasNotShownYetStaysUnreadWhenTheChatIsRead() async throws {
    let url = try makeDatabase(fixture)
    defer { cleanUp(url) }
    let markers = IMessageReadMarkerStore(
        fileURL: url.deletingLastPathComponent().appendingPathComponent("profile/imessage-read-markers.json")
    )
    let gateway = try makeGateway(url, markers: markers)
    _ = try await gateway.loadSnapshot()
    try messagesWrites("""
    INSERT INTO message (guid, text, handle_id, date, is_from_me, is_read)
      VALUES ('arrived-later', 'still there?', 1, 731160006000000000, 0, 0);
    INSERT INTO chat_message_join VALUES (1, 7);
    """, to: url)

    try await gateway.markRead(ConversationRoute(accountID: IMessageGateway.accountID, conversationID: chatA))

    let relaunched = try makeGateway(url, markers: markers)
    #expect(unreadCounts(in: try await relaunched.loadSnapshot()) == [chatA: 1, chatB: 1])
}
