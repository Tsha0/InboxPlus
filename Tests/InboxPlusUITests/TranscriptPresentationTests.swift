import Foundation
import Testing
import InboxPlusCore
import InboxPlusUI

private func transcriptMessage(_ id: String, sender: String? = "alice", time: TimeInterval = 1000, name: String? = nil) -> Message {
    Message(id: id, route: .init(accountID: "account", conversationID: "room"), senderIdentityID: sender,
            body: id, timestamp: Date(timeIntervalSince1970: time), deliveryState: .acknowledged, senderDisplayName: name)
}

@Test func transcriptGroupsOnlyNearbyMessagesFromSameSenderAndDay() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let first = transcriptMessage("first")
    #expect(TranscriptPresentation.sameRun(first, transcriptMessage("second", time: 1300), calendar: calendar))
    #expect(!TranscriptPresentation.sameRun(first, transcriptMessage("late", time: 1301), calendar: calendar))
    #expect(!TranscriptPresentation.sameRun(first, transcriptMessage("bob", sender: "bob"), calendar: calendar))
    #expect(!TranscriptPresentation.sameRun(first, transcriptMessage("own", sender: nil), calendar: calendar))
    #expect(!TranscriptPresentation.sameRun(transcriptMessage("night", time: 86399), transcriptMessage("morning", time: 86400), calendar: calendar))
    #expect(TranscriptPresentation.startsDay(first, after: nil, calendar: calendar))
    #expect(!TranscriptPresentation.startsDay(transcriptMessage("second", time: 1300), after: first, calendar: calendar))
    #expect(TranscriptPresentation.startsDay(transcriptMessage("tomorrow", time: 86400), after: first, calendar: calendar))
}

@Test func transcriptUsesProfileNamesAndReadableDayLabels() {
    #expect(TranscriptPresentation.senderName(transcriptMessage("a", name: "Alice Chen"), identities: []) == "Alice Chen")
    #expect(TranscriptPresentation.senderName(transcriptMessage("b", sender: nil, name: "Alice"), identities: []) == "You")
    #expect(TranscriptPresentation.senderName(transcriptMessage("c"), identities: []) == "alice")
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let now = Date(timeIntervalSince1970: 172900)
    #expect(TranscriptPresentation.dayLabel(now, now: now, calendar: calendar) == "Today")
    #expect(TranscriptPresentation.dayLabel(now.addingTimeInterval(-86400), now: now, calendar: calendar) == "Yesterday")
}

@Test func transcriptNamesSendersOnlyWhenMoreThanOneOtherPersonSpeaks() {
    let direct = [transcriptMessage("a"), transcriptMessage("mine", sender: nil), transcriptMessage("b")]
    #expect(!TranscriptPresentation.namesSenders(in: direct))
    #expect(!TranscriptPresentation.namesSenders(in: []))
    #expect(TranscriptPresentation.namesSenders(in: direct + [transcriptMessage("c", sender: "bob")]))
}
