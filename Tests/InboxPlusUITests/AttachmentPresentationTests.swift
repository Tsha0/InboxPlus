import Foundation
import Testing
import InboxPlusCore
@testable import InboxPlusUI

@Test func durationsReadAsClockTime() {
    #expect(AttachmentFormatting.durationLabel(.seconds(9)) == "0:09")
    #expect(AttachmentFormatting.durationLabel(.seconds(75)) == "1:15")
    #expect(AttachmentFormatting.durationLabel(.seconds(3_725)) == "1:02:05")
}

@Test func anUnknownOrZeroDurationIsSimplyNotShown() {
    // A "0:00" under a voice message is a claim; absence is the truth.
    #expect(AttachmentFormatting.durationLabel(nil) == nil)
    #expect(AttachmentFormatting.durationLabel(.zero) == nil)
    #expect(AttachmentFormatting.durationLabel(.milliseconds(400)) == nil)
}

@Test func anUnknownSizeIsSimplyNotShown() {
    #expect(AttachmentFormatting.byteLabel(nil) == nil)
    #expect(AttachmentFormatting.byteLabel(0) == nil)
    #expect(AttachmentFormatting.byteLabel(1_048_576) != nil)
}

@Test func everyKindReadsAsSomethingRatherThanNothing() {
    for kind in MessageKind.allCases {
        #expect(!AttachmentFormatting.noun(for: kind).isEmpty)
    }
}

@Test func voiceOverDescribesWhatIsKnownAndInventsNothing() {
    let known = MessageAttachment(
        id: "1",
        kind: .video,
        filename: "462555709_902766575152919_3265496144511665546_n.mp4",
        byteCount: 1_048_576,
        duration: .seconds(75)
    )
    let label = AttachmentFormatting.accessibilityLabel(for: known)
    #expect(label.contains("Video"))
    #expect(label.contains("1:15"))
    // A server's filename is noise read aloud, as it is on screen.
    #expect(!label.contains("462555709"))

    let document = MessageAttachment(id: "2", kind: .file, filename: "Lease.pdf")
    #expect(AttachmentFormatting.accessibilityLabel(for: document) == "File, Lease.pdf")

    // Nothing known but the kind: still a usable label, with no fabricated duration or size.
    let bare = AttachmentFormatting.accessibilityLabel(for: MessageAttachment(id: "3", kind: .video))
    #expect(bare == "Video")
}

private func message(body: String, attachments: [MessageAttachment]) -> Message {
    Message(
        id: "$1", route: ConversationRoute(accountID: "instagram", conversationID: "room"),
        senderIdentityID: "@maya:inboxplus.localhost", body: body, timestamp: Date(timeIntervalSince1970: 0),
        deliveryState: .acknowledged, kind: attachments.first?.kind ?? .text, attachments: attachments
    )
}

@Test func aCaptionShowsUnderTheMediaWhileACardsTitleIsNotRepeated() {
    let caption = "sample.account\nSunset over the bay\nhttps://www.instagram.com/p/Cabc123/"
    let post = MessageAttachment(id: "1", kind: .image, filename: "462555709_n.jpg", caption: caption)
    #expect(AttachmentFormatting.showsBody(of: message(body: post.displayName, attachments: [post])))

    let photo = MessageAttachment(id: "2", kind: .image, filename: "462555709_n.jpg")
    #expect(!AttachmentFormatting.showsBody(of: message(body: photo.displayName, attachments: [photo])))
    let document = MessageAttachment(id: "3", kind: .file, filename: "Lease.pdf")
    #expect(!AttachmentFormatting.showsBody(of: message(body: document.displayName, attachments: [document])))

    // Text sent alongside a photo, as iMessage does, is its own line.
    #expect(AttachmentFormatting.showsBody(of: message(body: "look at this", attachments: [photo])))
    #expect(AttachmentFormatting.showsBody(of: message(body: "hello", attachments: [])))
}

@Test func anAppNativeCardAnnouncesWhereItOpens() throws {
    let attachment = MessageAttachment(
        id: "1",
        kind: .appNative,
        deepLink: try DeepLinkVerifier.verify("https://instagram.com/reel/1", for: .instagram)
    )
    #expect(AttachmentFormatting.accessibilityLabel(for: attachment).contains("opens in Instagram"))
}
