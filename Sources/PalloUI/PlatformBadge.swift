import SwiftUI
import PalloCore

public struct PlatformBadgeDescriptor: Sendable {
    public let symbolName: String
    public let accessibilityLabel: String

    public init(platform: Platform) {
        symbolName = platform.symbolName
        accessibilityLabel = platform.accessibilityLabel
    }
}

public struct ContactConversationCardDescriptor: Sendable {
    public let route: ConversationRoute
    public let platform: Platform
    public let title: String
    public let preview: String

    public var accessibilityLabel: String {
        "\(platform.accessibilityLabel), \(title), \(preview)"
    }

    public init(route: ConversationRoute, platform: Platform, title: String, preview: String) {
        self.route = route
        self.platform = platform
        self.title = title
        self.preview = preview
    }
}

public struct PlatformBadge: View {
    let platform: Platform

    public init(platform: Platform) {
        self.platform = platform
    }

    public var body: some View {
        let descriptor = PlatformBadgeDescriptor(platform: platform)
        Image(systemName: descriptor.symbolName)
            .frame(width: 18, height: 18)
            .accessibilityLabel(descriptor.accessibilityLabel)
            .help(descriptor.accessibilityLabel)
    }
}
