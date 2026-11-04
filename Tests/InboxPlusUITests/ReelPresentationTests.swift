import AppKit
import AVKit
import SwiftUI
import Testing
import InboxPlusCore
import InboxPlusFeatures
import InboxPlusGateway
@testable import InboxPlusUI

private actor ReelFixtureFetcher: RemoteMediaFetching {
    let preview: Data
    let video: Data
    private(set) var fetched: [String] = []

    init(preview: Data, video: Data) {
        self.preview = preview
        self.video = video
    }

    func fetch(_ handle: MediaHandle) async throws -> Data {
        fetched.append(handle.source)
        return handle.mimeType == "video/mp4" ? video : preview
    }
}

private struct ReelFixtureSpace: FreeSpaceReporting {
    func freeBytes() -> Int? { 100 * 1024 * 1024 * 1024 }
}

private struct ReelDemo: View {
    @Bindable var preferences: AppPreferences
    let model: InboxPlusAppModel
    let attachment: MessageAttachment

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form { ReelPlaybackSection(preferences: preferences) }
                .formStyle(.grouped)
                .frame(height: 160)
            Divider()
            VStack(alignment: .leading, spacing: 12) {
                Text("Sample conversation").font(.headline)
                Text("Today · 9:41 AM").font(.caption).foregroundStyle(.secondary)
                AttachmentView(model: model, attachment: attachment, accountID: "instagram", messageID: "fixture")
                Text("Sanitized demo · generated media").font(.caption2).foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(.background)
        .environment(\.playsInstagramReels, preferences.playsInstagramReels)
    }
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func togglingReelsLoadsOnlyTheChosenMediaAndStopsPlayback() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let movie = directory.appendingPathComponent("fixture.mp4")
    let preview = try await makeReelMovie(at: movie)
    let fetcher = ReelFixtureFetcher(preview: preview, video: try Data(contentsOf: movie))
    let media = MediaController(loader: MediaLoader(
        cache: try MediaCache(directory: directory.appendingPathComponent("cache")),
        fetcher: fetcher, freeSpace: ReelFixtureSpace()
    ))
    let model = InboxPlusAppModel(gateway: InMemoryMessagingGateway(seed: .init(
        accounts: [], identities: [], conversations: [], messagesByRoute: [:]
    )), media: media)
    let suite = "InboxPlusTests.Reels.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let preferences = AppPreferences(defaults: defaults)
    let reel = MessageAttachment(
        id: "reel", kind: .video, mimeType: "video/mp4", pixelSize: .init(width: 240, height: 360),
        source: MediaHandle(source: "mxc://fixture/video", mimeType: "video/mp4"),
        thumbnail: MediaHandle(source: "mxc://fixture/preview", mimeType: "image/png"),
        deepLink: try DeepLinkVerifier.verify("https://instagram.com/reel/fixture/", for: .instagram)
    )
    var opened: URL?
    let host = NSHostingView(rootView: ReelDemo(preferences: preferences, model: model, attachment: reel)
        .environment(\.openURL, OpenURLAction { url in opened = url; return .handled }))
    host.frame = NSRect(x: 0, y: 0, width: 520, height: 720)
    let window = NSWindow(contentRect: host.frame, styleMask: [.titled, .closable], backing: .buffered, defer: false)
    window.title = "Inbox+ · Reel playback demo"
    window.isReleasedWhenClosed = false
    window.contentView = host
    window.center()
    window.orderFront(nil)
    defer { window.close() }

    let thumbnail = AttachmentFormatting.mediaAttachment(for: reel, playsInstagramReels: false)
    try await waitForReel(host) { if case .ready = media.state(for: thumbnail) { true } else { false } }
    #expect(await fetcher.fetched == ["mxc://fixture/preview"])
    #expect(reelPlayers(in: host).isEmpty)
    try await captureReel(host, name: "reels-off")

