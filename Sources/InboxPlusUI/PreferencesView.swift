import AppKit
import SwiftUI
import InboxPlusCore
import InboxPlusFeatures

public enum LaunchAtLoginStatus: Equatable, Sendable {
    /// Not an installed app, so there is nothing macOS could open at login.
    case unavailable
    case off
    case on
    /// Turned on, but waiting for the user to allow it in System Settings.
    case needsApproval
}

public enum SystemNotificationStatus: Equatable, Sendable {
    case unavailable
    case notDetermined
    case denied
    case allowed(soundEnabled: Bool)

    var canDeliverNotifications: Bool {
        if case .allowed = self { true } else { false }
    }

    var dockBadgeWarning: String? {
        self == .denied ? "Dock badges may also be blocked by macOS. The menu bar count still works." : nil
    }

    var warning: String? {
        switch self {
        case .unavailable: "Notifications are available when Inbox+ runs as an app."
        case .notDetermined: "Allow notifications in the macOS permission prompt."
        case .denied: "macOS is blocking Inbox+ notifications. Enable them in System Settings."
        case .allowed(soundEnabled: false): "Notification sounds are turned off for Inbox+ in System Settings."
        case .allowed(soundEnabled: true): nil
        }
    }

    var canOpenSettings: Bool {
        switch self {
        case .denied, .allowed(soundEnabled: false): true
        case .unavailable, .notDetermined, .allowed(soundEnabled: true): false
        }
    }
}

/// What the Settings pane needs from the app that the UI cannot do itself.
public struct AppSettingsServices {
    public var notificationStatus: SystemNotificationStatus
    public var refreshNotifications: @MainActor () async -> Void
    public var openNotificationSettings: @MainActor () -> Void
    public var launchAtLogin: LaunchAtLoginStatus
    public var setLaunchAtLogin: @MainActor (Bool) throws -> Void
    public var refreshLaunchAtLogin: @MainActor () -> Void
    public var openLoginItemsSettings: @MainActor () -> Void
    /// Nil when there is no messaging profile to collect from.
    public var exportDiagnostics: (@Sendable (URL) async throws -> Void)?

    public init(
        notificationStatus: SystemNotificationStatus = .unavailable,
        refreshNotifications: @escaping @MainActor () async -> Void = {},
        openNotificationSettings: @escaping @MainActor () -> Void = {},
        launchAtLogin: LaunchAtLoginStatus = .unavailable,
        setLaunchAtLogin: @escaping @MainActor (Bool) throws -> Void = { _ in },
        refreshLaunchAtLogin: @escaping @MainActor () -> Void = {},
        openLoginItemsSettings: @escaping @MainActor () -> Void = {},
        exportDiagnostics: (@Sendable (URL) async throws -> Void)? = nil
    ) {
        self.notificationStatus = notificationStatus
        self.refreshNotifications = refreshNotifications
        self.openNotificationSettings = openNotificationSettings
        self.launchAtLogin = launchAtLogin
        self.setLaunchAtLogin = setLaunchAtLogin
        self.refreshLaunchAtLogin = refreshLaunchAtLogin
        self.openLoginItemsSettings = openLoginItemsSettings
        self.exportDiagnostics = exportDiagnostics
    }
}

public enum UnreadBadge {
    public static func label(for count: Int) -> String? {
        count > 0 ? "\(count)" : nil
    }

    public static func menuBarAccessibilityLabel(health: ServiceHealth, unread: Int) -> String {
        unread > 0 ? "\(health.menuBarTitle), \(unread) unread" : health.menuBarTitle
    }
}

struct AppVersion: Equatable {
    let version: String
    let build: String

    /// A bare `swift run` executable has no bundle version, so it says it is a development build.
    init(info: [String: Any]) {
        version = info["CFBundleShortVersionString"] as? String ?? InboxPlusVersion.current
        build = info["CFBundleVersion"] as? String ?? "Development"
    }
}

