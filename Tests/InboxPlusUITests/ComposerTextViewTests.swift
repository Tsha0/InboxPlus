import AppKit
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import InboxPlusUI

/// A pasteboard of the test's own, so nothing here touches what the user has copied.
@MainActor
private func withPasteboard(_ body: (NSPasteboard) throws -> Void) rethrows {
    let pasteboard = NSPasteboard(name: NSPasteboard.Name("InboxPlusComposerTests-\(UUID().uuidString)"))
    defer { pasteboard.releaseGlobally() }
    pasteboard.clearContents()
    try body(pasteboard)
}

private func tiffBytes() throws -> Data {
    let image = NSImage(size: NSSize(width: 4, height: 4))
    image.lockFocus()
    NSColor.red.setFill()
    NSRect(x: 0, y: 0, width: 4, height: 4).fill()
    image.unlockFocus()
    return try #require(image.tiffRepresentation)
}

private let pngSignature = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

@MainActor
@Test func returnSendsAndShiftReturnStartsANewLine() {
    let textView = ComposerTextView()
    var sends = 0
    textView.onSubmit = { sends += 1 }
    textView.string = "ab"
    textView.setSelectedRange(NSRange(location: 1, length: 0))

    textView.returnPressed(modifiers: [])
    #expect(sends == 1)
    #expect(textView.string == "ab")

    textView.returnPressed(modifiers: .shift)
    #expect(sends == 1)
    #expect(textView.string == "a\nb")
}

@MainActor
@Test func theReturnKeyCommandSendsRatherThanInsertingALineBreak() {
    let textView = ComposerTextView()
    var sends = 0
    textView.onSubmit = { sends += 1 }
    textView.string = "hello"

    textView.insertNewline(nil)

    #expect(sends == 1)
    #expect(textView.string == "hello")
}

@MainActor
@Test func optionReturnStillStartsANewLine() {
    let textView = ComposerTextView()
    var sends = 0
    textView.onSubmit = { sends += 1 }
    textView.string = "hello"
    textView.setSelectedRange(NSRange(location: 5, length: 0))

    textView.insertNewlineIgnoringFieldEditor(nil)

    #expect(sends == 0)
    #expect(textView.string == "hello\n")
}

@MainActor
@Test func theComposerGrowsWithItsTextUpToSixLinesThenScrolls() {
    let textView = ComposerTextView()
    let width: CGFloat = 400
    let oneLine = textView.fittingHeight(forWidth: width)
    #expect(oneLine > 0)

    textView.string = "hi"
    #expect(textView.fittingHeight(forWidth: width) == oneLine)

    textView.string = "one\ntwo"
    let twoLines = textView.fittingHeight(forWidth: width)
    #expect(twoLines > oneLine)

    // Shift-Return at the end already puts the caret on a line of its own.
    textView.string = "one\n"
    #expect(textView.fittingHeight(forWidth: width) == twoLines)

    textView.string = Array(repeating: "line", count: 20).joined(separator: "\n")
    #expect(textView.fittingHeight(forWidth: width) == oneLine * CGFloat(ComposerTextView.maximumVisibleLines))
}

@MainActor
@Test func theFittingHeightMatchesTheLaidOutText() throws {
    let textView = ComposerTextView(frame: NSRect(x: 0, y: 0, width: 300, height: 0))
    textView.font = ComposerTextView.textFont
    textView.textContainerInset = .zero
    textView.textContainer?.lineFragmentPadding = 0
    // Laid out with TextKit 2, as the composer itself is; asking for `layoutManager` would switch
    // the view to TextKit 1.
    let layout = try #require(textView.textLayoutManager)

    for text in ["one", "one\ntwo", "one\ntwo\nthree", "a line long enough to wrap " + String(repeating: "word ", count: 30)] {
        textView.string = text
        layout.ensureLayout(for: layout.documentRange)
        let laidOut = layout.usageBoundsForTextContainer.height
        #expect(abs(laidOut - textView.fittingHeight(forWidth: 300)) < 1, "\(text.count) characters")
    }
}

@MainActor
@Test func copiedFilesAreStagedEvenWithTheirNameAndIconAlongside() throws {
    try withPasteboard { pasteboard in
        let url = URL(fileURLWithPath: "/tmp/holiday.png")
        pasteboard.writeObjects([url as NSURL])
        pasteboard.setString("holiday.png", forType: .string)
        pasteboard.setData(try tiffBytes(), forType: .tiff)

        #expect(StageableContent.isOffered(on: pasteboard))
        #expect(StageableContent.read(from: pasteboard) == .files([url]))
    }
}

@MainActor
@Test func copiedTextIsPastedAsTextEvenWithAPictureAlongside() throws {
    try withPasteboard { pasteboard in
        pasteboard.setString("Quarterly figures", forType: .string)
        pasteboard.setData(try tiffBytes(), forType: .tiff)

        #expect(!StageableContent.isOffered(on: pasteboard))
        #expect(StageableContent.read(from: pasteboard) == nil)
    }
}

@MainActor
@Test func aCopiedPictureIsStagedAsAPNG() throws {
    try withPasteboard { pasteboard in
        pasteboard.setData(try tiffBytes(), forType: .tiff)

        #expect(StageableContent.isOffered(on: pasteboard))
        guard case let .image(data, filename) = StageableContent.read(from: pasteboard) else {
            Issue.record("Expected a picture")
            return
        }
        #expect(filename == "Image.png")
        #expect(data.prefix(pngSignature.count) == pngSignature)
    }
}

@MainActor
@Test func formatsEveryNetworkTakesAreKeptAsTheyAre() throws {
    let gif = Data("GIF89a-not-really".utf8)
    #expect(StageableContent.image(gif, type: .gif) == .image(gif, filename: "Image.gif"))
    let png = pngSignature + Data(repeating: 0, count: 8)
    #expect(StageableContent.image(png, type: .png) == .image(png, filename: "Image.png"))
}

@MainActor
@Test func pastingAPictureStagesItInsteadOfInsertingText() throws {
    let textView = ComposerTextView()
    var staged: [StageableContent] = []
    textView.onStage = { staged.append($0) }
    try withPasteboard { pasteboard in
        pasteboard.setData(try tiffBytes(), forType: .tiff)

        #expect(textView.stage(from: pasteboard))
        #expect(staged.count == 1)
        #expect(textView.string.isEmpty)
    }
}

@MainActor
@Test func aConversationThatTakesNoAttachmentsPastesOnlyText() throws {
    let textView = ComposerTextView()
    try withPasteboard { pasteboard in
        pasteboard.setData(try tiffBytes(), forType: .tiff)

        #expect(!textView.stages(pasteboard))
        #expect(!textView.stage(from: pasteboard))
    }
}

@MainActor
@Test func pastedTextIsLeftToTheTextView() throws {
    let textView = ComposerTextView()
    var staged: [StageableContent] = []
    textView.onStage = { staged.append($0) }
    try withPasteboard { pasteboard in
        pasteboard.setString("hello", forType: .string)

        #expect(!textView.stage(from: pasteboard))
        #expect(staged.isEmpty)
    }
}
