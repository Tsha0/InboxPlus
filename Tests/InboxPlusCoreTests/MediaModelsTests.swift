import Foundation
import Testing
@testable import InboxPlusCore

@Test func aCardIsTitledWithWhatItHoldsRatherThanTheServersFilename() {
    let serverName = "462555709_902766575152919_3265496144511665546_n.jpg"
    let photo = MessageAttachment(id: "1", kind: .image, filename: serverName)
    #expect(photo.title == "Photo")
    // Kept for saving the photo under its own name.
    #expect(photo.filename == serverName)
    #expect(MessageAttachment(id: "2", kind: .video, filename: "video-1730.mp4").title == "Video")
    #expect(MessageAttachment(id: "3", kind: .audio, filename: "audioclip.m4a").title == "Audio message")

    // A document's name is what tells it apart from the others.
    #expect(MessageAttachment(id: "4", kind: .file, filename: "Lease.pdf").title == "Lease.pdf")
    #expect(MessageAttachment(id: "5", kind: .file, filename: "  ").title == "File")
}

@Test func aCaptionIsTheAttachmentsTextButNeverItsTitle() {
    let caption = """
    sample.account
    Sunset over the bay, with the whole crew for the last night of the trip.
    https://www.instagram.com/p/Cabc123/
    """
    let post = MessageAttachment(id: "1", kind: .image, filename: "462555709_n.jpg", caption: caption)
    #expect(post.title == "Photo")
    #expect(post.displayName == caption)

    let uncaptioned = MessageAttachment(id: "2", kind: .image, filename: "IMG_0042.HEIC", caption: "   ")
    #expect(uncaptioned.displayName == "Photo")

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
}
