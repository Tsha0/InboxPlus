import Darwin
import Foundation
import UserNotifications
#if os(macOS)
import Cocoa
import ServiceManagement
import FlutterMacOS
import InboxPlusCore
import InboxPlusIMessage
#else
import Flutter
import UIKit
import UniformTypeIdentifiers
#endif

@MainActor
final class InboxPlusAppleServices: NSObject, UNUserNotificationCenterDelegate {
    static weak var shared: InboxPlusAppleServices?
    private let channel: FlutterMethodChannel
    private let webLogin = InboxPlusWebLogin()
    private var hasUnfinishedWork = false
    #if os(macOS)
    private var gateway: IMessageGateway?
    private var gatewayProfile: String?
    private var readMarkersFile: URL?
    private(set) var canClose = false
    private var closePending = false
    private var statusItem: NSStatusItem?
    private var pendingNotificationRoute: [String: String]?
    #else
    private var documentController: UIDocumentInteractionController?
    private var documentPresenter: UIViewController?
    #endif

    init(messenger: FlutterBinaryMessenger) {
        channel = FlutterMethodChannel(name: "inboxplus/native", binaryMessenger: messenger)
        super.init()
        Self.shared = self
        channel.setMethodCallHandler { [weak self] call, result in
            guard let self else { return result(Self.failure("native_unavailable")) }
            self.handle(call, result: result)
        }
        UNUserNotificationCenter.current().delegate = self
    }

