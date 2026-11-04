import AVKit
import AppKit
import SwiftUI
import InboxPlusCore
import InboxPlusFeatures

extension EnvironmentValues {
    @Entry var playsInstagramReels = false
}

/// Renders one attachment, choosing its presentation from the kind the bridge reported.
///
/// Every branch produces something visible. The design forbids silently dropping a message, so an
/// attachment Inbox+ cannot draw becomes a card that says what the bridge actually said about it.
public struct AttachmentView: View {
    @Bindable var model: InboxPlusAppModel
    let attachment: MessageAttachment
    let accountID: String
    let messageID: String
    @State private var showsImagePreview = false
    @Environment(\.playsInstagramReels) private var playsInstagramReels
    @Environment(\.openURL) private var openURL

    public init(model: InboxPlusAppModel, attachment: MessageAttachment, accountID: String, messageID: String) {
        self.model = model
        self.attachment = attachment
        self.accountID = accountID
        self.messageID = messageID
    }

    private var mediaAttachment: MessageAttachment {
        AttachmentFormatting.mediaAttachment(for: attachment, playsInstagramReels: playsInstagramReels)
    }

    private var state: MediaController.State {
        model.media.state(for: mediaAttachment)
    }

    public var body: some View {
        Group {
            if attachment.isInstagramReel {
                reelContent
            } else {
                content
            }
        }
        .frame(maxWidth: 320, alignment: .leading)
        .task(id: mediaAttachment) {
            model.media.load(mediaAttachment, accountID: accountID, messageID: messageID)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityIdentifier("attachment-\(attachment.id)")
    }

    @ViewBuilder private var content: some View {
        switch attachment.kind {
        case .image, .sticker, .gallery:
            imageContent
                .frame(width: imageSize.width, height: imageSize.height)
        case .audio, .video:
            playableContent
        case .appNative:
            AppNativeCard(attachment: attachment)
        case .file:
            fileContent
        default:
            UnsupportedAttachmentCard(attachment: attachment)
        }
    }

    private var imageSize: CGSize {
        AttachmentFormatting.inlineMediaSize(for: attachment)
    }

    @ViewBuilder private var reelContent: some View {
        if playsInstagramReels, attachment.kind == .video, attachment.source != nil {
            playableContent
                .overlay(alignment: .topLeading) {
                    ReelBadge().padding(8)
                }
                .overlay(alignment: .topTrailing) {
                    if let link = attachment.deepLink {
                        Button {
                            openURL(link.url)
                        } label: {
                            Image(systemName: "arrow.up.right")
                                .font(.caption.weight(.semibold))
                                .padding(8)
                                .background(.regularMaterial, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .padding(8)
                        .accessibilityLabel("Open Reel in Instagram")
                        .accessibilityIdentifier("open-reel-in-instagram")
                        .help("Open Reel in Instagram")
                    }
                }
                .accessibilityIdentifier("reel-player-\(attachment.id)")
        } else if let link = attachment.deepLink {
            VStack(alignment: .leading, spacing: 6) {
                ReelThumbnail(image: previewImage, pixelSize: attachment.pixelSize,
                              isLoading: mediaAttachment.source != nil && (state == .idle || state == .loading)) {
                    openURL(link.url)
                }
                if mediaAttachment.source != nil {
                    switch state {
                    case let .failed(reason):
                        Text(reason).font(.caption).foregroundStyle(.secondary)
                        Button("Try again") {
                            model.media.retry(mediaAttachment, accountID: accountID, messageID: messageID)
                        }
                        .controlSize(.small)
                    case let .paused(reason):
                        Text(reason).font(.caption).foregroundStyle(.secondary)
                    default:
                        EmptyView()
                    }
                }
            }
            .accessibilityIdentifier("reel-thumbnail-\(attachment.id)")
        }
    }

    private var previewImage: NSImage? {
        guard case let .ready(url) = state else { return nil }
        return NSImage(contentsOf: url)
    }

    // MARK: - Images

    @ViewBuilder private var imageContent: some View {
        switch state {
        case let .ready(url):
            if let image = NSImage(contentsOf: url) {
                Button {
                    showsImagePreview = true
                } label: {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .clipShape(.rect(cornerRadius: 10))
                        .frame(width: imageSize.width, height: imageSize.height, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open \(attachment.title)")
                .help("Open image")
                .sheet(isPresented: $showsImagePreview) {
                    ImagePreview(image: image, url: url, filename: attachment.filename ?? url.lastPathComponent)
                }
            } else {
                // The bytes arrived but are not an image this Mac can decode. Say so rather than
                // showing an empty frame.
                UnsupportedAttachmentCard(
                    attachment: attachment,
                    reason: "This image could not be displayed."
                )
            }
        case .idle, .loading:
            MediaPlaceholder(attachment: attachment)
        case let .failed(reason):
            MediaRetryCard(attachment: attachment, reason: reason) {
                model.media.retry(mediaAttachment, accountID: accountID, messageID: messageID)
            }
        case let .paused(reason):
            MediaPausedCard(attachment: attachment, reason: reason)
        }
    }

    // MARK: - Audio and video

    @ViewBuilder private var playableContent: some View {
        switch state {
        case let .ready(url):
            if attachment.kind == .video {
                VideoAttachmentView(url: url, pixelSize: attachment.pixelSize, allowsEnlargement: !attachment.isInstagramReel)
                    .id(url)
            } else {
                VideoPlayer(player: AVPlayer(url: url))
                    .frame(width: 320, height: 60)
                    .clipShape(.rect(cornerRadius: 10))
                    .accessibilityLabel("\(attachment.title), \(durationLabel ?? "playable")")
            }
        case .idle, .loading:
            MediaPlaceholder(attachment: attachment, durationLabel: durationLabel)
        case let .failed(reason):
            MediaRetryCard(attachment: attachment, reason: reason) {
                model.media.retry(mediaAttachment, accountID: accountID, messageID: messageID)
            }
        case let .paused(reason):
            MediaPausedCard(attachment: attachment, reason: reason)
        }
    }

    // MARK: - Files

    @ViewBuilder private var fileContent: some View {
        switch state {
        case let .ready(url):
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            } label: {
                AttachmentCardLabel(
                    symbol: "doc.fill",
                    title: attachment.title,
                    detail: [attachment.mimeType, byteLabel].compactMap { $0 }.joined(separator: " · ")
                )
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Show \(attachment.title) in Finder")
        case .idle, .loading:
            MediaPlaceholder(attachment: attachment)
        case let .failed(reason):
            MediaRetryCard(attachment: attachment, reason: reason) {
                model.media.retry(mediaAttachment, accountID: accountID, messageID: messageID)
            }
        case let .paused(reason):
            MediaPausedCard(attachment: attachment, reason: reason)
        }
    }

    // MARK: - Labels

    private var byteLabel: String? {
        AttachmentFormatting.byteLabel(attachment.byteCount)
    }

    private var durationLabel: String? {
        AttachmentFormatting.durationLabel(attachment.duration)
    }

    private var accessibilityLabel: String {
        if attachment.isInstagramReel, playsInstagramReels, attachment.kind == .video {
            return "Reel, video playback in Inbox+"
        }
        return AttachmentFormatting.accessibilityLabel(for: attachment)
    }
}

// MARK: - Cards

/// Reserves the right amount of space while bytes are on their way, so a transcript does not jump
/// as images arrive.
struct MediaPlaceholder: View {
    let attachment: MessageAttachment
    var durationLabel: String?

    private var size: CGSize {
        switch attachment.kind {
        case .image, .sticker, .gallery, .video:
            AttachmentFormatting.inlineMediaSize(for: attachment)
        case .audio:
            CGSize(width: 320, height: 60)
        default:
            CGSize(width: 320, height: 120)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            placeholder
            if attachment.kind == .video, !attachment.isInstagramReel {
                Button("Open video", systemImage: "arrow.up.left.and.arrow.down.right") {}
                    .controlSize(.small)
                    .hidden()
                    .accessibilityHidden(true)
            }
        }
        .accessibilityLabel("Loading \(attachment.title)")
    }

    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10).fill(.quaternary)
            VStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text([attachment.title, durationLabel].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 12)
            }
        }
        .frame(width: size.width, height: size.height)
    }
}

struct MediaRetryCard: View {
    let attachment: MessageAttachment
    let reason: String
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            AttachmentCardLabel(
                symbol: "exclamationmark.triangle.fill",
                title: attachment.title,
                detail: reason
            )
            Button("Try again", action: retry)
                .controlSize(.small)
        }
        .padding(10)
        .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 10))
        .accessibilityIdentifier("attachment-retry-\(attachment.id)")
    }
}

