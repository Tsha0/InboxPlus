public enum Platform: String, CaseIterable, Codable, Hashable, Sendable {
    case whatsApp, instagram, facebookMessenger, telegram, signal, discord
    case slack, x, linkedIn, googleMessages, googleChat, googleVoice
    case iMessage, matrix, irc, bluesky

    public var accessibilityLabel: String {
        switch self {
        case .whatsApp: "WhatsApp"
        case .instagram: "Instagram"
        case .facebookMessenger: "Facebook Messenger"
        case .telegram: "Telegram"
        case .signal: "Signal"
        case .discord: "Discord"
        case .slack: "Slack"
        case .x: "X"
        case .linkedIn: "LinkedIn"
        case .googleMessages: "Google Messages"
        case .googleChat: "Google Chat"
        case .googleVoice: "Google Voice"
        case .iMessage: "iMessage"
        case .matrix: "Matrix"
        case .irc: "IRC"
        case .bluesky: "Bluesky"
        }
    }

    public var symbolName: String {
        switch self {
        case .iMessage, .googleMessages: "message.fill"
        case .instagram: "camera.fill"
        case .telegram: "paperplane.fill"
        case .discord, .slack, .googleChat, .irc: "bubble.left.and.bubble.right.fill"
        case .googleVoice: "phone.fill"
        case .linkedIn: "person.crop.square.fill"
        case .bluesky: "cloud.fill"
        default: "message.circle.fill"
        }
    }
}