    private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let arguments = call.arguments as? [String: Any] ?? [:]
        switch call.method {
        case "capabilities":
            var capabilities: [String: Any] = [
                "web_login_platforms": ["instagram", "messenger"],
                "imessage": Self.hasIMessage,
                "notifications": true,
            ]
            #if os(macOS)
            capabilities["launch_at_login_status"] = launchAtLoginStatus
            #endif
            result(capabilities)
        case "webLogin":
            guard let platform = arguments["platform"] as? String else {
                return result(Self.failure("invalid_request"))
            }
            webLogin.start(platform: platform) { response in
                switch response {
                case let .success(cookies): result(cookies)
                case let .failure(error): result(Self.failure(error.rawValue))
                }
            }
        case "protectPath":
            guard let path = arguments["path"] as? String,
                  let mode = arguments["mode"] as? Int,
                  mode == 0o600 || mode == 0o700 else {
                return result(Self.failure("invalid_request"))
            }
            var metadata = stat()
            guard lstat(path, &metadata) == 0,
                  metadata.st_mode & S_IFMT != S_IFLNK,
                  metadata.st_uid == getuid(), chmod(path, mode_t(mode)) == 0 else {
                return result(Self.failure("storage_permissions_failed"))
            }
            result(true)
        case "cancelWebLogin":
            webLogin.cancel()
            result(nil)
        case "setHasUnfinishedWork":
            hasUnfinishedWork = arguments["value"] as? Bool ?? false
            result(nil)
        case "requestNotificationPermission":
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                DispatchQueue.main.async { result(granted) }
            }
        case "notify":
            notify(arguments, result: result)
        #if os(macOS)
        case "notificationStatus":
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                let status: String
                switch settings.authorizationStatus {
                case .notDetermined: status = "not_determined"
                case .denied: status = "denied"
                case .authorized, .provisional: status = "allowed"
                @unknown default: status = "unavailable"
                }
                DispatchQueue.main.async {
                    result([
                        "status": status,
                        "sound_enabled": settings.soundSetting == .enabled,
                        "alerts_enabled": settings.alertSetting == .enabled && settings.alertStyle != .none,
                        "badges_enabled": settings.badgeSetting == .enabled,
                        "can_open_settings": true,
                    ])
                }
            }
        case "openNotificationSettings":
            guard let identifier = Bundle.main.bundleIdentifier,
                  var url = URLComponents(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension") else {
                return result(Self.failure("notification_settings_unavailable"))
            }
            url.queryItems = [URLQueryItem(name: "id", value: identifier)]
            guard let destination = url.url, NSWorkspace.shared.open(destination) else {
                return result(Self.failure("notification_settings_unavailable"))
            }
            result(nil)
        case "takeNotificationRoute":
            let route = pendingNotificationRoute
            pendingNotificationRoute = nil
            result(route)
        #if DEBUG
        case "previewNotification":
            guard Bundle.main.bundleIdentifier?.hasPrefix("com.inboxplus.desktop-") == true,
                  let route = arguments["route"] as? [String: String],
                  let account = route["account_id"], let conversation = route["conversation_id"] else {
                return result(Self.failure("invalid_request"))
            }
            activateNotification(account: account, conversation: conversation)
            result(nil)
        #endif
        #endif
        case "legacyProfileStatus":
            result(Self.legacyProfileStatus())
        case "legacyPreferences":
            let defaults = UserDefaults.standard
            var values: [String: Any] = [:]
            if let enabled = defaults.object(forKey: "notifications.enabled") as? Bool {
                values["notifications_enabled"] = enabled
            }
            if let appearance = defaults.string(forKey: "appearance.mode") {
                values["appearance"] = appearance
            }
            values["notification_previews"] = defaults.object(forKey: "notifications.showsPreviews") as? Bool
            values["notification_sound"] = defaults.object(forKey: "notifications.playsSound") as? Bool
            values["message_retention_days"] = defaults.object(forKey: "messages.retentionDays") as? Int
            values["imessage_history"] = defaults.string(forKey: "imessage.historyWindow")
            values["plays_instagram_reels"] = defaults.object(forKey: "media.playsInstagramReels") as? Bool
            values["theme_preset"] = defaults.string(forKey: "appearance.theme")
            if let colors = defaults.stringArray(forKey: "appearance.customColors") {
                let rgb = colors.compactMap { Int($0.hasPrefix("#") ? String($0.dropFirst()) : $0, radix: 16) }
                if rgb.count == 3 { values["custom_colors"] = rgb }
            }
            result(values)
        #if !os(macOS)
        case "openFile":
            openFile(arguments, result: result)
        #endif
        #if os(macOS)
        case "setWindowTheme":
            guard let window = NSApp.windows.first(where: { $0 is MainFlutterWindow }) else { return result(nil) }
            let background = arguments["background"] as? Int
            if let background, !(0...0xffffff).contains(background) { return result(Self.failure("invalid_request")) }
            let color = background.map { NSColor(srgbRed: Double($0 >> 16 & 255) / 255, green: Double($0 >> 8 & 255) / 255, blue: Double($0 & 255) / 255, alpha: 1) }
            window.titlebarAppearsTransparent = color != nil
            window.titleVisibility = color == nil ? .visible : .hidden
            window.backgroundColor = color ?? .windowBackgroundColor
            let appearance = arguments["appearance"] as? String
            window.appearance = appearance == "dark" ? NSAppearance(named: .darkAqua) : appearance == "light" ? NSAppearance(named: .aqua) : nil
            result(nil)
        case "setLaunchAtLogin":
            guard let enabled = arguments["enabled"] as? Bool else { return result(Self.failure("invalid_request")) }
            Task { @MainActor in
                do {
                    if enabled { try SMAppService.mainApp.register() }
                    else { try await SMAppService.mainApp.unregister() }
                    result(["status": launchAtLoginStatus])
                } catch { result(Self.failure("launch_at_login_failed")) }
            }
        case "openLoginItemsSettings":
            SMAppService.openSystemSettingsLoginItems()
            result(nil)
        case "setUnreadBadge":
            let count = max(0, arguments["count"] as? Int ?? 0)
            NSApp.dockTile.badgeLabel = count > 0 ? String(count) : nil
            if statusItem == nil {
                let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                item.button?.image = NSImage(systemSymbolName: "asterisk", accessibilityDescription: "Inbox+")
                let menu = NSMenu()
                let open = menu.addItem(withTitle: "Open Inbox+", action: #selector(showInbox), keyEquivalent: "")
                open.target = self
                menu.addItem(.separator())
                menu.addItem(withTitle: "Quit Inbox+", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
                item.menu = menu
                statusItem = item
            }
            statusItem?.button?.title = count > 0 ? " \(count)" : ""
            statusItem?.button?.setAccessibilityLabel(count > 0 ? "Inbox+, \(count) unread" : "Inbox+")
            result(nil)
        case "imessageRecipientContacts":
            Task { @MainActor in
                switch await SystemContactSource().recipientContacts() {
                case let .available(recipients):
                    result(["status": "available", "recipients": recipients.map {
                        ["name": $0.name, "address": $0.address,
                         "search_text": "\($0.name) \($0.address)".folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)]
                    }])
                case .accessUnavailable: result(["status": "access_unavailable"])
                case .failed: result(["status": "failed"])
                }
            }
        case "imessageSnapshot", "imessageSend", "imessageStartConversation", "imessageMarkRead", "imessageDisconnect":
            handleIMessage(call.method, arguments: arguments, result: result)
        #endif
        default:
            result(FlutterMethodNotImplemented)
        }
    }

    #if os(macOS)
    private var launchAtLoginStatus: String {
        switch SMAppService.mainApp.status {
        case .enabled: "on"
        case .requiresApproval: "needsApproval"
        case .notRegistered: "off"
        case .notFound: "unavailable"
        @unknown default: "unavailable"
        }
    }

    func prepareToHide(_ window: NSWindow) {
        channel.invokeMethod("prepareToClose", arguments: nil) { response in
            if response as? Bool == true { window.orderOut(nil) }
            else {
                let alert = NSAlert()
                alert.messageText = "Your changes could not be saved."
                alert.informativeText = "Keep Inbox+ open and try closing again once your changes have been saved."
                alert.runModal()
            }
        }
    }

    @objc private func showInbox() {
        NSApp.windows.first { $0 is MainFlutterWindow }?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    #endif

    private func notify(_ arguments: [String: Any], result: @escaping FlutterResult) {
        guard let title = arguments["title"] as? String else {
            return result(Self.failure("invalid_request"))
        }
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
                DispatchQueue.main.async { result(false) }
                return
            }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = arguments["body"] as? String ?? ""
            content.sound = arguments["sound"] as? Bool == false ? nil : .default
            if let route = arguments["route"] as? [String: String] { content.userInfo = route }
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            UNUserNotificationCenter.current().add(request) { error in
                DispatchQueue.main.async {
                    result(error == nil ? true : Self.failure("notification_failed"))
                }
            }
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }

    #if os(macOS)
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        guard response.actionIdentifier == UNNotificationDefaultActionIdentifier,
              let account = response.notification.request.content.userInfo["account_id"] as? String,
              let conversation = response.notification.request.content.userInfo["conversation_id"] as? String,
              !account.isEmpty, !conversation.isEmpty else {
            completionHandler()
            return
        }
        Task { @MainActor in
            activateNotification(account: account, conversation: conversation)
            completionHandler()
        }
    }

    private func activateNotification(account: String, conversation: String) {
        guard !account.isEmpty, !conversation.isEmpty else { return }
        pendingNotificationRoute = ["account_id": account, "conversation_id": conversation]
        showInbox()
        channel.invokeMethod("notificationActivated", arguments: nil)
    }
    #endif

    private static var hasIMessage: Bool {
        #if os(macOS)
        true
        #else
        false
        #endif
    }

    #if !os(macOS)
    private func openFile(_ arguments: [String: Any], result: @escaping FlutterResult) {
        guard let path = arguments["path"] as? String,
              let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first,
              let presenter = Self.presenter() else { return result(Self.failure("file_open_failed")) }
        let root = support.resolvingSymlinksInPath().appendingPathComponent("InboxPlus/profiles", isDirectory: true)
        let url = URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL
        guard url.path.hasPrefix(root.path + "/") else { return result(Self.failure("file_open_failed")) }
        let components = Array(url.pathComponents.dropFirst(root.pathComponents.count))
        guard components.count >= 4, components[1] == "flutter", ["media", "staging"].contains(components[2]),
              (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
            return result(Self.failure("file_open_failed"))
        }
        let controller = UIDocumentInteractionController(url: url)
        if let mime = arguments["mime_type"] as? String { controller.uti = UTType(mimeType: mime)?.identifier }
        if let name = arguments["name"] as? String { controller.name = name }
        controller.delegate = self
        documentController = controller
        documentPresenter = presenter
        if controller.presentPreview(animated: true) {
            result(true)
        } else if controller.presentOpenInMenu(from: presenter.view.bounds, in: presenter.view, animated: true) {
            result(true)
        } else {
            documentController = nil
            documentPresenter = nil
            result(Self.failure("file_open_failed"))
        }
    }

    private static func presenter() -> UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive }),
              var presenter = scene.windows.first(where: \.isKeyWindow)?.rootViewController else { return nil }
        while let presented = presenter.presentedViewController { presenter = presented }
        return presenter
    }
    #endif

    private static func failure(_ code: String) -> FlutterError {
        FlutterError(code: code, message: "The device could not complete this operation.", details: nil)
    }

    private static func legacyProfileStatus() -> [String: Any] {
        #if os(macOS)
        let root = legacyRoot()
        let files = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey])) ?? []
        let names = files.filter { url in
            guard validProfileName(url.lastPathComponent),
                  (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return false }
            return ["state", "data", "configuration"].contains { component in
                FileManager.default.fileExists(atPath: url.appendingPathComponent(component).path)
            }
        }.map(\.lastPathComponent).sorted()
        let name = ProcessInfo.processInfo.environment["INBOXPLUS_PROFILE"] ?? "default"
        return [
            "has_legacy_profile": !names.isEmpty,
            "profile_names": names,
            "profile_directory": root.appendingPathComponent(validProfileName(name) ? name : "default").path,
        ]
        #else
        return ["has_legacy_profile": false, "profile_names": []]
        #endif
    }

    #if os(macOS)
    private static func legacyRoot() -> URL {
        if let override = ProcessInfo.processInfo.environment["INBOXPLUS_RUNTIME_ROOT"], !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true).standardizedFileURL
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Inbox+/DeveloperRuntime", isDirectory: true)
    }

    private static func validProfileName(_ value: String) -> Bool {
        value.range(of: "^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$", options: .regularExpression) != nil
    }

    func confirmClose() -> Bool {
        guard hasUnfinishedWork else { return true }
        let alert = NSAlert()
        alert.messageText = "Close Inbox+?"
        alert.informativeText = "Your drafts and queued messages are saved on this device. Sending pauses while Inbox+ is closed."
        alert.addButton(withTitle: "Keep Open")
        alert.addButton(withTitle: "Close")
        return alert.runModal() == .alertSecondButtonReturn
    }

    func prepareToClose(completion: @escaping (Bool) -> Void) {
        if canClose { return completion(true) }
        guard !closePending else { return completion(false) }
        closePending = true
        let windows = NSApp.windows.map { ($0, $0.ignoresMouseEvents, $0.firstResponder) }
        for (window, _, _) in windows {
            window.ignoresMouseEvents = true
            window.makeFirstResponder(nil)
        }
        func restoreInput() {
            for (window, ignoredMouseEvents, responder) in windows {
                window.ignoresMouseEvents = ignoredMouseEvents
                window.makeFirstResponder(responder)
            }
        }
        channel.invokeMethod("prepareToClose", arguments: nil) { [weak self] result in
            guard let self else { return completion(false) }
            self.closePending = false
            guard result as? Bool == true else {
                restoreInput()
                let alert = NSAlert()
                alert.messageText = "Your changes could not be saved."
                alert.informativeText = "Keep Inbox+ open and try closing again once your changes have been saved."
                alert.runModal()
                return completion(false)
            }
            self.canClose = self.confirmClose()
            if !self.canClose { restoreInput() }
            completion(self.canClose)
        }
    }

    private func handleIMessage(_ method: String, arguments: [String: Any], result: @escaping FlutterResult) {
        let profile = arguments["profile_name"] as? String ?? "default"
        guard Self.validProfileName(profile) else { return result(Self.failure("invalid_request")) }
        Task { @MainActor in
            do {
                if method == "imessageDisconnect" {
                    await gateway?.pausePolling()
                    gateway = nil
                    gatewayProfile = nil
                    return result(nil)
                }
                let windows: [String: TimeInterval?] = ["month": 30 * 86400, "quarter": 91 * 86400, "year": 365 * 86400, "all": nil]
                let window = arguments["history_window"] as? String ?? "year"
                guard windows.keys.contains(window) else { return result(Self.failure("invalid_request")) }
                let gateway = try await iMessageGateway(profile: profile, activityWindow: windows[window]!)
                let route = ConversationRoute(
                    accountID: IMessageGateway.accountID,
                    conversationID: arguments["conversation_id"] as? String ?? ""
                )
                switch method {
                case "imessageSnapshot":
                    let snapshot = try await gateway.loadSnapshot()
                    await gateway.pausePolling()
                    var messages = snapshot.messagesByRoute.values.flatMap { $0 }
                    if !route.conversationID.isEmpty {
                        messages = try await gateway.recentMessagesSnapshot(in: route)
                    }
                    result([
                        "accounts": [["id": IMessageGateway.accountID, "platform": "imessage", "display_name": "iMessage", "is_connected": true]],
                        "conversations": snapshot.conversations.map(Self.conversation),
                        "messages": messages.map(Self.message),
                    ])
                case "imessageStartConversation":
                    guard let recipient = arguments["recipient"] as? String else {
                        return result(Self.failure("invalid_request"))
                    }
                    let started = try await gateway.startConversation(accountID: IMessageGateway.accountID, recipient: recipient)
                    result(Self.conversation(started.conversation))
                case "imessageSend":
                    guard !route.conversationID.isEmpty, let body = arguments["body"] as? String, !body.isEmpty else {
                        return result(Self.failure("invalid_request"))
                    }
                    let receipt = try await gateway.sendText(body, to: route)
                    result(["id": receipt.messageID, "timestamp": Int64(Date().timeIntervalSince1970 * 1000), "delivery_state": "pending"])
                case "imessageMarkRead":
                    guard !route.conversationID.isEmpty else { return result(Self.failure("invalid_request")) }
                    try await gateway.markRead(route)
                    if let readMarkersFile { _ = chmod(readMarkersFile.path, 0o600) }
                    result(nil)
                default:
                    result(FlutterMethodNotImplemented)
                }
            } catch is IMessageStoreError {
                result(Self.failure("imessage_access_required"))
            } catch {
                result(Self.failure("imessage_failed"))
            }
        }
    }

    private func iMessageGateway(profile: String, activityWindow: TimeInterval?) async throws -> IMessageGateway {
        if let gateway, gatewayProfile == profile { return gateway }
        await gateway?.pausePolling()
        let directory = Self.legacyRoot().appendingPathComponent(profile, isDirectory: true)
        var ancestor = URL(fileURLWithPath: "/", isDirectory: true)
        for component in directory.pathComponents.dropFirst() {
            ancestor.appendPathComponent(component, isDirectory: true)
            var metadata = stat()
            if lstat(ancestor.path, &metadata) == 0 {
                guard metadata.st_mode & S_IFMT == S_IFDIR else { throw CocoaError(.fileReadNoPermission) }
            } else if errno != ENOENT {
                throw CocoaError(.fileReadNoPermission)
            }
        }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        guard chmod(directory.path, 0o700) == 0 else { throw CocoaError(.fileWriteNoPermission) }
        let markers = directory.appendingPathComponent("imessage-read-markers.json")
        var metadata = stat()
        if lstat(markers.path, &metadata) == 0 {
            guard metadata.st_mode & S_IFMT == S_IFREG, metadata.st_uid == getuid(), chmod(markers.path, 0o600) == 0 else {
                throw CocoaError(.fileReadNoPermission)
            }
        } else if errno != ENOENT {
            throw CocoaError(.fileReadNoPermission)
        }
        let gateway = try IMessageGateway(store: IMessageStore(), contacts: SystemContactSource(), activityWindow: activityWindow, readMarkerStore: IMessageReadMarkerStore(fileURL: markers))
        self.gateway = gateway
        gatewayProfile = profile
        readMarkersFile = markers
        return gateway
    }

    private static func conversation(_ conversation: RemoteConversation) -> [String: Any] {
        [
            "account_id": conversation.accountID, "id": conversation.id, "title": conversation.title,
            "identity_id": conversation.identityID, "timestamp": Int64(conversation.latestActivity.timeIntervalSince1970 * 1000),
            "unread_count": conversation.unreadCount, "is_group": conversation.isGroup,
            "is_from_unknown_sender": conversation.isFromUnknownSender,
        ]
    }

    private static func message(_ message: Message) -> [String: Any] {
        var values: [String: Any] = [
            "account_id": message.route.accountID, "conversation_id": message.route.conversationID,
            "id": message.id, "body": message.body, "timestamp": Int64(message.timestamp.timeIntervalSince1970 * 1000),
            "outgoing": message.isOutgoing, "kind": message.kind.rawValue,
            "reactions": message.reactions.map { ["key": $0.key, "count": $0.count, "includes_me": $0.includesMe] as [String: Any] },
        ]
        if let name = message.senderDisplayName { values["sender_name"] = name }
        values["attachments"] = message.attachments.map { attachment -> [String: Any] in
            var values: [String: Any] = ["id": attachment.id, "kind": attachment.kind.rawValue]
            if let name = attachment.filename { values["name"] = name }
            if let mime = attachment.mimeType { values["mime_type"] = mime }
            if let size = attachment.byteCount { values["size"] = size }
            if let source = attachment.source?.source, let url = URL(string: source), url.isFileURL {
                values["local_path"] = url.path
            }
            return values
        }
        return values
    }
    #endif
}

#if !os(macOS)
extension InboxPlusAppleServices: UIDocumentInteractionControllerDelegate {
    func documentInteractionControllerViewControllerForPreview(_ controller: UIDocumentInteractionController) -> UIViewController {
        documentPresenter!
    }

    nonisolated func documentInteractionControllerDidEndPreview(_ controller: UIDocumentInteractionController) {
        Task { @MainActor in
            if documentController === controller {
                documentController = nil
                documentPresenter = nil
            }
        }
    }
}
#endif
