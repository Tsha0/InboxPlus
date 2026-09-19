import Foundation
import SwiftUI
import Testing
import MimoBridge
import MimoCore
@testable import MimoUI

private let box = CGRect(x: 0, y: 0, width: 24, height: 24)

@Test func everyConnectableNetworkHasItsOwnMark() throws {
    // A network Mimo offers but draws with a generic symbol looks unfinished next to the ones
    // that have real marks.
    for platform in BridgeCatalog.pickerOrder where BridgeCatalog.isAvailable(platform) {
        #expect(PlatformGlyph.brandColor(for: platform) != nil, "\(platform) has no brand colour")
        let path = try #require(PlatformGlyph.path(for: platform, in: box), "\(platform) has no mark")
        #expect(!path.isEmpty, "\(platform) produced an empty mark")
    }
}

@Test func aMarkStaysInsideTheSpaceItIsGiven() throws {
    // The paths are generated from a 24x24 source; one that escaped its box would draw over the
    // badge's rounded corners or bleed into neighbouring views.
    for platform in Platform.allCases {
        guard let path = PlatformGlyph.path(for: platform, in: box) else { continue }
        let bounds = path.boundingRect
        #expect(bounds.minX >= -0.5, "\(platform) overflows left")
        #expect(bounds.minY >= -0.5, "\(platform) overflows top")
        #expect(bounds.maxX <= 24.5, "\(platform) overflows right")
        #expect(bounds.maxY <= 26, "\(platform) overflows bottom")
    }
}

@Test func aMarkScalesWithTheSpaceItIsGiven() throws {
    // Vector, not a fixed-size image: the same badge is drawn in the inbox, the header and the
    // picker at different sizes.
    let small = try #require(PlatformGlyph.path(for: .instagram, in: box))
    let large = try #require(
        PlatformGlyph.path(for: .instagram, in: CGRect(x: 0, y: 0, width: 240, height: 240))
    )
    #expect(large.boundingRect.width > small.boundingRect.width * 9)
}

@Test func aMarkIsOffsetByTheRectItIsDrawnIn() throws {
    let moved = try #require(
        PlatformGlyph.path(for: .signal, in: CGRect(x: 100, y: 50, width: 24, height: 24))
    )
    #expect(moved.boundingRect.minX >= 99.5)
    #expect(moved.boundingRect.minY >= 49.5)
}

@Test func aPlatformWithoutAMarkFallsBackRatherThanDrawingNothing() {
    // Google Chat is in the domain model but has no mark; the badge must still render its symbol.
    #expect(PlatformGlyph.brandColor(for: .googleChat) == nil)
    #expect(PlatformGlyph.path(for: .googleChat, in: box) == nil)
    #expect(!Platform.googleChat.symbolName.isEmpty)
}

@Test func brandColoursAreTheOnesTheSourceRecords() {
    // Spot-checked against the pinned Simple Icons data, so a typo in a hex is caught rather than
    // shipping a nearly-right colour nobody notices.
    func components(_ platform: Platform) -> (Double, Double, Double)? {
        guard let color = PlatformGlyph.brandColor(for: platform) else { return nil }
        let native = NSColor(color).usingColorSpace(.sRGB)
        guard let native else { return nil }
        return (Double(native.redComponent), Double(native.greenComponent), Double(native.blueComponent))
    }
    // WhatsApp #25D366
    let whatsApp = components(.whatsApp)
    #expect(abs((whatsApp?.0 ?? 0) - 0x25 / 255.0) < 0.01)
    #expect(abs((whatsApp?.1 ?? 0) - 0xD3 / 255.0) < 0.01)
    #expect(abs((whatsApp?.2 ?? 0) - 0x66 / 255.0) < 0.01)
}
