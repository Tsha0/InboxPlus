import Foundation
import Testing
@testable import InboxPlusCore

@Test func reactionsAreTalliedPerEmojiInTheOrderTheyFirstAppeared() {
    let reactions = MessageReaction.tally([
        ("❤️", false), ("👍", true), ("❤️", true), ("❤️", false),
    ])
    #expect(reactions == [
        MessageReaction(key: "❤️", count: 3, includesMe: true),
        MessageReaction(key: "👍", count: 1, includesMe: true),
    ])
    #expect(MessageReaction.tally([]).isEmpty)
}

@Test func onlyDeliveredMessagesSomeoneSaidAcceptRepliesAndReactions() {
    let route = ConversationRoute(accountID: "account", conversationID: "room")
    func message(_ kind: MessageKind, _ state: MessageDeliveryState = .acknowledged) -> Message {
        Message(id: "id", route: route, senderIdentityID: "sender", body: "body", timestamp: .now, deliveryState: state, kind: kind)
    }
    #expect(message(.text).acceptsResponses)
    #expect(message(.image).acceptsResponses)
    #expect(!message(.text, .pending).acceptsResponses)
    #expect(!message(.text, .failed("no")).acceptsResponses)
    for kind in [MessageKind.redacted, .encrypted, .membership, .state] {
        #expect(!message(kind).acceptsResponses)
    }
}

@Test func repliesAndReactionsAreOnlyOfferedWhereTheNetworkTakesThem() {
    #expect(ConversationCapabilities.mediaCapable.canReply)
    #expect(ConversationCapabilities.mediaCapable.canReact)
    #expect(!ConversationCapabilities.textOnly.canReply)
    #expect(!ConversationCapabilities.textOnly.canReact)
    #expect(!ConversationCapabilities(canSendText: true, attachmentKinds: []).canReact)
}

@Test func everyNetworkInboxLinkPassesTheVerifierForItsOwnPlatform() throws {
    for platform in Platform.allCases {
        guard let link = DeepLinkVerifier.inboxLink(for: platform) else { continue }
        #expect(link.platform == platform)
        #expect(link.url.scheme == "https")
        #expect(try DeepLinkVerifier.verify(link.url, for: platform) == link)
    }
    #expect(DeepLinkVerifier.inboxLink(for: .instagram)?.url.absoluteString == "https://www.instagram.com/direct/inbox/")
    // iMessage has no web inbox, and the local Matrix account is Inbox+'s own plumbing.
    #expect(DeepLinkVerifier.inboxLink(for: .iMessage) == nil)
    #expect(DeepLinkVerifier.inboxLink(for: .matrix) == nil)
    #expect(DeepLinkVerifier.inboxLink(for: .slack) == nil)
}
