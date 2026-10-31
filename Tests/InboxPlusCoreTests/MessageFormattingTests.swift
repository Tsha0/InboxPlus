import Foundation
import Testing
@testable import InboxPlusCore

@Test func bridgeMarkdownReadsAsPlainTextOutsideTheTranscript() {
    #expect(MessageFormatting.plainText(markdown: "**sample.account** A caption") == "sample.account A caption")
    #expect(MessageFormatting.plainText(markdown: "Bridge status: `CONNECTED`") == "Bridge status: CONNECTED")
    #expect(MessageFormatting.plainText(markdown: "~~old~~ and _new_") == "old and new")
    #expect(MessageFormatting.plainText(markdown: "Read [these](https://example.com/n) first") == "Read these first")
    #expect(MessageFormatting.plainText(markdown: "first line\n\n  - second line") == "first line\n\n  - second line")
    #expect(MessageFormatting.plainText(markdown: "\\*literal\\*") == "*literal*")
}

@Test func aLinkLabelledWithItsOwnAddressShowsTheCleanAddress() {
    let markdown = "[https://example.com/post](https://example.com/post?utm_source=share&igsh=abc123)"
    #expect(MessageFormatting.plainText(markdown: markdown) == "https://example.com/post")

    let labelledWithTracking = "[https://example.com/a?id=7&fbclid=xyz](https://example.com/a?id=7&fbclid=xyz)"
    #expect(MessageFormatting.plainText(markdown: labelledWithTracking) == "https://example.com/a?id=7")
}

@Test func formattingIsCarriedIntoTheRichText() throws {
    let text = MessageFormatting.attributed(markdown: "**Bold** then `code` and [a link](https://example.com/page)")
    let runs = text.runs.map { (String(text[$0.range].characters), $0.inlinePresentationIntent, $0.link) }
    #expect(runs.contains { $0.0 == "Bold" && $0.1 == .stronglyEmphasized })
    #expect(runs.contains { $0.0 == "code" && $0.1 == .code })
    let link = try #require(runs.first { $0.0 == "a link" })
    #expect(link.2 == URL(string: "https://example.com/page"))
}

@Test func onlyWebLinksStayClickable() {
    let text = MessageFormatting.attributed(
        markdown: "[one](javascript:alert(1)) [two](file:///etc/hosts) [three](/relative) "
            + "[four](https://user:secret@example.com) [five](http://example.com)"
    )
    let links = text.runs.compactMap(\.link)
    #expect(links == [URL(string: "http://example.com")!])
    #expect(String(text.characters) == "one two three four five")
}

@Test func shareRedirectsAreUnwrappedAndTrackingIsDropped() throws {
    let redirect = try #require(URL(
        string: "https://l.instagram.com/?u=https%3A%2F%2Fexample.com%2Fpost%3Fid%3D7%26utm_source%3Dig&e=AT0abc"
    ))
    #expect(MessageFormatting.webURL(redirect) == URL(string: "https://example.com/post?id=7"))

    let facebook = try #require(URL(string: "https://l.facebook.com/l.php?u=https%3A%2F%2Fexample.com%2F&h=AT1"))
    #expect(MessageFormatting.webURL(facebook) == URL(string: "https://example.com/"))

    let tracked = try #require(URL(string: "https://example.com/p?q=a%2Bb&UTM_Medium=x&igshid=1&name=a+b#top"))
    #expect(MessageFormatting.webURL(tracked) == URL(string: "https://example.com/p?q=a%2Bb&name=a+b#top"))

    let untouched = try #require(URL(string: "https://example.com/search?q=swift"))
    #expect(MessageFormatting.webURL(untouched) == untouched)

    #expect(MessageFormatting.webURL(URL(string: "mailto:someone@example.com")!) == nil)
    #expect(MessageFormatting.webURL(URL(string: "instagram://user?username=sample")!) == nil)
}
