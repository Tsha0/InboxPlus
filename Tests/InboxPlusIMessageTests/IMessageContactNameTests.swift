import Foundation
import Testing
import InboxPlusGateway
@testable import InboxPlusIMessage

/// Stands in for the Mac's Contacts, so no test reads anyone's real address book.
private struct FakeContacts: IMessageContactSource {
    let contacts: [IMessageContactBook.Contact]
    func contactBook() async -> IMessageContactBook { IMessageContactBook(contacts) }
}

private let savedContacts = [
    IMessageContactBook.Contact(name: "Alex Rivera", shortName: "Alex", phoneNumbers: ["(555) 010-0100"]),
    IMessageContactBook.Contact(name: "Sam Lee", shortName: "Sam", emailAddresses: ["Friend@Example.com"]),
]

private let hexGroupGUID = "iMessage;+;0123456789abcdef0123456789abcdef"

/// Two one-to-one chats, two unnamed groups (one with an internal `chat…` id, one with a hex id),
/// and a group the user named, each with a recent message. Handle 4 is the same number as handle 1
/// over SMS.
private let namingFixture = """
INSERT INTO handle (id, service) VALUES ('+15550100100', 'iMessage'), ('friend@example.com', 'iMessage'),
  ('+15550100101', 'iMessage'), ('+15550100100', 'SMS'), ('+15550100102', 'iMessage'),
  ('+15550100103', 'iMessage');
INSERT INTO chat (guid, style, chat_identifier, service_name, display_name) VALUES
  ('iMessage;-;+15550100100', 45, '+15550100100', 'iMessage', NULL),
  ('iMessage;-;friend@example.com', 45, 'friend@example.com', 'iMessage', NULL),
  ('iMessage;+;chat123456789', 43, 'chat123456789', 'iMessage', NULL),
  ('\(hexGroupGUID)', 43, '0123456789abcdef0123456789abcdef', 'iMessage', ''),
  ('iMessage;+;chat987654321', 43, 'chat987654321', 'iMessage', 'Weekend Trip');
INSERT INTO chat_handle_join VALUES (3, 1), (3, 2), (3, 3), (3, 4),
  (4, 1), (4, 2), (4, 3), (4, 5), (4, 6), (5, 1), (5, 2);
INSERT INTO message (guid, text, handle_id, date, is_from_me) VALUES
  ('m1', 'see you soon', 1, \(recent), 0),
  ('m2', 'on the way', 2, \(recent), 0),
  ('m3', 'me too', 3, \(recent + 1_000_000_000), 0),
  ('m4', 'thanks', 2, \(recent), 0),
  ('m5', 'hello all', 1, \(recent), 0),
  ('m6', 'saturday?', 1, \(recent), 0);
INSERT INTO chat_message_join (chat_id, message_id) VALUES (1, 1), (3, 2), (3, 3), (2, 4), (4, 5), (5, 6);
"""

/// Yesterday, in the nanoseconds since 2001 that Messages writes. Chats quiet for a year are hidden.
private let recent = Int64((Date().timeIntervalSince1970 - 86_400 - AppleTimestamp.referenceOffset) * 1_000_000_000)

private func snapshot(contacts: any IMessageContactSource) async throws -> MessagingSnapshot {
    let url = try makeDatabase(namingFixture)
    defer { cleanUp(url) }
    let gateway = IMessageGateway(store: try IMessageStore(url: url), contacts: contacts, pollInterval: .seconds(3600))
    return try await gateway.loadSnapshot()
}

private func titles(_ snapshot: MessagingSnapshot) -> [String: String] {
    Dictionary(uniqueKeysWithValues: snapshot.conversations.map { ($0.id, $0.title) })
}

// MARK: - Gateway

@Test func conversationsAreTitledWithTheNamesInContacts() async throws {
    let titles = titles(try await snapshot(contacts: FakeContacts(contacts: savedContacts)))
    #expect(titles["iMessage;-;+15550100100"] == "Alex Rivera")
    #expect(titles["iMessage;-;friend@example.com"] == "Sam Lee")
    #expect(titles["iMessage;+;chat987654321"] == "Weekend Trip")
}

