import SwiftUI
import Testing
import InboxPlusFeatures
@testable import InboxPlusUI

@Test func aPickedColorIsSavedExactlyAsItWasShown() {
    let colors = [ThemeColor(0x4B2A6E), ThemeColor(0xFFD000), ThemeColor(0x0E9F6E), .white, .black]
        + ThemePreset.allCases.compactMap(\.palette).flatMap { [$0.background, $0.accent, $0.logo] }
    for color in colors {
        #expect(ThemeColor(Color(color)) == color, "\(color.hex)")
    }
}

@Test func aColorPickedInAnotherColorSpaceIsSavedAsItsSRGBEquivalent() throws {
    let displayP3Red = Color(.displayP3, red: 1, green: 0, blue: 0)
    let saved = try #require(ThemeColor(displayP3Red))
    // Wider than sRGB, so it clamps to the nearest sRGB red rather than wrapping around.
    #expect(saved == ThemeColor(0xFF0000))
}
