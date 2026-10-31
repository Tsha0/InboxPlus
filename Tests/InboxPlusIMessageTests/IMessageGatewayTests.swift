import Foundation
import SQLite3
import Testing
import InboxPlusCore
import InboxPlusGateway
@testable import InboxPlusIMessage

/// Writes to a fixture while the gateway has it open, as Messages does.
private func execute(_ statements: String, on url: URL) {
    var database: OpaquePointer?
    defer { sqlite3_close(database) }
    #expect(sqlite3_open(url.path, &database) == SQLITE_OK)
    #expect(sqlite3_exec(database, statements, nil, nil, nil) == SQLITE_OK)
}

/// A moment `days` ago, in the nanoseconds since 2001 that current macOS writes.
private func appleTime(daysAgo days: Double) -> Int64 {
    Int64((Date().timeIntervalSince1970 - days * 86_400 - AppleTimestamp.referenceOffset) * 1_000_000_000)
}

/// Polls only when a test asks, and fails the test rather than reach Messages.
private func makeGateway(_ url: URL, historyLimit: Int = 50) throws -> IMessageGateway {
    IMessageGateway(
        store: try IMessageStore(url: url),
        sender: IMessageSender { _ in
            Issue.record("a test tried to send through Messages")
            return ""
        },
        historyLimit: historyLimit,
        pollInterval: .seconds(3600)
    )
}

private func next(
    _ count: Int,
    from events: inout AsyncStream<GatewayEvent>.Iterator
) async -> [String] {
    var collected: [String] = []
    while collected.count < count, let event = await events.next() {
        switch event {
        case let .identityUpserted(identity): collected.append("identity \(identity.id)")
        case let .conversationUpserted(conversation): collected.append("conversation \(conversation.id)")
        case let .messageUpserted(message): collected.append("message \(message.id)")
        case let .historicalMessageUpserted(message): collected.append("history \(message.id)")
        case let .accountUpserted(account): collected.append("account \(account.id)")
        case let .connectionChanged(accountID, _): collected.append("connection \(accountID)")
        }
    }
    return collected
}

@Test func everyListedChatShowsItsOwnLatestMessage() async throws {
    // The snapshot once read only the newest few hundred messages across every chat, so a chat
    // with nothing in that window had no preview and the date "Jan 1".
    let url = try makeDatabase("""
    INSERT INTO handle (id, service) VALUES ('+15555550100', 'iMessage');
    INSERT INTO chat (guid, style, chat_identifier, service_name)
      VALUES ('iMessage;-;+15555550100', 45, '+15555550100', 'iMessage');
    INSERT INTO chat (guid, style, chat_identifier, service_name)
      VALUES ('iMessage;-;quiet@example.com', 45, 'quiet@example.com', 'iMessage');
    INSERT INTO message (guid, text, handle_id, date)
      VALUES ('q1', 'catch up next week?', 0, \(appleTime(daysAgo: 30)));
    INSERT INTO message (guid, text, handle_id, date) VALUES ('b1', 'first', 1, \(appleTime(daysAgo: 2)));
    INSERT INTO message (guid, text, handle_id, date) VALUES ('b2', 'second', 1, \(appleTime(daysAgo: 1)));
    INSERT INTO chat_message_join (chat_id, message_id) VALUES (2, 1), (1, 2), (1, 3);
    """)
    defer { cleanUp(url) }

    let snapshot = try await makeGateway(url, historyLimit: 2).loadSnapshot()

    #expect(snapshot.conversations.map(\.latestPreview) == ["second", "catch up next week?"])
    let quiet = try #require(snapshot.conversations.first { $0.id == "iMessage;-;quiet@example.com" })
    #expect(abs(quiet.latestActivity.timeIntervalSinceNow + 30 * 86_400) < 60)
}

@Test func chatsWithNoMessagesOrNoneThisYearAreLeftOut() async throws {
    let url = try makeDatabase("""
    INSERT INTO handle (id, service) VALUES ('active@example.com', 'iMessage');
    INSERT INTO chat (guid, style, chat_identifier, service_name)
      VALUES ('iMessage;-;active@example.com', 45, 'active@example.com', 'iMessage');
    INSERT INTO chat (guid, style, chat_identifier, service_name)
      VALUES ('iMessage;-;empty@example.com', 45, 'empty@example.com', 'iMessage');
    INSERT INTO chat (guid, style, chat_identifier, service_name)
      VALUES ('iMessage;-;reacted@example.com', 45, 'reacted@example.com', 'iMessage');
    INSERT INTO chat (guid, style, chat_identifier, service_name)
      VALUES ('iMessage;-;dormant@example.com', 45, 'dormant@example.com', 'iMessage');
    INSERT INTO message (guid, text, handle_id, date) VALUES ('a1', 'still here', 1, \(appleTime(daysAgo: 3)));
    INSERT INTO message (guid, text, date, associated_message_guid)
      VALUES ('r1', 'Loved an image', \(appleTime(daysAgo: 3)), 'p:0/elsewhere');
    INSERT INTO message (guid, text, date) VALUES ('d1', 'long ago', \(appleTime(daysAgo: 800)));
    INSERT INTO chat_message_join (chat_id, message_id) VALUES (1, 1), (3, 2), (4, 3);
    """)
    defer { cleanUp(url) }

    let snapshot = try await makeGateway(url).loadSnapshot()

    #expect(snapshot.conversations.map(\.id) == ["iMessage;-;active@example.com"])
    #expect(snapshot.identities.map(\.id) == ["active@example.com"])
}

