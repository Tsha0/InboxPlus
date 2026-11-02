import Foundation
import Testing
import InboxPlusCore
@testable import InboxPlusUI

private let route = ConversationRoute(accountID: "account", conversationID: "room")

private func message(
    _ id: String,
    body: String = "hello",
    sender: String? = "alice",
    kind: MessageKind = .text,
    attachments: [MessageAttachment] = [],
    reactions: [MessageReaction] = []
) -> Message {
    Message(id: id, route: route, senderIdentityID: sender, body: body, timestamp: .now,
            deliveryState: .acknowledged, kind: kind, attachments: attachments, reactions: reactions)
}

@Test func theReactMenuLeadsWithQuickReactionsAndKeepsOnesAlreadyThere() {
    let reacted = message("m", reactions: [
        MessageReaction(key: "🎉", count: 2, includesMe: false),
        MessageReaction(key: "👍", count: 3, includesMe: true),
    ])
    let choices = TranscriptPresentation.reactionChoices(for: reacted)
    #expect(choices.map(\.key) == TranscriptPresentation.quickReactions + ["🎉"])
    #expect(choices.filter(\.includesMe).map(\.key) == ["👍"])
    #expect(TranscriptPresentation.reactionLabel(MessageReaction(key: "👍", count: 3, includesMe: true)) == "👍 3")
    #expect(TranscriptPresentation.reactionLabel(MessageReaction(key: "🎉", count: 1, includesMe: false)) == "🎉")
}

@Test func aQuotePrefersTheTranscriptsOwnCopyOfTheMessage() {
    let identities = [RemoteIdentity(id: "alice", accountID: "account", displayName: "Alice")]
    let original = message("original", body: "Dinner at 8?")
    let reply = MessageReply(messageID: "original", senderDisplayName: "alice_ghost", body: "stale")
    #expect(TranscriptPresentation.quote(reply, in: [original], identities: identities)
        == ReplyQuote(sender: "Alice", text: "Dinner at 8?"))
    #expect(TranscriptPresentation.quote(reply, in: [], identities: identities)
        == ReplyQuote(sender: "alice_ghost", text: "stale"))
    #expect(TranscriptPresentation.quote(MessageReply(messageID: "gone"), in: [], identities: identities)
        == ReplyQuote(sender: nil, text: "Original message not loaded"))
    #expect(TranscriptPresentation.replyingToLabel(original, identities: identities) == "Replying to Alice")
    #expect(TranscriptPresentation.replyingToLabel(message("own", sender: nil), identities: identities) == "Replying to yourself")
}

@Test func copyTextCopiesWhatAMessageSaysAndNothingStandingInForIt() {
    let photo = MessageAttachment(id: "a", kind: .image, filename: "IMG_1.jpg")
    let captioned = MessageAttachment(id: "b", kind: .image, filename: "IMG_2.jpg", caption: "Look")
    #expect(TranscriptPresentation.copyableText(message("text", body: "See you")) == "See you")
    #expect(TranscriptPresentation.copyableText(message("photo", body: "Photo", kind: .image, attachments: [photo])) == nil)
    #expect(TranscriptPresentation.copyableText(
        message("captioned", body: "Look", kind: .image, attachments: [captioned])
    ) == "Look")
    #expect(TranscriptPresentation.copyableText(message("deleted", body: "Message deleted", kind: .redacted)) == nil)
    #expect(TranscriptPresentation.copyableText(message("blank", body: "  ")) == nil)
}

@Test func aSavedAttachmentKeepsItsNameOrGetsAnExtensionFromItsType() {
    #expect(AttachmentFormatting.suggestedFilename(for: MessageAttachment(id: "a", kind: .file, filename: "Notes.pdf")) == "Notes.pdf")
    #expect(AttachmentFormatting.suggestedFilename(for: MessageAttachment(id: "b", kind: .image, mimeType: "image/jpeg")) == "Photo.jpeg")
    #expect(AttachmentFormatting.suggestedFilename(for: MessageAttachment(id: "c", kind: .video)) == "Video")
}

@Test func everyEmojiOfferedToReactWithIsOneThatSearchFindsToo() {
    let browsed = EmojiCatalog.categories.flatMap(\.emoji)
    let searchable = Set(EmojiCatalog.all.map(\.emoji))
    #expect(Set(browsed).count == browsed.count)
    #expect(browsed.allSatisfy { searchable.contains($0) })
    #expect(TranscriptPresentation.quickReactions.allSatisfy { searchable.contains($0) })
}

@Test func searchingForAReactionMatchesEveryWordOfItsName() {
    #expect(EmojiCatalog.search("tears JOY") == ["😂", "😹"])
    #expect(EmojiCatalog.search("heart").contains("❤️"))
    #expect(EmojiCatalog.search("unicorn") == ["🦄"])
    // The usual reactions come before clock faces and moon faces.
    #expect(EmojiCatalog.search("face").prefix(3) == ["😀", "😃", "😄"])
    #expect(EmojiCatalog.search("  ").isEmpty)
    #expect(EmojiCatalog.search("no such emoji").isEmpty)
}

@Test func searchLeavesOutPiecesThatAreNotEmojiOnTheirOwn() {
    let searchable = Set(EmojiCatalog.all.map(\.emoji))
    #expect(!searchable.contains("🏽"))
    #expect(!searchable.contains("🇫"))
}