/// App preferences, shown beside the accounts list when Settings is open.
struct PreferencesView: View {
    @Bindable var model: InboxPlusAppModel
    @Bindable var preferences: AppPreferences
    let services: AppSettingsServices
    var onThemePicked: () -> Void = {}

    @State private var cacheSize: Int?
    @State private var confirmsClearingCache = false
    @State private var isClearingCache = false
    @State private var isExportingDiagnostics = false
    @State private var failure: Failure?

    private let version = AppVersion(info: Bundle.main.infoDictionary ?? [:])

    struct Failure {
        let title: String
        let message: String
    }

    var body: some View {
        Form {
            notifications
            AppearanceSection(preferences: preferences, onThemePicked: onThemePicked)
            general
            ReelPlaybackSection(preferences: preferences)
            storage
            about
        }
        .formStyle(.grouped)
        .accessibilityIdentifier("inboxplus-preferences")
        .task(id: model.health) { cacheSize = await model.media.cacheSize() }
        .onAppear { services.refreshLaunchAtLogin() }
        .task { await services.refreshNotifications() }
        .confirmationDialog("Clear downloaded media?", isPresented: $confirmsClearingCache) {
            Button("Clear Cache", role: .destructive, action: clearCache)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Photos, videos and files download again when you open them. Messages, drafts and attachments you have not sent are kept.")
        }
        .alert(
            failure?.title ?? "",
            isPresented: Binding(get: { failure != nil }, set: { if !$0 { failure = nil } })
        ) {
            Button("OK", role: .cancel) { failure = nil }
        } message: {
            Text(failure?.message ?? "")
        }
    }

    // MARK: - Sections

