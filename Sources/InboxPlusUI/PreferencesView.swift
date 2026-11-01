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

/// What the Settings pane needs from the app that the UI cannot do itself.
public struct AppSettingsServices {
    public var launchAtLogin: LaunchAtLoginStatus
    public var setLaunchAtLogin: @MainActor (Bool) throws -> Void
    public var refreshLaunchAtLogin: @MainActor () -> Void
    public var openLoginItemsSettings: @MainActor () -> Void
    /// Nil when there is no messaging profile to collect from.
    public var exportDiagnostics: (@Sendable (URL) async throws -> Void)?

    public init(
        launchAtLogin: LaunchAtLoginStatus = .unavailable,
        setLaunchAtLogin: @escaping @MainActor (Bool) throws -> Void = { _ in },
        refreshLaunchAtLogin: @escaping @MainActor () -> Void = {},
        openLoginItemsSettings: @escaping @MainActor () -> Void = {},
        exportDiagnostics: (@Sendable (URL) async throws -> Void)? = nil
    ) {
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
            general
            storage
            about
        }
        .formStyle(.grouped)
        .accessibilityIdentifier("inboxplus-preferences")
        .task(id: model.health) { cacheSize = await model.media.cacheSize() }
        .onAppear { services.refreshLaunchAtLogin() }
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
            Toggle("Show message previews", isOn: $preferences.notifications.showsPreviews)
                .disabled(!preferences.notifications.isEnabled)
            Toggle("Play a sound", isOn: $preferences.notifications.playsSound)
                .disabled(!preferences.notifications.isEnabled)
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
