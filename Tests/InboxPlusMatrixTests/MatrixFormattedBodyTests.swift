import Foundation
import MatrixRustSDK
import InboxPlusCore
import Testing
@testable import InboxPlusMatrix

private final class LatestEventProvider: LazyTimelineItemProvider, @unchecked Sendable {
    let json: String?

    init(json: String?) {
        self.json = json
        super.init(noHandle: .init())
    }

    required init(unsafeFromHandle handle: UInt64) {
        json = nil
        super.init(unsafeFromHandle: handle)
    }

    override func latestJson() -> String? { json }
}

private func event(_ id: String, _ msgType: MessageType, json: String? = nil) -> EventTimelineItem {
    EventTimelineItem(
        isRemote: true, eventOrTransactionId: .eventId(eventId: id), sender: "@instagram_456:local",
        senderProfile: .unavailable, forwarder: nil, forwarderProfile: nil,
        isOwn: false, isEditable: false,
        content: .msgLike(content: MsgLikeContent(
            kind: .message(content: MessageContent(
                msgType: msgType, body: "", isEdited: false, mentions: nil
            )), reactions: [], inReplyTo: nil, threadRoot: nil, threadSummary: nil
        )),
        eventTypeRaw: "m.room.message", timestamp: 123_000, localSendState: nil,
        localCreatedAt: nil, readReceipts: [:], origin: nil, canBeRepliedTo: true,
        lazyProvider: LatestEventProvider(json: json)
    )
}

private func html(_ body: String) -> FormattedBody {
    FormattedBody(format: .html, body: body)
}

private let normalizer = MatrixEventNormalizer(accountID: "matrix-local")

@Test func aFormattedMessageKeepsItsMarkdownAndReadsAsPlainText() throws {
    let markdown = "**sample.account** A caption with [a link](https://example.com/post?igsh=abc)"
    let message = try #require(normalizer.normalize(
        event("formatted", .text(content: TextMessageContent(
            body: markdown,
            formatted: html(
                "<strong>sample.account</strong> A caption with "
                    + "<a href=\"https://example.com/post?igsh=abc\">a link</a>"
            )
        ))),
        roomID: "room"
    ))
    #expect(message.body == "sample.account A caption with a link")
    #expect(message.markdownBody == markdown)
}

@Test func aBridgeNoticeLosesItsBackticks() throws {
    let message = try #require(normalizer.normalize(
        event("notice", .notice(content: NoticeMessageContent(
            body: "Bridge status: `CONNECTED`",
            formatted: html("Bridge status: <code>CONNECTED</code>")
        ))),
        roomID: "room"
    ))
    #expect(message.kind == .notice)
    #expect(message.body == "Bridge status: CONNECTED")
}

@Test func plainTextIsNeverReadAsMarkdown() throws {
    let literal = "2 * 3 * 4 is **not** bold and [this](https://example.com) is not a link"
    let plain = try #require(normalizer.normalize(
        event("plain", .text(content: TextMessageContent(body: literal, formatted: nil))),
        roomID: "room"
    ))
    #expect(plain.body == literal)
    #expect(plain.markdownBody == nil)

    let unknownFormat = try #require(normalizer.normalize(
        event("unknown", .text(content: TextMessageContent(
            body: literal, formatted: FormattedBody(format: .unknown(format: "org.example.custom"), body: literal)
        ))),
        roomID: "room"
    ))
    #expect(unknownFormat.body == literal)
    #expect(unknownFormat.markdownBody == nil)
}

@Test func aFormattedReelLinkStillBecomesAnOpenInAppCard() throws {
    let message = try #require(normalizer.normalize(
        event("reel", .text(content: TextMessageContent(
            body: "[https://www.instagram.com/reel/Cabc123/](https://www.instagram.com/reel/Cabc123/?igsh=abc)",
            formatted: html(
                "<a href=\"https://www.instagram.com/reel/Cabc123/?igsh=abc\">"
                    + "https://www.instagram.com/reel/Cabc123/</a>"
            )
        ))),
        roomID: "room"
    ))
    #expect(message.body == "https://www.instagram.com/reel/Cabc123/")
    #expect(message.kind == .appNative)
    #expect(message.attachments.first?.deepLink?.platform == .instagram)
}

private func video(caption: String? = nil) throws -> MessageType {
    .video(content: VideoMessageContent(
        filename: "clip.mp4", caption: caption, formattedCaption: nil,
        source: try MediaSource.fromUrl(url: "mxc://inboxplus.localhost/video"), info: nil
    ))
}

