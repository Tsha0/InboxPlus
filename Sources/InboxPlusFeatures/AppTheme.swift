import Foundation

/// An sRGB color as Settings saves it, written `#RRGGBB`.
public struct ThemeColor: Hashable, Sendable {
    /// `0xRRGGBB`.
    public let rgb: UInt32

    public init(_ rgb: UInt32) {
        self.rgb = rgb & 0xFF_FFFF
    }

    /// Components from 0 to 1; anything outside is clamped.
    public init(red: Double, green: Double, blue: Double) {
        func byte(_ component: Double) -> UInt32 { UInt32((min(max(component, 0), 1) * 255).rounded()) }
        self.init(byte(red) << 16 | byte(green) << 8 | byte(blue))
    }

    /// Hue wraps around the color wheel; saturation and brightness run from 0 to 1.
    public init(hue: Double, saturation: Double, brightness: Double) {
        let sector = (hue - hue.rounded(.down)) * 6
        let offset = sector - sector.rounded(.down)
        let low = brightness * (1 - saturation)
        let falling = brightness * (1 - saturation * offset)
        let rising = brightness * (1 - saturation * (1 - offset))
        let (red, green, blue): (Double, Double, Double) = switch Int(sector) {
        case 0: (brightness, rising, low)
        case 1: (falling, brightness, low)
        case 2: (low, brightness, rising)
        case 3: (low, falling, brightness)
        case 4: (rising, low, brightness)
        default: (brightness, low, falling)
        }
        self.init(red: red, green: green, blue: blue)
    }

    public init?(hex: String) {
        let digits = hex.hasPrefix("#") ? hex.dropFirst() : Substring(hex)
        guard digits.count == 6, digits.allSatisfy(\.isHexDigit), let rgb = UInt32(digits, radix: 16) else { return nil }
        self.init(rgb)
    }

    public static let white = ThemeColor(0xFFFFFF)
    public static let black = ThemeColor(0x000000)

    public var red: Double { Double(rgb >> 16 & 0xFF) / 255 }
    public var green: Double { Double(rgb >> 8 & 0xFF) / 255 }
    public var blue: Double { Double(rgb & 0xFF) / 255 }

    public var hex: String { String(format: "#%06X", rgb) }

