import AppKit
import AVKit
import InboxPlusCore
import Testing
import SwiftUI
@testable import InboxPlusUI

@MainActor
@Test func inlineVideoFitsLandscapePortraitAndSquareWithoutChangingProportions() {
    let landscape = VideoAttachmentPlayback.fittedSize(
        CGSize(width: 1920, height: 1080), within: CGSize(width: 320, height: 320)
    )
    let portrait = VideoAttachmentPlayback.fittedSize(
        CGSize(width: 1080, height: 1920), within: CGSize(width: 320, height: 320)
    )
    let square = VideoAttachmentPlayback.fittedSize(
        CGSize(width: 800, height: 800), within: CGSize(width: 320, height: 320)
    )
    #expect(landscape == CGSize(width: 320, height: 180))
    #expect(portrait == CGSize(width: 180, height: 320))
    #expect(square == CGSize(width: 320, height: 320))
}

@MainActor
@Test func videoTrackRotationDeterminesItsDisplayedDimensions() {
    let encodedSize = CGSize(width: 1920, height: 1080)
    let rotate = CGAffineTransform(a: 0, b: 1, c: -1, d: 0, tx: 1080, ty: 0)
    #expect(VideoAttachmentPlayback.orientedSize(encodedSize, transform: rotate) == CGSize(width: 1080, height: 1920))
    #expect(VideoAttachmentPlayback.orientedSize(encodedSize, transform: .identity) == encodedSize)
    #expect(VideoAttachmentPlayback.orientedSize(.zero, transform: .identity) == nil)
}

@MainActor
@Test func inlineVideoPreservesItsContentsAndDoubleClickOpensWithoutPlaying() {
    let view = InlineVideoPlayerView()
    let player = AVPlayer()
    view.player = player
    var opened = false
    view.onOpenPreview = { opened = true }

    #expect(view.videoGravity == .resizeAspect)
    let gesture = view.gestureRecognizers.compactMap { $0 as? NSClickGestureRecognizer }.first
    #expect(gesture?.numberOfClicksRequired == 2)
    #expect(gesture?.delaysPrimaryMouseButtonEvents == true)
    view.openPreview()

    #expect(opened)
    #expect(view.player === player)
    #expect(player.rate == 0)
}

@MainActor
@Test func videoPlaybackStartsPausedAndKeepsTheReportedPortraitSize() {
    let playback = VideoAttachmentPlayback(
        url: URL(fileURLWithPath: "/tmp/inboxplus-video-fixture.mov"),
        pixelSize: PixelSize(width: 1080, height: 1920)
    )
    let player = playback.player
    #expect(playback.player.rate == 0)
    #expect(!playback.showsPreview)
    #expect(playback.inlineSize == CGSize(width: 180, height: 320))
    playback.close()
    #expect(playback.player === player)
    #expect(playback.player.rate == 0)
}

@MainActor
@Test(arguments: [nil, PixelSize(width: 1080, height: 1920), PixelSize(width: 1920, height: 1080)])
func videoPlaceholderAndLoadedPlayerKeepTheSameHeight(pixelSize: PixelSize?) {
    let attachment = MessageAttachment(id: "video", kind: .video, pixelSize: pixelSize)
    let placeholder = NSHostingView(rootView: MediaPlaceholder(attachment: attachment))
    let loaded = NSHostingView(rootView: VideoAttachmentView(
        url: URL(fileURLWithPath: "/tmp/inboxplus-video-fixture.mov"), pixelSize: pixelSize
    ))
    #expect(abs(placeholder.fittingSize.height - loaded.fittingSize.height) < 1)
}

@MainActor
@Test(.timeLimit(.minutes(1)))
func aPortraitVideoTrackKeepsTheSpaceReservedBeforeItsDimensionsArrive() async throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("TranscriptVideo-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("portrait.mov")
    let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
    let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 32, AVVideoHeightKey: 64
    ])
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: nil)
    writer.add(input)
    #expect(writer.startWriting())
    writer.startSession(atSourceTime: .zero)
    var buffer: CVPixelBuffer?
    #expect(CVPixelBufferCreate(kCFAllocatorDefault, 32, 64, kCVPixelFormatType_32ARGB, nil, &buffer) == kCVReturnSuccess)
    let pixels = try #require(buffer)
    CVPixelBufferLockBaseAddress(pixels, [])
    if let bytes = CVPixelBufferGetBaseAddress(pixels) {
        memset(bytes, 0, CVPixelBufferGetDataSize(pixels))
    }
    CVPixelBufferUnlockBaseAddress(pixels, [])
    let deadline = ContinuousClock.now.advanced(by: .seconds(15))
    while !input.isReadyForMoreMediaData, ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(10))
    }
    try #require(input.isReadyForMoreMediaData)
    #expect(adaptor.append(pixels, withPresentationTime: .zero))
    input.markAsFinished()
    await writer.finishWriting()
    try #require(writer.status == .completed)

    let playback = VideoAttachmentPlayback(url: url, pixelSize: nil)
    let reserved = playback.inlineBounds
    await playback.loadPresentationSize()

    #expect(playback.presentationSize == CGSize(width: 32, height: 64))
    #expect(playback.inlineBounds == reserved)
    #expect(playback.inlineSize.height <= reserved.height)
    #expect(playback.inlineSize.width <= reserved.width)
    #expect(playback.player.rate == 0)
    playback.close()
}

@MainActor
@Test func reelPlaceholderDoesNotReserveSpaceForAnEnlargementButton() throws {
    let reel = MessageAttachment(
        id: "reel", kind: .video, pixelSize: PixelSize(width: 1080, height: 1920),
        deepLink: try DeepLinkVerifier.verify("https://instagram.com/reel/fixture/", for: .instagram)
    )
    let placeholder = NSHostingView(rootView: MediaPlaceholder(attachment: reel))
    let loaded = NSHostingView(rootView: VideoAttachmentView(
        url: URL(fileURLWithPath: "/tmp/inboxplus-reel-fixture.mov"), pixelSize: reel.pixelSize,
        allowsEnlargement: false
    ))
    #expect(abs(placeholder.fittingSize.height - loaded.fittingSize.height) < 1)
}