    private var notifications: some View {
        Section {
            Toggle("Show notifications", isOn: $preferences.notifications.isEnabled)
                .disabled(!services.notificationStatus.canDeliverNotifications)
            Toggle("Show message previews", isOn: $preferences.notifications.showsPreviews)
                .disabled(!preferences.notifications.isEnabled || !services.notificationStatus.canDeliverNotifications)
            Toggle("Play a sound", isOn: $preferences.notifications.playsSound)
                .disabled(!preferences.notifications.isEnabled || !services.notificationStatus.canDeliverNotifications)
            if let warning = services.notificationStatus.warning {
                VStack(alignment: .leading, spacing: 6) {
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .accessibilityIdentifier("notification-permission-warning")
                    if services.notificationStatus.canOpenSettings {
                        Button("Open Notifications Settings…") { services.openNotificationSettings() }
                            .controlSize(.small)
                            .accessibilityIdentifier("open-notification-settings")
                    }
                }
            }
            LabeledContent("Muted conversations") {
                if model.mutedConversations.isEmpty {
                    Text("None").foregroundStyle(.secondary)
                }
            }
            ForEach(model.mutedConversations) { summary in
                HStack(spacing: 8) {
                    PlatformBadge(platform: summary.platform)
                    Text(summary.title).lineLimit(1)
                    Spacer()
                    Button("Unmute") { model.setMuted(false, for: summary.route) }
                        .controlSize(.small)
                        .accessibilityLabel("Unmute \(summary.title)")
                }
            }
            if let preferenceError = model.preferenceError {
                Label(preferenceError, systemImage: "exclamationmark.triangle.fill").font(.caption)
            }
        } header: {
            Text("Notifications")
        } footer: {
            Text("Mute a conversation with the bell at the top of it, or by right-clicking it in the inbox. Muted conversations never notify and are left out of the unread badge.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var general: some View {
        Section("General") {
            Toggle("Open Inbox+ at login", isOn: Binding(
                get: { [.on, .needsApproval].contains(services.launchAtLogin) },
                set: { setLaunchAtLogin($0) }
            ))
            .disabled(services.launchAtLogin == .unavailable)
            switch services.launchAtLogin {
            case .needsApproval:
                HStack {
                    Text("Allow Inbox+ in Login Items to finish turning this on.")
                        .font(.caption)
                    Spacer()
                    Button("Open Login Items…") { services.openLoginItemsSettings() }
                        .controlSize(.small)
                }
            case .unavailable:
                Text("Available once Inbox+ is installed as an app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .on, .off:
                EmptyView()
            }
            Toggle("Show the unread count in the Dock and menu bar", isOn: $preferences.showsUnreadBadge)
            if let warning = services.notificationStatus.dockBadgeWarning {
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("dock-badge-permission-warning")
            }
        }
    }

    private var storage: some View {
        Section("Storage") {
            LabeledContent("Downloaded media") {
                Text(cacheSize.map(Self.formatted(bytes:)) ?? "—")
                    .monospacedDigit()
                    .accessibilityIdentifier("media-cache-size")
            }
            HStack {
                Text("Photos, videos and files download again when you open them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if isClearingCache { ProgressView().controlSize(.small) }
                Button("Clear Cache…") { confirmsClearingCache = true }
                    .disabled(cacheSize ?? 0 == 0 || isClearingCache)
                    .accessibilityIdentifier("clear-media-cache")
            }
            Picker("Keep messages for", selection: $preferences.messageRetention) {
                ForEach(MessageRetention.allCases) { retention in
                    Text(retention.title).tag(retention)
                }
            }
            .accessibilityIdentifier("message-retention")
            Text("Older messages are deleted from this Mac and stay on the network. iMessage uses its own history below. Applies the next time Inbox+ opens.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("iMessage history", selection: $preferences.iMessageHistory) {
                ForEach(IMessageHistoryWindow.allCases) { window in
                    Text(window.title).tag(window)
                }
            }
            Text("Chats with nothing newer are left out of the inbox. Applies the next time Inbox+ opens.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var about: some View {
        Section("About") {
            LabeledContent("Version", value: version.version)
            LabeledContent("Build", value: version.build)
            HStack {
                Text("Logs and settings with tokens, cookies, messages and links removed, safe to attach to a bug report.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if isExportingDiagnostics { ProgressView().controlSize(.small) }
                Button("Export Diagnostics…", action: exportDiagnostics)
                    .disabled(services.exportDiagnostics == nil || isExportingDiagnostics)
                    .accessibilityIdentifier("export-diagnostics")
            }
        }
    }

    // MARK: - Actions

    private func setLaunchAtLogin(_ enabled: Bool) {
        do { try services.setLaunchAtLogin(enabled) }
        catch {
            failure = Failure(
                title: enabled ? "Inbox+ could not be added to Login Items" : "Inbox+ could not be removed from Login Items",
                message: error.localizedDescription
            )
        }
    }

    private func clearCache() {
        isClearingCache = true
        Task {
            defer { isClearingCache = false }
            do { try await model.media.clearCache() }
            catch {
                failure = Failure(title: "The cache was not cleared", message: error.localizedDescription)
            }
            cacheSize = await model.media.cacheSize()
        }
    }

    private func exportDiagnostics() {
        guard let export = services.exportDiagnostics else { return }
        let panel = NSSavePanel()
        panel.title = "Export Diagnostics"
        panel.prompt = "Export"
        panel.nameFieldStringValue = "Inbox+ Diagnostics \(Date().formatted(.iso8601.year().month().day()))"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        isExportingDiagnostics = true
        Task {
            defer { isExportingDiagnostics = false }
            do {
                try await export(destination)
                NSWorkspace.shared.activateFileViewerSelecting([destination])
            } catch {
                failure = Failure(title: "Diagnostics were not exported", message: error.localizedDescription)
            }
        }
    }

    static func formatted(bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

struct ReelPlaybackSection: View {
    @Bindable var preferences: AppPreferences

    var body: some View {
        Section {
            Toggle("Play Instagram Reels in Inbox+", isOn: $preferences.playsInstagramReels)
                .accessibilityIdentifier("play-instagram-reels")
        } header: {
            Text("Instagram Reels")
        } footer: {
            Text("When off, Reels appear as labeled thumbnails that open in Instagram. When on, available videos play here when you press Play.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
