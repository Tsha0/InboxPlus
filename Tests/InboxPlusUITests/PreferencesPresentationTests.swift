import Testing
import InboxPlusCore
import InboxPlusFeatures
@testable import InboxPlusUI

@Test func theUnreadBadgeIsHiddenAtZeroAndCountedOtherwise() {
    #expect(UnreadBadge.label(for: 0) == nil)
    #expect(UnreadBadge.label(for: 12) == "12")
    #expect(UnreadBadge.menuBarAccessibilityLabel(health: .healthy, unread: 0) == "Inbox+ is running")
    #expect(UnreadBadge.menuBarAccessibilityLabel(health: .healthy, unread: 3) == "Inbox+ is running, 3 unread")
}

@Test func notificationSettingsExplainSystemRestrictionsAndOfferTheRelevantAction() {
    #expect(SystemNotificationStatus.denied.warning?.contains("macOS is blocking") == true)
    #expect(SystemNotificationStatus.denied.canOpenSettings)
    #expect(SystemNotificationStatus.allowed(soundEnabled: false).warning?.contains("sounds are turned off") == true)
    #expect(SystemNotificationStatus.allowed(soundEnabled: false).canOpenSettings)
    #expect(SystemNotificationStatus.allowed(soundEnabled: true).warning == nil)
    #expect(!SystemNotificationStatus.allowed(soundEnabled: true).canOpenSettings)
    #expect(SystemNotificationStatus.unavailable.warning != nil)
    #expect(!SystemNotificationStatus.unavailable.canOpenSettings)
    #expect(!SystemNotificationStatus.notDetermined.canOpenSettings)
}

@Test func aboutShowsTheBundleVersionAndBuild() {
    let released = AppVersion(info: ["CFBundleShortVersionString": "0.5.3", "CFBundleVersion": "112"])
    #expect(released.version == "0.5.3")
    #expect(released.build == "112")
    // `swift run` has no bundle, so it falls back to the source version.
    let development = AppVersion(info: [:])
    #expect(development.version == InboxPlusVersion.current)
    #expect(development.build == "Development")
}