struct MediaPausedCard: View {
    let attachment: MessageAttachment
    let reason: String

    var body: some View {
        AttachmentCardLabel(symbol: "internaldrive.fill", title: attachment.title, detail: reason)
            .padding(10)
            .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 10))
            .accessibilityIdentifier("attachment-paused-\(attachment.id)")
    }
}

/// Content only the originating app can display.
///
/// The button opens a link that has already been verified as belonging to the platform that claims
/// it, so this never hands an arbitrary URL from a bridge to the system.
struct AppNativeCard: View {
    let attachment: MessageAttachment
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AttachmentCardLabel(
                symbol: attachment.deepLink?.platform.symbolName ?? "square.and.arrow.up",
                title: attachment.title,
                detail: attachment.reportedDescription
            )
            if let link = attachment.deepLink {
                Button("Open in \(link.platform.accessibilityLabel)") {
                    openURL(link.url)
                }
                .controlSize(.small)
                .accessibilityIdentifier("open-in-app-\(attachment.id)")
            }
        }
        .padding(10)
        .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 10))
    }
}

/// The visible fallback the design requires: never a dropped message, always an explanation.
struct UnsupportedAttachmentCard: View {
    let attachment: MessageAttachment
    var reason: String?

    var body: some View {
        AttachmentCardLabel(
            symbol: "questionmark.square.dashed",
            title: attachment.title,
            detail: reason ?? attachment.reportedDescription
                ?? "Inbox+ cannot display this yet, so it is shown as reported."
        )
        .padding(10)
        .background(.quaternary.opacity(0.6), in: .rect(cornerRadius: 10))
    }
}