    for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
        let click = try #require(NSEvent.mouseEvent(
            with: type, location: NSPoint(x: 100, y: 380), modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, eventNumber: 1, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0
        ))
        window.sendEvent(click)
    }
    #expect(opened == reel.deepLink?.url)

    preferences.playsInstagramReels = true
    try await waitForReel(host) { !reelPlayers(in: host).isEmpty }
    let playerView = try #require(reelPlayers(in: host).first)
    let player = try #require(playerView.player)
    try await waitForReel(host) { player.currentItem?.status == .readyToPlay }
    #expect(player.rate == 0)
    #expect(await fetcher.fetched == ["mxc://fixture/preview", "mxc://fixture/video"])
    opened = nil
    let corner = playerView.convert(NSPoint(
        x: playerView.bounds.maxX - 21,
        y: playerView.isFlipped ? 21 : playerView.bounds.maxY - 21
    ), to: nil)
    for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
        let click = try #require(NSEvent.mouseEvent(
            with: type, location: corner, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
            context: nil, eventNumber: 2, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0
        ))
        window.sendEvent(click)
    }
    #expect(opened == reel.deepLink?.url)
    try await Task.sleep(for: .milliseconds(250))
    try await captureReel(host, name: "reels-on")
    player.play()
    try await waitForReel(host) { player.rate > 0 }
    try await Task.sleep(for: .milliseconds(500))
    try await captureReel(host, name: "reels-playing")

    #expect(playerView.onOpenPreview == nil)
    #expect(!playerView.showsFullScreenToggleButton)
    #expect(playerView.gestureRecognizers.compactMap { $0 as? NSClickGestureRecognizer }.isEmpty)
    let rate = player.rate
    playerView.openPreview()
    #expect(player.rate == rate)
    preferences.playsInstagramReels = false
    try await waitForReel(host) { reelPlayers(in: host).isEmpty && player.rate == 0 }
    #expect(player.rate == 0)
    #expect(!NSApplication.shared.windows.contains { $0.title == "Video" && $0.isVisible })
    try await Task.sleep(for: .milliseconds(300))
    try await captureReel(host, name: "reels-off-again")
}

@MainActor
private func reelViews(in view: NSView) -> [NSView] {
    view.subviews.flatMap { [$0] + reelViews(in: $0) }
}

@MainActor
private func reelPlayers(in view: NSView) -> [InlineVideoPlayerView] {
    reelViews(in: view).compactMap { $0 as? InlineVideoPlayerView }
}

@MainActor
private func waitForReel(_ host: NSView, condition: () -> Bool) async throws {
    let deadline = ContinuousClock.now.advanced(by: .seconds(15))
    while ContinuousClock.now < deadline {
        host.layoutSubtreeIfNeeded()
        if condition() { return }
        try await Task.sleep(for: .milliseconds(50))
    }
    throw NSError(domain: "ReelFixtureTimeout", code: 1)
}

@MainActor
private func captureReel(_ host: NSView, name: String) async throws {
    guard let path = ProcessInfo.processInfo.environment["INBOXPLUS_REEL_SCREENSHOTS"] else { return }
    let directory = URL(fileURLWithPath: path, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    host.layoutSubtreeIfNeeded()
    let screenshot = Process()
    screenshot.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
    screenshot.arguments = ["-x", "-o", "-l", "\(try #require(host.window).windowNumber)",
                            directory.appendingPathComponent("\(name).png").path]
    try screenshot.run()
    defer { if screenshot.isRunning { screenshot.terminate() } }
    let deadline = ContinuousClock.now.advanced(by: .seconds(30))
    while screenshot.isRunning, ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(50))
    }
    guard !screenshot.isRunning else { throw NSError(domain: "ReelScreenshotTimeout", code: 1) }
    #expect(screenshot.terminationStatus == 0)
}

@MainActor
private func makeReelMovie(at url: URL) async throws -> Data {
    let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 240, AVVideoHeightKey: 360
    ])
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
        kCVPixelBufferWidthKey as String: 240, kCVPixelBufferHeightKey as String: 360
    ])
    writer.add(input)
    #expect(writer.startWriting())
    writer.startSession(atSourceTime: .zero)
    var preview = Data()
    for frame in 0..<60 {
        let deadline = ContinuousClock.now.advanced(by: .seconds(10))
        while !input.isReadyForMoreMediaData, ContinuousClock.now < deadline {
            try await Task.sleep(for: .milliseconds(10))
        }
        #expect(input.isReadyForMoreMediaData)
        var buffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, try #require(adaptor.pixelBufferPool), &buffer)
        let pixel = try #require(buffer)
        CVPixelBufferLockBaseAddress(pixel, [])
        let context = try #require(CGContext(
            data: CVPixelBufferGetBaseAddress(pixel), width: 240, height: 360, bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixel), space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ))
        context.setFillColor(NSColor(calibratedRed: 0.16, green: 0.48, blue: 0.58, alpha: 1).cgColor)
        context.fill(CGRect(x: 0, y: 0, width: 240, height: 360))
        context.setFillColor(NSColor(calibratedRed: 1, green: 0.83, blue: 0.48, alpha: 1).cgColor)
        context.fillEllipse(in: CGRect(x: 130 - frame, y: 240, width: 70, height: 70))
        context.setFillColor(NSColor(calibratedRed: 0.12, green: 0.31, blue: 0.36, alpha: 1).cgColor)
        context.fillEllipse(in: CGRect(x: -80, y: -140, width: 420, height: 350))
        if frame == 0 {
            let image = try #require(context.makeImage())
            preview = try #require(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
        }
        CVPixelBufferUnlockBaseAddress(pixel, [])
        #expect(adaptor.append(pixel, withPresentationTime: CMTime(value: Int64(frame), timescale: 30)))
    }
    input.markAsFinished()
    await writer.finishWriting()
    #expect(writer.status == .completed)
    return preview
}