@Test(.timeLimit(.minutes(1)))
func openingAChatLoadsItsRecentHistoryOnce() async throws {
    let url = try makeDatabase("""
    INSERT INTO handle (id, service) VALUES ('+15555550103', 'iMessage');
    INSERT INTO handle (id, service) VALUES ('+15555550104', 'iMessage');
    INSERT INTO chat (guid, style, chat_identifier, service_name, display_name)
      VALUES ('iMessage;+;chat-test', 43, 'chat-test', 'iMessage', 'Test Group');
    INSERT INTO message (guid, text, handle_id, date, is_from_me)
      VALUES ('g1', 'oldest', 1, \(appleTime(daysAgo: 3)), 0);
    INSERT INTO message (guid, text, handle_id, date, is_from_me)
      VALUES ('g2', 'middle', 2, \(appleTime(daysAgo: 2)), 0);
    INSERT INTO message (guid, text, handle_id, date, is_from_me)
      VALUES ('g3', 'newest', 0, \(appleTime(daysAgo: 1)), 1);
    INSERT INTO chat_message_join (chat_id, message_id) VALUES (1, 1), (1, 2), (1, 3);
    """)
    defer { cleanUp(url) }
    let gateway = try makeGateway(url, historyLimit: 2)
    let route = ConversationRoute(accountID: IMessageGateway.accountID, conversationID: "iMessage;+;chat-test")

    let snapshot = try await gateway.loadSnapshot()
    #expect(snapshot.messagesByRoute[route]?.map(\.id) == ["g3"])

    var events = await gateway.events().makeAsyncIterator()
    try await gateway.loadRecentMessages(in: route)
    // A sender the inbox has not met yet is introduced before their message.
    #expect(await next(3, from: &events) == ["identity +15555550104", "history g2", "history g3"])

    // Opening it again reads nothing more, and a message arriving afterwards is still live.
    try await gateway.loadRecentMessages(in: route)
    execute("""
    INSERT INTO message (guid, text, handle_id, date) VALUES ('g4', 'just now', 1, \(appleTime(daysAgo: 0)));
    INSERT INTO chat_message_join (chat_id, message_id) VALUES (1, 4);
    """, on: url)
    await gateway.pollOnce()
    #expect(await next(2, from: &events) == ["identity +15555550103", "message g4"])
}

@Test(.timeLimit(.minutes(1)))
func aNewMessageBringsAQuietChatBackButOldHistoryDoesNot() async throws {
    let url = try makeDatabase("""
    INSERT INTO handle (id, service) VALUES ('+15555550101', 'iMessage');
    INSERT INTO handle (id, service) VALUES ('+15555550102', 'iMessage');
    INSERT INTO chat (guid, style, chat_identifier, service_name)
      VALUES ('iMessage;-;+15555550101', 45, '+15555550101', 'iMessage');
    INSERT INTO chat (guid, style, chat_identifier, service_name)
      VALUES ('iMessage;-;+15555550102', 45, '+15555550102', 'iMessage');
    INSERT INTO message (guid, text, handle_id, date) VALUES ('o1', 'long ago', 1, \(appleTime(daysAgo: 800)));
    INSERT INTO message (guid, text, handle_id, date) VALUES ('o2', 'long ago', 2, \(appleTime(daysAgo: 800)));
    INSERT INTO chat_message_join (chat_id, message_id) VALUES (1, 1), (2, 2);
    """)
    defer { cleanUp(url) }
    let gateway = try makeGateway(url)
    #expect(try await gateway.loadSnapshot().conversations.isEmpty)

    var events = await gateway.events().makeAsyncIterator()
    // Row order matters: had the synced message produced anything, it would come first.
    execute("""
    INSERT INTO message (guid, text, handle_id, date)
      VALUES ('synced', 'older history from iCloud', 2, \(appleTime(daysAgo: 700)));
    INSERT INTO message (guid, text, handle_id, date)
      VALUES ('new', 'are you free tonight?', 1, \(appleTime(daysAgo: 0)));
    INSERT INTO chat_message_join (chat_id, message_id) VALUES (2, 3), (1, 4);
    """, on: url)
    await gateway.pollOnce()

    #expect(await next(3, from: &events) == [
        "identity +15555550101", "conversation iMessage;-;+15555550101", "message new",
    ])
}
