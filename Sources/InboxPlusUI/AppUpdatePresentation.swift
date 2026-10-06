import Foundation

/// Display-only state. The UI never imports Sparkle or owns an installer.
public struct AppUpdatePresentation: Equatable, Sendable {
    public let version: String
    public let isReadyToInstall: Bool

    public init(version: String, isReadyToInstall: Bool = false) {
        self.version = version
        self.isReadyToInstall = isReadyToInstall
    }

    public var help: String {
        isReadyToInstall ? "Restart to update to Inbox+ \(version)" : "Update to Inbox+ \(version)"
    }
}
