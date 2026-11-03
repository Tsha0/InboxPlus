import Foundation
import InboxPlusCore
import UniformTypeIdentifiers

/// Attachment presentation, kept out of the views so it can be tested without a main actor.
enum AttachmentFormatting {
    // Late media dimensions must not resize a row after the transcript has scrolled to its focus.
    static func inlineMediaSize(for attachment: MessageAttachment) -> CGSize {
        guard let ratio = attachment.pixelSize?.aspectRatio else {
            return CGSize(width: 320, height: attachment.kind == .video ? 200 : 320)
        }
        return ratio >= 1
            ? CGSize(width: 320, height: 320 / ratio)
            : CGSize(width: 320 * ratio, height: 320)
    }

    /// What **Save Attachment…** proposes. A photo the bridge sent without a filename still gets
    /// an extension, or Finder would not know how to open it.
    static func suggestedFilename(for attachment: MessageAttachment) -> String {
        if let filename = attachment.filename { return filename }
        let ext = attachment.mimeType.flatMap { UTType(mimeType: $0)?.preferredFilenameExtension }
        return ext.map { "\(attachment.displayName).\($0)" } ?? attachment.displayName
    }

    static func byteLabel(_ byteCount: Int?) -> String? {
        guard let byteCount, byteCount > 0 else { return nil }
        return ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
    }

    /// `m:ss`, or `h:mm:ss` once there is an hour to show.
    static func durationLabel(_ duration: Duration?) -> String? {
        guard let duration else { return nil }
        let totalSeconds = Int(duration.components.seconds)
        guard totalSeconds > 0 else { return nil }
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// Whether a message's text is shown under its attachments. A caption is the text, so it reads
    /// under the media. Without one the text is only the card's title, kept for previews, and
    /// printing it again under the card would say it twice.
    static func showsBody(of message: Message) -> Bool {
        guard !message.attachments.isEmpty else { return true }
        let body = message.body.trimmingCharacters(in: .whitespacesAndNewlines)
        return !body.isEmpty && !message.attachments.contains { $0.title == body }
    }

    /// What VoiceOver reads for an attachment: what it is, then whatever is actually known about
    /// it. Nothing is invented — an unknown size simply goes unmentioned. The caption is not part
    /// of it: it is the message's text, read on its own under the media.
    static func accessibilityLabel(for attachment: MessageAttachment) -> String {
        var parts = [noun(for: attachment.kind)]
        // Only a file's title says more than its noun: it is the file's name.
        if attachment.title != parts[0] { parts.append(attachment.title) }
        if let duration = durationLabel(attachment.duration) { parts.append(duration) }
        if let bytes = byteLabel(attachment.byteCount) { parts.append(bytes) }
        if let link = attachment.deepLink {
            parts.append("opens in \(link.platform.accessibilityLabel)")
        }
        return parts.joined(separator: ", ")
    }

    static func symbol(for kind: MessageKind) -> String {
        switch kind {
        case .image, .gallery, .sticker: "photo"
        case .audio: "waveform"
        case .video: "film"
        case .location: "mappin.and.ellipse"
        default: "doc"
        }
    }

    static func noun(for kind: MessageKind) -> String {
        switch kind {
        case .image: "Photo"
        case .gallery: "Photo gallery"
        case .sticker: "Sticker"
        case .audio: "Audio message"
        case .video: "Video"
        case .file: "File"
        case .location: "Location"
        case .appNative: "Shared post"
        case .poll: "Poll"
        case .redacted: "Deleted message"
        case .encrypted: "Undecryptable message"
        default: "Attachment"
        }
    }
}
