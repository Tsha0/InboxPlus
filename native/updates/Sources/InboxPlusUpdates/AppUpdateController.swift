import AppKit
import Sparkle

@MainActor
public final class AppUpdateController {
    private var controller: SPUStandardUpdaterController?
    public var isEnabled: Bool { controller != nil }

    public init() {}

    public func start(bundle: Bundle = .main) {
        guard controller == nil,
              AppUpdateConfiguration.isEnabled(bundleURL: bundle.bundleURL, info: bundle.infoDictionary ?? [:]) else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        do {
            try controller.updater.start()
            self.controller = controller
        } catch {
            return
        }
    }

    public func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }
}

public enum AppUpdateConfiguration {
    public static func isEnabled(bundleURL: URL, info: [String: Any]) -> Bool {
        guard bundleURL.pathExtension == "app",
              info["InboxPlusUpdatesEnabled"] as? Bool == true,
              let feed = info["SUFeedURL"] as? String,
              let url = URL(string: feed), url.scheme == "https", url.host != nil,
              url.user == nil, url.password == nil,
              let key = info["SUPublicEDKey"] as? String,
              Data(base64Encoded: key)?.count == 32,
              let build = info["CFBundleVersion"] as? String,
              build.allSatisfy({ $0.isASCII && $0.isNumber }),
              let number = UInt64(build), number > 0 else { return false }
        return true
    }
}
