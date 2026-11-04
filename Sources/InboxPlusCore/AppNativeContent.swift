import Foundation

/// Recognises shared-content links when the bridge has supplied no media.
public enum AppNativeContentDetector {
    /// Path prefixes that identify app-only content, per platform. A profile or a normal post link
    /// is deliberately absent: those are ordinary links and dressing them up as cards would be
    /// noise.
    private static func appOnlyPathPrefixes(for platform: Platform) -> [String] {
        switch platform {
        case .instagram: ["/reel/", "/reels/", "/stories/", "/tv/"]
        case .facebookMessenger: ["/reel/", "/stories/", "/watch/"]
        default: []
        }
    }

    /// Builds an app-native attachment for a message body, or nil when the body is ordinary text.
    ///
    /// Only fires when the body is essentially just the link. A sentence that happens to mention a
    /// Reel is a message about a Reel, not a Reel.
    public static func attachment(forBody body: String, id: String) -> MessageAttachment? {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let url = URL(string: trimmed), url.host != nil else { return nil }
        guard let link = DeepLinkVerifier.verifyAgainstAnyPlatform(url) else { return nil }

        let path = url.path.lowercased()
        let prefixes = appOnlyPathPrefixes(for: link.platform)
        guard prefixes.contains(where: { path.hasPrefix($0) }) else { return nil }

        return MessageAttachment(
            id: id,
            kind: .appNative,
            mimeType: nil,
            deepLink: link,
            reportedDescription: description(for: link)
        )
    }

    /// What the card says when there is no preview. It reports the platform and the link, because
    /// claiming to know more than the bridge told us would be an invention.
    public static func description(for link: VerifiedDeepLink) -> String {
        "Shared from \(link.platform.accessibilityLabel). Inbox+ cannot display this content, "
            + "so it opens in \(link.platform.accessibilityLabel)."
    }
}
