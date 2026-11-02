import Foundation
import Testing
@testable import InboxPlusFeatures

/// Every 17th step of each channel: 4,096 colors spread across the whole cube.
private let colorGrid: [ThemeColor] = stride(from: 0, through: 255, by: 17).flatMap { red in
    stride(from: 0, through: 255, by: 17).flatMap { green in
        stride(from: 0, through: 255, by: 17).map { blue in ThemeColor(UInt32(red << 16 | green << 8 | blue)) }
    }
}

private let surprises: [ThemePalette] = stride(from: 0.0, to: 1.0, by: 1.0 / 36).flatMap { hue in
    [true, false].map { ThemePalette.surprise(hue: hue, lightBackground: $0) }
}

@Test func colorsAreSavedAsHexAndAnythingElseIsRejected() {
    #expect(ThemeColor(0x4B2A6E).hex == "#4B2A6E")
    #expect(ThemeColor(hex: "#4b2a6e") == ThemeColor(0x4B2A6E))
    #expect(ThemeColor(hex: "4B2A6E") == ThemeColor(0x4B2A6E))
    for invalid in ["", "#FFF", "#GG0000", "#+FFFFF", "#1234567", "purple"] {
        #expect(ThemeColor(hex: invalid) == nil, "\(invalid)")
    }
}

@Test func hueSaturationAndBrightnessLandOnTheExpectedColors() {
    #expect(ThemeColor(hue: 0, saturation: 1, brightness: 1) == ThemeColor(0xFF0000))
    #expect(ThemeColor(hue: 1.0 / 3, saturation: 1, brightness: 1) == ThemeColor(0x00FF00))
    #expect(ThemeColor(hue: 2.0 / 3, saturation: 1, brightness: 1) == ThemeColor(0x0000FF))
    // The hue wraps, so a palette can be spun from any starting point.
    #expect(ThemeColor(hue: 1.5, saturation: 1, brightness: 1) == ThemeColor(0x00FFFF))
    #expect(ThemeColor(hue: 0.25, saturation: 0, brightness: 0.5) == ThemeColor(0x808080))
}

@Test func contrastFollowsTheWCAGFormula() {
    #expect(abs(ThemeColor.black.contrast(with: .white) - 21) < 0.001)
    #expect(ThemeColor(0x4B2A6E).contrast(with: ThemeColor(0x4B2A6E)) == 1)
    // #767676 is the lightest gray that passes 4.5:1 on white.
    #expect(abs(ThemeColor(0x767676).contrast(with: .white) - 4.54) < 0.01)
}

@Test func textOnAnyColorSomeoneCanPickIsReadable() {
    #expect(ThemeColor(0xFFF1A8).legibleText == .black)
    #expect(ThemeColor(0x102A43).legibleText == .white)
    for color in colorGrid {
        #expect(color.contrast(with: color.legibleText) >= 4.5, "\(color.hex)")
    }
}

@Test func anAccentIsAdjustedOnlyAsFarAsItNeedsToStandOut() {
    let lightWindow = ThemeColor(0xECECEC)
    let darkWindow = ThemeColor(0x323232)
    let blue = ThemeColor(0x1D4ED8)
    #expect(blue.readable(on: lightWindow, minimumContrast: 3) == blue)

    let yellow = ThemeColor(0xFFD000)
    let darkened = yellow.readable(on: lightWindow, minimumContrast: 3)
    #expect(darkened.contrast(with: lightWindow) >= 3)
    #expect(darkened != .black)
    #expect(yellow.readable(on: darkWindow, minimumContrast: 3) == yellow)

    for color in colorGrid {
        #expect(color.readable(on: lightWindow, minimumContrast: 3).contrast(with: lightWindow) >= 3, "\(color.hex)")
        #expect(color.readable(on: darkWindow, minimumContrast: 3).contrast(with: darkWindow) >= 3, "\(color.hex)")
    }
}

@Test func classicComesFirstAndEveryOtherThemeIsItsOwn() {
    #expect(ThemePreset.allCases.first == .classic)
    #expect(AppTheme.standard.palette == nil)
    let palettes = ThemePreset.allCases.compactMap(\.palette)
    #expect(palettes.count == ThemePreset.allCases.count - 1)
    #expect(Set(palettes).count == palettes.count)
    #expect(Set(ThemePreset.allCases.map(\.name)).count == ThemePreset.allCases.count)
}

@Test func aSurprisePaletteKeepsItsDarkOrLightBackground() {
    for palette in surprises {
        #expect(palette.background != palette.accent)
        #expect(palette.background != palette.logo)
    }
    let light = ThemePalette.surprise(hue: 0.6, lightBackground: true)
    let dark = ThemePalette.surprise(hue: 0.6, lightBackground: false)
    #expect(light.background.legibleText == .black)
    #expect(dark.background.legibleText == .white)
}

@MainActor
@Test func aThemeIsRememberedAndACustomOneSurvivesTryingAnother() throws {
    let suite = "InboxPlusTests-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }

    let first = AppPreferences(defaults: defaults)
    #expect(first.theme == .standard)
    #expect(first.appearanceMode == .system)
    #expect(first.customPalette == nil)

    let mine = ThemePalette(background: ThemeColor(0x123456), accent: ThemeColor(0xABCDEF), logo: ThemeColor(0xFF00AA))
    first.theme = .custom(mine)
    first.appearanceMode = .dark
    first.theme = .preset(.matcha)
    #expect(first.customPalette == mine)

    let relaunched = AppPreferences(defaults: defaults)
    #expect(relaunched.theme == .preset(.matcha))
    #expect(relaunched.customPalette == mine)
    #expect(relaunched.appearanceMode == .dark)

    relaunched.theme = .custom(mine)
    #expect(AppPreferences(defaults: defaults).theme == .custom(mine))
}

@MainActor
@Test func aThemeThisVersionCannotReadFallsBackToClassic() throws {
    let suite = "InboxPlusTests-\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }

    defaults.set("discoBall", forKey: "appearance.theme")
    defaults.set("sepia", forKey: "appearance.mode")
    let unknown = AppPreferences(defaults: defaults)
    #expect(unknown.theme == .standard)
    #expect(unknown.appearanceMode == .system)

    defaults.set("custom", forKey: "appearance.theme")
    defaults.set(["#123456", "not a color", "#FFFFFF"], forKey: "appearance.customColors")
    let unreadable = AppPreferences(defaults: defaults)
    #expect(unreadable.theme == .standard)
    #expect(unreadable.customPalette == nil)
}