@Test func anUnnamedGroupIsTitledAfterThePeopleInIt() async throws {
    // Its identifier is an internal id, which is what the inbox showed before.
    let titles = titles(try await snapshot(contacts: FakeContacts(contacts: savedContacts)))
    #expect(titles["iMessage;+;chat123456789"] == "Alex, Sam, +1 (555) 010-0101")
    #expect(titles[hexGroupGUID] == "Alex, Sam +3")
}

@Test func groupSendersAreNamedFromContacts() async throws {
    let snapshot = try await snapshot(contacts: FakeContacts(contacts: savedContacts))
    let names = Dictionary(uniqueKeysWithValues: snapshot.identities.map { ($0.id, $0.displayName) })
    // The id stays the raw handle so it is stable; only what the user reads changes.
    #expect(names["+15550100100"] == "Alex Rivera")
    #expect(names["friend@example.com"] == "Sam Lee")
    #expect(names["+15550100101"] == "+1 (555) 010-0101")
}

@Test func withoutContactsAccessEveryTitleIsStillReadable() async throws {
    let titles = titles(try await snapshot(contacts: IMessageContactBook()))
    #expect(titles["iMessage;-;+15550100100"] == "+1 (555) 010-0100")
    #expect(titles["iMessage;-;friend@example.com"] == "friend@example.com")
    #expect(titles["iMessage;+;chat123456789"] == "+1 (555) 010-0100, friend@example.com, +1 (555) 010-0101")
    #expect(!titles.values.contains { $0.contains("chat123456789") || $0.contains("0123456789abcdef") })
}

@Test func groupParticipantsAreReadOncePerPerson() throws {
    let url = try makeDatabase(namingFixture)
    defer { cleanUp(url) }
    let store = try IMessageStore(url: url)
    #expect(try store.participants(inChat: 3) == ["+15550100100", "friend@example.com", "+15550100101"])
    #expect(try store.participants(inChat: 1).isEmpty)
}

// MARK: - Matching

@Test(arguments: [
    ("(555) 010-0100", "+15550100100"),
    ("+1 555 010 0100", "+15550100100"),
    ("1-555-010-0100", "+15550100100"),
    ("07700 900123", "+447700900123"),
    ("+44 (0)7700 900123", "+447700900123"),
    ("0044 7700 900123", "+447700900123"),
])
func aNumberSavedInAnyCommonFormFindsItsContact(saved: String, handle: String) {
    let book = IMessageContactBook([.init(name: "Alex Rivera", phoneNumbers: [saved])])
    #expect(book.name(forHandle: handle) == "Alex Rivera")
}

@Test func aShortLocalNumberDoesNotClaimSomeoneInAnotherArea() {
    let book = IMessageContactBook([.init(name: "Alex Rivera", phoneNumbers: ["010-0100"])])
    #expect(book.name(forHandle: "+15550100100") == "+1 (555) 010-0100")
}

@Test func anEmailMatchesWhateverCaseItWasSavedIn() {
    let book = IMessageContactBook(savedContacts)
    #expect(book.name(forHandle: "friend@example.com") == "Sam Lee")
    #expect(book.name(forHandle: "FRIEND@example.com") == "Sam Lee")
}

@Test func anUnknownHandleIsShownTheWayMessagesShowsIt() {
    let book = IMessageContactBook()
    #expect(book.name(forHandle: "+15550100199") == "+1 (555) 010-0199")
    // Other countries group digits too differently to guess, so they stay as stored.
    #expect(book.name(forHandle: "+447700900123") == "+447700900123")
    #expect(book.name(forHandle: "12345") == "12345")
    #expect(book.name(forHandle: "someone@example.com") == "someone@example.com")
}

@Test func aGroupTitleNamesAFewPeopleAndCountsTheRest() {
    let book = IMessageContactBook(savedContacts)
    #expect(book.groupTitle(forHandles: []) == nil)
    #expect(book.groupTitle(forHandles: ["+15550100100"]) == "Alex")
    #expect(book.groupTitle(forHandles: ["+15550100100", "friend@example.com"]) == "Alex, Sam")
    #expect(
        book.groupTitle(forHandles: ["+15550100100", "friend@example.com", "+15550100101", "+15550100102"])
            == "Alex, Sam +2"
    )
}
