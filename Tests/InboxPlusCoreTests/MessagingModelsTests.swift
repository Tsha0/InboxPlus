import Foundation
import Testing
@testable import InboxPlusCore

@Test func everyPlatformHasAccessibleIconMetadata() {
    for platform in Platform.allCases {
        #expect(!platform.accessibilityLabel.isEmpty)
        #expect(!platform.symbolName.isEmpty)
    }
}

@Test func accountPolicyRejectsTwoAccountsForOnePlatform() {
    let accounts = [
        ConnectedAccount(id: "wa-1", platform: .whatsApp, displayName: "One"),
        ConnectedAccount(id: "wa-2", platform: .whatsApp, displayName: "Two")
    ]
    #expect(throws: AccountPolicyError.duplicatePlatform(.whatsApp)) {
        try AccountPolicy.validate(accounts)
    }
}
