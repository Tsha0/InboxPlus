import Foundation
import XCTest
@testable import InboxPlusUpdates

final class AppUpdateConfigurationTests: XCTestCase {
    private var info: [String: Any] {
        [
            "InboxPlusUpdatesEnabled": true,
            "SUFeedURL": "https://tsha0.github.io/InboxPlus/appcast.xml",
            "SUPublicEDKey": Data(repeating: 1, count: 32).base64EncodedString(),
            "CFBundleVersion": "115",
        ]
    }

    func testOnlyConfiguredAppBundlesCanUpdate() {
        XCTAssertTrue(enabled(info))
        XCTAssertFalse(AppUpdateConfiguration.isEnabled(bundleURL: URL(fileURLWithPath: "/tmp/Runner"), info: info))
        var development = info
        development["InboxPlusUpdatesEnabled"] = false
        XCTAssertFalse(enabled(development))
        for field in ["SUFeedURL", "SUPublicEDKey", "CFBundleVersion"] {
            var missing = info
            missing.removeValue(forKey: field)
            XCTAssertFalse(enabled(missing))
        }
    }

    func testInvalidFeedsKeysAndBuildNumbersDisableUpdates() {
        for (field, values) in [
            ("SUFeedURL", ["http://example.com/feed", "https://user:password@example.com/feed", "https:///feed"]),
            ("SUPublicEDKey", ["invalid", Data(repeating: 0, count: 31).base64EncodedString()]),
            ("CFBundleVersion", ["0", "-1", "0.9.0", "١١٥", ""]),
        ] {
            for value in values {
                var invalid = info
                invalid[field] = value
                XCTAssertFalse(enabled(invalid), "\(field): \(value)")
            }
        }
    }

    private func enabled(_ info: [String: Any]) -> Bool {
        AppUpdateConfiguration.isEnabled(bundleURL: URL(fileURLWithPath: "/Applications/Inbox+.app"), info: info)
    }
}
