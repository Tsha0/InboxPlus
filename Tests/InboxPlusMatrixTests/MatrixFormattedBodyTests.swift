import Foundation
import MatrixRustSDK
import InboxPlusCore
import Testing
@testable import InboxPlusMatrix

private func event(_ id: String, _ msgType: MessageType) -> EventTimelineItem {
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
        lazyProvider: LazyTimelineItemProvider(noHandle: .init())
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
