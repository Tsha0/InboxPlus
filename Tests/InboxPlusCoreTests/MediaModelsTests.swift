import Foundation
import Testing
@testable import InboxPlusCore

@Test func aPlainTextMessageStillCompilesAndDefaultsToText() {
    let message = Message(
        id: "m",
        route: ConversationRoute(accountID: "ig", conversationID: "c"),
        senderIdentityID: nil,
        body: "hi",
        timestamp: Date(timeIntervalSince1970: 1),
        deliveryState: .pending
    )
    #expect(message.kind == .text)
    #expect(message.attachments.isEmpty)
}

@Test func anAttachmentPrefersTheSendersCaptionThenTheFilename() {
    let captioned = MessageAttachment(id: "1", kind: .image, filename: "IMG_0042.HEIC", caption: "beach")
    #expect(captioned.displayName == "beach")

    let named = MessageAttachment(id: "2", kind: .image, filename: "IMG_0042.HEIC", caption: "   ")
    #expect(named.displayName == "IMG_0042.HEIC")

    // Never an empty bubble.
    #expect(MessageAttachment(id: "3", kind: .video).displayName == "Video")
    #expect(MessageAttachment(id: "4", kind: .appNative).displayName == "Shared post")
}

@Test func onlyAnAttachmentWithBytesIsDownloadable() {
    // An app-native card has a deep link and nothing to fetch.
    #expect(!MessageAttachment(id: "1", kind: .appNative).isDownloadable)
    #expect(MessageAttachment(id: "2", kind: .image, source: MediaHandle(source: "mxc://s/1")).isDownloadable)
}

@Test func pixelSizeReservesLayoutOnlyWhenItIsUsable() {
    #expect(PixelSize(width: 1600, height: 900).aspectRatio == 16.0 / 9.0)
    #expect(PixelSize(width: 0, height: 900).aspectRatio == nil)
    #expect(PixelSize(width: -1, height: -1).aspectRatio == nil)
}

@Test func anAttachmentSurvivesAStorageRoundTrip() throws {
    let attachment = MessageAttachment(
        id: "1",
        kind: .video,
        filename: "clip.mp4",
        mimeType: "video/mp4",
        byteCount: 1_048_576,
        pixelSize: PixelSize(width: 1920, height: 1080),
        duration: .milliseconds(12_500),
        source: MediaHandle(source: "mxc://inboxplus.localhost/abc", mimeType: "video/mp4", byteCount: 1_048_576),
        thumbnail: MediaHandle(source: "mxc://inboxplus.localhost/thumb"),
        deepLink: try DeepLinkVerifier.verify("https://instagram.com/reel/1", for: .instagram)
    )
    let decoded = try JSONDecoder().decode(
        MessageAttachment.self, from: JSONEncoder().encode(attachment)
    )
    #expect(decoded == attachment)
    #expect(decoded.duration == .milliseconds(12_500))
}
