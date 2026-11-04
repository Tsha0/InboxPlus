import AppKit
import AVKit
import InboxPlusCore
import Observation
import SwiftUI

struct VideoAttachmentView: View {
    @State private var playback: VideoAttachmentPlayback

    init(url: URL, pixelSize: PixelSize?) {
        _playback = State(initialValue: VideoAttachmentPlayback(url: url, pixelSize: pixelSize))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            InlineVideoPlayer(playback: playback)
                .frame(width: playback.inlineSize.width, height: playback.inlineSize.height)
                .frame(width: playback.inlineBounds.width, height: playback.inlineBounds.height)
                .clipShape(.rect(cornerRadius: 10))
                .accessibilityLabel("Video")
            Button("Open video", systemImage: "arrow.up.left.and.arrow.down.right") {
                playback.openPreview()
            }
            .controlSize(.small)
            .help("Open a larger player. You can also double-click the video.")
        }
        .task { await playback.loadPresentationSize() }
        .onDisappear { playback.close() }
    }
}

@MainActor
@Observable
final class VideoAttachmentPlayback: NSObject, NSWindowDelegate {
    let player: AVPlayer
    let inlineBounds: CGSize
    private(set) var presentationSize: CGSize?
    private(set) var showsPreview = false
    @ObservationIgnored private(set) var previewWindow: NSWindow?

    init(url: URL, pixelSize: PixelSize?) {
        player = AVPlayer(url: url)
        let size = pixelSize.flatMap { size in
            size.aspectRatio.map { _ in CGSize(width: size.width, height: size.height) }
        }
        presentationSize = size
        inlineBounds = Self.fittedSize(size, within: CGSize(width: 320, height: 320))
        super.init()
    }

    var inlineSize: CGSize {
        Self.fittedSize(presentationSize, within: inlineBounds)
    }

    func loadPresentationSize() async {
        // Track dimensions refine layout; AVPlayer itself presents any playback failure.
        guard let asset = player.currentItem?.asset,
              let tracks = try? await asset.loadTracks(withMediaType: .video),
              let track = tracks.first,
              let (size, transform) = try? await track.load(.naturalSize, .preferredTransform),
              !Task.isCancelled else { return }
        presentationSize = Self.orientedSize(size, transform: transform)
    }

    func openPreview() {
        player.pause()
        if let previewWindow {
            previewWindow.makeKeyAndOrderFront(nil)
            return
        }

        let available = NSScreen.main?.visibleFrame.size ?? CGSize(width: 1024, height: 768)
        let size = Self.fittedSize(
            presentationSize,
            within: CGSize(width: min(960, available.width - 80), height: min(720, available.height - 80))
        )
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Video"
        window.minSize = CGSize(width: 320, height: 240)
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.isReleasedWhenClosed = false
        window.delegate = self
        let view = AVPlayerView()
        view.player = player
        view.videoGravity = .resizeAspect
        view.controlsStyle = .floating
        view.showsFullScreenToggleButton = true
        view.setAccessibilityLabel("Video preview")
        window.contentView = view
        previewWindow = window
        showsPreview = true
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        player.pause()
        (previewWindow?.contentView as? AVPlayerView)?.player = nil
        previewWindow = nil
        showsPreview = false
    }

    func close() {
        player.pause()
        previewWindow?.close()
    }

    static func orientedSize(_ size: CGSize, transform: CGAffineTransform) -> CGSize? {
        let transformed = size.applying(transform)
        let result = CGSize(width: abs(transformed.width), height: abs(transformed.height))
        guard result.width.isFinite, result.height.isFinite, result.width > 0, result.height > 0 else { return nil }
        return result
    }

    static func fittedSize(_ size: CGSize?, within bounds: CGSize) -> CGSize {
        let size = size ?? CGSize(width: 320, height: 200)
        let scale = min(bounds.width / size.width, bounds.height / size.height)
        return CGSize(width: size.width * scale, height: size.height * scale)
    }
}

private struct InlineVideoPlayer: NSViewRepresentable {
    let playback: VideoAttachmentPlayback

    func makeNSView(context: Context) -> InlineVideoPlayerView {
        let view = InlineVideoPlayerView()
        view.onOpenPreview = { playback.openPreview() }
        return view
    }

    func updateNSView(_ view: InlineVideoPlayerView, context: Context) {
        view.player = playback.showsPreview ? nil : playback.player
    }

    static func dismantleNSView(_ view: InlineVideoPlayerView, coordinator: ()) {
        view.player?.pause()
        view.player = nil
    }
}

final class InlineVideoPlayerView: AVPlayerView {
    var onOpenPreview: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        videoGravity = .resizeAspect
        controlsStyle = .inline
        let doubleClick = NSClickGestureRecognizer(target: self, action: #selector(openPreview))
        doubleClick.numberOfClicksRequired = 2
        // Hold the first click so a double-click cannot also toggle playback in AVKit.
        doubleClick.delaysPrimaryMouseButtonEvents = true
        addGestureRecognizer(doubleClick)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    @objc func openPreview() {
        player?.pause()
        onOpenPreview?()
    }
}
