import Foundation
import Testing
@testable import InboxPlusUI

@Test func aConversationWithNoActivityShowsNoTime() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    #expect(RelativeTime.short(Date(timeIntervalSince1970: 0), now: now) == "")
    #expect(RelativeTime.short(now.addingTimeInterval(-120), now: now) == "2m")
}
