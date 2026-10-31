import Foundation

/// Turns a bridge's Markdown into rich text for the transcript and plain text for everywhere else.
///
/// Only inline syntax is read, and whitespace is kept, so a message keeps its own line breaks and a
/// line that starts with `-` or `>` stays as typed.
public enum MessageFormatting {
    public static func attributed(markdown: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        guard let parsed = try? AttributedString(markdown: markdown, options: options) else {
            return AttributedString(markdown)
        }
        var result = AttributedString()
        for run in parsed.runs {
            var piece = AttributedString(parsed[run.range])
            if let link = run.link {
                let destination = webURL(link)
                if destination != nil,
                   let label = URL(string: String(piece.characters), encodingInvalidCharacters: false),
                   let shown = webURL(label) {
                    piece = AttributedString(shown.absoluteString, attributes: run.attributes)
                }
                piece.link = destination
            }
            result += piece
        }
        return result
    }

    /// What previews, notifications and VoiceOver show: a link reads as its label.
    public static func plainText(markdown: String) -> String {
        String(attributed(markdown: markdown).characters)
    }

    /// A link fit to open: web only, with share redirects unwrapped and tracking parameters dropped.
    public static func webURL(_ url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(), scheme == "https" || scheme == "http",
              let host = components.host?.lowercased(), !host.isEmpty,
              components.user == nil, components.password == nil else { return nil }

        if redirectHosts.contains(host),
           let target = components.queryItems?.first(where: { $0.name == "u" })?.value,
           let targetURL = URL(string: target), let unwrapped = webURL(targetURL) {
            return unwrapped
        }

        // Percent-encoded items are filtered so the parameters that remain keep their exact bytes.
        if let items = components.percentEncodedQueryItems {
            let kept = items.filter { !isTrackingParameter($0.name) }
            if kept.count != items.count {
                components.percentEncodedQueryItems = kept.isEmpty ? nil : kept
            }
        }
        return components.url ?? url
    }

    private static let redirectHosts: Set<String> = ["l.instagram.com", "l.facebook.com", "lm.facebook.com"]

    private static let trackingParameters: Set<String> = ["fbclid", "gclid", "igsh", "igshid", "mibextid"]

    private static func isTrackingParameter(_ name: String) -> Bool {
        let name = name.lowercased()
        return name.hasPrefix("utm_") || trackingParameters.contains(name)
    }
}