struct AttachmentCardLabel: View {
    let symbol: String
    let title: String
    var detail: String?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                // A title is a noun or a filename; the middle goes first so the extension stays.
                Text(title)
                    .font(.callout)
                    .lineLimit(2)
                    .truncationMode(.middle)
                if let detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

struct ReelThumbnail: View {
    let image: NSImage?
    let pixelSize: PixelSize?
    var isLoading = false
    let open: () -> Void

    private var size: CGSize {
        let dimensions = image?.size ?? pixelSize.map { CGSize(width: $0.width, height: $0.height) }
        return VideoAttachmentPlayback.fittedSize(dimensions, within: CGSize(width: 320, height: 320))
    }

    var body: some View {
        Button(action: open) {
            ZStack {
                if let image {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                } else {
                    Rectangle().fill(.quaternary)
                    if isLoading {
                        ProgressView("Loading preview…").controlSize(.small)
                    } else {
                        Label("Reel preview unavailable", systemImage: "photo")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(width: size.width, height: size.height)
            .overlay(alignment: .topLeading) {
                ReelBadge().padding(8)
            }
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "arrow.up.right")
                    .font(.caption.weight(.semibold))
                    .padding(8)
                    .background(.regularMaterial, in: Circle())
                    .padding(8)
            }
            .clipShape(.rect(cornerRadius: 10))
            .contentShape(.rect(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Reel, open in Instagram")
        .help("Open Reel in Instagram")
    }
}

private struct ReelBadge: View {
    var body: some View {
        Label("Reel", systemImage: "film")
            .font(.caption.weight(.semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(.regularMaterial, in: Capsule())
    }
}