    /// WCAG relative luminance: 0 for black, 1 for white.
    public var luminance: Double {
        func linear(_ component: Double) -> Double {
            component <= 0.04045 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// WCAG contrast ratio, from 1 for the same color to 21 for black on white.
    public func contrast(with other: ThemeColor) -> Double {
        (max(luminance, other.luminance) + 0.05) / (min(luminance, other.luminance) + 0.05)
    }

    /// White or black, whichever reads better on this color. One of them always clears 4.5:1,
    /// which is what lets people pick any color without making text unreadable.
    public var legibleText: ThemeColor {
        contrast(with: .white) >= contrast(with: .black) ? .white : .black
    }

    /// This color, darkened or lightened only as far as it takes to stand out on `surface`.
    public func readable(on surface: ThemeColor, minimumContrast: Double) -> ThemeColor {
        let target = surface.legibleText
        return stride(from: 0.0, through: 1.0, by: 0.05)
            .lazy
            .map { mixed(with: target, by: $0) }
            .first { $0.contrast(with: surface) >= minimumContrast } ?? target
    }

    private func mixed(with other: ThemeColor, by fraction: Double) -> ThemeColor {
        ThemeColor(
            red: red + (other.red - red) * fraction,
            green: green + (other.green - green) * fraction,
            blue: blue + (other.blue - blue) * fraction
        )
    }
}

/// The three colors a theme sets.
public struct ThemePalette: Hashable, Sendable {
    /// The navigation rail, and a tint behind the inbox, contacts and accounts lists.
    public var background: ThemeColor
    /// Your own message bubbles, unread counts, selection and the send button.
    public var accent: ThemeColor
    /// The tile behind the Inbox+ asterisk.
    public var logo: ThemeColor

    public init(background: ThemeColor, accent: ThemeColor, logo: ThemeColor) {
        self.background = background
        self.accent = accent
        self.logo = logo
    }

    /// Where custom colors start from Classic, close to how it looks in the current mode.
    public static func monochrome(dark: Bool) -> ThemePalette {
        dark
            ? ThemePalette(background: ThemeColor(0x2A2A2E), accent: ThemeColor(0xF5F5F7), logo: .black)
            : ThemePalette(background: ThemeColor(0xE8E8ED), accent: ThemeColor(0x1D1D1F), logo: .black)
    }

    /// A palette spun from one hue: the accent sits beside it on the color wheel, the logo opposite.
    public static func surprise(hue: Double, lightBackground: Bool) -> ThemePalette {
        lightBackground
            ? ThemePalette(
                background: ThemeColor(hue: hue, saturation: 0.2, brightness: 0.97),
                accent: ThemeColor(hue: hue + 0.04, saturation: 0.75, brightness: 0.78),
                logo: ThemeColor(hue: hue + 0.5, saturation: 0.7, brightness: 0.75)
            )
            : ThemePalette(
                background: ThemeColor(hue: hue, saturation: 0.6, brightness: 0.3),
                accent: ThemeColor(hue: hue + 0.04, saturation: 0.65, brightness: 0.88),
                logo: ThemeColor(hue: hue + 0.5, saturation: 0.65, brightness: 0.95)
            )
    }
}

/// The ready-made themes in Settings.
public enum ThemePreset: String, CaseIterable, Identifiable, Sendable {
    case classic, grapeSoda, nightSwim, matcha, sunset, toast, arcade, bubblegum, lemonade, mintChip

    public var id: String { rawValue }

    public var name: String {
        switch self {
        case .classic: "Classic"
        case .grapeSoda: "Grape Soda"
        case .nightSwim: "Night Swim"
        case .matcha: "Matcha"
        case .sunset: "Sunset"
        case .toast: "Toast"
        case .arcade: "Arcade"
        case .bubblegum: "Bubblegum"
        case .lemonade: "Lemonade"
        case .mintChip: "Mint Chip"
        }
    }

    /// Nil is the monochrome Inbox+ look, which follows light and dark mode.
    public var palette: ThemePalette? {
        switch self {
        case .classic: nil
        case .grapeSoda: palette(background: 0x4B2A6E, accent: 0x8E5CE6, logo: 0xF25CA2)
        case .nightSwim: palette(background: 0x102A43, accent: 0x3A86FF, logo: 0x00C2D1)
        case .matcha: palette(background: 0x2E4A36, accent: 0x4CA36B, logo: 0xA7D49B)
        case .sunset: palette(background: 0x5A1E33, accent: 0xF26A3D, logo: 0xFFB238)
        case .toast: palette(background: 0x3B2A20, accent: 0xD9893B, logo: 0xF4E3C1)
        case .arcade: palette(background: 0x14111F, accent: 0x00C27A, logo: 0xFF3EA5)
        case .bubblegum: palette(background: 0xF9D3E5, accent: 0xE2559C, logo: 0x5BC0EB)
        case .lemonade: palette(background: 0xFFF1A8, accent: 0xE3A600, logo: 0x2F9E44)
        case .mintChip: palette(background: 0xD8F3E8, accent: 0x0E9F6E, logo: 0x3B2A20)
        }
    }

    private func palette(background: UInt32, accent: UInt32, logo: UInt32) -> ThemePalette {
        ThemePalette(background: ThemeColor(background), accent: ThemeColor(accent), logo: ThemeColor(logo))
    }
}

public enum AppTheme: Hashable, Sendable {
    case preset(ThemePreset)
    case custom(ThemePalette)

    public static let standard = AppTheme.preset(.classic)

    public var palette: ThemePalette? {
        switch self {
        case let .preset(preset): preset.palette
        case let .custom(palette): palette
        }
    }
}

/// Whether Inbox+ follows macOS or stays light or dark.
public enum AppearanceMode: String, CaseIterable, Identifiable, Sendable {
    case system, light, dark

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}
