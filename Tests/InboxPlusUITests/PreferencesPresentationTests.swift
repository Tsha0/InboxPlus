import AppKit
import SwiftUI
import Testing
import InboxPlusGateway
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

@Test func notificationControlsReflectPermissionWithoutDisablingTheMenuBarCount() {
    for status in [SystemNotificationStatus.unavailable, .notDetermined, .denied] {
        #expect(!status.canDeliverNotifications)
    }
    for status in [SystemNotificationStatus.allowed(soundEnabled: true), .allowed(soundEnabled: false)] {
        #expect(status.canDeliverNotifications)
        #expect(status.dockBadgeWarning == nil)
    }
    #expect(SystemNotificationStatus.denied.dockBadgeWarning?.contains("Dock badges") == true)
    #expect(SystemNotificationStatus.denied.dockBadgeWarning?.contains("menu bar count still works") == true)
    #expect(SystemNotificationStatus.unavailable.dockBadgeWarning == nil)
    #expect(SystemNotificationStatus.notDetermined.dockBadgeWarning == nil)
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

@MainActor
@Test func notificationPermissionStatesRenderWithoutChangingSavedChoices() throws {
    let suite = "InboxPlusTests.NotificationPresentation.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let preferences = AppPreferences(defaults: defaults)
    let model = InboxPlusAppModel(gateway: InMemoryMessagingGateway(seed: .init(
        accounts: [], identities: [], conversations: [], messagesByRoute: [:]
    )))
    let states: [(String, SystemNotificationStatus)] = [
        ("denied", .denied), ("allowed", .allowed(soundEnabled: true)),
        ("sound-disabled", .allowed(soundEnabled: false)), ("unavailable", .unavailable),
        ("not-determined", .notDetermined)
    ]
    for (name, status) in states {
        let view = NSHostingView(rootView: PreferencesView(
            model: model, preferences: preferences, services: AppSettingsServices(notificationStatus: status)
        ))
        view.frame = NSRect(x: 0, y: 0, width: 660, height: 1100)
        view.layoutSubtreeIfNeeded()
        let bitmap = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        #expect(bitmap.pixelsWide > 0 && bitmap.pixelsHigh > 0)
        #expect(preferences.notifications == NotificationPreferences())
        #expect(preferences.showsUnreadBadge)
        if let directory = ProcessInfo.processInfo.environment["INBOXPLUS_NOTIFICATION_SCREENSHOTS"] {
            let url = URL(fileURLWithPath: directory, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try #require(bitmap.representation(using: .png, properties: [:]))
                .write(to: url.appendingPathComponent("notifications-\(name).png"))
        }
    }
}
