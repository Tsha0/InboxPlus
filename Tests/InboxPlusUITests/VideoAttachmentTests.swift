import AppKit
import AVKit
import InboxPlusCore
import Testing
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
