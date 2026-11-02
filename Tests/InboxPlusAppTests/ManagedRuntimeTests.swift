import Foundation
import InboxPlusCore
import InboxPlusFeatures
import Testing
@testable import InboxPlusApp

@MainActor
@Test func theRuntimeIsStartedWithTheRetentionChosenInSettings() throws {
    let suite = "InboxPlusTests-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }

    #expect(ManagedRuntime.startArguments(profileName: "default", defaults: defaults) == [
        "start", "--profile", "default", "--exit-with-parent", "--message-retention-days", "7",
    ])

    AppPreferences(defaults: defaults).messageRetention = .year

    #expect(ManagedRuntime.startArguments(profileName: "default", defaults: defaults) == [
        "start", "--profile", "default", "--exit-with-parent", "--message-retention-days", "365",
    ])
}