@Test func aBridgeFetchedReelBecomesALinkWithoutDownloadableVideo() throws {
    for path in ["reel", "reels"] {
        let message = try #require(normalizer.normalize(
            event("shared-video", try video(caption: "An author's caption"), json:
                """
                {"content":{"external_url":"https://www.instagram.com/\(path)/Cabc123/"}}
                """
            ), roomID: "room"
        ))
        #expect(message.kind == .appNative)
        let attachment = try #require(message.attachments.first)
        #expect(attachment.kind == .appNative)
        #expect(attachment.deepLink?.platform == .instagram)
        #expect(!attachment.isDownloadable)
        #expect(attachment.source == nil)
        #expect(attachment.thumbnail == nil)
    }
}

@Test func anOrdinaryDirectVideoIsNotBlockedByACaptionMentioningAReel() throws {
    let message = try #require(normalizer.normalize(
        event("direct-video", try video(caption: "This reminds me of https://instagram.com/reel/Cabc123/")),
        roomID: "room"
    ))
    #expect(message.kind == .video)
    #expect(message.attachments.first?.isDownloadable == true)
}

@Test func unverifiedAndNonReelMetadataDoesNotTurnVideoIntoAnAppLink() throws {
    for url in [
        "https://instagram.com.evil.example/reel/Cabc123/", "http://instagram.com/reel/Cabc123/",
        "https://instagram.com/profile", "https://instagram.com/p/Cabc123/",
        "https://instagram.com/reel-lookalike/Cabc123/", "javascript:alert(1)"
    ] {
        let message = try #require(normalizer.normalize(
            event("direct-video", try video(), json: "{\"content\":{\"external_url\":\"\(url)\"}}"),
            roomID: "room"
        ))
        #expect(message.kind == .video)
        #expect(message.attachments.first?.deepLink == nil)
    }
    #expect(MatrixEventNormalizer.appNativeVideoCard(json: "not JSON", id: "video") == nil)
    #expect(MatrixEventNormalizer.appNativeVideoCard(json: "{\"content\":{}}", id: "video") == nil)
}

@Test func aFormattedCaptionIsStoredAsPlainText() {
    let caption = MatrixEventNormalizer.plainCaption(
        "**sample.account** at the beach", formatted: html("<b>sample.account</b> at the beach")
    )
    #expect(caption == "sample.account at the beach")
    #expect(MatrixEventNormalizer.plainCaption("my_file_*draft*.txt", formatted: nil) == "my_file_*draft*.txt")
    #expect(MatrixEventNormalizer.plainCaption(nil, formatted: html("<b>x</b>")) == nil)
}

@Test func aFormattedGalleryCaptionReadsAsPlainText() throws {
    let message = try #require(normalizer.normalize(
        event("gallery", .gallery(content: GalleryMessageContent(
            body: "**Weekend** photos", formatted: html("<strong>Weekend</strong> photos"), itemtypes: []
        ))),
        roomID: "room"
    ))
    #expect(message.kind == .gallery)
    #expect(message.body == "Weekend photos")
    #expect(message.markdownBody == "**Weekend** photos")
}

private let serverFilename = "462555709_902766575152919_3265496144511665546_n.jpg"

private func photo(caption: String?, formatted: FormattedBody?) throws -> MessageType {
    .image(content: ImageMessageContent(
        filename: serverFilename,
        caption: caption,
        formattedCaption: formatted,
        source: try MediaSource.fromUrl(url: "mxc://inboxplus.localhost/photo"),
        info: nil
    ))
}

@Test func aSharedPostsCaptionIsTheMessageTextAndNotItsCardTitle() throws {
    let caption = "**sample.account** Sunset over the bay\n\n[instagram.com/p/Cabc123](https://www.instagram.com/p/Cabc123/)"
    let message = try #require(normalizer.normalize(
        event("post", try photo(caption: caption, formatted: html(
            "<b>sample.account</b> Sunset over the bay<br><br>"
                + "<a href=\"https://www.instagram.com/p/Cabc123/\">instagram.com/p/Cabc123</a>"
        ))),
        roomID: "room"
    ))
    let attachment = try #require(message.attachments.first)
    #expect(attachment.title == "Photo")
    #expect(attachment.filename == serverFilename)
    #expect(message.body == "sample.account Sunset over the bay\n\ninstagram.com/p/Cabc123")
    // Read as Markdown under the media, so its link opens like a link in any other message.
    #expect(message.markdownBody == caption)
}

@Test func anUncaptionedPhotoReadsAsAPhotoRatherThanItsFilename() throws {
    let message = try #require(normalizer.normalize(
        event("photo", try photo(caption: nil, formatted: nil)), roomID: "room"
    ))
    #expect(message.body == "Photo")
    #expect(message.markdownBody == nil)
    #expect(message.attachments.first?.filename == serverFilename)
}
