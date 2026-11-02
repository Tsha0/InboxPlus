import Foundation
import InboxPlusBridge
import InboxPlusCore

public enum BridgeLoginPreparation: Sendable {
    case ready(any BridgeLoginSession)
    case waitingForExternalRuntime(BridgeInstallOutcome)
}

public struct BridgeInstallOutcome: Sendable, Equatable {
    public let platform: Platform
    public let profile: String

    public init(platform: Platform, profile: String) {
        self.platform = platform
        self.profile = profile
    }

    public var title: String { "\(platform.accessibilityLabel) needs its runtime restarted" }

    public var message: String {
        """
        The \(platform.accessibilityLabel) connection is installed. Restart the runtime for profile \
        '\(profile)' in the terminal that started it, then choose \(platform.accessibilityLabel) again \
        to sign in. You can leave Inbox+ open.
        """
    }
}
